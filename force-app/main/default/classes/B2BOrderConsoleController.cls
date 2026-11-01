/**
 * @description Thin LWC Controller exposing @AuraEnabled entry points for the B2B Order & Inventory Console.
 *              Delegates all business logic and queries to B2BOrderService and Selector classes.
 */
public with sharing class B2BOrderConsoleController {
    /**
     * @description Retrieves B2B Customer Accounts for the Order Builder account selector.
     */
    @AuraEnabled(cacheable=true)
    public static List<Account> getCustomerAccounts() {
        try {
            return [
                SELECT Id, Name, Type, Industry, BillingCity, BillingCountry
                FROM Account
                WITH USER_MODE
                ORDER BY Name ASC
                LIMIT 100
            ];
        } catch (Exception ex) {
            throw buildAuraException(ex.getMessage());
        }
    }

    /**
     * @description Retrieves catalog Product_Inventory__c records filtered by search term and stock status.
     */
    @AuraEnabled(cacheable=true)
    public static List<Product_Inventory__c> getCatalogInventory(String searchTerm, String stockStatus) {
        try {
            return ProductInventoriesSelector.selectCatalog(searchTerm, stockStatus);
        } catch (Exception ex) {
            throw buildAuraException(ex.getMessage());
        }
    }

    /**
     * @description Retrieves recent B2B_Order__c records with child line items.
     */
    @AuraEnabled(cacheable=true)
    public static List<B2B_Order__c> getRecentOrders(Id accountId) {
        try {
            return B2BOrdersSelector.selectRecentOrders(accountId, 50);
        } catch (Exception ex) {
            throw buildAuraException(ex.getMessage());
        }
    }

    /**
     * @description Creates a B2B Order with line items and optionally submits it immediately.
     */
    @AuraEnabled
    public static B2B_Order__c saveOrder(
        Id accountId,
        String notes,
        List<B2BOrderService.OrderLineInput> items,
        Boolean submitOrder
    ) {
        try {
            return B2BOrderService.createOrder(accountId, notes, items, submitOrder);
        } catch (Exception ex) {
            throw buildAuraException(ex.getMessage());
        }
    }

    /**
     * @description Transitions an existing B2B Order to a new status (Submitted, Shipped, Cancelled).
     */
    @AuraEnabled
    public static B2B_Order__c changeOrderStatus(Id orderId, String newStatus) {
        try {
            return B2BOrderService.updateOrderStatus(orderId, newStatus);
        } catch (Exception ex) {
            throw buildAuraException(ex.getMessage());
        }
    }

    /**
     * @description Triggers a live outbound REST sync with the external ERP API via Named Credential.
     */
    @AuraEnabled
    public static List<Product_Inventory__c> syncCatalogWithErp(List<Id> inventoryIds) {
        try {
            return B2BOrderService.syncInventoryWithErp(inventoryIds);
        } catch (Exception ex) {
            throw buildAuraException(ex.getMessage());
        }
    }

    /**
     * @description Seeds sample B2B Accounts, Products, and Inventory records for immediate demo use.
     */
    @AuraEnabled
    public static String seedSampleCatalog() {
        try {
            return B2BOrderService.seedDemoData();
        } catch (Exception ex) {
            throw buildAuraException(ex.getMessage());
        }
    }

    private static AuraHandledException buildAuraException(String message) {
        AuraHandledException err = new AuraHandledException(message);
        err.setMessage(message);
        return err;
    }
}

