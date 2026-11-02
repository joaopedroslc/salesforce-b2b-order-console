/**
 * @description Domain Layer for Product_Inventory__c.
 *              Enforces field defaults, uppercase SKU normalization, and non-negative stock invariants.
 */
public inherited sharing class ProductInventoriesDomain {
    public static final Decimal DEFAULT_REORDER_THRESHOLD = 10;

    /**
     * @description Validates and applies defaults before inserting Product_Inventory__c records.
     * @param newRecords List of new Product_Inventory__c records from Trigger.new.
     */
    public static void onBeforeInsert(List<Product_Inventory__c> newRecords) {
        applyDefaultsAndValidate(newRecords);
    }

    /**
     * @description Validates invariants before updating Product_Inventory__c records.
     * @param newRecords List of updated Product_Inventory__c records from Trigger.new.
     * @param oldMap Map of prior Product_Inventory__c states from Trigger.oldMap.
     */
    @SuppressWarnings('PMD.UnusedFormalParameter')
    public static void onBeforeUpdate(
        List<Product_Inventory__c> newRecords,
        Map<Id, Product_Inventory__c> oldMap
    ) {
        applyDefaultsAndValidate(newRecords);
    }

    private static void applyDefaultsAndValidate(List<Product_Inventory__c> records) {
        for (Product_Inventory__c inv : records) {
            if (inv.Product__c == null) {
                inv.Product__c.addError('A Catalog Product (Product2) is required for every Product Inventory record.');
            }

            if (String.isNotBlank(inv.External_SKU__c)) {
                inv.External_SKU__c = inv.External_SKU__c.trim().toUpperCase();
            } else {
                inv.External_SKU__c.addError('External SKU is required.');
            }

            if (inv.On_Hand_Quantity__c == null) {
                inv.On_Hand_Quantity__c = 0;
            }
            if (inv.Reserved_Quantity__c == null) {
                inv.Reserved_Quantity__c = 0;
            }
            if (inv.Unit_Price__c == null) {
                inv.Unit_Price__c = 0;
            }
            if (inv.Reorder_Threshold__c == null) {
                inv.Reorder_Threshold__c = DEFAULT_REORDER_THRESHOLD;
            }

            if (inv.On_Hand_Quantity__c < 0) {
                inv.On_Hand_Quantity__c.addError('On Hand Quantity cannot be negative.');
            }
            if (inv.Reserved_Quantity__c < 0) {
                inv.Reserved_Quantity__c.addError('Reserved Quantity cannot be negative.');
            }
            if (inv.Unit_Price__c < 0) {
                inv.Unit_Price__c.addError('Unit Price cannot be negative.');
            }
            if (inv.Reserved_Quantity__c > inv.On_Hand_Quantity__c) {
                inv.Reserved_Quantity__c.addError(
                    'Reserved Quantity (' +
                    inv.Reserved_Quantity__c +
                    ') cannot exceed On Hand Quantity (' +
                    inv.On_Hand_Quantity__c +
                    ').'
                );
            }
        }
    }
}

