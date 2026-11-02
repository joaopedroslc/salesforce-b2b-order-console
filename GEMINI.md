# B2B Order & Inventory Console: Engineering & AI Guidelines

This document defines the architectural rules, UI constraints, and writing standards for the `B2B Order & Inventory Console` Salesforce DX repository. All contributors and AI coding agents must follow these rules and the tone standards in `.rules/writing-style.md`.

---

## 1. Hard Constraints

### 1.1. Code Comments & Documentation
Use only formal class and method header docstrings (`/** ... */`). Never add inline comments (`// ...`, `/* ... */`, or `<!-- ... -->`) inside method bodies, JavaScript functions, CSS files, or HTML templates. Keep change logs, revision explanations, and patch notes in Git commit messages rather than source files.

### 1.2. Writing & Tone Standards (`.rules/writing-style.md`)
All documentation, docstrings, and agent responses must follow `.rules/writing-style.md`. Lead directly with the answer, code, or command without conversational warmups or formulaic sign-offs. Write natural prose paragraphs instead of formatting every section as a colon-separated bullet list. Reserve bold formatting strictly for field names, exact keywords, or critical warnings. Do not use em-dashes, decorative emojis, or banned hype words (`delve`, `foster`, `navigate`, `harness`, `leverage`, `empower`, `elevate`, `optimize`, `streamline`, `unlock`, `illuminate`, `encapsulate`, `facilitate`, `spearhead`, `tapestry`, `testament`, `landscape`, `journey`, `paradigm`, `synergy`, `realm`, `bastion`, `cornerstone`, `beacon`, `pivotal`, `seamless`, `holistic`, `vibrant`, `bespoke`, `robust`, `transformative`, `paramount`, `meticulously`, `fundamentally`).

### 1.3. Apex Test Assertions (`System.Assert`)
Use the `System.Assert` class for all Apex test assertions (`Assert.areEqual`, `Assert.areNotEqual`, `Assert.isTrue`, `Assert.isFalse`, `Assert.isNotNull`, `Assert.isNull`). Legacy `System.assert`, `System.assertEquals`, and `System.assertNotEquals` calls are forbidden.

### 1.4. Ignored Files & Media
Files in `screen recordings/` (`*.mp4`, `*.mov`, `*.webm`) must never be staged, committed to Git, or deployed to Salesforce orgs. These exclusions are enforced in `.gitignore`, `.forceignore`, and `.prettierignore`.

---

## 2. SLDS & Mobile UI Standards

### 2.1. SLDS Fidelity
Build all interfaces with Salesforce Lightning Design System (SLDS) utility classes (`slds-p-*`, `slds-m-*`, `slds-box`, `slds-card_boundary`, `slds-theme_shade`, `slds-badge`, `slds-table`) and design tokens (`var(--lwc-colorBorder, #e5e5e5)`).

### 2.2. Mobile & Touch Layouts
Mobile switcher buttons, action grids, and card controls must stretch to 100% width across mobile viewports. Do not use `<lightning-button-icon>` when dynamic flex sizing is needed because its internal Shadow DOM locks button width to `32px`. Use native `<button class="slds-button slds-button_neutral mobile-tab-btn">` elements wrapping `<lightning-icon>` instead.

Because SLDS responsive visibility helpers such as `slds-show_large` behave inconsistently inside Experience Cloud LWR and Aura Shadow DOM boundaries, pair layout rules with explicit CSS media queries at `@media (max-width: 767px)` for mobile phones, `@media (max-width: 1023px)` for tablets, and `@media (min-width: 1024px)` for desktop screens. On viewports under `768px`, replace wide data tables with stacked SLDS cards and place unit prices and line totals on a dedicated sub-row below quantity steppers to prevent text collision.

---

## 3. Apex Enterprise Architecture

The backend follows Apex Enterprise Patterns (fflib) separation of concerns across six distinct layers.

`TriggerHandler.cls` enforces a single trigger per sObject (`B2BOrderTrigger`, `B2BOrderItemTrigger`, `ProductInventoryTrigger`, `OrderStatusEventTrigger`) with context routing, recursion guards, and static bypass methods (`TriggerHandler.bypass()`).

`B2BOrdersSelector.cls` and `ProductInventoriesSelector.cls` centralize SOQL queries using `Database.queryWithBinds` and `AccessLevel.USER_MODE` enforcement.

`B2BOrdersDomain.cls`, `B2BOrderItemsDomain.cls`, and `ProductInventoriesDomain.cls` enforce state transitions (`Draft` to `Submitted` to `Confirmed` to `Shipped` or `Cancelled`), Draft-only item lock rules, SKU normalization, and bulk inventory reservations across 200+ records.

`B2BOrderService.cls`, `ERPInventoryCalloutService.cls`, and `ERPOrderSyncQueueable.cls` manage multi-object transactions with `Database.setSavepoint()`, `Security.stripInaccessible()`, outbound REST callouts via Named Credentials (`callout:ERP_Inventory_API`), and asynchronous Queueable jobs capped at `MAX_CALLOUTS_PER_TRANSACTION = 90`.

`B2B_Order_Channel__c` handles Lightning Message Service (LMS) communication across independent LWC DOM trees, while `Order_Status_Event__e` delivers asynchronous ERP status confirmations to `OrderStatusEventTrigger` and UI subscribers. `B2BOrderConsoleController.cls` exposes `@AuraEnabled` methods for LWC wires and imperative calls.

---

## 4. Development & Verification Workflow

Run terminal commands inside the standard sandbox first. Escalate with sandbox bypass only when a command requires network access or reads outside the workspace (such as `~/.sf/config.json` or `git push`), keeping the command summary identical across retries.

Verify every Apex change by running the synchronous test suite before completion:

```bash
sf apex run test --class-names B2BOrderConsoleTest --target-org joaoslc_portfolio --code-coverage --result-format human --synchronous
```

Maintain at least 85% code coverage across all classes (currently 92%) and verify positive, negative, HTTP callout mock, and 210-record bulk scenarios. Format commit messages using Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`).

---

## 5. CLI Reference

| Action | Command |
| :--- | :--- |
| Deploy Apex & LWCs | `sf project deploy start --source-dir force-app/main/default/classes --source-dir force-app/main/default/lwc` |
| Deploy Entire Project | `sf project deploy start` |
| Run Synchronous Tests | `sf apex run test --class-names B2BOrderConsoleTest --target-org joaoslc_portfolio --code-coverage --result-format human --synchronous` |
| Check Git Status | `git status --short` |
| Stage & Commit | `git add <files>; git commit -m "<message>"` |
| Push to Origin | `git push origin main` |
