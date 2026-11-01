import { LightningElement, wire } from 'lwc';
import { publish, subscribe as lmsSubscribe, unsubscribe as lmsUnsubscribe, APPLICATION_SCOPE, MessageContext } from 'lightning/messageService';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import B2B_ORDER_CHANNEL from '@salesforce/messageChannel/B2B_Order_Channel__c';
import getRecentOrders from '@salesforce/apex/B2BOrderConsoleController.getRecentOrders';
import changeOrderStatus from '@salesforce/apex/B2BOrderConsoleController.changeOrderStatus';

export default class B2bOrderTracker extends LightningElement {
    filterAccountId = null;
    orders = [];
    isLoading = true;
    isProcessing = false;
    empConnected = true;
    wiredOrdersResult;
    lmsSubscription = null;
    pendingOrderIds = new Set();
    pollTimer = null;

    @wire(MessageContext)
    messageContext;

    @wire(getRecentOrders, { accountId: '$filterAccountId' })
    wiredOrders(result) {
        this.wiredOrdersResult = result;
        this.isLoading = false;
        if (result.data) {
            const newlyConfirmed = [];
            const currentPending = new Set();

            this.orders = result.data.map((ord) => {
                const status = ord.Status__c || 'Draft';
                const syncStatus = ord.ERP_Sync_Status__c || 'Not Started';

                if (status === 'Submitted' || syncStatus === 'Pending') {
                    currentPending.add(ord.Id);
                } else if (
                    this.pendingOrderIds.has(ord.Id) &&
                    (status === 'Confirmed' || status === 'Backordered')
                ) {
                    newlyConfirmed.push(ord);
                }

                const items = (ord.B2B_Order_Items__r || []).map((line) => ({
                    ...line,
                    productName: line.Product__r ? line.Product__r.Name : 'Product'
                }));
                return {
                    ...ord,
                    accountName: ord.Account__r ? ord.Account__r.Name : 'Customer',
                    erpRefDisplay: ord.ERP_Reference_Id__c ? ord.ERP_Reference_Id__c : 'Pending ERP',
                    syncStatusDisplay: syncStatus,
                    statusBadgeClass: this.computeSldsOrderBadgeClass(status),
                    progressStep: this.computeProgressStep(status),
                    hasErrorStep: status === 'Backordered' || status === 'Cancelled',
                    showProgressBar: status !== 'Cancelled',
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

            this.pendingOrderIds = currentPending;

            // Notify user when an Order_Status_Event__e Platform Event transitions a Pending order
            newlyConfirmed.forEach((ord) => {
                const ref = ord.ERP_Reference_Id__c ? ` (${ord.ERP_Reference_Id__c})` : '';
                this.showToast(
                    `Platform Event Received: ${ord.Status__c}${ref}`,
                    ord.ERP_Sync_Message__c || `Order ${ord.Name} synchronized with ERP.`,
                    ord.Status__c === 'Confirmed' ? 'success' : 'warning'
                );
            });

            if (currentPending.size > 0) {
                this.schedulePendingOrderPoll();
            }
        } else if (result.error) {
            this.showToast('Error Loading Orders', this.reduceError(result.error), 'error');
        }
    }

    connectedCallback() {
        this.subscribeToLms();
    }

    disconnectedCallback() {
        if (this.lmsSubscription) {
            lmsUnsubscribe(this.lmsSubscription);
            this.lmsSubscription = null;
        }
        window.clearTimeout(this.pollTimer);
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
            if (message.payload?.orderId && message.payload?.status === 'Submitted') {
                this.pendingOrderIds.add(message.payload.orderId);
            }
            this.handleRefreshOrders();
            this.schedulePendingOrderPoll();
        }
    }

    schedulePendingOrderPoll() {
        window.clearTimeout(this.pollTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.pollTimer = window.setTimeout(async () => {
            await this.handleRefreshOrders();
            publish(this.messageContext, B2B_ORDER_CHANNEL, {
                actionType: 'CATALOG_REFRESH',
                payload: { source: 'OrderStatusEvent' }
            });
        }, 1800);
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
            if (nextStatus === 'Submitted') {
                this.pendingOrderIds.add(orderId);
            }
            const updated = await changeOrderStatus({ orderId, newStatus: nextStatus });
            await this.handleRefreshOrders();

            publish(this.messageContext, B2B_ORDER_CHANNEL, {
                actionType: 'ORDER_UPDATED',
                payload: {
                    orderId: updated.Id,
                    status: updated.Status__c
                }
            });

            if (nextStatus === 'Submitted') {
                this.schedulePendingOrderPoll();
            }

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

    computeProgressStep(status) {
        if (status === 'Submitted') {
            return 'Submitted';
        }
        if (status === 'Confirmed' || status === 'Backordered') {
            return 'Confirmed';
        }
        if (status === 'Shipped') {
            return 'Shipped';
        }
        return 'Draft';
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
