import { LightningElement, wire } from 'lwc';
import { publish, subscribe, unsubscribe, APPLICATION_SCOPE, MessageContext } from 'lightning/messageService';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import B2B_ORDER_CHANNEL from '@salesforce/messageChannel/B2B_Order_Channel__c';
import getCustomerAccounts from '@salesforce/apex/B2BOrderConsoleController.getCustomerAccounts';
import saveOrder from '@salesforce/apex/B2BOrderConsoleController.saveOrder';

/**
 * @description Interactive order construction component for B2B accounts.
 *              Supports line item management, inventory stock guards, financial breakdown summaries,
 *              and direct submission to ERP with asynchronous queueable fallbacks.
 */
export default class B2bOrderBuilder extends LightningElement {
    selectedAccountId = '';
    accountOptions = [];
    orderNotes = '';
    cartItems = [];
    isSubmitting = false;
    wiredAccountsResult;
    subscription = null;

    @wire(MessageContext)
    messageContext;

    @wire(getCustomerAccounts)
    wiredAccounts(result) {
        this.wiredAccountsResult = result;
        if (result.data) {
            this.accountOptions = result.data.map((acc) => ({
                label: `${acc.Name}${acc.Industry ? ' (' + acc.Industry + ')' : ''}`,
                value: acc.Id
            }));
            if (!this.selectedAccountId && this.accountOptions.length > 0) {
                this.selectedAccountId = this.accountOptions[0].value;
            }
        } else if (result.error) {
            this.showToast('Error Loading Accounts', this.reduceError(result.error), 'error');
        }
    }

    connectedCallback() {
        this.subscribeToChannel();
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = null;
        }
    }

    subscribeToChannel() {
        if (!this.subscription) {
            this.subscription = subscribe(
                this.messageContext,
                B2B_ORDER_CHANNEL,
                (message) => this.handleChannelMessage(message),
                { scope: APPLICATION_SCOPE }
            );
        }
    }

    handleChannelMessage(message) {
        if (!message) {
            return;
        }
        if (message.actionType === 'ADD_TO_ORDER' && message.payload) {
            this.addProductToCart(message.payload);
        } else if (message.actionType === 'CATALOG_REFRESH') {
            if (this.wiredAccountsResult) {
                refreshApex(this.wiredAccountsResult);
            }
        }
    }

    addProductToCart(itemPayload) {
        const existingIndex = this.cartItems.findIndex(
            (line) => line.inventoryId === itemPayload.inventoryId
        );

        if (existingIndex > -1) {
            const existing = this.cartItems[existingIndex];
            const nextQty = existing.quantity + 1;
            if (nextQty > itemPayload.availableQuantity) {
                this.showToast(
                    'Stock Limit Reached',
                    `Cannot exceed available stock (${itemPayload.availableQuantity}) for ${itemPayload.externalSku}.`,
                    'warning'
                );
                return;
            }
            const updated = [...this.cartItems];
            updated[existingIndex] = { ...existing, quantity: nextQty };
            this.cartItems = updated;
        } else {
            this.cartItems = [
                ...this.cartItems,
                {
                    inventoryId: itemPayload.inventoryId,
                    productId: itemPayload.productId,
                    productName: itemPayload.productName,
                    productCode: itemPayload.productCode,
                    externalSku: itemPayload.externalSku,
                    unitPrice: itemPayload.unitPrice || 0,
                    availableQuantity: itemPayload.availableQuantity || 0,
                    quantity: 1
                }
            ];
        }
    }

    handleAccountChange(event) {
        this.selectedAccountId = event.detail.value;
        publish(this.messageContext, B2B_ORDER_CHANNEL, {
            actionType: 'ACCOUNT_SELECTED',
            payload: { accountId: this.selectedAccountId }
        });
    }

    handleNotesChange(event) {
        this.orderNotes = event.target.value;
    }

    handleLineQuantityChange(event) {
        const { inventoryId, quantity } = event.detail;
        this.cartItems = this.cartItems.map((item) =>
            item.inventoryId === inventoryId ? { ...item, quantity } : item
        );
    }

    handleRemoveLineItem(event) {
        const { inventoryId } = event.detail;
        this.cartItems = this.cartItems.filter((item) => item.inventoryId !== inventoryId);
    }

    handleClearCart() {
        this.cartItems = [];
        this.orderNotes = '';
    }

    handleNavigateToCatalog() {
        publish(this.messageContext, B2B_ORDER_CHANNEL, {
            actionType: 'NAVIGATE_TAB',
            payload: { tab: 'catalog' }
        });
    }

    async handleSaveDraft() {
        await this.persistOrder(false);
    }

    async handleSubmitOrder() {
        await this.persistOrder(true);
    }

    async persistOrder(submitImmediately) {
        if (!this.selectedAccountId) {
            this.showToast('Account Required', 'Please select a B2B Customer Account first.', 'warning');
            return;
        }
        if (!this.hasCartItems) {
            this.showToast('Empty Order', 'Add at least one catalog item from the left panel.', 'warning');
            return;
        }
        if (this.hasInvalidStockLines) {
            this.showToast(
                'Insufficient Stock',
                'One or more line items exceed available warehouse stock.',
                'error'
            );
            return;
        }

        this.isSubmitting = true;
        try {
            const itemsPayload = this.cartItems.map((item) => ({
                productId: item.productId,
                inventoryId: item.inventoryId,
                quantity: item.quantity,
                unitPrice: item.unitPrice
            }));

            const createdOrder = await saveOrder({
                accountId: this.selectedAccountId,
                notes: this.orderNotes,
                items: itemsPayload,
                submitOrder: submitImmediately
            });

            this.cartItems = [];
            this.orderNotes = '';

            publish(this.messageContext, B2B_ORDER_CHANNEL, {
                actionType: 'ORDER_UPDATED',
                payload: {
                    orderId: createdOrder.Id,
                    orderNumber: createdOrder.Name,
                    status: createdOrder.Status__c
                }
            });

            if (submitImmediately) {
                this.showToast(
                    'Order Submitted & Queued for ERP',
                    `Order ${createdOrder.Name} reserved stock and queued async ERP confirmation.`,
                    'success'
                );
            } else {
                this.showToast(
                    'Draft Order Saved',
                    `Draft Order ${createdOrder.Name} created.`,
                    'success'
                );
            }
        } catch (error) {
            this.showToast('Order Creation Failed', this.reduceError(error), 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    get hasSelectedAccount() {
        return Boolean(this.selectedAccountId);
    }

    get hasCartItems() {
        return this.cartItems && this.cartItems.length > 0;
    }

    get totalLineCount() {
        return this.cartItems ? this.cartItems.length : 0;
    }

    get totalUnitsCount() {
        if (!this.cartItems) {
            return 0;
        }
        return this.cartItems.reduce((sum, item) => sum + (item.quantity || 0), 0);
    }

    get estimatedOrderTotal() {
        if (!this.cartItems) {
            return 0;
        }
        return this.cartItems.reduce(
            (sum, item) => sum + (item.quantity || 0) * (item.unitPrice || 0),
            0
        );
    }

    get hasInvalidStockLines() {
        return this.cartItems.some((item) => item.quantity > item.availableQuantity);
    }

    get isActionDisabled() {
        return this.isSubmitting || !this.hasCartItems || !this.selectedAccountId || this.hasInvalidStockLines;
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
