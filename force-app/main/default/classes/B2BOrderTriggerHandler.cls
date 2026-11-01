/**
 * @description Trigger Handler for B2B_Order__c.
 *              Strictly routes trigger events to B2BOrdersDomain and triggers async ERP sync when needed.
 */
public inherited sharing class B2BOrderTriggerHandler extends TriggerHandler {
    private static Set<Id> processedSubmittedOrderIds = new Set<Id>();

    protected override void beforeInsert() {
        B2BOrdersDomain.onBeforeInsert((List<B2B_Order__c>) Trigger.new);
    }

    protected override void beforeUpdate() {
        B2BOrdersDomain.onBeforeUpdate(
            (List<B2B_Order__c>) Trigger.new,
            (Map<Id, B2B_Order__c>) Trigger.oldMap
        );
    }

    protected override void afterUpdate() {
        Set<Id> newlySubmittedIds = B2BOrdersDomain.onAfterUpdate(
            (List<B2B_Order__c>) Trigger.new,
            (Map<Id, B2B_Order__c>) Trigger.oldMap
        );

        Set<Id> idsToEnqueue = new Set<Id>();
        for (Id ordId : newlySubmittedIds) {
            if (!processedSubmittedOrderIds.contains(ordId)) {
                idsToEnqueue.add(ordId);
                processedSubmittedOrderIds.add(ordId);
            }
        }

        if (!idsToEnqueue.isEmpty()) {
            enqueueErpSyncIfAvailable(idsToEnqueue);
        }
    }

    /**
     * @description Resets the recursion guard between test phases inside a single test method.
     */
    @TestVisible
    private static void resetProcessedOrders() {
        processedSubmittedOrderIds.clear();
    }

    /**
     * @description Dynamically invokes ERPOrderSyncQueueable if deployed, keeping Layer 4A decoupled.
     * @param orderIds Set of newly submitted B2B_Order__c IDs.
     */
    private static void enqueueErpSyncIfAvailable(Set<Id> orderIds) {
        Type syncServiceType = Type.forName('B2BOrderService');
        if (syncServiceType != null && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            Callable serviceCallable = (Callable) syncServiceType.newInstance();
            serviceCallable.call('enqueueOrderSync', new Map<String, Object>{ 'orderIds' => orderIds });
        }
    }
}

