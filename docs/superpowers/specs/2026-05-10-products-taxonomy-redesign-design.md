# New Product Sheet — Taxonomy & Relationship Redesign

**Bug**: `164e0595-d972-4957-a2a9-06fcbe9db7b4` — Catalog · Products · "New product sheet needs to be redesigned with user's help."
**Date**: 2026-05-10
**Author**: AI agent (brainstormed with operator Jackson)
**Related phases**: P1-22 (task↔product interlink), P1-28 (Products & Services overhaul)

---

## Problem

`QuickAddProductSheet.swift` makes the user pick from **two overlapping classification fields**:

- `Kind`: `Service | Good`
- `Line item type`: `Labor | Material | Other`

Live data (15 products) shows users always choose redundant pairs (`service+LABOR`, `material+MATERIAL`). The defaults disagree by default (`kind=service`, `type=other`). The user cannot intuitively place a composite product like *"Picket Rail Install"* — is it Labor (it's a job) or Material (it ships physical things) or Other (it's both)?

Two further weaknesses surface in this same sheet:

1. **No connection to inventory.** A `Material` product called "Composite Decking Board" lives in `products`. A `catalog_item` called "Composite Decking Board" lives in inventory. The two are unrelated unless a recipe row manually bridges them.
2. **No connection to tasks.** Bible §10 says a Service product should set `task_type_ref` so install tasks auto-generate when sold. 0 of 15 live products use it because the form doesn't expose the picker.

## Goal

Redesign the New Product sheet so the operator answers **one** category question instead of two, and so the relationships to inventory + tasks are wired in the same flow. Bug `164e0595` resolved end-to-end. iOS sync stays additive — old App Store builds keep working unchanged.

## Non-goals

- **Stock auto-deduction on sale.** The new "// SHOW IN STOCK" toggle creates the inventory link, but the deduction-at-sale wiring (line item → `inventory_deductions`) belongs to the broader P1-28 stock overhaul. The link column is set so P1-28 can deliver it without further iOS work.
- **Configurable products** (options + pricing modifiers). Authoring stays web-only per the existing `ProductDetailView` footer pattern. Components/recipe authoring is in scope; options/modifiers are not.
- **Tax rate picking.** Per-rate `product_tax_rates` selection stays web-only. The boolean `taxable` toggle stays on iOS but pre-defaults intelligently per category.

---

## Final design (locked with operator)

### Section A — Taxonomy collapses to a single 3-way picker

Form replaces the two pickers (`Kind` segmented + `Line item type` segmented under ADVANCED) with one prominent picker at the top:

```
TYPE
┌─────────┬──────────┬──────┐
│ SERVICE │ MATERIAL │ FEE  │
└─────────┴──────────┴──────┘
SERVICE  → something your crew does
MATERIAL → physical thing you sell or supply
FEE      → permit, disposal, subcontractor passthrough
```

Save mapping to existing columns (no schema change for this part):

| User picks | `kind` | `type` | Default `taxable` |
|---|---|---|---|
| **Service**  | `service`  | `LABOR`    | `true` |
| **Material** | `material` | `MATERIAL` | `true` |
| **Fee**      | `service`  | `OTHER`    | `false` |

