import { LightningElement, wire } from 'lwc';
import { publish, subscribe as lmsSubscribe, unsubscribe as lmsUnsubscribe, APPLICATION_SCOPE, MessageContext } from 'lightning/messageService';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import B2B_ORDER_CHANNEL from '@salesforce/messageChannel/B2B_Order_Channel__c';
import getRecentOrders from '@salesforce/apex/B2BOrderConsoleController.getRecentOrders';
import changeOrderStatus from '@salesforce/apex/B2BOrderConsoleController.changeOrderStatus';

const DEBOUNCE_DELAY = 300;

/**
 * @description Real-time fulfillment monitor tracking B2B order lifecycles and ERP synchronization.
 *              Subscribes to Platform Events and Lightning Message Service, with support for
 *              status filtering, text search, ERP telemetry inspection, and status transitions.
 */
export default class B2bOrderTracker extends LightningElement {
    filterAccountId = null;
    rawOrders = [];
    searchTerm = '';
    selectedStatusFilter = 'All';
    isLoading = true;
    isProcessing = false;
    empConnected = true;
    wiredOrdersResult;
    lmsSubscription = null;
    pendingOrderIds = new Set();
    pollTimer = null;
    searchTimeout = null;
    isErpModalOpen = false;
    selectedErpOrder = null;

    statusFilterOptions = [
        { label: 'All Lifecycles', value: 'All' },
        { label: 'In-Flight / Pending', value: 'In-Flight' },
        { label: 'Confirmed by ERP', value: 'Confirmed' },
        { label: 'Shipped', value: 'Shipped' },
        { label: 'Drafts', value: 'Draft' }
    ];

    @wire(MessageContext)
    messageContext;

    @wire(getRecentOrders, { accountId: '$filterAccountId' })
    wiredOrders(result) {
        this.wiredOrdersResult = result;
        this.isLoading = false;
        if (result.data) {
            const newlyConfirmed = [];
            const currentPending = new Set();

            this.rawOrders = result.data.map((ord) => {
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
        window.clearTimeout(this.searchTimeout);
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
        this.pollTimer = window.setTimeout(async () => {
            await this.handleRefreshOrders();
            publish(this.messageContext, B2B_ORDER_CHANNEL, {
                actionType: 'CATALOG_REFRESH',
                payload: { source: 'OrderStatusEvent' }
            });
        }, 1800);
    }

    handleSearchChange(event) {
        const val = event.target.value;
        window.clearTimeout(this.searchTimeout);
        this.searchTimeout = window.setTimeout(() => {
            this.searchTerm = val;
        }, DEBOUNCE_DELAY);
    }

    handleStatusFilterChange(event) {
        this.selectedStatusFilter = event.detail.value;
    }

    handleClearSearch() {
        this.searchTerm = '';
        const searchInput = this.template.querySelector('lightning-input[type="search"]');
        if (searchInput) {
            searchInput.value = '';
        }
    }

    handleClearStatusFilter() {
        this.selectedStatusFilter = 'All';
    }

    handleResetOrderFilters() {
        this.searchTerm = '';
        this.selectedStatusFilter = 'All';
        const searchInput = this.template.querySelector('lightning-input[type="search"]');
        if (searchInput) {
            searchInput.value = '';
        }
    }

    handleOpenErpDetails(event) {
        const orderId = event.currentTarget.dataset.id;
        const targetOrder = this.rawOrders.find((ord) => ord.Id === orderId);
        if (targetOrder) {
            this.selectedErpOrder = targetOrder;
            this.isErpModalOpen = true;
        }
    }

    handleCloseErpDetails() {
        this.isErpModalOpen = false;
        this.selectedErpOrder = null;
    }

    handleNavigateToCatalog() {
        publish(this.messageContext, B2B_ORDER_CHANNEL, {
            actionType: 'NAVIGATE_TAB',
            payload: { tab: 'catalog' }
        });
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

    get filteredOrders() {
        if (!this.rawOrders || this.rawOrders.length === 0) {
            return [];
        }
        return this.rawOrders.filter((ord) => {
            const matchesSearch =
                !this.searchTerm ||
                ord.Name.toLowerCase().includes(this.searchTerm.toLowerCase()) ||
                ord.accountName.toLowerCase().includes(this.searchTerm.toLowerCase()) ||
                (ord.ERP_Reference_Id__c && ord.ERP_Reference_Id__c.toLowerCase().includes(this.searchTerm.toLowerCase()));

            let matchesStatus = true;
            if (this.selectedStatusFilter === 'In-Flight') {
                matchesStatus = ord.Status__c === 'Submitted' || ord.Status__c === 'Confirmed' || ord.Status__c === 'Backordered';
            } else if (this.selectedStatusFilter !== 'All') {
                matchesStatus = ord.Status__c === this.selectedStatusFilter;
            }

            return matchesSearch && matchesStatus;
        });
    }

    get hasFilteredOrders() {
        return this.filteredOrders && this.filteredOrders.length > 0;
    }

    get hasAnyOrdersInDatabase() {
        return this.rawOrders && this.rawOrders.length > 0;
    }

    get hasActiveFilters() {
        return Boolean(this.searchTerm) || this.selectedStatusFilter !== 'All';
    }

    get hasSearchTerm() {
        return Boolean(this.searchTerm);
    }

    get hasStatusFilter() {
        return this.selectedStatusFilter !== 'All';
    }

    get totalOrdersCount() {
        return this.rawOrders ? this.rawOrders.length : 0;
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
