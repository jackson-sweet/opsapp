# I6 · Universal-search deep-link destination matrix

**Bug:** `dc74f393-0c2f-45fd-95e4-85ae28d933c6` — "Deep links from search results on iOS do not work for clients. Audit ALL deep links from search results."

**Method:** code-level audit of every result type — tap handler → routing method → destination surface — plus verification of the underlying data-source invariant that guarantees resolution. All paths in `OPS/Views/JobBoard/UniversalSearchSheet.swift`, `OPS/AppState.swift`, `OPS/Views/MainTabView.swift`.

## Entry points (3)

Universal search is one sheet reached from three places; all set `appState.showingUniversalSearch = true`, presented once at `MainTabView.swift:457`.

1. **Job Board** tab — `AppHeader` search button
2. **Schedule** tab — `AppHeader` search button
3. **Catalog** tab — `CatalogView` search button

Every result type is reachable from every entry point (they share the one sheet).

## Destination matrix

| Result type | Tap handler (UniversalSearchSheet.swift) | Routing mechanism | Destination surface | Status |
|---|---|---|---|---|
| **Project** | `navigateToProject` :1154 | `appState.viewProjectDetails` → `showProjectDetails` | `ProjectSheetContainer` (app-root sheet) | ✅ PASS |
| **Task** | `navigateToTask` :1161 | resolves `task.project` → `viewProjectDetails` | parent project detail | ✅ PASS |
| **Client** | `navigateToClient` :1169 | `appState.viewClientDetailsById` → `showClientDetails` | `ContactDetailView` — MainTabView :471 | ✅ PASS (fixed `5c5da9f7`) |
| **Invoice** | `navigateToInvoice` :1176 | `appState.viewInvoiceDetailsById` → `showInvoiceDetails` | `InvoiceDetailViewDeepLinkWrapper` — MainTabView :481 | ✅ PASS (fixed `5c5da9f7`) |
| **Estimate** | `navigateToEstimate` :1183 | `appState.viewEstimateDetailsById` → `showEstimateDetails` | `EstimateDetailViewDeepLinkWrapper` — MainTabView :497 | ✅ PASS (fixed `5c5da9f7`) |
| **User / team** | `selectedDetail = .user` :809 | consolidated enum sheet (attached last) | `ContactDetailView(user:)` — UniversalSearchSheet :444 | ✅ PASS |
| **Inventory item** | `selectedDetail = .inventory` :630 | consolidated enum sheet | `InventoryFormSheet` — UniversalSearchSheet :444 | ✅ PASS |
| **Catalog variant** | `selectedDetail = .catalog` :616 | consolidated enum sheet | `VariantDetailView` — UniversalSearchSheet :444 | ✅ PASS |

## Why the routing is reliable (not just "worked once")

Every result row is backed by SwiftData `@Query`, including the two types most at risk of a network/cache gap:

```
UniversalSearchSheet.swift:39  @Query(filter: #Predicate<Invoice>  { $0.deletedAt == nil }) allLocalInvoices
UniversalSearchSheet.swift:40  @Query(filter: #Predicate<Estimate> { $0.deletedAt == nil }) allLocalEstimates
UniversalSearchSheet.swift:26-38  projects / clients / users / inventory / catalog — all @Query
```

Every app-root deep-link sheet re-fetches the entity **by id from the same `modelContext`** (MainTabView :472–501). Because a result can only appear if it is already in that context, the id lookup is guaranteed to resolve — the deep link cannot silently open an empty sheet for a **search result**. (The empty-sheet edge only exists for external **Spotlight** deep links, which pass an id for a possibly-uncached entity — a different entry point, out of scope for this search-results bug.)

## Root cause of the original client failure

`5c5da9f7` diagnosis: SwiftUI silently drops `.sheet` modifiers beyond ~12 siblings on one view. UniversalSearchSheet had stacked 13; the **client** detail sheet was the one dropped, so `showClient…` flipped true but nothing presented — "deep link broken for clients." The fix de-stacked to 8: client/invoice/estimate route to pre-existing **app-root** sheets; user/inventory/catalog share **one** enum-driven sheet attached last (outermost, never dropped).

## Verdict

All 8 search-result types route to a correct, reachable destination from all 3 entry points; the data-source invariant proves resolution. No broken route remains, and no code change was required for the search path in this pass. Device build compiles clean (routes reference valid symbols). Remaining gate: on-device tap-through of each type — a human QA step, not a code defect.
