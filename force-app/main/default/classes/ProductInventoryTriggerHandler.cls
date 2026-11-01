/**
 * @description Trigger Handler for Product_Inventory__c.
 *              Strictly routes trigger events to ProductInventoriesDomain.
 */
public inherited sharing class ProductInventoryTriggerHandler extends TriggerHandler {
    protected override void beforeInsert() {
        ProductInventoriesDomain.onBeforeInsert((List<Product_Inventory__c>) Trigger.new);
    }

    protected override void beforeUpdate() {
        ProductInventoriesDomain.onBeforeUpdate(
            (List<Product_Inventory__c>) Trigger.new,
            (Map<Id, Product_Inventory__c>) Trigger.oldMap
        );
    }
}