Rationale for Fee → `kind=service`: the `kind` CHECK constraint allows `{service, material, package}` — no `fee` value. Picking `service` keeps Fees out of the Material/inventory paths (they aren't physical) without requiring a constraint relaxation that would break old iOS clients. The `type=OTHER` is the load-bearing classifier; `kind` is mostly legacy.

The previous `Kind` and `Line item type` pickers in the ADVANCED disclosure are **deleted** from the new form.

### Section B — Conditional widgets per category

A small block under the TYPE picker shows category-specific affordances. Clean and tight — only the relevant widget shows.

**SERVICE**:
```
GENERATES TASK
[ NONE                          ▾ ]
```
Picker pulls from `task_types` for the company. Default "None." Saves to `products.task_type_ref`. Hidden when the company has zero TaskTypes (rare; the seed defaults are added during onboarding per `TaskType.createDefaults`).

**MATERIAL**:
```
// SHOW IN STOCK   [ ○○○ ]
(when ON →)
LINKED STOCK ITEM
[ + LINK OR CREATE ITEM         ▾ ]
```
Toggle defaults OFF for fast entry. When ON, opens a picker with two paths:
- **Pick existing** — search `catalog_items` for this company; select one to link.
- **Create new** — auto-creates a `catalog_item` with `name = product.name`, `category_id = product.category_id`, `default_price = base_price`, `default_unit_cost = unit_cost`, `default_unit_id = unit_id`, then creates a single default `catalog_variant` with no option pins. Returns the new `catalog_item_id`.

Saves the chosen item id to a NEW column `products.linked_catalog_item_id` (additive migration — see § Schema Changes). Footer note under the toggle:

> "Adds this product to your stock catalog so you can manage quantities. Auto-deduction on sale ships with the next stock release."

This honesty matters — without it the toggle's name implies behavior we don't yet deliver.

**FEE**:
No extras. Fees don't generate tasks and aren't tracked as stock.

### Section C — "// COMPONENTS" disclosure (Service only)

A new collapsible disclosure mirrors the existing "// ADVANCED" block. Shown **only when TYPE = Service**. Collapsed by default. Lives between CATEGORY (folder picker) and ADVANCED.

When expanded:
```
// COMPONENTS                                               ▾
Components consumed when this service is sold.
─────────────────────────
[Pressure-Treated 2x6 Joist · 8ft]   qty 12   each   [×]
[Joist Hanger]                       qty 24   each   [×]
[ + ADD COMPONENT ]
```

Each row is a `ProductMaterial` (variant-pinned). Tapping `+ ADD COMPONENT` opens the existing `AddProductMaterialSheet` — which already supports the family + variant + quantity flow on iOS.

**Staging behavior (new):** During product creation, the productId doesn't exist yet, so we can't write recipe rows immediately. The form holds pending recipe rows in local state and commits them after the parent product is created. `AddProductMaterialSheet` gains a "draft" mode (when `productId` is empty, return a synthetic DTO via `onCreated` instead of writing to the repo). On main SAVE: product creates first, then each pending recipe row is written via `ProductRichnessRepository.createMaterial` with the freshly-minted `productId`. Errors on a recipe row do not roll back the product (mirror the thumbnail-upload pattern: surface a retry, leave the product visible).

Variant-pinned only on iOS (matches existing iOS recipe authoring scope per bible §13a). Family-pinned with selectors stays web-only.

### Section D — Tax defaults follow category

The `Taxable` toggle stays in ADVANCED. Its default flips automatically when the user picks a category:

| Category | Pre-defaulted toggle |
|---|---|
| Service  | ON  |
| Material | ON  |
| Fee      | OFF |

Once the user manually flips the toggle, that user choice **wins** for the rest of the session — switching categories does not stomp a manual override (track via a `taxableUserOverridden` flag in the form's view-state).

### Section E — Form layout (top to bottom)

```
NEW PRODUCT
─────────────────────────
PRODUCT
  Name      [ _____________________ ]
  Price [ ___ ]   Unit [ Flat rate ▾ ]

TYPE
  [ SERVICE ] [ MATERIAL ] [ FEE ]

  ┌─ conditional per category ─┐
  IF SERVICE:
    GENERATES TASK   [ None ▾ ]
  IF MATERIAL:
    // SHOW IN STOCK [ ○ ]
    (when ON) LINKED STOCK ITEM [ + LINK OR CREATE ▾ ]
  IF FEE:
    (none)

THUMBNAIL
  [ + ADD THUMBNAIL ]

CATEGORY                        ← catalog_category folder; existing
  [ None ▾ ]

// COMPONENTS                   ← NEW; Service-only; collapsed
  (recipe rows + add button)

// ADVANCED                     ← existing, slimmed
  Description
  SKU            Unit cost   [margin: 23%]
  Toggle: Taxable  ← pre-defaulted by TYPE; user override sticky
  // REMOVED: Kind picker
  // REMOVED: Line item type picker

[ SAVE ]                        ← pinned bar; existing
[ // SAVE AND ADD ANOTHER ]     ← pinned toggle; existing
```

Visual rules per `ops-design-system/project/SKILL.md`: all spacing/colors/typography from `OPSStyle`. Numbers in JetBrains Mono. Section headers use existing `CatalogSectionHeader` and `CatalogFieldLabel` components. Touch targets ≥ 60pt for primary controls, 44pt minimum for everything else. Haptics: `.light` on picker selection, `.medium` on save commit, `.success` notification on save success.

---

## Schema changes (additive only)

One new column on `products`:

```sql
ALTER TABLE public.products
ADD COLUMN linked_catalog_item_id uuid NULL
  REFERENCES public.catalog_items(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS products_linked_catalog_item_id_idx
  ON public.products (linked_catalog_item_id)
  WHERE linked_catalog_item_id IS NOT NULL;
```

- Nullable, defaults to NULL → safe for existing rows and old iOS clients (they neither read nor write it).
- `ON DELETE SET NULL` — deleting a stock item doesn't cascade-delete the priced product.
- Partial index because most rows will be NULL until users adopt the toggle.

No other schema changes. `kind`, `type`, `task_type_ref`, `taxable`, `category_id`, `unit_id` all already exist. `product_materials` already supports the recipe rows.

iOS `Product` SwiftData model gets a corresponding `var linkedCatalogItemId: String?` field. DTO gets `let linked_catalog_item_id: String?` (snake_case in JSON). Old App Store iOS builds simply ignore the unknown column on read (Codable ignores unknown keys by default).

---

## Code-level architecture

### New / modified files

| File | Change |
|---|---|
| `OPS/Views/Catalog/Products/QuickAddProductSheet.swift` | Major refactor — replace `kind` + `lineItemType` with single `category` enum; add conditional widget block; add components disclosure; add tax-default sticky-override logic. |
| `OPS/Views/Catalog/Products/AddProductMaterialSheet.swift` | Add draft mode — when `productId` is empty, return synthetic DTO instead of writing to repo. |
| `OPS/Views/Catalog/Products/Components/CategoryPicker.swift` | NEW — segmented `Service / Material / Fee` picker styled per `OPSStyle`. Reused later in ProductDetailView. |
| `OPS/Views/Catalog/Products/Components/StockItemPicker.swift` | NEW — bottom-sheet picker over `catalog_items` with "Create new" affordance. Returns `catalog_item_id`. |
| `OPS/Views/Catalog/Products/Components/TaskTypeChooser.swift` | NEW — Menu-style picker over `task_types`. Returns `task_type_ref` uuid. |
| `OPS/DataModels/Supabase/Product.swift` | Add `var linkedCatalogItemId: String?`. Add `enum ProductCategory { case service, material, fee }` with `kind`/`type`/`defaultTaxable` derivation helpers. |
| `OPS/DataModels/Enums/FinancialEnums.swift` | Leave `LineItemType` and `ProductKind` unchanged (legacy mirror). Add `ProductCategory` here next to `LineItemType` so all financial classifiers live together. |
| `OPS/Network/Supabase/DTOs/ProductDTOs.swift` | Add `linked_catalog_item_id` field to read/create/update DTOs. |
| `OPS/Network/Supabase/Repositories/ProductRepository.swift` | No change to interface; DTO carries the new field through. |
| `OPS/Network/Supabase/Repositories/CatalogRepository.swift` | Add `createDefaultItemForProduct(productName, companyId, categoryId, defaultPrice, defaultUnitCost, defaultUnitId)` helper that wraps the existing `createFamily` + `createVariant` calls in a single round-trip-friendly call for the "Create new" stock-link path. |
| `ops-software-bible/03_DATA_ARCHITECTURE.md` | Update `Product` field list with `linkedCatalogItemId`. |
| `ops-software-bible/09_FINANCIAL_SYSTEM.md` | Update §Products & Services Catalog with the new 3-way category model. Document `category` as the user-facing concept derived to `kind`+`type`. |

### `ProductCategory` derivation

```swift
enum ProductCategory: String, CaseIterable, Codable {
    case service, material, fee

    /// Recover from the legacy two-field representation. Used when
    /// hydrating the form from an existing Product (edit flow) and when
    /// reading from the wire.
    static func from(kind: ProductKind, type: LineItemType) -> ProductCategory {
        switch type {
        case .labor:    return .service
        case .material: return .material
        case .other:    return .fee
        }
    }

    var derivedKind: String {
        switch self {
        case .service, .fee: return "service"
        case .material:      return "material"
        }
    }

    var derivedType: String {
        switch self {
        case .service:  return "LABOR"
        case .material: return "MATERIAL"
        case .fee:      return "OTHER"
        }
    }

    var defaultTaxable: Bool {
        switch self {
        case .service, .material: return true
        case .fee:                return false
        }
    }
}
```

`type` is the load-bearing classifier (it has higher cardinality alignment with the user's intent), so `from()` derives from `type` alone. `kind` follows `type` on save.

### Save-flow sequence

```
SAVE tapped
  ├─ validate name + price + (if components: each row's qty)
  ├─ ProductRepository.create(dto)           ← writes products row, returns id
  │     dto.kind = category.derivedKind
  │     dto.type = category.derivedType
  │     dto.task_type_ref = (Service only) selectedTaskTypeId
  │     dto.linked_catalog_item_id = (Material only) selectedStockItemId
  │     dto.is_taxable = taxable             (sticky override)
  │
  ├─ if Material + linkStock + selection == "create new":
  │     CatalogItemRepository.createDefaultForProduct(...)
  │     → returns catalog_item_id
  │     → ProductRepository.update(productId, fields: { linked_catalog_item_id })
  │
  ├─ if any pending recipe rows (Service):
  │     for each → ProductRichnessRepository.createMaterial(productId, ...)
  │       on failure: surface inline retry per-row, do NOT roll back product
  │
  ├─ if thumbnail picked:
  │     existing thumbnail upload flow (unchanged)
  │
  └─ success haptic + (saveAndAddAnother ? reset : dismiss)
```

The Material "Create new" path requires two round-trips (create catalog_item, then PATCH product). Acceptable cost for the convenience — typical operator time ~250ms on cellular.

---

## Edit flow

`ProductDetailView.swift` currently exposes a lightweight in-place editor for base fields. Editing existing Products through the new category model:

- Hydrate `selectedCategory` via `ProductCategory.from(kind:type:)`.
- Show the same conditional widget block under the type picker.
- Components section already exists in ProductDetailView (read-only with manage sheet behind a button) — leave that path alone for now; the new sheet is the create-time experience.
- Saving an edit writes `kind`, `type`, `task_type_ref`, `linked_catalog_item_id`, and `is_taxable` per the same rules.

Out of scope for this fix: full ProductDetailView UI refresh to use the new category picker. That can ride on top in a follow-up; the core fix is the create-time sheet plus the additive schema column.

---

## Backward compatibility

| Surface | Behavior |
|---|---|
| Old iOS App Store builds reading new-shape Products | `kind` always one of `{service, material}` (Fees write `kind=service`). `type` always one of `{LABOR, MATERIAL, OTHER}`. Both fall within the existing iOS Codable enums. New `linked_catalog_item_id` column ignored on read. **No breakage.** |
| Old iOS builds writing Products | Continue to write today's `kind` + `type` pair. New column stays NULL. **No breakage.** |
| Web app reading new-shape Products | Web reads `kind` + `type` independently today. Web already understands `kind = 'material'`. `linked_catalog_item_id` column appears in `products` and is initially read-nowhere — web migration to surface it is P1-28 territory. **No breakage.** |
| Estimate / Invoice line-item generation | Reads `products.type` to set `EstimateLineItem.type`. Unchanged. **No regression.** |
| Recipe resolver / cut-list materializer | Reads `product_materials`. Unchanged. **No regression.** |

---

## Test plan

Build verification (`xcodebuild -scheme OPS -destination 'generic/platform=iOS'` per OPS/CLAUDE.md — no simulator).

Manual checks (recorded in PR description):

1. **Three categories save correctly.** Create one product per category. Verify in Supabase that `kind`/`type` pair matches the table above.
2. **Tax default flips with category.** Pick Fee → toggle goes OFF. Pick Material → ON. Manually flip toggle. Switch categories. Manual override sticks.
3. **Service + TaskType.** Pick Service. Pick "Roofing" (or any seed task type). Save. Verify `task_type_ref` set.
4. **Material + Show in Stock + Pick existing.** Toggle on, pick an existing `catalog_item`. Save. Verify `linked_catalog_item_id` set to that uuid.
5. **Material + Show in Stock + Create new.** Toggle on, pick "Create new." Save. Verify a new `catalog_items` row exists with the expected name + a default `catalog_variant`. Verify product's `linked_catalog_item_id` references the new row.
6. **Service + Components.** Add 2 recipe rows in the Components disclosure. Save. Verify `product_materials` has 2 rows pinned to the chosen variants.
7. **Components row failure.** Force one recipe-row creation to fail (e.g. delete a chosen variant mid-flight). Save. Verify product was created and inline retry surfaces. Verify product visible in catalog list.
8. **Edit flow hydrates correctly.** Save a Material product, reopen `ProductDetailView`. Verify category resolves from `type=MATERIAL` to MATERIAL. (Detail view doesn't yet show category picker — verify base fields hydrate.)
9. **Old iOS build compatibility (manual via TestFlight prior build).** Install previous build. Browse catalog. Verify products created in the new format display without crash and edit without losing fields.

---

## Open questions resolved

- **Q1 (taxonomy)**: A — Service / Material / Fee. **Reconciled mid-implementation to 4-way (Service / Material / Fee / Bundle)** to merge with a parallel iOS session that extended `ProductCategory` with `.bundle` (mapping to existing `kind='package'`). Bundle behaves like Service for the conditional widgets — required task type + Components disclosure.
- **Q2 (composites)**: B — optional Components disclosure for Service AND Bundle. Use existing `AddProductMaterialSheet` with new draft mode. Bundle conceptually requires components; we don't enforce it (empty bundle still saves), but the disclosure is always pre-visible for Bundle.
- **Q3 (inventory link)**: B — optional `// SHOW IN STOCK` toggle (Material only). Auto-deduction on sale deferred to P1-28; copy is honest about that.
- **Q4 (task type link)**: B — Task Type picker on Service AND Bundle products. Writes `task_type_ref`.
- **Tax handling**: Category sets a sensible default for the existing `taxable` toggle. Manual user override sticks across category switches. Per-rate `product_tax_rates` selection stays web-only.

### Taxonomy mapping (final, 4-way)

| User picks | `kind` | `type` | Default `taxable` | Task type | Components | Stock link |
|---|---|---|---|---|---|---|
| **Service**  | `service`  | `LABOR`    | `true`  | required | optional | — |
| **Material** | `material` | `MATERIAL` | `true`  | — | — | optional |
| **Fee**      | `service`  | `OTHER`    | `false` | — | — | — |
| **Bundle**   | `package`  | `OTHER`    | `true`  | required | optional | — |

---

## Out-of-scope for this fix (filed for later)

- **P1-28**: Wire `inventory_deductions` to fire when a Material line item with `linked_catalog_item_id` is sold (estimate approved or invoice finalized).
- **P1-22**: Extend the Task Type picker to support per-product custom task titles + dependency overrides.
- **ProductDetailView**: Refresh to use the new category picker instead of the legacy two-field shape.
- **Configurable products**: Options + pricing modifiers authoring on iOS. Stays web-only per existing pattern.
- **Per-rate tax picker on iOS**: Continue to defer. Current toggle is good enough for the 90% case.
