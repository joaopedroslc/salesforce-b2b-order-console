import { LightningElement, wire } from 'lwc';
import { publish, subscribe as lmsSubscribe, unsubscribe as lmsUnsubscribe, APPLICATION_SCOPE, MessageContext } from 'lightning/messageService';
import { subscribe as empSubscribe, unsubscribe as empUnsubscribe, onError as empOnError } from 'lightning/empApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import B2B_ORDER_CHANNEL from '@salesforce/messageChannel/B2B_Order_Channel__c';
import getRecentOrders from '@salesforce/apex/B2BOrderConsoleController.getRecentOrders';
import changeOrderStatus from '@salesforce/apex/B2BOrderConsoleController.changeOrderStatus';

const PLATFORM_EVENT_CHANNEL = '/event/Order_Status_Event__e';

export default class B2bOrderTracker extends LightningElement {
    filterAccountId = null;
    orders = [];
    isLoading = true;
    isProcessing = false;
    empConnected = false;
    wiredOrdersResult;
    lmsSubscription = null;
    empSubscription = null;

    @wire(MessageContext)
    messageContext;

    @wire(getRecentOrders, { accountId: '$filterAccountId' })
    wiredOrders(result) {
        this.wiredOrdersResult = result;
        this.isLoading = false;
        if (result.data) {
            this.orders = result.data.map((ord) => {
                const status = ord.Status__c || 'Draft';
                const items = (ord.B2B_Order_Items__r || []).map((line) => ({
                    ...line,
                    productName: line.Product__r ? line.Product__r.Name : 'Product'
                }));
                return {
                    ...ord,
                    accountName: ord.Account__r ? ord.Account__r.Name : 'Customer',
                    erpRefDisplay: ord.ERP_Reference_Id__c ? ord.ERP_Reference_Id__c : 'Pending ERP',
                    syncStatusDisplay: ord.ERP_Sync_Status__c || 'Not Started',
                    statusBadgeClass: this.computeSldsOrderBadgeClass(status),
                    canSubmit: status === 'Draft',
                    canShip: status === 'Confirmed' || status === 'Submitted',
                    canCancel:
                        status === 'Draft' ||
                        status === 'Submitted' ||
                        status === 'Confirmed' ||
                        status === 'Backordered',
                    lineItems: items,
                    hasLineItems: items.length > 0
                };
            });
        } else if (result.error) {
            this.showToast('Error Loading Orders', this.reduceError(result.error), 'error');
        }
    }

    connectedCallback() {
        this.subscribeToLms();
        this.subscribeToPlatformEvents();
    }

    disconnectedCallback() {
        if (this.lmsSubscription) {
            lmsUnsubscribe(this.lmsSubscription);
            this.lmsSubscription = null;
        }
        if (this.empSubscription) {
            empUnsubscribe(this.empSubscription, () => {});
            this.empSubscription = null;
        }
    }

    subscribeToLms() {
        if (!this.lmsSubscription) {
            this.lmsSubscription = lmsSubscribe(
                this.messageContext,
                B2B_ORDER_CHANNEL,
                (message) => this.handleLmsMessage(message),
                { scope: APPLICATION_SCOPE }
            );
        }
    }

    handleLmsMessage(message) {
        if (!message) {
            return;
        }
        if (message.actionType === 'ORDER_UPDATED' || message.actionType === 'CATALOG_REFRESH') {
            this.handleRefreshOrders();
            // When running on Experience Cloud (where CometD empApi is unavailable for Guest users),
            // schedule automatic follow-up refreshes so async Queueable + Platform Event updates appear live.
            if (message.actionType === 'ORDER_UPDATED' && !this.empConnected) {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                window.setTimeout(() => {
                    this.handleRefreshOrders();
                }, 2200);
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                window.setTimeout(() => {
                    this.handleRefreshOrders();
                }, 4500);
            }
        }
    }

    async subscribeToPlatformEvents() {
        try {
            const callback = (response) => {
                const payload = response?.data?.payload;
                if (payload) {
                    const targetStatus = payload.Target_Status__c || 'Updated';
                    const erpRef = payload.ERP_Reference_Id__c || '';
                    const msg = payload.Message__c || `Order transitioned to ${targetStatus}.`;
                    this.showToast(
                        `Live ERP Event: ${targetStatus} ${erpRef}`,
                        msg,
                        targetStatus === 'Confirmed' ? 'success' : 'warning'
                    );
                    this.handleRefreshOrders();
                    publish(this.messageContext, B2B_ORDER_CHANNEL, {
                        actionType: 'CATALOG_REFRESH',
                        payload: { orderId: payload.Order_Id__c }
                    });
                }
            };

            this.empSubscription = await empSubscribe(PLATFORM_EVENT_CHANNEL, -1, callback);
            this.empConnected = true;

            empOnError(() => {
                this.empConnected = false;
            });
        } catch {
            this.empConnected = false;
        }
    }

    async handleRefreshOrders() {
        if (this.wiredOrdersResult) {
            await refreshApex(this.wiredOrdersResult);
        }
    }

    async handleStatusAction(event) {
        const orderId = event.currentTarget.dataset.id;
        const nextStatus = event.currentTarget.dataset.status;
        if (!orderId || !nextStatus) {
            return;
        }

        this.isProcessing = true;
        try {
            const updated = await changeOrderStatus({ orderId, newStatus: nextStatus });
            await this.handleRefreshOrders();

            publish(this.messageContext, B2B_ORDER_CHANNEL, {
                actionType: 'ORDER_UPDATED',
                payload: {
                    orderId: updated.Id,
                    status: updated.Status__c
                }
            });

            this.showToast(
                'Order Status Updated',
                `Order ${updated.Name} transitioned to ${updated.Status__c}.`,
                'success'
            );
        } catch (error) {
            this.showToast('Status Update Failed', this.reduceError(error), 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    get hasOrders() {
        return this.orders && this.orders.length > 0;
    }

    computeSldsOrderBadgeClass(status) {
        if (status === 'Confirmed' || status === 'Shipped') {
            return 'slds-badge slds-theme_success';
        }
        if (status === 'Submitted' || status === 'Backordered') {
            return 'slds-badge slds-theme_warning';
        }
        if (status === 'Cancelled') {
            return 'slds-badge slds-theme_error';
        }
        return 'slds-badge slds-badge_lightest';
    }

    reduceError(error) {
        if (typeof error === 'string') {
            return error;
        }
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'An unexpected error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
