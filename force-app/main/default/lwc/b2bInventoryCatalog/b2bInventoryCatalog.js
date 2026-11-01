import { LightningElement, wire } from 'lwc';
import { publish, subscribe, unsubscribe, APPLICATION_SCOPE, MessageContext } from 'lightning/messageService';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import B2B_ORDER_CHANNEL from '@salesforce/messageChannel/B2B_Order_Channel__c';
import getCatalogInventory from '@salesforce/apex/B2BOrderConsoleController.getCatalogInventory';
import syncCatalogWithErp from '@salesforce/apex/B2BOrderConsoleController.syncCatalogWithErp';
import seedSampleCatalog from '@salesforce/apex/B2BOrderConsoleController.seedSampleCatalog';

const DEBOUNCE_DELAY = 300;

/**
 * @description Catalog management component displaying available B2B warehouse inventory.
 *              Supports debounced searching, stock status filtering, sorting, interactive KPI filters,
 *              and real-time ERP synchronization via Named Credentials.
 */
export default class B2bInventoryCatalog extends LightningElement {
    searchTerm = '';
    selectedStatus = 'All';
    selectedSort = 'name-asc';
    inventoryItems = [];
    isLoading = true;
    isSyncing = false;
    wiredCatalogResult;
    subscription = null;
    searchTimeout;

    statusOptions = [
        { label: 'All Stock Statuses', value: 'All' },
        { label: 'In Stock', value: 'In Stock' },
        { label: 'Low Stock', value: 'Low Stock' },
        { label: 'Out of Stock', value: 'Out of Stock' }
    ];

    sortOptions = [
        { label: 'Name (A to Z)', value: 'name-asc' },
        { label: 'Name (Z to A)', value: 'name-desc' },
        { label: 'Price (Low to High)', value: 'price-asc' },
        { label: 'Price (High to Low)', value: 'price-desc' },
        { label: 'Availability (Highest First)', value: 'avail-desc' }
    ];

    @wire(MessageContext)
    messageContext;

