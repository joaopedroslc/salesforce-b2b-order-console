# End-to-End QA & Live Demo Walkthrough Guide

This checklist verifies catalog seeding, search and filter queries, Named Credential REST callouts, asynchronous Queueable and Platform Event processing, stock reservation lifecycles, and negative validation rules in `joaoslc_portfolio`.

---

## Pre-Flight Check

1. Open the target Salesforce org:
   ```powershell
   sf org open
   ```
2. Open the App Launcher, search for **B2B Order Console**, and open the workspace.
3. Confirm the two-column desktop layout renders **B2B Inventory Catalog** on the left, **B2B Order Builder** on the top right, and **B2B Order & ERP Fulfillment Monitor** with the **Live ERP Event Stream** badge on the bottom right. On viewports under `1024px`, confirm the top switcher bar toggles between `Catalog`, `Cart`, `Orders`, and `All`.

---

## Test Case 1: Idempotent Demo Catalog Seeding

1. Click **Seed Data** in the **B2B Inventory Catalog** header.
2. Verify the toast message confirms `Seeded 6 new B2B catalog products and verified customer accounts.` The KPI strip displays `6` Active SKUs, `284` Available Units, and `2` Low / Out Alerts (`Hydraulic Valve Manifold 12-Bar` with 8 units and `Three-Phase Variable Frequency Drive (VFD)` with 5 units). In **B2B Order Builder**, the customer account combobox populates via LMS with `Acme Industrial Corp`, `Globex Logistics Ltd`, and `Stark Manufacturing B2B`.
3. Click **Seed Data** a second time.
4. Because `B2BOrderService.seedDemoData()` checks existing records by `External_SKU__c`, it creates `0` duplicate products and preserves current stock quantities.

---

## Test Case 2: Search, Interactive KPI Cards, and Sorting

1. Type `PLC` or `SKU-IND-1002` into the catalog search input.
2. After the 300ms debounce, the catalog displays only `Programmable Logic Controller (PLC) X8` and renders a removable `Search: "PLC"` filter pill.
3. Click the `Low / Out Alerts` KPI card.
4. The status filter switches to `Low Stock`, displaying only `SKU-IND-1003` and `SKU-IND-1006`.
5. Click **Reset All** on the filter pill bar to restore all 6 SKUs, then test the **Sort By** selector (`Price (High to Low)` and `Availability (Highest First)`).

---

## Test Case 3: Outbound ERP Inventory Sync via Named Credential

1. Confirm `Hydraulic Valve Manifold 12-Bar` (`SKU-IND-1003`) has `8` available units and `Three-Phase VFD` (`SKU-IND-1006`) has `5` available units.
2. Click **ERP Sync** in the catalog header.
3. `ERPInventoryCalloutService.fetchInventoryFromErp()` sends an outbound HTTPS POST request through the `ERP_Inventory_API` Named Credential (`https://postman-echo.com/post`). Low-stock SKUs are replenished by +25 units (`8` to `33` and `5` to `30`), updating their badges from `Low Stock` to `In Stock` and reducing `Low / Out Alerts` to `0`.

---

## Test Case 4: Order Submission & Platform Event Confirmation

1. Click **Add to Order** on `Industrial Servo Motor 5kW` (`$1,450.00`, `85` available) and `Optical LiDAR Safety Scanner` (`$3,150.00`, `24` available).
2. Both SKUs appear in **B2B Order Builder** via the `B2B_Order_Channel__c` message channel, and the mobile `Cart` tab pulses with the updated SKU count.
3. Increment `Industrial Servo Motor 5kW` to `3` units. Confirm the **Order Financial Summary** displays `2 SKUs (4 units)` and `$7,500.00`.
4. Enter delivery notes in **Fulfillment / Delivery Instructions** and click **Submit Order to ERP**.
5. In the catalog, `Industrial Servo Motor 5kW` immediately updates to `Reserved: 3` and `Available: 82`. Within 2 seconds, `ERPOrderSyncQueueable` completes the outbound callout and publishes `Order_Status_Event__e`. **B2B Order & ERP Fulfillment Monitor** displays the confirmation toast, updates the order badge to `Confirmed`, and populates the generated `ERP_Reference_Id__c`. Click the ERP reference pill on the order card to inspect the **ERP Synchronization Telemetry** modal.

---

## Test Case 5: Draft Lifecycle, Shipping, and Cancellation Stock Adjustments

1. Add `Programmable Logic Controller (PLC) X8` (`Quantity: 2`) to the cart and click **Save as Draft**.
2. The order appears in the fulfillment monitor with status `Draft` and sync status `Not Started`. Reserved stock remains `0` while the order is in `Draft`.
3. Click **Submit to ERP** on the draft order row.
4. `Reserved_Quantity__c` increases by `2` and the asynchronous Queueable transitions the order to `Confirmed`.
5. Click **Mark Shipped** on the confirmed order.
6. The order transitions to `Shipped`, decreasing both `On_Hand_Quantity__c` and `Reserved_Quantity__c` by `2`.
7. Create and submit one additional order, then click **Cancel** in the fulfillment monitor.
8. The order transitions to `Cancelled` and releases its `Reserved_Quantity__c` back into `Available_Quantity__c` without reducing `On_Hand_Quantity__c`.

---

## Test Case 6: Stock Guardrails & 210-Record Bulk Test Suite

1. Add an item to the cart, type `9999` into the quantity input, and press Tab (`blur`).
2. `b2bOrderLineItem` clamps the input value to `availableQuantity`. If an invalid quantity is entered prior to blur, the line displays `Exceeds available stock` and disables both **Save as Draft** and **Submit Order to ERP**.
3. Run the synchronous Apex test suite from the terminal to verify all 8 unit and 210-record bulk tests:
   ```powershell
   sf apex run test --class-names B2BOrderConsoleTest --target-org joaoslc_portfolio --code-coverage --result-format human --synchronous
   ```
