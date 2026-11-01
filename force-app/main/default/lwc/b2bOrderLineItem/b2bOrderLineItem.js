import { LightningElement, api } from 'lwc';

export default class B2bOrderLineItem extends LightningElement {
    @api item;

    get lineTotal() {
        if (!this.item) {
            return 0;
        }
        return (this.item.quantity || 0) * (this.item.unitPrice || 0);
    }

    get isDecrementDisabled() {
        return !this.item || this.item.quantity <= 1;
    }

    get isIncrementDisabled() {
        return !this.item || this.item.quantity >= this.item.availableQuantity;
    }

    get hasStockError() {
        return this.item && this.item.quantity > this.item.availableQuantity;
    }

    handleDecrement() {
        if (this.item && this.item.quantity > 1) {
            this.emitQuantityChange(this.item.quantity - 1);
        }
    }

    handleIncrement() {
        if (this.item && this.item.quantity < this.item.availableQuantity) {
            this.emitQuantityChange(this.item.quantity + 1);
        }
    }

    handleInputChange(event) {
        const parsed = parseInt(event.target.value, 10);
        const safeQty = Number.isNaN(parsed) || parsed < 1 ? 1 : parsed;
        this.emitQuantityChange(safeQty);
    }

    handleRemove() {
        this.dispatchEvent(
            new CustomEvent('removeitem', {
                detail: {
                    inventoryId: this.item.inventoryId
                }
            })
        );
    }

    emitQuantityChange(newQuantity) {
        this.dispatchEvent(
            new CustomEvent('quantitychange', {
                detail: {
                    inventoryId: this.item.inventoryId,
                    quantity: newQuantity
                }
            })
        );
    }
}
