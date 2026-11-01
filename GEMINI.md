# B2B Order & Inventory Console - Developer & AI Guidelines

This document serves as the persistent engineering handbook and AI coding contract for the **B2B Order & Inventory Console** Salesforce DX project. Every AI agent, assistant (Gemini/Antigravity), and human contributor working in this repository must adhere to the conventions, hard constraints, and architectural standards outlined below.

---

## 1. Non-Negotiable Hard Constraints

### 1.1. Code Comments & Documentation Integrity
* **Strict Header-Only Rule:** ONLY use formal class and method header docstrings (`/** ... */`).
* **Zero Inline Comments:** **NEVER** add inline comments (`// ...`, `/* ... */`, or `<!-- ... -->`) inside method bodies, scripts, or markup.
* **No Iteration Commentary:** Never include change logs, patch notes, fix explanations, or revision commentary inside code files. Keep explanations in Git commit messages or external documentation.

### 1.2. Apex Test Assertions (`System.Assert`)
* **Modern Assert Class Only:** Always use the modern `System.Assert` class for all Apex unit tests and test mocks:
  * `Assert.areEqual(expected, actual, msg)`
  * `Assert.areNotEqual(notExpected, actual, msg)`
  * `Assert.isTrue(condition, msg)`
  * `Assert.isFalse(condition, msg)`
  * `Assert.isNotNull(instance, msg)`
  * `Assert.isNull(instance, msg)`
* **Forbidden:** Never use legacy `System.assert(...)`, `System.assertEquals(...)`, or `System.assertNotEquals(...)`.

### 1.3. Ignored Files & Media
* Files in `screen recordings/` (`*.mp4`, `*.mov`, `*.webm`) must **never** be staged, committed to Git, or deployed to Salesforce orgs. These patterns are strictly enforced in `.gitignore`, `.forceignore`, and `.prettierignore`.

---

## 2. UI / UX & Mobile-First Standards (SLDS Strict)

### 2.1. SLDS Fidelity
* **Never steer away from the Salesforce Lightning Design System (SLDS).**
* Use native SLDS utility classes (`slds-p-*`, `slds-m-*`, `slds-box`, `slds-card_boundary`, `slds-theme_shade`, `slds-badge`, `slds-table`, etc.) and official SLDS design tokens (`var(--lwc-colorBorder, #e5e5e5)`) instead of custom ad-hoc styling.

### 2.2. Mobile-First & Touch-Optimized Layouts
* **Full-Width Stretch on Mobile:** Mobile switcher buttons, action grids, and card controls must stretch edge-to-edge (100% width) across the viewport.
* **Shadow DOM Button Sizing:** Do not use `<lightning-button-icon>` when full-width or dynamic flex stretching is required, as its internal Shadow DOM hard-codes button width (`32px`). Instead, use native SLDS buttons (`<button class="slds-button slds-button_neutral mobile-tab-btn">`) wrapping `<lightning-icon>`.
* **Experience Cloud LWR/Aura Responsiveness:** SLDS responsive helper classes (e.g., `slds-show_large`) can behave unpredictably inside Shadow DOM. Always pair responsive designs with explicit CSS media queries:
  * `@media (max-width: 767px)` for mobile phone views.
  * `@media (max-width: 1023px)` for tablet views.
  * `@media (min-width: 1024px)` for desktop views.
* **Card-Based Mobile Architecture:** On viewports under 768px, convert dense tabular views into touch-friendly SLDS cards with clear visual hierarchy (Badges $\rightarrow$ Title $\rightarrow$ Progress Bar $\rightarrow$ Metrics Strip $\rightarrow$ Action Buttons).
* **Dedicated Price Lines:** Avoid placing stepper controls and currency labels on the same cramped horizontal row; place unit price and total calculations on a dedicated sub-row to prevent text collision.

---

## 3. Architecture & Enterprise Design Patterns

This repository implements the **Apex Enterprise Patterns (fflib)** layer separation:

1. **Trigger Handler Layer (`TriggerHandler.cls`):** 
   * Single trigger per sObject (`B2BOrderTrigger`, `OrderStatusEventTrigger`).
   * Provides reentrancy prevention, recursion guards, bypass controls, and context routing.
2. **Selector Layer (`B2BOrdersSelector.cls`):**
   * Centralizes all SOQL queries and field sets with object and field-level security checks.
3. **Domain Layer (`B2BOrdersDomain.cls`, `B2BOrderItemsDomain.cls`):**
   * Encapsulates entity validation, state machines, and business rules during trigger executions.
4. **Service Layer (`B2BOrderService.cls`, `ERPInventoryCalloutService.cls`):**
   * Orchestrates multi-object transactions, external REST callouts via Named Credentials (`ERP_Inventory_API`), and asynchronous Queueables.
5. **Event-Driven Messaging & Decoupling:**
   * **Lightning Message Channel (`B2B_Order_Channel__c`):** Facilitates real-time, cross-component UI synchronization between independent LWCs across DOM hierarchies and Experience Cloud pages.
   * **Platform Events (`Order_Status_Event__e`):** Delivers asynchronous ERP callback confirmations directly to subscribing Apex triggers and client-side listeners.
6. **Controller Facade (`B2BOrderConsoleController.cls`):**
   * Exposes clean `@AuraEnabled` endpoints consumed by Lightning Web Components.

---

## 4. AI Development & Agentic Best Practices

When developing or refactoring with AI assistants, follow these validated industry and agentic practices:

### 4.1. The Principle of High-Signal Context
* Keep prompt instructions and documentation concise and dense.
* Prioritize non-obvious architecture, constraints, and gotchas over generic language explanations.
* Prevent "context rot" by referencing existing files rather than duplicating large snippets into chat conversations.

### 4.2. Safe Sandbox Execution & Escalation
* **Try Sandboxed First:** Run terminal and CLI commands within the standard sandboxed execution mode first.
* **Controlled Escalation:** If a system call requires network or user-home access (e.g., Salesforce CLI auth storage `~/.sf/config.json` or Git remote operations), escalate with sandbox bypass while keeping command summaries identical.

### 4.3. Test-Driven Verification Loop
* Never declare an Apex change complete without running the synchronous test suite:
  ```bash
  sf apex run test --class-names B2BOrderConsoleTest --code-coverage --synchronous
  ```
* Enforce **>85% code coverage** (current: **92%**) across all service, domain, selector, and controller logic.
* Ensure all positive, negative, and bulk (200+ record) scenarios pass.

### 4.4. Atomic Commits
* Format Git commits following the **Conventional Commits** specification:
  * `feat: ...` for user-facing features or new components.
  * `fix: ...` for bug fixes and UI repairs.
  * `refactor: ...` for restructuring code without changing functionality.
  * `test: ...` for updating or extending unit tests.

---

## 5. Key CLI Reference

| Action | Command |
| :--- | :--- |
| **Deploy Apex & LWCs** | `sf project deploy start --source-dir force-app/main/default/classes --source-dir force-app/main/default/lwc` |
| **Deploy Entire Project** | `sf project deploy start` |
| **Run Synchronous Tests** | `sf apex run test --class-names B2BOrderConsoleTest --code-coverage --result-format human --synchronous` |
| **Check Git Status** | `git status --short` |
| **Stage & Commit** | `git add <files>; git commit -m "<conventional commit message>"` |
| **Push to Origin** | `git push origin main` |

