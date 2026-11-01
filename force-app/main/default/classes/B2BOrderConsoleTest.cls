/**
 * @description Comprehensive unit test suite covering TriggerHandler, Selectors, Domains,
 *              Services, Queueable + Platform Event integration, LWC Controller, and 210-record bulkification.
 */
@IsTest
private class B2BOrderConsoleTest {
    @TestSetup
    static void setupTestData() {
        B2BTestDataFactory.createAccount('Apex Enterprise Corp', true);
        List<Product2> products = B2BTestDataFactory.createProducts(3, true);
        B2BTestDataFactory.createInventories(products, 1000, 250.00, true);
    }

    @IsTest
    static void testCreateAndSubmitOrderPositiveWithErpConfirmation() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        List<Product_Inventory__c> inventories = ProductInventoriesSelector.selectCatalog(null, null);
        System.assertEquals(3, inventories.size(), 'Expected 3 seeded inventory items from TestSetup.');

        Test.setMock(HttpCalloutMock.class, ERPInventoryHttpCalloutMock.buildSuccessOrderMock('ERP-2026-99001'));

        List<B2BOrderService.OrderLineInput> lineInputs = new List<B2BOrderService.OrderLineInput>();
        B2BOrderService.OrderLineInput line1 = new B2BOrderService.OrderLineInput();
        line1.productId = inventories[0].Product__c;
        line1.inventoryId = inventories[0].Id;
        line1.quantity = 10;
        line1.unitPrice = inventories[0].Unit_Price__c;
        lineInputs.add(line1);

        Test.startTest();
        B2B_Order__c createdOrder = B2BOrderConsoleController.saveOrder(
            acc.Id,
            'Priority rush shipment',
            lineInputs,
            true
        );
        Test.stopTest();
        Test.getEventBus().deliver();

        B2B_Order__c refreshedOrder = B2BOrdersSelector.selectByIdsWithItems(new Set<Id>{ createdOrder.Id })[0];
        Product_Inventory__c refreshedInv = ProductInventoriesSelector.selectByIds(new Set<Id>{ inventories[0].Id })[0];

