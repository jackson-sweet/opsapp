# Catalog Inventory Quality Pass Design

**Goal:** Bring the iOS Catalog/Inventory tab to production standard by resolving the reported UX defects, moving crowded creation actions out of the global FAB, tightening guided setup, replacing system-font drift, and closing the stock quick-adjust bug surfaced from Supabase.

**Source Inputs**

| Source | Item | Required outcome |
| --- | --- | --- |
| User report | Stock list cards have uneven left/right padding | Parent and child stock cards align with balanced horizontal spacing. Nested children may show hierarchy, but the card itself cannot look left-heavy. |
| User report | Catalog section in FAB has too many actions | Catalog creation/setup actions move to the Catalog header ellipsis menu. The global FAB no longer carries the Catalog action stack while the Catalog tab is active. |
| User report | Guided setup cannot be exited | Guided setup gets an explicit close/exit affordance that preserves draft state and dismisses the flow. |
| User report | First guided setup question is ambiguous | The capture prompt tells operators to list each part, material, service, and bundle component instead of one umbrella system name. |
| User report | Attribute options cards have no top/left padding | Attribute value editor content is padded inside the nested card. |
| User report | Guided setup footer has a hard cutoff | Bottom controls use the shared floating footer treatment rather than a hard full-width slab. |
| User report | Offcut inputs should show selected unit | Offcut length fields render the active unit beside the input, for example `ft`. |
| User report | Product drilldown title uses system font | Catalog drilldown/create sheet titles use OPS typography instead of default navigation-title rendering. |
| User report | New bundle form is disorganized and missing task link | New bundle creation is reorganized into identity, task link, composition, pricing, and detail sections with a floating save footer. |
| Supabase bug `a472ca5d-30b5-4d1b-ae00-f2a86affa58f` | Stock card tap should open quick quantity controls | Tapping a stock card opens a half-height quick-adjust sheet; full variant detail remains available from the sheet and via long press/context action. |
| Supabase bug `26123ca0-510f-4424-b564-50966f2980e9` | Draft deck design can be replaced but not edited | Logged as related Catalog/Inventory surface but not part of this UI pass because it sits in project design editing, not the Catalog tab. |
| Supabase QA `a0ead424-8163-411f-96a9-b38486b5e1c6` | Product-stock missing mappings need persistent setup notification | Logged as related Catalog/P6 contract work; no notification schema changes in this visual pass. |

## Final UX Shape

### Catalog Header Ellipsis

The Catalog header ellipsis becomes the command center for Catalog-specific work. It keeps existing advanced stock management actions and adds product creation actions so the global FAB stays clean.

Sections:

- `STOCK`: Guided setup, stock setup, add variant, add family, import.
- `PRODUCTS`: New service, new good, new bundle.
- `MANAGE`: Snapshots, categories, tags, units, thresholds, defaults.
- `ORDERS`: Orders.

The global FAB should not show the Catalog action stack while the Catalog tab is active. Catalog work belongs in the Catalog header because it is context-specific and already has a local command surface.

### Stock List And Quick Adjust

Stock cards keep the current dense operational content but fix visual alignment. Nested child rows use a hierarchy indicator or inset wrapper without changing the perceived left/right padding inside the card.

Tap behavior changes from opening full variant detail directly to opening a quick-adjust sheet at medium detent. The sheet shows the item identity, current on-hand/available quantity, plus/minus controls, exact quantity entry, and two actions: save adjustment and open full detail. Full detail is also reachable from a long-press context menu on the row.

### Guided Setup

Guided setup gets a persistent top control row with step progress and a close button. Closing dismisses the sheet and keeps the local draft so the operator can return later.

The first capture screen asks for physical parts, materials, services, and bundle components. The copy explicitly warns against entering a broad system name when the operator actually needs stockable parts underneath it.

Footer controls use `OPSFloatingButtonBar` so the bottom area feels intentional and safe-area aware. Offcut rows show the active unit suffix beside each numeric field.

### Catalog Typography

Main Catalog drilldown and create sheets avoid default navigation title rendering for visible page titles. Use OPS typography tokens for principal titles, headers, action labels, metadata, and numbers. Existing SF Symbols remain acceptable for icons.

### New Bundle

New bundle creation becomes a structured workflow:

- Identity: bundle name, category, description.
- Task link: optional task type picker so the bundle can be tied to field work when appropriate.
- Composition: selected child products, quantities, required/add-on state, and search/add drawer.
- Pricing: rolled total, override toggle, override price, taxable state.
- Detail: thumbnail URL and lower-priority metadata.

The save/cancel controls use the shared floating footer treatment. Errors render above the footer in an OPS alert card.

## Implementation Checklist

- [ ] Update `OPS/Views/Catalog/CatalogView.swift` header menu actions.
- [ ] Update `OPS/Views/Components/FloatingActionMenu.swift` to remove Catalog-tab action crowding.
- [ ] Update `OPS/Views/Catalog/Stock/CategoryGroupSection.swift` row hierarchy spacing.
- [ ] Add quick-adjust sheet behavior around `OPS/Views/Catalog/Stock/StockView.swift`.
- [ ] Reuse or extract quantity controls from `OPS/Views/Catalog/Stock/VariantDetailView.swift` where practical.
- [ ] Update guided setup shell in `OPS/Views/Catalog/Stock/GuidedStockSetup/GuidedStockSetupFlow.swift`.
- [ ] Update first capture prompt in `OPS/Views/Catalog/Stock/GuidedStockSetup/GuidedStockCaptureView.swift`.
- [ ] Fix attribute/offcut layout in `OPS/Views/Catalog/Stock/GuidedStockSetup/GuidedStockStructureView.swift`.
- [ ] Update Catalog navigation titles in touched product/stock sheets to OPS typography.
- [ ] Rework `OPS/Views/Catalog/Products/NewBundleSheet.swift`.
- [ ] Run focused tests/build.
- [ ] Update the OPS Software Bible if the Catalog action model or quick-adjust behavior changed from documented behavior.

## Verification Checklist

- [ ] `xcodebuild` build succeeds for the OPS scheme.
- [ ] Existing Catalog unit tests still pass or failure is documented with exact cause.
- [ ] Stock list parent and nested rows have balanced spacing.
- [ ] Stock card tap opens quick-adjust at medium detent.
- [ ] Quick-adjust can open full variant detail.
- [ ] Catalog FAB no longer shows the Catalog action stack on the Catalog tab.
- [ ] Catalog header ellipsis exposes stock and product creation actions.
- [ ] Guided setup can be closed and reopened without losing draft state.
- [ ] Guided setup first question no longer encourages umbrella system names.
- [ ] Attribute option cards have internal top/left padding.
- [ ] Offcut rows show the active unit suffix.
- [ ] Guided setup bottom actions use floating footer treatment.
- [ ] Product drilldown and New Bundle visible titles use OPS typography.
- [ ] New Bundle includes task type link and clear composition/pricing hierarchy.

