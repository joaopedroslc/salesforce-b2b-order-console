/**
 * @description Configurable HttpCalloutMock for testing ERPInventoryCalloutService and ERPOrderSyncQueueable
 *              across 200 OK (Confirmed), 409 Conflict (Backordered), and 500 Server Error scenarios.
 */
@IsTest
public class ERPInventoryHttpCalloutMock implements HttpCalloutMock {
    private final Integer statusCode;
    private final String statusText;
    private final Map<String, Object> customResponseMap;

    public ERPInventoryHttpCalloutMock(Integer statusCode, String statusText, Map<String, Object> customResponseMap) {
        this.statusCode = statusCode;
        this.statusText = statusText;
        this.customResponseMap = customResponseMap;
    }

    public static ERPInventoryHttpCalloutMock buildSuccessOrderMock(String erpRef) {
        return new ERPInventoryHttpCalloutMock(
            200,
            'OK',
            new Map<String, Object>{
                'status' => 'CONFIRMED',
                'erpReferenceId' => erpRef
            }
        );
    }

    public static ERPInventoryHttpCalloutMock buildBackorderMock() {
        return new ERPInventoryHttpCalloutMock(
            409,
            'Conflict',
            new Map<String, Object>{ 'status' => 'BACKORDERED' }
        );
    }

    public static ERPInventoryHttpCalloutMock buildServerErrorMock() {
        return new ERPInventoryHttpCalloutMock(
            500,
            'Internal Server Error',
            new Map<String, Object>{ 'error' => 'ERP gateway timeout' }
        );
    }

    public static ERPInventoryHttpCalloutMock buildInventorySyncMock(Map<String, Decimal> stockLevels) {
        return new ERPInventoryHttpCalloutMock(
            200,
            'OK',
            new Map<String, Object>{ 'stockLevels' => stockLevels }
        );
    }

    public HttpResponse respond(HttpRequest req) {
        System.assertNotEquals(null, req.getEndpoint(), 'Endpoint must be populated on outbound ERP request.');
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setStatusCode(this.statusCode);
        res.setStatus(this.statusText);
        res.setBody(JSON.serialize(this.customResponseMap != null ? this.customResponseMap : new Map<String, Object>()));
        return res;
    }
}

