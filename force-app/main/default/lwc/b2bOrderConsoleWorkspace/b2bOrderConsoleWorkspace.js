import { LightningElement, wire } from 'lwc';
import { subscribe, unsubscribe, APPLICATION_SCOPE, MessageContext } from 'lightning/messageService';
import B2B_ORDER_CHANNEL from '@salesforce/messageChannel/B2B_Order_Channel__c';

/**
 * @description Unified single-drop workspace container for Experience Cloud (LWR/Aura) and Lightning App Pages.
 *              Provides a side-by-side 2-column SLDS desktop workspace, interactive mobile tab navigation,
 *              dynamic cart pulse micro-interactions, and real-time LMS message routing.
 */
export default class B2bOrderConsoleWorkspace extends LightningElement {
    activeMobileTab = 'catalog';
    mobileCartSkus = new Set();
    lmsSubscription = null;
    isCartPulsing = false;
    pulseTimeout = null;

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
        window.clearTimeout(this.pulseTimeout);
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
            this.triggerCartPulse();
        } else if (message.actionType === 'ORDER_UPDATED') {
            this.mobileCartSkus = new Set();
            if (this.activeMobileTab === 'cart') {
                this.activeMobileTab = 'orders';
            }
        } else if (message.actionType === 'NAVIGATE_TAB' && message.payload?.tab) {
            this.activeMobileTab = message.payload.tab;
        }
    }

    triggerCartPulse() {
        this.isCartPulsing = true;
        window.clearTimeout(this.pulseTimeout);
        this.pulseTimeout = window.setTimeout(() => {
            this.isCartPulsing = false;
        }, 650);
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

    get catalogTabClass() {
        return this.activeMobileTab === 'catalog'
            ? 'slds-button slds-button_brand mobile-tab-btn mobile-tab-btn_active'
            : 'slds-button slds-button_neutral mobile-tab-btn';
    }

    get cartTabClass() {
        let baseClass =
            this.activeMobileTab === 'cart'
                ? 'slds-button slds-button_brand mobile-tab-btn mobile-tab-btn_active'
                : 'slds-button slds-button_neutral mobile-tab-btn';
        if (this.isCartPulsing) {
            baseClass += ' cart-tab-btn_pulse';
        }
        return baseClass;
    }

    get ordersTabClass() {
        return this.activeMobileTab === 'orders'
            ? 'slds-button slds-button_brand mobile-tab-btn mobile-tab-btn_active'
            : 'slds-button slds-button_neutral mobile-tab-btn';
    }

    get allTabClass() {
        return this.activeMobileTab === 'all'
            ? 'slds-button slds-button_brand mobile-tab-btn mobile-tab-btn_active'
            : 'slds-button slds-button_neutral mobile-tab-btn';
    }

    get catalogColumnClass() {
        if (this.activeMobileTab === 'catalog' || this.activeMobileTab === 'all') {
            return 'workspace-col-left';
        }
        return 'workspace-col-left mobile-pane-hidden';
    }

    get rightColumnClass() {
        if (this.activeMobileTab === 'catalog') {
            return 'workspace-col-right mobile-pane-hidden';
        }
        return 'workspace-col-right';
    }

    get builderWrapperClass() {
        if (this.activeMobileTab === 'orders') {
            return 'slds-m-bottom_medium mobile-pane-hidden';
        }
        return 'slds-m-bottom_medium';
    }

    get trackerWrapperClass() {
        if (this.activeMobileTab === 'cart') {
            return 'mobile-pane-hidden';
        }
        return '';
    }
}
