/**
 * @description Test Data Factory for generating Accounts, Products, Product Inventories,
 *              B2B Orders, and B2B Order Items in unit and bulk (200+ record) tests.
 */
@IsTest
public class B2BTestDataFactory {
    /**
     * @description Creates and inserts a B2B Customer Account.
     */
    public static Account createAccount(String name, Boolean doInsert) {
        Account acc = new Account(
            Name = name,
            Type = 'Customer - Direct',
            Industry = 'Manufacturing',
            BillingCity = 'San Francisco'
        );
        if (doInsert) {
            insert acc;
        }
        return acc;
    }

    /**
     * @description Creates a list of Product2 records.
     */
    public static List<Product2> createProducts(Integer count, Boolean doInsert) {
        List<Product2> products = new List<Product2>();
        for (Integer i = 1; i <= count; i++) {
            products.add(
                new Product2(
                    Name = 'Test Industrial Unit ' + i,
                    ProductCode = 'TEST-PROD-' + i,
                    Family = 'Robotics & Motion',
                    Description = 'Enterprise B2B test product #' + i,
                    IsActive = true
                )
            );
        }
        if (doInsert) {
            insert products;
        }
        return products;
    }

    /**
     * @description Creates Product_Inventory__c records for a given list of Product2 records.
     */
    public static List<Product_Inventory__c> createInventories(
        List<Product2> products,
        Decimal onHandQty,
        Decimal unitPrice,
        Boolean doInsert
    ) {
        List<Product_Inventory__c> inventories = new List<Product_Inventory__c>();
        Integer idx = 1;
        for (Product2 prod : products) {
            inventories.add(
                new Product_Inventory__c(
                    Product__c = prod.Id,
                    External_SKU__c = 'SKU-TEST-' + idx,
                    On_Hand_Quantity__c = onHandQty,
                    Reserved_Quantity__c = 0,
                    Unit_Price__c = unitPrice,
                    Reorder_Threshold__c = 10
                )
            );
            idx++;
        }
        if (doInsert) {
            insert inventories;
        }
        return inventories;
    }

    /**
     * @description Creates B2B_Order__c records in Draft status for the specified Account.
     */
    public static List<B2B_Order__c> createDraftOrders(Id accountId, Integer count, Boolean doInsert) {
        List<B2B_Order__c> orders = new List<B2B_Order__c>();
        for (Integer i = 1; i <= count; i++) {
            orders.add(
                new B2B_Order__c(
                    Account__c = accountId,
                    Status__c = B2BOrdersDomain.STATUS_DRAFT,
                    Notes__c = 'Bulk test order #' + i
                )
            );
        }
        if (doInsert) {
            insert orders;
        }
        return orders;
    }
}
