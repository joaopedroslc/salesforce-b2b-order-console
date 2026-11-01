/**
 * @description Single trigger for B2B_Order__c. Delegates all logic to B2BOrderTriggerHandler.
 */
trigger B2BOrderTrigger on B2B_Order__c(before insert, before update, after update) {
    new B2BOrderTriggerHandler().run();
}

