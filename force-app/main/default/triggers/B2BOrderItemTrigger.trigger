/**
 * @description Single trigger for B2B_Order_Item__c. Delegates all logic to B2BOrderItemTriggerHandler.
 */
trigger B2BOrderItemTrigger on B2B_Order_Item__c(before insert, before update, before delete) {
    new B2BOrderItemTriggerHandler().run();
}

