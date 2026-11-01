/**
 * @description Thin LWC Controller exposing @AuraEnabled entry points for the B2B Order & Inventory Console.
 *              Enforces strict with sharing + USER_MODE for authenticated users, while supporting
 *              Experience Cloud public portfolio demos for unauthenticated Guest Users.
 */
public with sharing class B2BOrderConsoleController {
    @TestVisible
    private static Boolean forceGuestMode = false;

    /**
     * @description Determines whether the current execution context is an Experience Cloud Guest User
     *              or the Salesforce AutomatedProcess system user (for Platform Event subscribers).
     */
    public static Boolean isGuestContext() {
        String userType = UserInfo.getUserType();
        return forceGuestMode || userType == 'Guest' || userType == 'AutomatedProcess';
    }

    /**
     * @description Returns USER_MODE for authenticated users and SYSTEM_MODE for Experience Cloud Guest demo users.
     */
    public static System.AccessLevel getExecutionAccessLevel() {
        return isGuestContext() ? AccessLevel.SYSTEM_MODE : AccessLevel.USER_MODE;
    }

    /**
     * @description Retrieves B2B Customer Accounts for the Order Builder account selector.
     */
    @AuraEnabled(cacheable=true)
    public static List<Account> getCustomerAccounts() {
        try {
            if (isGuestContext()) {
                return new GuestPortfolioRunner().fetchAccounts();
            }
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
            if (isGuestContext()) {
                return new GuestPortfolioRunner().fetchCatalog(searchTerm, stockStatus);
            }
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
            if (isGuestContext()) {
                return new GuestPortfolioRunner().fetchRecentOrders(accountId);
            }
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
            if (isGuestContext()) {
                return new GuestPortfolioRunner().createOrder(accountId, notes, items, submitOrder);
            }
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
            if (isGuestContext()) {
                return new GuestPortfolioRunner().updateOrderStatus(orderId, newStatus);
            }
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
            if (isGuestContext()) {
                return new GuestPortfolioRunner().syncInventory(inventoryIds);
            }
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
            if (isGuestContext()) {
                return new GuestPortfolioRunner().seedDemo();
            }
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

    /**
     * @description Controlled elevation runner used exclusively when UserInfo.getUserType() == 'Guest'
     *              on the public Experience Cloud portfolio site, allowing inherited sharing classes
     *              to operate for anonymous demo visitors without relaxing internal security.
     */
    private without sharing class GuestPortfolioRunner {
        public List<Account> fetchAccounts() {
            return [
                SELECT Id, Name, Type, Industry, BillingCity, BillingCountry
                FROM Account
                WITH SYSTEM_MODE
                ORDER BY Name ASC
                LIMIT 100
            ];
        }

        public List<Product_Inventory__c> fetchCatalog(String searchTerm, String stockStatus) {
            return ProductInventoriesSelector.selectCatalog(searchTerm, stockStatus);
        }

        public List<B2B_Order__c> fetchRecentOrders(Id accountId) {
            return B2BOrdersSelector.selectRecentOrders(accountId, 50);
        }

        public B2B_Order__c createOrder(
            Id accountId,
            String notes,
            List<B2BOrderService.OrderLineInput> items,
            Boolean submitOrder
        ) {
            return B2BOrderService.createOrder(accountId, notes, items, submitOrder);
        }

        public B2B_Order__c updateOrderStatus(Id orderId, String newStatus) {
            return B2BOrderService.updateOrderStatus(orderId, newStatus);
        }

        public List<Product_Inventory__c> syncInventory(List<Id> inventoryIds) {
            return B2BOrderService.syncInventoryWithErp(inventoryIds);
        }

        public String seedDemo() {
            return B2BOrderService.seedDemoData();
        }
    }
}

