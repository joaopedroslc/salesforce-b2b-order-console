/**
 * @description Single trigger for Product_Inventory__c. Delegates all logic to ProductInventoryTriggerHandler.
 */
trigger ProductInventoryTrigger on Product_Inventory__c(before insert, before update) {
    new ProductInventoryTriggerHandler().run();
}

