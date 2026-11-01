/**
 * @description Selector Layer for Product_Inventory__c and related Product2 data.
 *              Centralizes all SOQL queries with strict AccessLevel.USER_MODE enforcement
 *              (and Experience Cloud Guest demo support via B2BOrderConsoleController.getExecutionAccessLevel()).
 */
public inherited sharing class ProductInventoriesSelector {
    private static final String BASE_FIELDS =
        'Id, Name, Product__c, Product__r.Name, Product__r.ProductCode, ' +
        'Product__r.Family, Product__r.Description, Product__r.IsActive, ' +
        'External_SKU__c, Unit_Price__c, On_Hand_Quantity__c, Reserved_Quantity__c, ' +
        'Available_Quantity__c, Reorder_Threshold__c, Stock_Status__c, Last_ERP_Sync__c';

    /**
     * @description Selects Product_Inventory__c records by their Salesforce IDs.
     * @param inventoryIds Set of Product_Inventory__c IDs.
     * @return List of Product_Inventory__c records with related Product2 fields.
     */
    public static List<Product_Inventory__c> selectByIds(Set<Id> inventoryIds) {
        if (inventoryIds == null || inventoryIds.isEmpty()) {
            return new List<Product_Inventory__c>();
        }
        String soql =
            'SELECT ' +
            BASE_FIELDS +
            ' FROM Product_Inventory__c WHERE Id IN :inventoryIds ORDER BY Product__r.Name ASC';
        return (List<Product_Inventory__c>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'inventoryIds' => inventoryIds },
            B2BOrderConsoleController.getExecutionAccessLevel()
        );
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
        String soql =
            'SELECT ' +
            BASE_FIELDS +
            ' FROM Product_Inventory__c WHERE Product__c IN :productIds ORDER BY Product__r.Name ASC';
        return (List<Product_Inventory__c>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'productIds' => productIds },
            B2BOrderConsoleController.getExecutionAccessLevel()
        );
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
        String soql =
            'SELECT ' +
            BASE_FIELDS +
            ' FROM Product_Inventory__c WHERE External_SKU__c IN :externalSkus ORDER BY External_SKU__c ASC';
        return (List<Product_Inventory__c>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'externalSkus' => externalSkus },
            B2BOrderConsoleController.getExecutionAccessLevel()
        );
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

        Map<String, Object> binds = new Map<String, Object>();
        List<String> whereClauses = new List<String>();

        if (cleanSearch != null) {
            binds.put('cleanSearch', cleanSearch);
            whereClauses.add(
                '(Product__r.Name LIKE :cleanSearch OR Product__r.ProductCode LIKE :cleanSearch OR External_SKU__c LIKE :cleanSearch)'
            );
        }
        if (cleanStatus != null) {
            binds.put('cleanStatus', cleanStatus);
            whereClauses.add('Stock_Status__c = :cleanStatus');
        }

        String soql = 'SELECT ' + BASE_FIELDS + ' FROM Product_Inventory__c';
        if (!whereClauses.isEmpty()) {
            soql += ' WHERE ' + String.join(whereClauses, ' AND ');
        }
        soql += ' ORDER BY Product__r.Name ASC LIMIT 200';

        return (List<Product_Inventory__c>) Database.queryWithBinds(
            soql,
            binds,
            B2BOrderConsoleController.getExecutionAccessLevel()
        );
    }
}

