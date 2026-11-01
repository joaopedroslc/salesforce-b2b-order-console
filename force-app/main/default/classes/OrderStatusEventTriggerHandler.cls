/**
 * @description Trigger Handler for Order_Status_Event__e Platform Events.
 *              Routes received events to B2BOrderService for order confirmation/backorder updates.
 */
public inherited sharing class OrderStatusEventTriggerHandler extends TriggerHandler {
    protected override void afterInsert() {
        B2BOrderService.applyOrderStatusEvents((List<Order_Status_Event__e>) Trigger.new);
    }
}

