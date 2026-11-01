/**
 * @description Asynchronous Queueable worker implementing Database.AllowsCallouts.
 *              Synchronizes newly submitted B2B Orders with the external ERP API,
 *              enforcing Salesforce callout governor limits (chaining remaining orders when > 90),
 *              and publishes Order_Status_Event__e Platform Events for downstream subscribers and LWC empApi.
 */
public without sharing class ERPOrderSyncQueueable implements Queueable, Database.AllowsCallouts {
    private static final Integer MAX_CALLOUTS_PER_TRANSACTION = 90;
    private final Set<Id> orderIds;

    public ERPOrderSyncQueueable(Set<Id> orderIds) {
        this.orderIds = orderIds != null ? new Set<Id>(orderIds) : new Set<Id>();
    }

    public void execute(QueueableContext context) {
        if (this.orderIds.isEmpty()) {
            return;
        }

        List<B2B_Order__c> ordersWithItems = B2BOrdersSelector.selectByIdsWithItems(this.orderIds);
        if (ordersWithItems.isEmpty()) {
            return;
        }

        List<Order_Status_Event__e> statusEvents = new List<Order_Status_Event__e>();
        Set<Id> remainingOrderIds = new Set<Id>();

        for (B2B_Order__c ord : ordersWithItems) {
            if (
                Limits.getCallouts() < MAX_CALLOUTS_PER_TRANSACTION &&
                Limits.getCallouts() < Limits.getLimitCallouts()
            ) {
                ERPInventoryCalloutService.ErpOrderSyncResult syncResult = ERPInventoryCalloutService.sendOrderToErp(
                    ord
                );

                statusEvents.add(
                    new Order_Status_Event__e(
                        Order_Id__c = String.valueOf(ord.Id),
                        Target_Status__c = syncResult.targetOrderStatus,
                        ERP_Reference_Id__c = syncResult.erpReferenceId,
                        Sync_Status__c = syncResult.syncStatus,
                        Message__c = syncResult.message
                    )
                );
            } else {
                remainingOrderIds.add(ord.Id);
            }
        }

        if (!statusEvents.isEmpty()) {
            EventBus.publish(statusEvents);
        }

        if (
            !remainingOrderIds.isEmpty() &&
            !Test.isRunningTest() &&
            Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()
        ) {
            System.enqueueJob(new ERPOrderSyncQueueable(remainingOrderIds));
        }
    }
}
