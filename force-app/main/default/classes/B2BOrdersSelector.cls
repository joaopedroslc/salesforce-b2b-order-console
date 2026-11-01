/**
 * @description Selector Layer for B2B_Order__c and B2B_Order_Item__c.
 *              Centralizes all SOQL queries with strict WITH USER_MODE security enforcement.
 */
public inherited sharing class B2BOrdersSelector {
    /**
     * @description Selects B2B_Order__c headers by ID.
     * @param orderIds Set of B2B_Order__c IDs.
     * @return List of B2B_Order__c records.
     */
    public static List<B2B_Order__c> selectByIds(Set<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) {
            return new List<B2B_Order__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Account__c,
                Account__r.Name,
                Status__c,
                Total_Amount__c,
                Total_Items__c,
                ERP_Reference_Id__c,
                ERP_Sync_Status__c,
                ERP_Sync_Message__c,
                Submitted_Date__c,
                Notes__c,
                CreatedDate
            FROM B2B_Order__c
            WHERE Id IN :orderIds
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ];
    }

    /**
     * @description Selects B2B_Order__c records along with their child B2B_Order_Items__r.
     * @param orderIds Set of B2B_Order__c IDs.
     * @return List of B2B_Order__c records with child line items.
     */
    public static List<B2B_Order__c> selectByIdsWithItems(Set<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) {
            return new List<B2B_Order__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Account__c,
                Account__r.Name,
                Status__c,
                Total_Amount__c,
                Total_Items__c,
                ERP_Reference_Id__c,
                ERP_Sync_Status__c,
                ERP_Sync_Message__c,
                Submitted_Date__c,
                Notes__c,
                CreatedDate,
                (
                    SELECT
                        Id,
                        Name,
                        B2B_Order__c,
                        Product__c,
                        Product__r.Name,
                        Product__r.ProductCode,
                        Product_Inventory__c,
                        Product_Inventory__r.External_SKU__c,
                        Quantity__c,
                        Unit_Price__c,
                        Line_Total__c
                    FROM B2B_Order_Items__r
                    ORDER BY Name ASC
                )
            FROM B2B_Order__c
            WHERE Id IN :orderIds
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ];
    }

    /**
     * @description Selects recent B2B_Order__c records (optionally filtered by Account ID) with line items.
     * @param accountId Optional Account ID filter. If null, returns recent orders across accessible Accounts.
     * @param limitCount Maximum number of orders to return (defaults to 50).
     * @return List of B2B_Order__c records with child items.
     */
    public static List<B2B_Order__c> selectRecentOrders(Id accountId, Integer limitCount) {
        Integer rowLimit = (limitCount != null && limitCount > 0 && limitCount <= 200) ? limitCount : 50;

        if (accountId != null) {
            return [
                SELECT
                    Id,
                    Name,
                    Account__c,
                    Account__r.Name,
                    Status__c,
                    Total_Amount__c,
                    Total_Items__c,
                    ERP_Reference_Id__c,
                    ERP_Sync_Status__c,
                    ERP_Sync_Message__c,
                    Submitted_Date__c,
                    Notes__c,
                    CreatedDate,
                    (
                        SELECT
                            Id,
                            Name,
                            Product__c,
                            Product__r.Name,
                            Product__r.ProductCode,
                            Product_Inventory__c,
                            Quantity__c,
                            Unit_Price__c,
                            Line_Total__c
                        FROM B2B_Order_Items__r
                        ORDER BY Name ASC
                    )
                FROM B2B_Order__c
                WHERE Account__c = :accountId
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT :rowLimit
            ];
        }

        return [
            SELECT
                Id,
                Name,
                Account__c,
                Account__r.Name,
                Status__c,
                Total_Amount__c,
                Total_Items__c,
                ERP_Reference_Id__c,
                ERP_Sync_Status__c,
                ERP_Sync_Message__c,
                Submitted_Date__c,
                Notes__c,
                CreatedDate,
                (
                    SELECT
                        Id,
                        Name,
                        Product__c,
                        Product__r.Name,
                        Product__r.ProductCode,
                        Product_Inventory__c,
                        Quantity__c,
                        Unit_Price__c,
                        Line_Total__c
                    FROM B2B_Order_Items__r
                    ORDER BY Name ASC
                )
            FROM B2B_Order__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :rowLimit
        ];
    }

    /**
     * @description Selects all B2B_Order_Item__c records belonging to the specified B2B_Order__c IDs.
     * @param orderIds Set of parent B2B_Order__c IDs.
     * @return List of B2B_Order_Item__c records.
     */
    public static List<B2B_Order_Item__c> selectItemsByOrderIds(Set<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) {
            return new List<B2B_Order_Item__c>();
        }
        return [
            SELECT
                Id,
                Name,
                B2B_Order__c,
                Product__c,
                Product__r.Name,
                Product__r.ProductCode,
                Product_Inventory__c,
                Product_Inventory__r.External_SKU__c,
                Quantity__c,
                Unit_Price__c,
                Line_Total__c
            FROM B2B_Order_Item__c
            WHERE B2B_Order__c IN :orderIds
            WITH USER_MODE
            ORDER BY Name ASC
        ];
    }
}