    @wire(getCatalogInventory, { searchTerm: '$searchTerm', stockStatus: '$selectedStatus' })
    wiredCatalog(result) {
        this.wiredCatalogResult = result;
        this.isLoading = false;
        if (result.data) {
            this.inventoryItems = result.data.map((inv) => {
                const avail = inv.Available_Quantity__c || 0;
                const status = inv.Stock_Status__c || 'Out of Stock';
                return {
                    ...inv,
                    productName: inv.Product__r ? inv.Product__r.Name : 'Unnamed Product',
                    productCode: inv.Product__r ? inv.Product__r.ProductCode : '',
                    productFamily: inv.Product__r ? inv.Product__r.Family : 'General',
                    isOutOfStock: avail <= 0,
                    sldsBadgeClass: this.computeSldsBadgeClass(status)
                };
            });
        } else if (result.error) {
            this.showToast('Error Loading Catalog', this.reduceError(result.error), 'error');
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
        if (
            message &&
            (message.actionType === 'ORDER_UPDATED' || message.actionType === 'CATALOG_REFRESH')
        ) {
            this.refreshCatalog();
            if (message.actionType === 'ORDER_UPDATED') {
                window.setTimeout(() => {
                    this.refreshCatalog();
                }, 2400);
            }
        }
    }

    handleSearchChange(event) {
        const value = event.target.value;
        window.clearTimeout(this.searchTimeout);
        this.searchTimeout = window.setTimeout(() => {
            this.isLoading = true;
            this.searchTerm = value;
        }, DEBOUNCE_DELAY);
    }

    handleStatusChange(event) {
        this.isLoading = true;
        this.selectedStatus = event.detail.value;
    }

    handleSortChange(event) {
        this.selectedSort = event.detail.value;
    }

    handleKpiClick(event) {
        const filterType = event.currentTarget.dataset.filter;
        if (filterType === 'alerts') {
            this.isLoading = true;
            this.selectedStatus = this.selectedStatus === 'Low Stock' ? 'All' : 'Low Stock';
        } else if (filterType === 'all') {
            if (this.selectedStatus !== 'All' || this.searchTerm) {
                this.handleResetFilters();
            }
        }
    }

    handleKpiKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleKpiClick(event);
        }
    }

    handleClearSearch() {
        this.isLoading = true;
        this.searchTerm = '';
        const searchInput = this.template.querySelector('lightning-input[type="search"]');
        if (searchInput) {
            searchInput.value = '';
        }
    }

    handleClearStatus() {
        this.isLoading = true;
        this.selectedStatus = 'All';
    }

    handleResetFilters() {
        this.isLoading = true;
        this.searchTerm = '';
        this.selectedStatus = 'All';
        this.selectedSort = 'name-asc';
        const searchInput = this.template.querySelector('lightning-input[type="search"]');
        if (searchInput) {
            searchInput.value = '';
        }
    }

    handleAddToOrder(event) {
        const inventoryId = event.currentTarget.dataset.id;
        const selected = this.inventoryItems.find((item) => item.Id === inventoryId);
        if (!selected) {
            return;
        }

        publish(this.messageContext, B2B_ORDER_CHANNEL, {
            actionType: 'ADD_TO_ORDER',
            payload: {
                inventoryId: selected.Id,
                productId: selected.Product__c,
                productName: selected.productName,
                productCode: selected.productCode,
                externalSku: selected.External_SKU__c,
                unitPrice: selected.Unit_Price__c,
                availableQuantity: selected.Available_Quantity__c
            }
        });

        this.showToast(
            'Added to Order',
            `${selected.productName} (${selected.External_SKU__c}) added to the active order.`,
            'success'
        );
    }

    async handleSyncErp() {
        this.isSyncing = true;
        try {
            const ids = this.inventoryItems.map((item) => item.Id);
            await syncCatalogWithErp({ inventoryIds: ids });
            await this.refreshCatalog();
            this.showToast(
                'ERP Sync Complete',
                'Live warehouse inventory synchronized via Named Credential (ERP_Inventory_API).',
                'success'
            );
        } catch (error) {
            this.showToast('ERP Sync Failed', this.reduceError(error), 'error');
        } finally {
            this.isSyncing = false;
        }
    }

    async handleSeedCatalog() {
        this.isSyncing = true;
        try {
            const message = await seedSampleCatalog();
            await this.refreshCatalog();
            publish(this.messageContext, B2B_ORDER_CHANNEL, {
                actionType: 'CATALOG_REFRESH',
                payload: { seeded: true }
            });
            this.showToast('Demo Data Ready', message, 'success');
        } catch (error) {
            this.showToast('Seed Data Error', this.reduceError(error), 'error');
        } finally {
            this.isSyncing = false;
        }
    }

    async refreshCatalog() {
        if (this.wiredCatalogResult) {
            await refreshApex(this.wiredCatalogResult);
        }
    }

    get sortedInventoryItems() {
        if (!this.inventoryItems || this.inventoryItems.length === 0) {
            return [];
        }
        const items = [...this.inventoryItems];
        switch (this.selectedSort) {
            case 'name-desc':
                return items.sort((a, b) => b.productName.localeCompare(a.productName));
            case 'price-asc':
                return items.sort((a, b) => (a.Unit_Price__c || 0) - (b.Unit_Price__c || 0));
            case 'price-desc':
                return items.sort((a, b) => (b.Unit_Price__c || 0) - (a.Unit_Price__c || 0));
            case 'avail-desc':
                return items.sort((a, b) => (b.Available_Quantity__c || 0) - (a.Available_Quantity__c || 0));
            case 'name-asc':
            default:
                return items.sort((a, b) => a.productName.localeCompare(b.productName));
        }
    }

    get hasInventoryItems() {
        return this.sortedInventoryItems && this.sortedInventoryItems.length > 0;
    }

    get isDatabaseEmpty() {
        return !this.isLoading && this.inventoryItems.length === 0 && !this.searchTerm && this.selectedStatus === 'All';
    }

    get showFilterPills() {
        return Boolean(this.searchTerm) || this.selectedStatus !== 'All';
    }

    get hasSearchTerm() {
        return Boolean(this.searchTerm);
    }

    get hasStatusFilter() {
        return this.selectedStatus !== 'All';
    }

    get totalSkus() {
        return this.inventoryItems ? this.inventoryItems.length : 0;
    }

    get totalAvailableUnits() {
        if (!this.inventoryItems) {
            return 0;
        }
        return this.inventoryItems.reduce((sum, item) => sum + (item.Available_Quantity__c || 0), 0);
    }

    get lowOrOutCount() {
        if (!this.inventoryItems) {
            return 0;
        }
        return this.inventoryItems.filter((item) => item.Stock_Status__c !== 'In Stock').length;
    }

    get kpiAllClass() {
        const base = 'slds-box slds-box_x-small slds-theme_shade slds-card_boundary kpi-card kpi-card_interactive';
        return this.selectedStatus === 'All' ? `${base} kpi-card_active` : base;
    }

    get kpiAlertsClass() {
        const base = 'slds-box slds-box_x-small slds-theme_shade slds-card_boundary kpi-card kpi-card_interactive';
        return this.selectedStatus === 'Low Stock' || this.selectedStatus === 'Out of Stock' ? `${base} kpi-card_active` : base;
    }

    computeSldsBadgeClass(status) {
        if (status === 'In Stock') {
            return 'slds-badge slds-theme_success';
        }
        if (status === 'Low Stock') {
            return 'slds-badge slds-theme_warning';
        }
        return 'slds-badge slds-theme_error';
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
