import { LightningElement, wire } from 'lwc';
import { subscribe, unsubscribe, APPLICATION_SCOPE, MessageContext } from 'lightning/messageService';
import B2B_ORDER_CHANNEL from '@salesforce/messageChannel/B2B_Order_Channel__c';

/**
 * @description Unified single-drop workspace container for Experience Cloud (LWR/Aura) and Lightning App Pages.
 *              Provides a side-by-side 2-column SLDS desktop workspace and a compact mobile switcher
 *              (showing text only on the active tab and icon-only buttons on inactive tabs)
 *              while keeping all child LWCs mounted in the DOM so LMS state is never lost.
 */
export default class B2bOrderConsoleWorkspace extends LightningElement {
    activeMobileTab = 'catalog';
    mobileCartSkus = new Set();
    lmsSubscription = null;

    @wire(MessageContext)
    messageContext;

    connectedCallback() {
        this.subscribeToLms();
    }

    disconnectedCallback() {
        if (this.lmsSubscription) {
            unsubscribe(this.lmsSubscription);
            this.lmsSubscription = null;
        }
    }

    subscribeToLms() {
        if (!this.lmsSubscription) {
            this.lmsSubscription = subscribe(
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
        if (message.actionType === 'ADD_TO_ORDER' && message.payload?.inventoryId) {
            this.mobileCartSkus = new Set([...this.mobileCartSkus, message.payload.inventoryId]);
        } else if (message.actionType === 'ORDER_UPDATED') {
            this.mobileCartSkus = new Set();
            if (this.activeMobileTab === 'cart') {
                this.activeMobileTab = 'orders';
            }
        }
    }

    handleMobileTabChange(event) {
        const selectedTab = event.currentTarget.dataset.tab;
        if (selectedTab) {
            this.activeMobileTab = selectedTab;
        }
    }

    get mobileCartCount() {
        return this.mobileCartSkus.size;
    }

    get cartTabLabel() {
        return this.mobileCartCount > 0 ? `Cart (${this.mobileCartCount})` : 'Cart';
    }

    get showMobileCartPrompt() {
        return this.mobileCartCount > 0 && this.activeMobileTab === 'catalog';
    }

    get isCatalogTabActive() {
        return this.activeMobileTab === 'catalog';
    }

    get isCartTabActive() {
        return this.activeMobileTab === 'cart';
    }

    get isOrdersTabActive() {
        return this.activeMobileTab === 'orders';
    }

    get isAllTabActive() {
        return this.activeMobileTab === 'all';
    }

    get catalogColumnClass() {
        const base = 'slds-col slds-size_1-of-1 slds-large-size_7-of-12 slds-m-bottom_medium';
        if (this.activeMobileTab === 'catalog' || this.activeMobileTab === 'all') {
            return base;
        }
        return `${base} slds-show_large`;
    }

    get rightColumnClass() {
        const base = 'slds-col slds-size_1-of-1 slds-large-size_5-of-12';
        if (this.activeMobileTab === 'catalog') {
            return `${base} slds-show_large`;
        }
        return base;
    }

    get builderWrapperClass() {
        if (this.activeMobileTab === 'orders') {
            return 'slds-m-bottom_medium slds-show_large';
        }
        return 'slds-m-bottom_medium';
    }

    get trackerWrapperClass() {
        if (this.activeMobileTab === 'cart') {
            return 'slds-show_large';
        }
        return '';
    }
}
