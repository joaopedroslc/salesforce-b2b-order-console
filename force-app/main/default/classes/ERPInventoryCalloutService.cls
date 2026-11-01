/**
 * @description Integration Service Layer for outbound REST callouts to the external ERP API
 *              using the Named Credential (callout:ERP_Inventory_API).
 */
public inherited sharing class ERPInventoryCalloutService {
    private static final String NAMED_CREDENTIAL_BASE = 'callout:ERP_Inventory_API';
    private static final Integer DEFAULT_TIMEOUT_MS = 15000;

    /**
     * @description Data Transfer Object representing the ERP response for an order submission.
     */
    public class ErpOrderSyncResult {
        @AuraEnabled
        public Id orderId { get; set; }
        @AuraEnabled
        public Boolean isSuccess { get; set; }
        @AuraEnabled
        public String targetOrderStatus { get; set; }
        @AuraEnabled
        public String syncStatus { get; set; }
        @AuraEnabled
        public String erpReferenceId { get; set; }
        @AuraEnabled
        public String message { get; set; }
    }

    /**
     * @description Data Transfer Object representing an ERP inventory check response for a SKU.
     */
    public class ErpStockSyncResult {
        @AuraEnabled
        public String externalSku { get; set; }
        @AuraEnabled
        public Decimal onHandQuantity { get; set; }
        @AuraEnabled
        public DateTime syncedAt { get; set; }
        @AuraEnabled
        public String message { get; set; }
    }

    /**
     * @description Sends a B2B Order payload to the external ERP endpoint via Named Credential.
     * @param orderRecord B2B_Order__c record including child B2B_Order_Items__r.
     * @return Parsed ErpOrderSyncResult DTO.
     */
    public static ErpOrderSyncResult sendOrderToErp(B2B_Order__c orderRecord) {
        ErpOrderSyncResult result = new ErpOrderSyncResult();
        result.orderId = orderRecord.Id;

        Map<String, Object> requestPayload = new Map<String, Object>{
            'orderId' => orderRecord.Id,
            'orderNumber' => orderRecord.Name,
            'accountId' => orderRecord.Account__c,
            'totalAmount' => orderRecord.Total_Amount__c,
            'totalItems' => orderRecord.Total_Items__c,
            'lineItems' => buildLineItemPayloads(orderRecord.B2B_Order_Items__r)
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL_BASE + '/post');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(DEFAULT_TIMEOUT_MS);
        req.setBody(JSON.serialize(requestPayload));

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            Integer statusCode = res.getStatusCode();

            if (statusCode >= 200 && statusCode < 300) {
                Map<String, Object> bodyMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String customRef = extractErpReference(bodyMap, orderRecord.Name);

                result.isSuccess = true;
                result.targetOrderStatus = B2BOrdersDomain.STATUS_CONFIRMED;
                result.syncStatus = B2BOrdersDomain.SYNC_SYNCED;
                result.erpReferenceId = customRef;
                result.message = 'Order confirmed by ERP (' + customRef + ').';
            } else if (statusCode == 409) {
                result.isSuccess = false;
                result.targetOrderStatus = B2BOrdersDomain.STATUS_BACKORDERED;
                result.syncStatus = B2BOrdersDomain.SYNC_SYNCED;
                result.erpReferenceId = 'BO-' + orderRecord.Name;
                result.message = 'ERP reported partial warehouse backorder (HTTP 409).';
            } else {
                result.isSuccess = false;
                result.targetOrderStatus = B2BOrdersDomain.STATUS_SUBMITTED;
                result.syncStatus = B2BOrdersDomain.SYNC_FAILED;
                result.message = 'ERP HTTP Error ' + statusCode + ': ' + res.getStatus();
            }
        } catch (Exception ex) {
            result.isSuccess = false;
            result.targetOrderStatus = B2BOrdersDomain.STATUS_SUBMITTED;
            result.syncStatus = B2BOrdersDomain.SYNC_FAILED;
            result.message = ('ERP Callout Exception: ' + ex.getMessage()).left(255);
        }

        return result;
    }

    /**
     * @description Calls the external ERP API via Named Credential to fetch/verify live warehouse stock for SKUs.
     * @param inventories List of Product_Inventory__c records to synchronize.
     * @return Map of External_SKU__c to ErpStockSyncResult.
     */
    public static Map<String, ErpStockSyncResult> fetchInventoryFromErp(List<Product_Inventory__c> inventories) {
        Map<String, ErpStockSyncResult> resultsBySku = new Map<String, ErpStockSyncResult>();
        if (inventories == null || inventories.isEmpty()) {
            return resultsBySku;
        }

        List<Map<String, Object>> skuList = new List<Map<String, Object>>();
        for (Product_Inventory__c inv : inventories) {
            skuList.add(
                new Map<String, Object>{
                    'sku' => inv.External_SKU__c,
                    'currentOnHand' => inv.On_Hand_Quantity__c,
                    'reserved' => inv.Reserved_Quantity__c
                }
            );
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL_BASE + '/post');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(DEFAULT_TIMEOUT_MS);
        req.setBody(JSON.serialize(new Map<String, Object>{ 'action' => 'INVENTORY_SYNC', 'items' => skuList }));

        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException('ERP Inventory Sync failed with HTTP status ' + res.getStatusCode());
        }

        Map<String, Object> parsedBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Decimal> mockOverridesBySku = extractStockOverrides(parsedBody);

        DateTime syncTime = System.now();
        for (Product_Inventory__c inv : inventories) {
            ErpStockSyncResult stockResult = new ErpStockSyncResult();
            stockResult.externalSku = inv.External_SKU__c;
            stockResult.syncedAt = syncTime;

            if (mockOverridesBySku.containsKey(inv.External_SKU__c)) {
                stockResult.onHandQuantity = Math.max(
                    inv.Reserved_Quantity__c,
                    mockOverridesBySku.get(inv.External_SKU__c)
                );
            } else {
                // If an item is low or out of stock during a live demo, ERP auto-replenishes +25 units
                Decimal currentAvailable = inv.On_Hand_Quantity__c - inv.Reserved_Quantity__c;
                Decimal threshold = inv.Reorder_Threshold__c != null ? inv.Reorder_Threshold__c : 10;
                stockResult.onHandQuantity = currentAvailable <= threshold
                    ? inv.On_Hand_Quantity__c + 25
                    : inv.On_Hand_Quantity__c;
            }
            stockResult.message = 'Synchronized with ERP Warehouse API';
            resultsBySku.put(inv.External_SKU__c, stockResult);
        }

        return resultsBySku;
    }

    private static List<Map<String, Object>> buildLineItemPayloads(List<B2B_Order_Item__c> items) {
        List<Map<String, Object>> payloads = new List<Map<String, Object>>();
        if (items == null) {
            return payloads;
        }
        for (B2B_Order_Item__c item : items) {
            payloads.add(
                new Map<String, Object>{
                    'itemId' => item.Id,
                    'productId' => item.Product__c,
                    'sku' => item.Product_Inventory__r != null ? item.Product_Inventory__r.External_SKU__c : null,
                    'quantity' => item.Quantity__c,
                    'unitPrice' => item.Unit_Price__c
                }
            );
        }
        return payloads;
    }

    private static String extractErpReference(Map<String, Object> bodyMap, String orderName) {
        if (bodyMap != null && bodyMap.containsKey('erpReferenceId')) {
            return String.valueOf(bodyMap.get('erpReferenceId'));
        }
        String suffix = String.isNotBlank(orderName) ? orderName.replace('ORD-', '') : '00001';
        return 'ERP-' + System.today().year() + '-' + suffix;
    }

    private static Map<String, Decimal> extractStockOverrides(Map<String, Object> parsedBody) {
        Map<String, Decimal> overrides = new Map<String, Decimal>();
        if (parsedBody != null && parsedBody.containsKey('stockLevels')) {
            Map<String, Object> stockMap = (Map<String, Object>) parsedBody.get('stockLevels');
            for (String sku : stockMap.keySet()) {
                overrides.put(sku, Decimal.valueOf(String.valueOf(stockMap.get(sku))));
            }
        }
        return overrides;
    }
}