        System.assertEquals(
            B2BOrdersDomain.STATUS_CONFIRMED,
            refreshedOrder.Status__c,
            'Order should transition to Confirmed after Queueable + Platform Event processing.'
        );
        System.assertEquals(
            'ERP-2026-99001',
            refreshedOrder.ERP_Reference_Id__c,
            'ERP Reference ID should be stamped from mock callout.'
        );
        System.assertEquals(
            B2BOrdersDomain.SYNC_SYNCED,
            refreshedOrder.ERP_Sync_Status__c,
            'ERP Sync Status should be Synced.'
        );
        System.assertEquals(2500.00, refreshedOrder.Total_Amount__c, 'Roll-up Total Amount should equal 10 * 250.');
        System.assertEquals(10, refreshedInv.Reserved_Quantity__c, 'Reserved Quantity should increase by 10.');
        System.assertEquals(990, refreshedInv.Available_Quantity__c, 'Available Quantity should be 990.');
    }

    @IsTest
    static void testDraftOrderItemUpdateAndDeletePlusLifecycleTransitions() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product_Inventory__c inv = ProductInventoriesSelector.selectCatalog(null, null)[0];
        Test.setMock(HttpCalloutMock.class, ERPInventoryHttpCalloutMock.buildSuccessOrderMock('ERP-2026-100'));

        // Create a Draft order first (submitOrder = false)
        B2BOrderService.OrderLineInput line = new B2BOrderService.OrderLineInput();
        line.productId = inv.Product__c;
        line.inventoryId = inv.Id;
        line.quantity = 10;

        B2B_Order__c draftOrder = B2BOrderConsoleController.saveOrder(
            acc.Id,
            'Draft order for item edits',
            new List<B2BOrderService.OrderLineInput>{ line },
            false
        );

        // Add a second item, update it, and delete it while order is in Draft
        B2B_Order_Item__c tempItem = new B2B_Order_Item__c(
            B2B_Order__c = draftOrder.Id,
            Product__c = inv.Product__c,
            Product_Inventory__c = inv.Id,
            Quantity__c = 5
        );
        insert tempItem;

        // Update without passing the non-reparentable Master-Detail field B2B_Order__c
        B2B_Order_Item__c itemUpdateValid = new B2B_Order_Item__c(
            Id = tempItem.Id,
            Quantity__c = 8
        );
        update itemUpdateValid;

        // Exceed available stock on Draft item update
        Boolean updateStockError = false;
        try {
            update new B2B_Order_Item__c(Id = tempItem.Id, Quantity__c = 50000);
        } catch (DmlException ex) {
            updateStockError = true;
        }
        System.assert(updateStockError, 'Updating Draft item quantity beyond available stock must fail.');

        delete new B2B_Order_Item__c(Id = tempItem.Id);

        // Now submit the draft order and ship it
        B2BOrderConsoleController.changeOrderStatus(draftOrder.Id, B2BOrdersDomain.STATUS_SUBMITTED);
        B2BOrderTriggerHandler.resetProcessedOrders();

        B2B_Order__c orderToCancel = B2BOrderConsoleController.saveOrder(
            acc.Id,
            'Order to cancel',
            new List<B2BOrderService.OrderLineInput>{ line },
            true
        );

        Product_Inventory__c invAfterSubmit = ProductInventoriesSelector.selectByIds(new Set<Id>{ inv.Id })[0];
        System.assertEquals(20, invAfterSubmit.Reserved_Quantity__c, 'Both orders should reserve 10 units (total 20).');

        B2BOrderConsoleController.changeOrderStatus(draftOrder.Id, B2BOrdersDomain.STATUS_SHIPPED);
        B2BOrderConsoleController.changeOrderStatus(orderToCancel.Id, B2BOrdersDomain.STATUS_CANCELLED);

        Product_Inventory__c invFinal = ProductInventoriesSelector.selectByIds(new Set<Id>{ inv.Id })[0];
        System.assertEquals(0, invFinal.Reserved_Quantity__c, 'All reservations should be cleared after ship + cancel.');
        System.assertEquals(990, invFinal.On_Hand_Quantity__c, 'On Hand should decrease by 10 for the shipped order.');
        System.assertEquals(990, invFinal.Available_Quantity__c, 'Available Quantity should equal 990.');
    }

    @IsTest
    static void testErpBackorderAndServerErrorCalloutResponses() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product_Inventory__c inv = ProductInventoriesSelector.selectCatalog(null, null)[0];

        Test.setMock(HttpCalloutMock.class, ERPInventoryHttpCalloutMock.buildBackorderMock());
        B2BOrderService.OrderLineInput line = new B2BOrderService.OrderLineInput();
        line.productId = inv.Product__c;
        line.inventoryId = inv.Id;
        line.quantity = 5;

        Test.startTest();
        B2B_Order__c backordered = B2BOrderService.createOrder(
            acc.Id,
            'Backorder test',
            new List<B2BOrderService.OrderLineInput>{ line },
            true
        );
        Test.stopTest();
        Test.getEventBus().deliver();

        B2B_Order__c updatedOrder = B2BOrdersSelector.selectByIds(new Set<Id>{ backordered.Id })[0];
        System.assertEquals(
            B2BOrdersDomain.STATUS_BACKORDERED,
            updatedOrder.Status__c,
            'HTTP 409 response should transition order to Backordered.'
        );

        Test.setMock(HttpCalloutMock.class, ERPInventoryHttpCalloutMock.buildServerErrorMock());
        B2B_Order__c fullOrder = B2BOrdersSelector.selectByIdsWithItems(new Set<Id>{ backordered.Id })[0];
        ERPInventoryCalloutService.ErpOrderSyncResult errResult = ERPInventoryCalloutService.sendOrderToErp(fullOrder);
        System.assertEquals(false, errResult.isSuccess, '500 response should mark isSuccess = false.');
        System.assertEquals(B2BOrdersDomain.SYNC_FAILED, errResult.syncStatus, 'Sync status should be Failed.');

        // Also test controller exception when syncCatalogWithErp receives 500 error
        Boolean syncErpExceptionThrown = false;
        try {
            B2BOrderConsoleController.syncCatalogWithErp(new List<Id>{ inv.Id });
        } catch (Exception ex) {
            syncErpExceptionThrown = true;
        }
        System.assert(syncErpExceptionThrown, 'HTTP 500 during inventory sync should throw AuraHandledException.');
    }

    @IsTest
    static void testSelectorsControllerAndCatalogSync() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        System.assertEquals(3, B2BOrderConsoleController.getCatalogInventory('Industrial', 'In Stock').size());
        System.assertEquals(3, B2BOrderConsoleController.getCatalogInventory('Industrial', 'All').size());
        System.assertEquals(3, B2BOrderConsoleController.getCatalogInventory(null, 'In Stock').size());
        System.assertEquals(3, B2BOrderConsoleController.getCatalogInventory(null, null).size());
        System.assertEquals(0, ProductInventoriesSelector.selectByIds(null).size());
        System.assertEquals(0, ProductInventoriesSelector.selectByProductIds(null).size());
        System.assertEquals(0, ProductInventoriesSelector.selectByExternalSkus(null).size());
        System.assertEquals(0, B2BOrdersSelector.selectByIds(null).size());
        System.assertEquals(0, B2BOrdersSelector.selectByIdsWithItems(null).size());
        System.assertEquals(0, B2BOrdersSelector.selectItemsByOrderIds(null).size());

        List<Product_Inventory__c> currentCatalog = B2BOrderConsoleController.getCatalogInventory(null, null);
        Map<String, Decimal> newLevels = new Map<String, Decimal>{
            'SKU-TEST-1' => 1500,
            'SKU-TEST-2' => 750
        };
        Test.setMock(HttpCalloutMock.class, ERPInventoryHttpCalloutMock.buildInventorySyncMock(newLevels));

        Test.startTest();
        List<Product_Inventory__c> synced = B2BOrderConsoleController.syncCatalogWithErp(
            new List<Id>{ currentCatalog[0].Id, currentCatalog[1].Id }
        );
        String seedMsg = B2BOrderConsoleController.seedSampleCatalog();
        Test.stopTest();

        System.assertEquals(2, synced.size(), 'Expected 2 synced inventory records.');
        System.assertNotEquals(null, seedMsg, 'Seed message should be returned.');
        System.assert(B2BOrderConsoleController.getCustomerAccounts().size() >= 3, 'Should have demo accounts.');
        System.assertNotEquals(null, B2BOrderConsoleController.getRecentOrders(acc.Id), 'Filtered recent orders query.');
        System.assertNotEquals(null, B2BOrderConsoleController.getRecentOrders(null), 'Unfiltered recent orders query.');
    }

    @IsTest
    static void testNegativeValidationAndGuardrails() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product_Inventory__c inv = ProductInventoriesSelector.selectCatalog(null, null)[0];

        // 1. Controller exception paths
        Boolean nullAccountThrown = false;
        try {
            B2BOrderConsoleController.saveOrder(null, null, null, false);
        } catch (Exception ex) {
            nullAccountThrown = true;
        }
        System.assert(nullAccountThrown, 'Null account must throw AuraHandledException.');

        Boolean nullOrderStatusThrown = false;
        try {
            B2BOrderConsoleController.changeOrderStatus(null, null);
        } catch (Exception ex) {
            nullOrderStatusThrown = true;
        }
        System.assert(nullOrderStatusThrown, 'Null orderId must throw AuraHandledException.');

        // 2. Insufficient stock error on insert
        B2BOrderService.OrderLineInput excessiveLine = new B2BOrderService.OrderLineInput();
        excessiveLine.productId = inv.Product__c;
        excessiveLine.inventoryId = inv.Id;
        excessiveLine.quantity = 50000;

        Boolean insufficientStockThrown = false;
        try {
            B2BOrderConsoleController.saveOrder(
                acc.Id,
                'Exceeds stock',
                new List<B2BOrderService.OrderLineInput>{ excessiveLine },
                true
            );
        } catch (Exception ex) {
            insufficientStockThrown = true;
        }
        System.assert(insufficientStockThrown, 'Ordering more than Available Quantity must throw an exception.');

        // 3. Creating an order directly in Submitted status must fail
        Boolean nonDraftInsertBlocked = false;
        try {
            insert new B2B_Order__c(Account__c = acc.Id, Status__c = B2BOrdersDomain.STATUS_SUBMITTED);
        } catch (DmlException ex) {
            nonDraftInsertBlocked = true;
        }
        System.assert(nonDraftInsertBlocked, 'Inserting an order directly in Submitted status must be blocked.');

        // 4. Submitting an order with 0 line items
        B2B_Order__c emptyOrder = new B2B_Order__c(Account__c = acc.Id);
        insert emptyOrder;

        Boolean emptySubmitBlocked = false;
        try {
            emptyOrder.Status__c = B2BOrdersDomain.STATUS_SUBMITTED;
            update emptyOrder;
        } catch (DmlException ex) {
            emptySubmitBlocked = true;
        }
        System.assert(emptySubmitBlocked, 'Submitting an order with zero line items must be blocked.');

        // 5. Modifying/Deleting line items on a Submitted order
        B2B_Order_Item__c validItem = new B2B_Order_Item__c(
            B2B_Order__c = emptyOrder.Id,
            Product__c = inv.Product__c,
            Quantity__c = 5
        );
        insert validItem;

        B2BOrderTriggerHandler.resetProcessedOrders();
        emptyOrder.Status__c = B2BOrdersDomain.STATUS_SUBMITTED;
        update emptyOrder;

        Boolean itemInsertOnSubmittedBlocked = false;
        try {
            insert new B2B_Order_Item__c(
                B2B_Order__c = emptyOrder.Id,
                Product__c = inv.Product__c,
                Quantity__c = 1
            );
        } catch (DmlException ex) {
            itemInsertOnSubmittedBlocked = true;
        }
        System.assert(itemInsertOnSubmittedBlocked, 'Adding item to a Submitted order must be blocked.');

        Boolean itemEditBlocked = false;
        try {
            update new B2B_Order_Item__c(Id = validItem.Id, Quantity__c = 10);
        } catch (DmlException ex) {
            itemEditBlocked = true;
        }
        System.assert(itemEditBlocked, 'Editing a line item on a Submitted order must be blocked.');

        Boolean itemDeleteBlocked = false;
        try {
            delete new B2B_Order_Item__c(Id = validItem.Id);
        } catch (DmlException ex) {
            itemDeleteBlocked = true;
        }
        System.assert(itemDeleteBlocked, 'Deleting a line item from a Submitted order must be blocked.');

        // 6. Illegal status revert (Submitted -> Draft) and terminal status change (Cancelled -> Shipped)
        Boolean revertToDraftBlocked = false;
        try {
            update new B2B_Order__c(Id = emptyOrder.Id, Status__c = B2BOrdersDomain.STATUS_DRAFT);
        } catch (DmlException ex) {
            revertToDraftBlocked = true;
        }
        System.assert(revertToDraftBlocked, 'Reverting a Submitted order to Draft must be blocked.');

        update new B2B_Order__c(Id = emptyOrder.Id, Status__c = B2BOrdersDomain.STATUS_CANCELLED);
        Boolean terminalStatusChangeBlocked = false;
        try {
            update new B2B_Order__c(Id = emptyOrder.Id, Status__c = B2BOrdersDomain.STATUS_SHIPPED);
        } catch (DmlException ex) {
            terminalStatusChangeBlocked = true;
        }
        System.assert(terminalStatusChangeBlocked, 'Changing status of a Cancelled order must be blocked.');

        // 7. Inventory domain validation rules
        Boolean negativeInvBlocked = false;
        try {
            update new Product_Inventory__c(
                Id = inv.Id,
                On_Hand_Quantity__c = -5,
                Reserved_Quantity__c = -1,
                Unit_Price__c = -10
            );
        } catch (DmlException ex) {
            negativeInvBlocked = true;
        }
        System.assert(negativeInvBlocked, 'Negative inventory quantities must be blocked.');

        Boolean reservedExceedsOnHandBlocked = false;
        try {
            update new Product_Inventory__c(
                Id = inv.Id,
                On_Hand_Quantity__c = 10,
                Reserved_Quantity__c = 50
            );
        } catch (DmlException ex) {
            reservedExceedsOnHandBlocked = true;
        }
        System.assert(reservedExceedsOnHandBlocked, 'Reserved Quantity exceeding On Hand must be blocked.');
    }

    @IsTest
    static void testBulk210OrdersAndItemsReservation() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product_Inventory__c inv = ProductInventoriesSelector.selectCatalog(null, null)[0];

        inv.On_Hand_Quantity__c = 5000;
        update inv;

        Test.setMock(HttpCalloutMock.class, ERPInventoryHttpCalloutMock.buildSuccessOrderMock('ERP-BULK-210'));

        List<B2B_Order__c> bulkOrders = B2BTestDataFactory.createDraftOrders(acc.Id, 210, true);
        List<B2B_Order_Item__c> bulkItems = new List<B2B_Order_Item__c>();
        for (B2B_Order__c ord : bulkOrders) {
            bulkItems.add(
                new B2B_Order_Item__c(
                    B2B_Order__c = ord.Id,
                    Product__c = inv.Product__c,
                    Product_Inventory__c = inv.Id,
                    Quantity__c = 2
                )
            );
        }
        insert bulkItems;

        Test.startTest();
        B2BOrderTriggerHandler.resetProcessedOrders();
        for (B2B_Order__c ord : bulkOrders) {
            ord.Status__c = B2BOrdersDomain.STATUS_SUBMITTED;
        }
        update bulkOrders;
        Test.stopTest();

        Product_Inventory__c updatedInv = ProductInventoriesSelector.selectByIds(new Set<Id>{ inv.Id })[0];
        System.assertEquals(
            420,
            updatedInv.Reserved_Quantity__c,
            'Bulk submission of 210 orders (2 units each) must reserve exactly 420 units without hitting limits.'
        );
        System.assertEquals(
            4580,
            updatedInv.Available_Quantity__c,
            'Available Quantity should be 5000 - 420 = 4580.'
        );
    }

    @IsTest
    static void testTriggerHandlerBypassAndContextHooks() {
        TriggerHandler.bypass('B2BOrderTriggerHandler');
        System.assert(
            TriggerHandler.isBypassed('B2BOrderTriggerHandler'),
            'Handler should report bypassed.'
        );
        TriggerHandler.clearBypass('B2BOrderTriggerHandler');
        System.assert(
            !TriggerHandler.isBypassed('B2BOrderTriggerHandler'),
            'Handler bypass should be cleared.'
        );
        TriggerHandler.bypass('TempHandler');
        TriggerHandler.clearAllBypasses();
        System.assert(!TriggerHandler.isBypassed('TempHandler'), 'All bypasses should be cleared.');

        TriggerHandler baseHandler = new TriggerHandler();
        for (String ctx : new List<String>{
            'before insert',
            'before update',
            'before delete',
            'after insert',
            'after update',
            'after delete',
            'after undelete'
        }) {
            baseHandler.setTriggerContext(ctx, true);
            baseHandler.run();
        }
    }
}
