/**
 * @description Domain Layer for B2B_Order_Item__c.
 *              Enforces order lock rules, auto-populates inventory references and pricing,
 *              and validates bulk stock availability across 200+ line items.
 */
public inherited sharing class B2BOrderItemsDomain {
    /**
     * @description Validates new order items, resolves Product_Inventory__c & Unit_Price__c,
     *              and verifies available stock in bulk before insert.
     * @param newItems List of B2B_Order_Item__c records from Trigger.new.
     */
    public static void onBeforeInsert(List<B2B_Order_Item__c> newItems) {
        Set<Id> orderIds = new Set<Id>();
        Set<Id> productIds = new Set<Id>();
        Set<Id> inventoryIds = new Set<Id>();

        for (B2B_Order_Item__c item : newItems) {
            if (item.B2B_Order__c != null) {
                orderIds.add(item.B2B_Order__c);
            }
            if (item.Product__c == null) {
                item.Product__c.addError('Product is required on every B2B Order Item.');
            } else {
                productIds.add(item.Product__c);
            }
            if (item.Product_Inventory__c != null) {
                inventoryIds.add(item.Product_Inventory__c);
            }
            if (item.Quantity__c == null || item.Quantity__c <= 0) {
                item.Quantity__c.addError('Quantity must be greater than zero.');
            }
        }

        // 1. Ensure parent orders are in Draft status
        Map<Id, B2B_Order__c> parentOrdersById = new Map<Id, B2B_Order__c>(
            B2BOrdersSelector.selectByIds(orderIds)
        );
        for (B2B_Order_Item__c item : newItems) {
            B2B_Order__c parentOrder = parentOrdersById.get(item.B2B_Order__c);
            if (parentOrder != null && parentOrder.Status__c != B2BOrdersDomain.STATUS_DRAFT) {
                item.addError(
                    'Line items can only be added when the B2B Order is in Draft status (current status: ' +
                    parentOrder.Status__c +
                    ').'
                );
            }
        }

        // 2. Bulk-resolve Product_Inventory__c by Product__c or explicit Product_Inventory__c
        Map<Id, Product_Inventory__c> inventoryByProductId = new Map<Id, Product_Inventory__c>();
        Map<Id, Product_Inventory__c> inventoryById = new Map<Id, Product_Inventory__c>();

        for (Product_Inventory__c inv : ProductInventoriesSelector.selectByProductIds(productIds)) {
            inventoryByProductId.put(inv.Product__c, inv);
            inventoryById.put(inv.Id, inv);
        }
        if (!inventoryIds.isEmpty()) {
            for (Product_Inventory__c inv : ProductInventoriesSelector.selectByIds(inventoryIds)) {
                inventoryById.put(inv.Id, inv);
                if (inv.Product__c != null && !inventoryByProductId.containsKey(inv.Product__c)) {
                    inventoryByProductId.put(inv.Product__c, inv);
                }
            }
        }

        // 3. Link inventory, default Unit_Price__c, and aggregate requested quantities per Inventory record
        Map<Id, Decimal> requestedQtyByInventoryId = new Map<Id, Decimal>();
        for (B2B_Order_Item__c item : newItems) {
            Product_Inventory__c resolvedInv = item.Product_Inventory__c != null
                ? inventoryById.get(item.Product_Inventory__c)
                : inventoryByProductId.get(item.Product__c);

            if (resolvedInv != null) {
                item.Product_Inventory__c = resolvedInv.Id;
                if (item.Unit_Price__c == null || item.Unit_Price__c <= 0) {
                    item.Unit_Price__c = resolvedInv.Unit_Price__c;
                }
                if (item.Quantity__c != null && item.Quantity__c > 0) {
                    Decimal runningTotal = requestedQtyByInventoryId.containsKey(resolvedInv.Id)
                        ? requestedQtyByInventoryId.get(resolvedInv.Id)
                        : 0;
                    requestedQtyByInventoryId.put(resolvedInv.Id, runningTotal + item.Quantity__c);
                }
            } else if (item.Unit_Price__c == null) {
                item.Unit_Price__c = 0;
            }

            if (item.Unit_Price__c != null && item.Unit_Price__c < 0) {
                item.Unit_Price__c.addError('Unit Price cannot be negative.');
            }
        }

        // 4. Validate cumulative requested quantity against Available_Quantity__c
        for (B2B_Order_Item__c item : newItems) {
            if (item.Product_Inventory__c != null && requestedQtyByInventoryId.containsKey(item.Product_Inventory__c)) {
                Product_Inventory__c inv = inventoryById.get(item.Product_Inventory__c);
                Decimal totalRequested = requestedQtyByInventoryId.get(item.Product_Inventory__c);
                Decimal available = inv != null && inv.Available_Quantity__c != null ? inv.Available_Quantity__c : 0;
                if (totalRequested > available) {
                    item.Quantity__c.addError(
                        'Insufficient available stock for SKU ' +
                        inv.External_SKU__c +
                        '. Requested: ' +
                        totalRequested +
                        ', Available: ' +
                        available +
                        '.'
                    );
                }
            }
        }
    }

    /**
     * @description Validates modifications to existing B2B_Order_Item__c records before update.
     * @param newItems List of updated B2B_Order_Item__c records from Trigger.new.
     * @param oldMap Map of prior B2B_Order_Item__c records from Trigger.oldMap.
     */
    public static void onBeforeUpdate(
        List<B2B_Order_Item__c> newItems,
        Map<Id, B2B_Order_Item__c> oldMap
    ) {
        Set<Id> orderIds = new Set<Id>();
        Set<Id> inventoryIds = new Set<Id>();

        for (B2B_Order_Item__c item : newItems) {
            orderIds.add(item.B2B_Order__c);
            if (item.Product__c == null) {
                item.Product__c.addError('Product is required on every B2B Order Item.');
            }
            if (item.Quantity__c == null || item.Quantity__c <= 0) {
                item.Quantity__c.addError('Quantity must be greater than zero.');
            }
            if (item.Unit_Price__c == null || item.Unit_Price__c < 0) {
                item.Unit_Price__c.addError('Unit Price cannot be negative.');
            }
            if (item.Product_Inventory__c != null) {
                inventoryIds.add(item.Product_Inventory__c);
            }
        }

        Map<Id, B2B_Order__c> parentOrdersById = new Map<Id, B2B_Order__c>(
            B2BOrdersSelector.selectByIds(orderIds)
        );
        Map<Id, Product_Inventory__c> inventoryById = new Map<Id, Product_Inventory__c>(
            ProductInventoriesSelector.selectByIds(inventoryIds)
        );

        Map<Id, Decimal> requestedQtyByInventoryId = new Map<Id, Decimal>();
        for (B2B_Order_Item__c item : newItems) {
            B2B_Order__c parentOrder = parentOrdersById.get(item.B2B_Order__c);
            if (parentOrder != null && parentOrder.Status__c != B2BOrdersDomain.STATUS_DRAFT) {
                item.addError(
                    'Line items cannot be modified when the B2B Order is in ' +
                    parentOrder.Status__c +
                    ' status.'
                );
            }

            if (item.Product_Inventory__c != null && item.Quantity__c != null && item.Quantity__c > 0) {
                Decimal runningTotal = requestedQtyByInventoryId.containsKey(item.Product_Inventory__c)
                    ? requestedQtyByInventoryId.get(item.Product_Inventory__c)
                    : 0;
                requestedQtyByInventoryId.put(item.Product_Inventory__c, runningTotal + item.Quantity__c);
            }
        }

        for (B2B_Order_Item__c item : newItems) {
            B2B_Order_Item__c oldItem = oldMap.get(item.Id);
            if (
                item.Product_Inventory__c != null &&
                oldItem != null &&
                item.Quantity__c > oldItem.Quantity__c &&
                inventoryById.containsKey(item.Product_Inventory__c)
            ) {
                Product_Inventory__c inv = inventoryById.get(item.Product_Inventory__c);
                Decimal totalRequested = requestedQtyByInventoryId.get(item.Product_Inventory__c);
                Decimal available = inv.Available_Quantity__c != null ? inv.Available_Quantity__c : 0;
                if (totalRequested > available) {
                    item.Quantity__c.addError(
                        'Insufficient available stock for SKU ' +
                        inv.External_SKU__c +
                        '. Requested: ' +
                        totalRequested +
                        ', Available: ' +
                        available +
                        '.'
                    );
                }
            }
        }
    }

    /**
     * @description Prevents deleting line items from orders that are no longer in Draft status.
     * @param oldItems List of B2B_Order_Item__c records from Trigger.old.
     */
    public static void onBeforeDelete(List<B2B_Order_Item__c> oldItems) {
        Set<Id> orderIds = new Set<Id>();
        for (B2B_Order_Item__c item : oldItems) {
            orderIds.add(item.B2B_Order__c);
        }

        Map<Id, B2B_Order__c> parentOrdersById = new Map<Id, B2B_Order__c>(
            B2BOrdersSelector.selectByIds(orderIds)
        );
        for (B2B_Order_Item__c item : oldItems) {
            B2B_Order__c parentOrder = parentOrdersById.get(item.B2B_Order__c);
            if (parentOrder != null && parentOrder.Status__c != B2BOrdersDomain.STATUS_DRAFT) {
                item.addError(
                    'Line items cannot be deleted once the B2B Order is in ' +
                    parentOrder.Status__c +
                    ' status.'
                );
            }
        }
    }
}

