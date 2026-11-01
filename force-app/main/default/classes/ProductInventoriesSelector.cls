/**
 * @description Selector Layer for Product_Inventory__c and related Product2 data.
 *              Centralizes all SOQL queries with strict WITH USER_MODE security enforcement.
 */
public inherited sharing class ProductInventoriesSelector {
    /**
     * @description Selects Product_Inventory__c records by their Salesforce IDs.
     * @param inventoryIds Set of Product_Inventory__c IDs.
     * @return List of Product_Inventory__c records with related Product2 fields.
     */
    public static List<Product_Inventory__c> selectByIds(Set<Id> inventoryIds) {
        if (inventoryIds == null || inventoryIds.isEmpty()) {
            return new List<Product_Inventory__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Product__c,
                Product__r.Name,
                Product__r.ProductCode,
                Product__r.Family,
                Product__r.Description,
                Product__r.IsActive,
                External_SKU__c,
                Unit_Price__c,
                On_Hand_Quantity__c,
                Reserved_Quantity__c,
                Available_Quantity__c,
                Reorder_Threshold__c,
                Stock_Status__c,
                Last_ERP_Sync__c
            FROM Product_Inventory__c
            WHERE Id IN :inventoryIds
            WITH USER_MODE
            ORDER BY Product__r.Name ASC
        ];
    }

    /**
     * @description Selects Product_Inventory__c records by their parent Product2 IDs.
     * @param productIds Set of Product2 IDs.
     * @return List of matching Product_Inventory__c records.
     */
    public static List<Product_Inventory__c> selectByProductIds(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new List<Product_Inventory__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Product__c,
                Product__r.Name,
                Product__r.ProductCode,
                Product__r.Family,
                External_SKU__c,
                Unit_Price__c,
                On_Hand_Quantity__c,
                Reserved_Quantity__c,
                Available_Quantity__c,
                Reorder_Threshold__c,
                Stock_Status__c,
                Last_ERP_Sync__c
            FROM Product_Inventory__c
            WHERE Product__c IN :productIds
            WITH USER_MODE
            ORDER BY Product__r.Name ASC
        ];
    }

    /**
     * @description Selects Product_Inventory__c records by External SKU codes.
     * @param externalSkus Set of External_SKU__c strings.
     * @return List of matching Product_Inventory__c records.
     */
    public static List<Product_Inventory__c> selectByExternalSkus(Set<String> externalSkus) {
        if (externalSkus == null || externalSkus.isEmpty()) {
            return new List<Product_Inventory__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Product__c,
                Product__r.Name,
                Product__r.ProductCode,
                External_SKU__c,
                Unit_Price__c,
                On_Hand_Quantity__c,
                Reserved_Quantity__c,
                Available_Quantity__c,
                Reorder_Threshold__c,
                Stock_Status__c,
                Last_ERP_Sync__c
            FROM Product_Inventory__c
            WHERE External_SKU__c IN :externalSkus
            WITH USER_MODE
            ORDER BY External_SKU__c ASC
        ];
    }

    /**
     * @description Searches catalog inventory records by search term and optional stock status filter.
     * @param searchTerm Optional substring matching Product Name, ProductCode, or External SKU.
     * @param stockStatus Optional filter ('In Stock', 'Low Stock', 'Out of Stock').
     * @return List of matching Product_Inventory__c records.
     */
    public static List<Product_Inventory__c> selectCatalog(String searchTerm, String stockStatus) {
        String cleanSearch = String.isNotBlank(searchTerm) ? '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%' : null;
        String cleanStatus = String.isNotBlank(stockStatus) && stockStatus != 'All'
            ? String.escapeSingleQuotes(stockStatus.trim())
            : null;

        if (cleanSearch != null && cleanStatus != null) {
            return [
                SELECT
                    Id,
                    Name,
                    Product__c,
                    Product__r.Name,
                    Product__r.ProductCode,
                    Product__r.Family,
                    Product__r.Description,
                    External_SKU__c,
                    Unit_Price__c,
                    On_Hand_Quantity__c,
                    Reserved_Quantity__c,
                    Available_Quantity__c,
                    Reorder_Threshold__c,
                    Stock_Status__c,
                    Last_ERP_Sync__c
                FROM Product_Inventory__c
                WHERE
                    (Product__r.Name LIKE :cleanSearch
                    OR Product__r.ProductCode LIKE :cleanSearch
                    OR External_SKU__c LIKE :cleanSearch)
                    AND Stock_Status__c = :cleanStatus
                WITH USER_MODE
                ORDER BY Product__r.Name ASC
                LIMIT 200
            ];
        } else if (cleanSearch != null) {
            return [
                SELECT
                    Id,
                    Name,
                    Product__c,
                    Product__r.Name,
                    Product__r.ProductCode,
                    Product__r.Family,
                    Product__r.Description,
                    External_SKU__c,
                    Unit_Price__c,
                    On_Hand_Quantity__c,
                    Reserved_Quantity__c,
                    Available_Quantity__c,
                    Reorder_Threshold__c,
                    Stock_Status__c,
                    Last_ERP_Sync__c
                FROM Product_Inventory__c
                WHERE
                    Product__r.Name LIKE :cleanSearch
                    OR Product__r.ProductCode LIKE :cleanSearch
                    OR External_SKU__c LIKE :cleanSearch
                WITH USER_MODE
                ORDER BY Product__r.Name ASC
                LIMIT 200
            ];
        } else if (cleanStatus != null) {
            return [
                SELECT
                    Id,
                    Name,
                    Product__c,
                    Product__r.Name,
                    Product__r.ProductCode,
                    Product__r.Family,
                    Product__r.Description,
                    External_SKU__c,
                    Unit_Price__c,
                    On_Hand_Quantity__c,
                    Reserved_Quantity__c,
                    Available_Quantity__c,
                    Reorder_Threshold__c,
                    Stock_Status__c,
                    Last_ERP_Sync__c
                FROM Product_Inventory__c
                WHERE Stock_Status__c = :cleanStatus
                WITH USER_MODE
                ORDER BY Product__r.Name ASC
                LIMIT 200
            ];
        }

        return [
            SELECT
                Id,
                Name,
                Product__c,
                Product__r.Name,
                Product__r.ProductCode,
                Product__r.Family,
                Product__r.Description,
                External_SKU__c,
                Unit_Price__c,
                On_Hand_Quantity__c,
                Reserved_Quantity__c,
                Available_Quantity__c,
                Reorder_Threshold__c,
                Stock_Status__c,
                Last_ERP_Sync__c
            FROM Product_Inventory__c
            WITH USER_MODE
            ORDER BY Product__r.Name ASC
            LIMIT 200
        ];
    }
}

