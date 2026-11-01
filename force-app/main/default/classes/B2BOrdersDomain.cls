/**
 * @description Domain Layer for B2B_Order__c.
 *              Enforces order status state machine transitions, stamps audit fields,
 *              and executes bulk stock reservations, deductions, and releases.
 */
public inherited sharing class B2BOrdersDomain {
    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String STATUS_CONFIRMED = 'Confirmed';
    public static final String STATUS_BACKORDERED = 'Backordered';
    public static final String STATUS_SHIPPED = 'Shipped';
    public static final String STATUS_CANCELLED = 'Cancelled';

    public static final String SYNC_NOT_STARTED = 'Not Started';
    public static final String SYNC_PENDING = 'Pending';
    public static final String SYNC_SYNCED = 'Synced';
    public static final String SYNC_FAILED = 'Failed';

    private static final Set<String> RESERVED_STATUSES = new Set<String>{
        STATUS_SUBMITTED,
        STATUS_CONFIRMED,
        STATUS_BACKORDERED
    };

    /**
     * @description Applies default field values and validates initial status on before insert.
     * @param newOrders List of new B2B_Order__c records from Trigger.new.
     */
    public static void onBeforeInsert(List<B2B_Order__c> newOrders) {
        for (B2B_Order__c ord : newOrders) {
            if (String.isBlank(ord.Status__c)) {
                ord.Status__c = STATUS_DRAFT;
            }
            if (String.isBlank(ord.ERP_Sync_Status__c)) {
                ord.ERP_Sync_Status__c = SYNC_NOT_STARTED;
            }
            if (ord.Status__c != STATUS_DRAFT) {
                ord.Status__c.addError('New B2B Orders must be created in Draft status before adding line items.');
            }
        }
    }

    /**
     * @description Enforces legal state transitions and stamps submission metadata on before update.
     * @param newOrders List of updated B2B_Order__c records from Trigger.new.
     * @param oldMap Map of prior B2B_Order__c records from Trigger.oldMap.
     */
    public static void onBeforeUpdate(
        List<B2B_Order__c> newOrders,
        Map<Id, B2B_Order__c> oldMap
    ) {
        for (B2B_Order__c ord : newOrders) {
            B2B_Order__c oldOrd = oldMap.get(ord.Id);
            if (oldOrd == null || ord.Status__c == oldOrd.Status__c) {
                continue;
            }

            // Terminal statuses cannot transition to any other status
            if (oldOrd.Status__c == STATUS_SHIPPED || oldOrd.Status__c == STATUS_CANCELLED) {
                ord.Status__c.addError(
                    'Cannot change status of an order that is already ' + oldOrd.Status__c + '.'
                );
                continue;
            }

            // Cannot revert an active order back to Draft
            if (ord.Status__c == STATUS_DRAFT && oldOrd.Status__c != STATUS_DRAFT) {
                ord.Status__c.addError('Cannot revert a ' + oldOrd.Status__c + ' order back to Draft.');
                continue;
            }

            // Submitting an order requires at least 1 line item and transitions from Draft
            if (ord.Status__c == STATUS_SUBMITTED) {
                if (oldOrd.Status__c != STATUS_DRAFT) {
                    ord.Status__c.addError('Only Draft orders can be transitioned to Submitted.');
                    continue;
                }
                if (ord.Total_Items__c == null || ord.Total_Items__c <= 0) {
                    ord.addError('Cannot submit a B2B Order with no line items.');
                    continue;
                }
                if (ord.Submitted_Date__c == null) {
                    ord.Submitted_Date__c = System.now();
                }
                ord.ERP_Sync_Status__c = SYNC_PENDING;
            }
        }
    }

    /**
     * @description Coordinates bulk inventory reservation, release, and physical stock deduction
     *              when B2B_Order__c records transition between statuses.
     * @param newOrders List of updated B2B_Order__c records from Trigger.new.
     * @param oldMap Map of prior B2B_Order__c records from Trigger.oldMap.
     * @return Set of Order IDs that just transitioned to Submitted and require async ERP sync.
     */
    public static Set<Id> onAfterUpdate(
        List<B2B_Order__c> newOrders,
        Map<Id, B2B_Order__c> oldMap
    ) {
        Set<Id> newlySubmittedOrderIds = new Set<Id>();
        Set<Id> cancelledFromReservedOrderIds = new Set<Id>();
        Set<Id> shippedFromReservedOrderIds = new Set<Id>();
        Map<Id, B2B_Order__c> newOrdersById = new Map<Id, B2B_Order__c>(newOrders);

        for (B2B_Order__c ord : newOrders) {
            B2B_Order__c oldOrd = oldMap.get(ord.Id);
            if (oldOrd == null || ord.Status__c == oldOrd.Status__c) {
                continue;
            }

            if (oldOrd.Status__c == STATUS_DRAFT && ord.Status__c == STATUS_SUBMITTED) {
                newlySubmittedOrderIds.add(ord.Id);
            } else if (RESERVED_STATUSES.contains(oldOrd.Status__c) && ord.Status__c == STATUS_CANCELLED) {
                cancelledFromReservedOrderIds.add(ord.Id);
            } else if (RESERVED_STATUSES.contains(oldOrd.Status__c) && ord.Status__c == STATUS_SHIPPED) {
                shippedFromReservedOrderIds.add(ord.Id);
            }
        }

        Set<Id> allAffectedOrderIds = new Set<Id>();
        allAffectedOrderIds.addAll(newlySubmittedOrderIds);
        allAffectedOrderIds.addAll(cancelledFromReservedOrderIds);
        allAffectedOrderIds.addAll(shippedFromReservedOrderIds);

        if (allAffectedOrderIds.isEmpty()) {
            return newlySubmittedOrderIds;
        }

        List<B2B_Order_Item__c> orderItems = B2BOrdersSelector.selectItemsByOrderIds(allAffectedOrderIds);
        Set<Id> inventoryIds = new Set<Id>();
        Map<Id, List<B2B_Order_Item__c>> itemsByOrderId = new Map<Id, List<B2B_Order_Item__c>>();

        for (B2B_Order_Item__c item : orderItems) {
            if (item.Product_Inventory__c != null) {
                inventoryIds.add(item.Product_Inventory__c);
            }
            if (!itemsByOrderId.containsKey(item.B2B_Order__c)) {
                itemsByOrderId.put(item.B2B_Order__c, new List<B2B_Order_Item__c>());
            }
            itemsByOrderId.get(item.B2B_Order__c).add(item);
        }

        if (inventoryIds.isEmpty()) {
            return newlySubmittedOrderIds;
        }

        Map<Id, Product_Inventory__c> inventoriesById = new Map<Id, Product_Inventory__c>(
            ProductInventoriesSelector.selectByIds(inventoryIds)
        );
        Map<Id, Product_Inventory__c> inventoriesToUpdate = new Map<Id, Product_Inventory__c>();

        // Process reservations, cancellations, and shipments in bulk
        for (Id orderId : allAffectedOrderIds) {
            List<B2B_Order_Item__c> items = itemsByOrderId.get(orderId);
            if (items == null || items.isEmpty()) {
                continue;
            }

            B2B_Order__c triggerOrder = newOrdersById.get(orderId);

            for (B2B_Order_Item__c item : items) {
                if (item.Product_Inventory__c == null || !inventoriesById.containsKey(item.Product_Inventory__c)) {
                    continue;
                }
                Product_Inventory__c inv = inventoriesById.get(item.Product_Inventory__c);
                Decimal qty = item.Quantity__c != null ? item.Quantity__c : 0;

                if (newlySubmittedOrderIds.contains(orderId)) {
                    Decimal newReserved = (inv.Reserved_Quantity__c != null ? inv.Reserved_Quantity__c : 0) + qty;
                    if (newReserved > inv.On_Hand_Quantity__c) {
                        triggerOrder.addError(
                            'Insufficient available stock to reserve SKU ' +
                            inv.External_SKU__c +
                            '. Requested: ' +
                            qty +
                            ', Available: ' +
                            (inv.On_Hand_Quantity__c - inv.Reserved_Quantity__c) +
                            '.'
                        );
                        newlySubmittedOrderIds.remove(orderId);
                        break;
                    }
                    inv.Reserved_Quantity__c = newReserved;
                    inventoriesToUpdate.put(inv.Id, inv);
                } else if (cancelledFromReservedOrderIds.contains(orderId)) {
                    Decimal currentReserved = inv.Reserved_Quantity__c != null ? inv.Reserved_Quantity__c : 0;
                    inv.Reserved_Quantity__c = Math.max(0, currentReserved - qty);
                    inventoriesToUpdate.put(inv.Id, inv);
                } else if (shippedFromReservedOrderIds.contains(orderId)) {
                    Decimal currentReserved = inv.Reserved_Quantity__c != null ? inv.Reserved_Quantity__c : 0;
                    Decimal currentOnHand = inv.On_Hand_Quantity__c != null ? inv.On_Hand_Quantity__c : 0;
                    inv.Reserved_Quantity__c = Math.max(0, currentReserved - qty);
                    inv.On_Hand_Quantity__c = Math.max(0, currentOnHand - qty);
                    inventoriesToUpdate.put(inv.Id, inv);
                }
            }
        }

        if (!inventoriesToUpdate.isEmpty()) {
            if (B2BOrderConsoleController.isGuestContext()) {
                Database.update(inventoriesToUpdate.values(), AccessLevel.SYSTEM_MODE);
            } else {
                SObjectAccessDecision decision = Security.stripInaccessible(
                    AccessType.UPDATABLE,
                    inventoriesToUpdate.values()
                );
                Database.update(decision.getRecords(), AccessLevel.USER_MODE);
            }
        }

        return newlySubmittedOrderIds;
    }
}

