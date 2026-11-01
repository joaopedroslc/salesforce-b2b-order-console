/**
 * @description Platform Event subscriber trigger for Order_Status_Event__e.
 */
trigger OrderStatusEventTrigger on Order_Status_Event__e(after insert) {
    new OrderStatusEventTriggerHandler().run();
}

