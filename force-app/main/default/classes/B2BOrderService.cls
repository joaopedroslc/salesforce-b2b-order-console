/**
 * @description Service Layer orchestrating B2B Order creation, submission, fulfillment transitions,
 *              live ERP inventory synchronization, Platform Event processing, and demo catalog seeding.
 */
public inherited sharing class B2BOrderService implements Callable {
    public class B2BOrderServiceException extends Exception {
    }

    /**
     * @description DTO representing a line item request from LWC or service callers.
     */
    public class OrderLineInput {
        @AuraEnabled
        public Id productId { get; set; }
        @AuraEnabled
        public Id inventoryId { get; set; }
        @AuraEnabled
        public Decimal quantity { get; set; }
        @AuraEnabled
        public Decimal unitPrice { get; set; }
    }

    /**
     * @description Callable implementation allowing decoupled invocation from B2BOrderTriggerHandler.
     */
    public Object call(String action, Map<String, Object> args) {
        switch on action {
            when 'enqueueOrderSync' {
                Set<Id> orderIds = (Set<Id>) args.get('orderIds');
                return enqueueOrderSync(orderIds);
            }
            when else {
                throw new B2BOrderServiceException('Unsupported callable action: ' + action);
            }
        }
    }

    /**
     * @description Enqueues ERPOrderSyncQueueable for newly submitted orders.
     * @param orderIds Set of B2B_Order__c IDs.
     * @return AsyncApexJob ID (or null if skipped).
     */
    public static Id enqueueOrderSync(Set<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) {
            return null;
        }
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return null;
        }
        return System.enqueueJob(new ERPOrderSyncQueueable(orderIds));
    }

    /**
     * @description Creates a B2B Order with line items, and optionally submits it immediately
     *              within an atomic Savepoint transaction.
     * @param accountId Target B2B Customer Account ID.
     * @param notes Optional order fulfillment notes.
     * @param lineInputs List of OrderLineInput DTOs.
     * @param submitImmediately True to transition order from Draft to Submitted after inserting items.
     * @return Newly created (and optionally submitted) B2B_Order__c record with items.
     */
    public static B2B_Order__c createOrder(
        Id accountId,
        String notes,
        List<OrderLineInput> lineInputs,
        Boolean submitImmediately
    ) {
        if (accountId == null) {
            throw new B2BOrderServiceException('Customer Account is required to create a B2B Order.');
        }
        if (lineInputs == null || lineInputs.isEmpty()) {
            throw new B2BOrderServiceException('At least one line item is required to create a B2B Order.');
        }

        Savepoint sp = Database.setSavepoint();
        try {
            Boolean isGuest = B2BOrderConsoleController.isGuestContext();
            System.AccessLevel accessMode = B2BOrderConsoleController.getExecutionAccessLevel();

            B2B_Order__c newOrder = new B2B_Order__c(
                Account__c = accountId,
                Status__c = B2BOrdersDomain.STATUS_DRAFT,
                ERP_Sync_Status__c = B2BOrdersDomain.SYNC_NOT_STARTED,
                Notes__c = notes
            );

            List<B2B_Order__c> insertedOrders;
            if (isGuest) {
                insertedOrders = new List<B2B_Order__c>{ newOrder };
            } else {
                SObjectAccessDecision orderDecision = Security.stripInaccessible(
                    AccessType.CREATABLE,
                    new List<B2B_Order__c>{ newOrder }
                );
                insertedOrders = (List<B2B_Order__c>) orderDecision.getRecords();
            }
            Database.insert(insertedOrders, accessMode);
            Id orderId = insertedOrders[0].Id;

            List<B2B_Order_Item__c> itemsToInsert = new List<B2B_Order_Item__c>();
            for (OrderLineInput input : lineInputs) {
                if (input.productId == null) {
                    throw new B2BOrderServiceException('Each line item must specify a Product.');
                }
                if (input.quantity == null || input.quantity <= 0) {
                    throw new B2BOrderServiceException('Line item quantity must be greater than zero.');
                }
                itemsToInsert.add(
                    new B2B_Order_Item__c(
                        B2B_Order__c = orderId,
                        Product__c = input.productId,
                        Product_Inventory__c = input.inventoryId,
                        Quantity__c = input.quantity,
                        Unit_Price__c = input.unitPrice
                    )
                );
            }

            if (isGuest) {
                Database.insert(itemsToInsert, accessMode);
            } else {
                SObjectAccessDecision itemDecision = Security.stripInaccessible(
                    AccessType.CREATABLE,
                    itemsToInsert
                );
                Database.insert(itemDecision.getRecords(), accessMode);
            }

            if (submitImmediately != null && submitImmediately) {
                B2B_Order__c orderToSubmit = new B2B_Order__c(
                    Id = orderId,
                    Status__c = B2BOrdersDomain.STATUS_SUBMITTED
                );
                Database.update(orderToSubmit, accessMode);
            }

            List<B2B_Order__c> resultOrders = B2BOrdersSelector.selectByIdsWithItems(new Set<Id>{ orderId });
            return resultOrders.isEmpty() ? null : resultOrders[0];
        } catch (Exception ex) {
            Database.rollback(sp);
            throw new B2BOrderServiceException(ex.getMessage(), ex);
        }
    }

    /**
     * @description Transitions an existing B2B_Order__c to a target status (e.g., Submitted, Shipped, Cancelled).
     * @param orderId B2B_Order__c ID.
     * @param targetStatus New Status__c value.
     * @return Updated B2B_Order__c record with items.
     */
    public static B2B_Order__c updateOrderStatus(Id orderId, String targetStatus) {
        if (orderId == null || String.isBlank(targetStatus)) {
            throw new B2BOrderServiceException('Order ID and target status are required.');
        }

        B2B_Order__c orderUpdate = new B2B_Order__c(Id = orderId, Status__c = targetStatus.trim());
        if (B2BOrderConsoleController.isGuestContext()) {
            Database.update(orderUpdate, AccessLevel.SYSTEM_MODE);
        } else {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE,
                new List<B2B_Order__c>{ orderUpdate }
            );
            Database.update(decision.getRecords(), AccessLevel.USER_MODE);
        }

        List<B2B_Order__c> updated = B2BOrdersSelector.selectByIdsWithItems(new Set<Id>{ orderId });
        return updated.isEmpty() ? null : updated[0];
    }

    /**
     * @description Processes Order_Status_Event__e Platform Events published by ERPOrderSyncQueueable.
     * @param events List of Order_Status_Event__e records.
     */
    public static void applyOrderStatusEvents(List<Order_Status_Event__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        Map<Id, Order_Status_Event__e> latestEventByOrderId = new Map<Id, Order_Status_Event__e>();
        for (Order_Status_Event__e evt : events) {
            if (String.isNotBlank(evt.Order_Id__c)) {
                latestEventByOrderId.put((Id) evt.Order_Id__c, evt);
            }
        }

        if (latestEventByOrderId.isEmpty()) {
            return;
        }

        List<B2B_Order__c> existingOrders = B2BOrdersSelector.selectByIds(latestEventByOrderId.keySet());
        List<B2B_Order__c> ordersToUpdate = new List<B2B_Order__c>();

        for (B2B_Order__c ord : existingOrders) {
            // Do not overwrite orders already Shipped or Cancelled
            if (
                ord.Status__c == B2BOrdersDomain.STATUS_SHIPPED ||
                ord.Status__c == B2BOrdersDomain.STATUS_CANCELLED
            ) {
                continue;
            }
            Order_Status_Event__e evt = latestEventByOrderId.get(ord.Id);
            ordersToUpdate.add(
                new B2B_Order__c(
                    Id = ord.Id,
                    Status__c = String.isNotBlank(evt.Target_Status__c) ? evt.Target_Status__c : ord.Status__c,
                    ERP_Reference_Id__c = evt.ERP_Reference_Id__c,
                    ERP_Sync_Status__c = evt.Sync_Status__c,
                    ERP_Sync_Message__c = evt.Message__c
                )
            );
        }

        if (!ordersToUpdate.isEmpty()) {
            Database.update(ordersToUpdate, AccessLevel.SYSTEM_MODE);
        }
    }

    /**
     * @description Synchronizes Product_Inventory__c records with the external ERP REST endpoint.
     * @param inventoryIds Optional subset of Product_Inventory__c IDs. If empty/null, syncs all catalog items.
     * @return Updated list of Product_Inventory__c records.
     */
    public static List<Product_Inventory__c> syncInventoryWithErp(List<Id> inventoryIds) {
        List<Product_Inventory__c> inventories = (inventoryIds != null && !inventoryIds.isEmpty())
            ? ProductInventoriesSelector.selectByIds(new Set<Id>(inventoryIds))
            : ProductInventoriesSelector.selectCatalog(null, null);

        if (inventories.isEmpty()) {
            return inventories;
        }

        Map<String, ERPInventoryCalloutService.ErpStockSyncResult> syncResults = ERPInventoryCalloutService.fetchInventoryFromErp(
            inventories
        );

        List<Product_Inventory__c> recordsToUpdate = new List<Product_Inventory__c>();
        for (Product_Inventory__c inv : inventories) {
            ERPInventoryCalloutService.ErpStockSyncResult res = syncResults.get(inv.External_SKU__c);
            if (res != null) {
                recordsToUpdate.add(
                    new Product_Inventory__c(
                        Id = inv.Id,
                        On_Hand_Quantity__c = res.onHandQuantity,
                        Last_ERP_Sync__c = res.syncedAt
                    )
                );
            }
        }

        if (!recordsToUpdate.isEmpty()) {
            if (B2BOrderConsoleController.isGuestContext()) {
                Database.update(recordsToUpdate, AccessLevel.SYSTEM_MODE);
            } else {
                SObjectAccessDecision decision = Security.stripInaccessible(
                    AccessType.UPDATABLE,
                    recordsToUpdate
                );
                Database.update(decision.getRecords(), AccessLevel.USER_MODE);
            }
        }

        Set<Id> refreshedIds = new Map<Id, Product_Inventory__c>(inventories).keySet();
        return ProductInventoriesSelector.selectByIds(refreshedIds);
    }

    /**
     * @description Seeds realistic B2B Accounts, Products, and Product Inventories for immediate live demos.
     *              Idempotent by External_SKU__c so it can be clicked safely at any time.
     * @return Summary message of seeded records.
     */
    public static String seedDemoData() {
        System.AccessLevel accessMode = B2BOrderConsoleController.getExecutionAccessLevel();
        Set<String> demoNames = new Set<String>{
            'Acme Industrial Corp',
            'Globex Logistics Ltd',
            'Stark Manufacturing B2B'
        };
        List<Account> existingAccounts = (List<Account>) Database.queryWithBinds(
            'SELECT Id, Name FROM Account WHERE Name IN :demoNames LIMIT 10',
            new Map<String, Object>{ 'demoNames' => demoNames },
            accessMode
        );

        if (existingAccounts.isEmpty()) {
            List<Account> demoAccounts = new List<Account>{
                new Account(Name = 'Acme Industrial Corp', Type = 'Customer - Direct', Industry = 'Manufacturing'),
                new Account(Name = 'Globex Logistics Ltd', Type = 'Customer - Channel', Industry = 'Transportation'),
                new Account(Name = 'Stark Manufacturing B2B', Type = 'Customer - Direct', Industry = 'Electronics')
            };
            Database.insert(demoAccounts, accessMode);
        }

        Map<String, Map<String, Object>> catalogBlueprints = new Map<String, Map<String, Object>>{
            'SKU-IND-1001' => new Map<String, Object>{
                'name' => 'Industrial Servo Motor 5kW',
                'code' => 'IND-SERVO-5KW',
                'family' => 'Robotics & Motion',
                'desc' => 'High-torque brushless AC servo motor for automated assembly lines.',
                'price' => 1450.00,
                'onHand' => 85,
                'threshold' => 15
            },
            'SKU-IND-1002' => new Map<String, Object>{
                'name' => 'Programmable Logic Controller (PLC) X8',
                'code' => 'PLC-X8-PRO',
                'family' => 'Control Systems',
                'desc' => 'Modular industrial PLC with dual gigabit Ethernet and Modbus TCP.',
                'price' => 2200.00,
                'onHand' => 42,
                'threshold' => 10
            },
            'SKU-IND-1003' => new Map<String, Object>{
                'name' => 'Hydraulic Valve Manifold 12-Bar',
                'code' => 'HYD-VALVE-12B',
                'family' => 'Hydraulics',
                'desc' => 'Precision CNC-machined aluminum manifold rated to 350 Bar.',
                'price' => 680.00,
                'onHand' => 8,
                'threshold' => 12
            },
            'SKU-IND-1004' => new Map<String, Object>{
                'name' => 'Optical LiDAR Safety Scanner',
                'code' => 'SAFE-LIDAR-360',
                'family' => 'Safety Sensors',
                'desc' => '360-degree safety laser scanner for autonomous warehouse AGVs.',
                'price' => 3150.00,
                'onHand' => 24,
                'threshold' => 8
            },
            'SKU-IND-1005' => new Map<String, Object>{
                'name' => 'Heavy-Duty Conveyor Roller Kit',
                'code' => 'CONV-ROLL-HD',
                'family' => 'Material Handling',
                'desc' => 'Galvanized steel roller set (10-pack) for pallet conveyors.',
                'price' => 495.00,
                'onHand' => 120,
                'threshold' => 20
            },
            'SKU-IND-1006' => new Map<String, Object>{
                'name' => 'Three-Phase Variable Frequency Drive (VFD)',
                'code' => 'VFD-3PH-15KW',
                'family' => 'Power Electronics',
                'desc' => '480V 15kW variable frequency drive with regenerative braking.',
                'price' => 1890.00,
                'onHand' => 5,
                'threshold' => 10
            }
        };

        Map<String, Product_Inventory__c> existingBySku = new Map<String, Product_Inventory__c>();
        for (
            Product_Inventory__c inv : ProductInventoriesSelector.selectByExternalSkus(catalogBlueprints.keySet())
        ) {
            existingBySku.put(inv.External_SKU__c, inv);
        }

        List<Product2> productsToInsert = new List<Product2>();
        List<String> skusToCreate = new List<String>();

        for (String sku : catalogBlueprints.keySet()) {
            if (!existingBySku.containsKey(sku)) {
                Map<String, Object> spec = catalogBlueprints.get(sku);
                productsToInsert.add(
                    new Product2(
                        Name = (String) spec.get('name'),
                        ProductCode = (String) spec.get('code'),
                        Family = (String) spec.get('family'),
                        Description = (String) spec.get('desc'),
                        IsActive = true
                    )
                );
                skusToCreate.add(sku);
            }
        }

        if (!productsToInsert.isEmpty()) {
            Database.insert(productsToInsert, accessMode);

            List<Product_Inventory__c> newInventories = new List<Product_Inventory__c>();
            for (Integer i = 0; i < skusToCreate.size(); i++) {
                String sku = skusToCreate[i];
                Map<String, Object> spec = catalogBlueprints.get(sku);
                newInventories.add(
                    new Product_Inventory__c(
                        Product__c = productsToInsert[i].Id,
                        External_SKU__c = sku,
                        Unit_Price__c = (Decimal) spec.get('price'),
                        On_Hand_Quantity__c = (Decimal) spec.get('onHand'),
                        Reserved_Quantity__c = 0,
                        Reorder_Threshold__c = (Decimal) spec.get('threshold'),
                        Last_ERP_Sync__c = System.now()
                    )
                );
            }
            Database.insert(newInventories, accessMode);
        }

        return 'Seeded ' +
            productsToInsert.size() +
            ' new B2B catalog products and verified customer accounts.';
    }
}

