/**
 * @description Trigger Handler for B2B_Order_Item__c.
 *              Strictly routes trigger events to B2BOrderItemsDomain.
 */
public inherited sharing class B2BOrderItemTriggerHandler extends TriggerHandler {
    protected override void beforeInsert() {
        B2BOrderItemsDomain.onBeforeInsert((List<B2B_Order_Item__c>) Trigger.new);
    }

    protected override void beforeUpdate() {
        B2BOrderItemsDomain.onBeforeUpdate(
            (List<B2B_Order_Item__c>) Trigger.new,
            (Map<Id, B2B_Order_Item__c>) Trigger.oldMap
        );
    }

    protected override void beforeDelete() {
        B2BOrderItemsDomain.onBeforeDelete((List<B2B_Order_Item__c>) Trigger.old);
    }
}

