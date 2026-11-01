# End-to-End QA & Live Demo Walkthrough Guide

Use this step-by-step checklist to test every functional, architectural, security, and edge-case scenario in the **B2B Order & Inventory Console** inside your Salesforce org (`joaoslc_portfolio`).

---

## Pre-Flight Check

1. Open your Salesforce org in the browser:
   ```powershell
   sf org open
   ```
2. Click the **App Launcher** (9-dot icon in the upper-left corner), type **`B2B Order Console`**, and open the page.
3. Verify that you see three Lightning cards arranged in two columns:
   * **Left Column:** `B2B Warehouse Inventory Catalog`
   * **Right Column (Top):** `B2B Order Builder`
   * **Right Column (Bottom):** `B2B Order & ERP Fulfillment Monitor` (verify the green **`empApi Live Stream Active`** badge in the card header).

---

## Test Case 1: 1-Click Demo Catalog Seeding (Idempotency Check)

1. In the **B2B Warehouse Inventory Catalog** card, click **Seed Demo Data** (or **Seed Sample B2B Catalog**).
2. **Expected Result:**
   * A green toast notification appears: *"Demo Data Ready: Seeded 6 new B2B catalog products and verified customer accounts."*
   * The KPI strip updates to show **6 Active SKUs**, **284 Available Units**, and **2 Low / Out Alerts** (`Hydraulic Valve Manifold 12-Bar` with 8 units and `Three-Phase Variable Frequency Drive (VFD)` with 5 units, both flagged with yellow SLDS `Low Stock` badges).
   * In the **B2B Order Builder** card on the right, the **B2B Customer Account** dropdown automatically populates via LMS (`Acme Industrial Corp`, `Globex Logistics Ltd`, `Stark Manufacturing B2B`).
3. Click **Seed Demo Data** a second time.
4. **Expected Result:**
   * Because `B2BOrderService.seedDemoData()` is idempotent by `External_SKU__c`, it reports **0 duplicate products created** and preserves existing stock quantities.

---

## Test Case 2: Search & Stock Status Filtering (Selector Layer Verification)

1. In the catalog search bar, type **`PLC`** or **`SKU-IND-1002`**.
2. **Expected Result:** After the 300ms debounce, the table filters down to **`Programmable Logic Controller (PLC) X8`**.
3. Clear the search bar and change the **Stock Status** filter dropdown from `All Stock Statuses` to **`Low Stock`**.
4. **Expected Result:** Only the 2 low-stock items (`SKU-IND-1003` and `SKU-IND-1006`) are displayed.
5. Reset the filter back to **`All Stock Statuses`**.

---

## Test Case 3: Live External ERP Inventory Sync (Named Credential REST Callout)

1. Note that `Hydraulic Valve Manifold 12-Bar` (`SKU-IND-1003`) has **8 Available** units and `Three-Phase VFD` (`SKU-IND-1006`) has **5 Available** units (both in `Low Stock`).
2. Click the blue **Sync with ERP** button in the top-right of the **B2B Warehouse Inventory Catalog**.
3. **Expected Result:**
   * Apex executes a live outbound HTTPS `POST` callout via the **`ERP_Inventory_API` Named Credential** (`https://postman-echo.com/post`).
   * Low-stock items are automatically replenished by **+25 units** (`8 → 33` and `5 → 30`), transitioning their SLDS badges from yellow (`Low Stock`) to green (`In Stock`), and **Low / Out Alerts** drops to `0`!

---

## Test Case 4: Building & Submitting an Order + Live Platform Event Confirmation

1. In the catalog, click **Add to Order** on **`Industrial Servo Motor 5kW`** (`$1,450.00`, `85` available) and **`Optical LiDAR Safety Scanner`** (`$3,150.00`, `24` available).
2. **Expected Result:**
   * Both items appear immediately in the **B2B Order Builder** via **Lightning Message Service (`B2B_Order_Channel__c`)**.
3. In the **B2B Order Builder**, use the `+` button on `Industrial Servo Motor 5kW` to increase its quantity to **`3`** (testing the `CustomEvent('quantitychange')` from child `b2bOrderLineItem` to parent `b2bOrderBuilder`).
4. Verify the **Order Summary** box calculates **`$7,500.00`** (`3 × $1,450 + 1 × $3,150`).
5. Enter a note in **Fulfillment / Delivery Instructions** (e.g., `"Deliver to Loading Dock B"`), then click **Submit Order to ERP**.
6. **Expected Result (Synchronous + Asynchronous Flow):**
   * **Immediate Stock Reservation:** In the catalog on the left, `Industrial Servo Motor 5kW` immediately updates to **`Reserved: 3`**, **`Available: 82`**.
   * **Asynchronous ERP Callout & Platform Event:** Within 1–3 seconds, `ERPOrderSyncQueueable` completes its outbound REST callout and publishes `Order_Status_Event__e`.
   * **Live `empApi` Toast & Status Transition:** A live green toast pops up (`"Live ERP Event: Confirmed ERP-2026-XXXXX"`), and in the **B2B Order & ERP Fulfillment Monitor**, the order status badge updates to **`CONFIRMED`** (`Synced`) with its generated **ERP Reference ID**!

---

## Test Case 5: Draft Order Lifecycle, Shipping & Cancellation Stock Adjustments

1. Add **`Programmable Logic Controller (PLC) X8`** (`Quantity: 2`) to the cart and click **Save as Draft** (instead of Submit).
2. **Expected Result:**
   * The order appears in the **B2B Order & ERP Fulfillment Monitor** with status **`DRAFT`** (`Not Started`).
   * Because the order is still a `Draft`, **`Reserved` stock is NOT locked yet** (`Reserved: 0`).
3. On that `Draft` order row in the monitor, click **Submit to ERP**.
4. **Expected Result:**
   * `Reserved` stock increases by `2`, and the async ERP Queueable confirms the order (`Confirmed`).
5. Now click **Mark Shipped** on the confirmed order.
6. **Expected Result:**
   * The order transitions to **`SHIPPED`**.
   * In the catalog, **`On Hand`** permanently decreases by `2` AND **`Reserved`** decreases by `2` (physical stock left the warehouse!).
7. Create one more order, submit it, and click **Cancel** in the monitor.
8. **Expected Result:**
   * The order transitions to **`CANCELLED`**, and its **`Reserved`** units are released back to **`Available`** without reducing `On Hand` stock!

---

## Test Case 6: Negative Guardrail & Bulk (200+ Orders) Verification

1. **Client-Side Stock Guardrail:** Add an item to the cart and type `9999` into its quantity input box.
   * **Expected Result:** A red SLDS error message (`Exceeds available stock`) appears on the line item and both **Save as Draft** and **Submit Order to ERP** buttons are automatically disabled.
2. **Backend Domain & Bulkification Verification:** Run the automated test suite from your terminal at any time to verify all 7 unit and 210-record bulk tests:
   ```powershell
   sf apex run test --class-names B2BOrderConsoleTest --code-coverage --result-format human --synchronous
   ```
