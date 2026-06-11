# Catalog Inventory Quality Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the iOS Catalog/Inventory tab defects captured in `docs/superpowers/specs/2026-06-05-catalog-inventory-quality-pass-design.md`.

**Architecture:** Keep the work inside the existing Catalog SwiftUI structure. Move command ownership into `CatalogView`, keep global FAB generic, add a focused quick-adjust sheet for stock rows, and reuse existing OPS style components such as `OPSFloatingButtonBar`, `nestedCard`, and OPS typography tokens instead of inventing new visual primitives.

**Tech Stack:** SwiftUI, SwiftData, OPS design tokens in `OPSStyle`, existing Catalog DTO/repository models, Xcode build/test verification.

---

### Task 1: Catalog Command Ownership

**Files:**
- Modify: `OPS/Views/Catalog/CatalogView.swift`
- Modify: `OPS/Views/Components/FloatingActionMenu.swift`
- Verify: Catalog header ellipsis and global FAB while the Catalog tab is active.

- [ ] Add stock creation actions to the Catalog header ellipsis: guided setup, stock setup, add variant, add family, import.
- [ ] Add product creation actions to the Catalog header ellipsis: new service, new good, new bundle.
- [ ] Keep manage actions in the Catalog header ellipsis: snapshots, categories, tags, units, thresholds, defaults, orders.
- [ ] Remove the Catalog-specific action stack from the global FAB while the Catalog tab is active.
- [ ] Preserve the existing sheet bindings and permissions checks.

### Task 2: Stock List Row Hierarchy And Quick Adjust

**Files:**
- Modify: `OPS/Views/Catalog/Stock/CategoryGroupSection.swift`
- Modify: `OPS/Views/Catalog/Stock/StockView.swift`
- Modify or create: `OPS/Views/Catalog/Stock/StockQuickAdjustSheet.swift`
- Reference: `OPS/Views/Catalog/Stock/VariantDetailView.swift`
- Verify: Supabase bug `a472ca5d-30b5-4d1b-ae00-f2a86affa58f`.

- [ ] Replace one-sided child card padding with a balanced nested row treatment.
- [ ] Change stock row tap to open a quick-adjust sheet at medium detent.
- [ ] Add a full-detail action in the quick-adjust sheet.
- [ ] Add a context-menu full-detail path on stock rows.
- [ ] Keep existing full detail editing behavior available after the quick sheet action.
- [ ] Use OPS typography for quantity labels and numeric values.

### Task 3: Guided Setup Shell And Copy

**Files:**
- Modify: `OPS/Views/Catalog/Stock/GuidedStockSetup/GuidedStockSetupFlow.swift`
- Modify: `OPS/Views/Catalog/Stock/GuidedStockSetup/GuidedStockCaptureView.swift`
- Modify: `OPS/Views/Catalog/Stock/GuidedStockSetup/GuidedStockStructureView.swift`
- Verify: guided setup exit, footer, capture prompt, attribute option padding, offcut unit suffix.

- [ ] Add an always-visible close button to the guided setup shell.
- [ ] Preserve existing draft behavior on close.
- [ ] Replace hard-cut bottom bars with `OPSFloatingButtonBar`.
- [ ] Rewrite the first capture heading/helper/prompt so operators list each physical part, service, and bundle component.
- [ ] Move attribute option editor padding inside the nested card.
- [ ] Render the active length/area unit beside offcut inputs.
- [ ] Keep existing validation and draft-builder semantics unchanged.

### Task 4: Catalog Typography Pass

**Files:**
- Modify: `OPS/Views/Catalog/Stock/VariantDetailView.swift`
- Modify: `OPS/Views/Catalog/Products/ProductDetailView.swift`
- Modify: `OPS/Views/Catalog/Products/NewBundleSheet.swift`
- Opportunistic touch only where needed: Catalog create/manage sheets opened by this work.
- Verify: visible drilldown and creation titles do not use default system navigation-title rendering.

- [ ] Replace visible `navigationTitle` text surfaces in touched Catalog paths with tokenized principal/header titles.
- [ ] Keep system SF Symbols only for icons.
- [ ] Ensure action labels use `OPSStyle.Typography.button`.

### Task 5: New Bundle UX Overhaul

**Files:**
- Modify: `OPS/Views/Catalog/Products/NewBundleSheet.swift`
- Reference: `OPS/Views/Catalog/Products/ProductDetailView.swift`
- Reference: `OPS/Views/Catalog/Products/TaskTypePickerSheet.swift`
- Verify: new bundle form has identity, task link, composition, pricing, detail, and floating footer.

- [ ] Add task type selection state and `TaskTypePickerSheet` integration.
- [ ] Save selected `taskTypeId` and `taskTypeRef` into `CreateProductDTO`.
- [ ] Reorganize the form into clear sections with OPS cards.
- [ ] Separate composition from pricing.
- [ ] Move error output above the floating footer.
- [ ] Replace the hard save bar with `OPSFloatingButtonBar`.

### Task 6: Verification And Documentation

**Files:**
- Modify if needed: `../ops-software-bible/07_SPECIALIZED_FEATURES.md`
- Verify: build/tests/diff.

- [ ] Run the focused Catalog tests that cover guided setup and inventory behavior.
- [ ] Run an OPS iOS build.
- [ ] Inspect `git diff --stat` and `git diff --check`.
- [ ] Update the Bible if the implemented Catalog command model or quick-adjust sheet differs from current documentation.
- [ ] Close out every checklist item in the final response with pass/fail evidence.

