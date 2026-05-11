# iOS Catalog & Variant Model — Design Spec

**Date:** 2026-05-06
**Author:** Jackson Sweet (with Claude)
**Status:** Pending review
**Origin bugs:** `41d6f2b4`, `3c98650a`, `217c3d1f`, `e08c63a2`, `6192bcc5`, `2837ddae`
**Related artifacts:** `ops-software-bible/03_DATA_ARCHITECTURE.md` § 21 + § Inventory Models · `ops-software-bible/07_SPECIALIZED_FEATURES.md` § 13 · `ops-software-bible/09_FINANCIAL_SYSTEM.md` § Products & Services Catalog · `ops-ios/OPS/Network/Sync/InboundProcessor.swift` · `ops-ios/OPS/Network/Supabase/DTOs/ProductDTOs.swift`

---

## 1. Problem

The iOS app's **Inventory** tab and **Products & Services** screen are out of step with how a trades business actually models goods. Six bug reports and one undocumented schema gap converge on the same fault line:

1. Trades businesses stock items along multiple axes simultaneously (color × mount × size). Today's `inventory_tags` table forces those axes into a single multi-select bucket. Canpro's data shape — six separate `Corner` rows differing only by tag combinations — is the smoking gun.
2. Trades businesses bill at per-unit prices with modifiers (railings per linear foot, +$5/ft for concrete mount, +N hardware kits per corner). Today's `Product` model is a flat `name + price`. The bible's recipe table (`product_materials`) is undocumented and absent from iOS.
3. iOS `ProductDTO` reads/writes wire fields `unit_price` / `cost_price` that **do not exist** in the Supabase `products` table (the actual columns are `default_price` / `unit_cost`). Every product round-trip from iOS to Supabase fails. Canpro masks the bug by having zero products.
4. The Inventory tab today gates on `inventory.view`. The new IA expands the surface to cover stock, billable products, recipes, and threshold-driven order suggestions — a single permission no longer fits.
5. The full sync loop in `InboundProcessor.fullSync` is unprotected — one entity throwing aborts the entire pull. This is the most likely root cause of bug `2837ddae` (Canpro's 58 server-side inventory items not landing on iOS).

The redesign collapses the answers into one coherent system: a **configurable Product model** plus a **variant-aware Catalog** plus a **drawing-driven adapter** that produces one-click estimates and installer cut lists.

## 2. Goals & Non-Goals

### Goals

- Model variant inventory (Color × Mount × Size) properly. Canpro's "Corner" becomes one family with N variants; `task_materials` deductions reference concrete variants.
- Model configurable products. A "Custom Composite Railing" carries options (Mount Type, Mount Surface, Color, Corners) with pricing modifiers (+$5/ft for concrete) and recipe rules that scale by configuration.
- Make richness opt-in. A user can drop a flat `PICKET RAIL — $2500` Product into the system in 8 seconds and never touch options/recipes.
- Land one-click estimates from a Deck Builder drawing — adapter walks design components, finds default Products per company, auto-fills options from design metadata, computes price, snapshots to line items.
- Compile installer cut lists. When a project moves to install, the recipe resolves against the line item's `configured_options` and writes concrete `task_materials` rows.
- Reach the new IA: replace the `Inventory` tab with **`CATALOG`**, sub-segments **`STOCK`** and **`PRODUCTS`**, kebab for everything else (Snapshots, Categories, Tags, Units, Thresholds, Defaults, Orders, Import/Export). Orders surfaces via banner + notification rail + kebab — never a tab segment.
- Fix the sync abort root cause regardless of bug `2837ddae`'s exact origin: per-entity error isolation in `fullSync` plus `app_events` instrumentation so the next failure is diagnosable.
- Keep the bible canonical — same session as the code lands, update eight sections to reflect the new model and document the six previously-undocumented tables.

### Non-Goals (this session)

- OPS-Web Product editor (option authoring, modifier authoring, recipe-rule authoring) — **named follow-up session**. Canpro's initial set of rich Products is seeded via the same hand-crafted migration SQL.
- Coordinated change to ops-web inventory UI — **named follow-up session**. The catalog schema is web-readable as soon as this lands; ops-web continues to render the legacy inventory shape until the follow-up.
- Deck Builder canvas/AR/polygon refactors — **owned by another agent**. We coordinate on a reserved `component_type` and metadata vocabulary; we don't touch their canvas code.
- Backwards compatibility shims for renamed permissions or deleted tables. Old keys/tables get cut clean, per OPS standard.

## 3. Architecture Overview

### 3.1 Two-domain split, one bridge

`products` and the new `catalog_*` tables remain separate domains. The bridge is the recipe table.

```
products  (billable line-item template — Stripe/Shopify "product")
   │
   └─→ product_materials  (recipe rows; resolves variants from line.configured_options)
           │
           └─→ catalog_variants  (the SKU — has quantity, threshold, sku, unit)
                   │
                   └─ belongs to → catalog_items  (variant family — has name, default price/cost, category)
                           │
                           └─ belongs to → catalog_categories  (nested via parent_id, 2-level UI max)

project_tasks ─→ task_materials ─→ catalog_variants  (cut list at install)
estimate_line_items ─→ line_items.configured_options + resolved_unit_price (snapshot)
inventory_deductions ─→ catalog_variants  (audit trail)
```

This split is endorsed by the bible (`09_FINANCIAL_SYSTEM.md` § Products & Services Catalog and `02_USER_EXPERIENCE_AND_WORKFLOWS.md` § Inventory) which has always treated billable templates and stockable SKUs as separate concerns. The redesign documents the bridge (`product_materials`) that the bible has always been silent on.

### 3.2 Configurable Products with options + modifiers + recipe rules

A Product carries optional layers, each `0..N`. A "barebones" Product has zero rows in every optional layer and behaves identically to today's flat product.

```
products                                (always)
  base_price       numeric               -- replaces today's default_price
  pricing_unit     text                  -- 'each' | 'flat_rate' | 'linear_foot' | 'sqft' | 'hour'
  -- existing fields preserved (name, type, kind, taxable, isActive, etc.)
  -- existing wire-field bug fixed: DTO maps to `default_price`/`unit_cost`, not `unit_price`/`cost_price`

product_options                          (0..N — knobs the user configures on a line item)
  name             text                  -- "Mount Type", "Color", "Corners"
  kind             enum                  -- 'select' | 'integer' | 'boolean'
  affects_price    bool
  affects_recipe   bool
  required         bool
  default_value    text                  -- option_value_id, integer, or boolean
  option_default_source text              -- "$design.color" | "$design.mount_type" | NULL
  sort_order       int

product_option_values                    (0..N — for kind='select')
  value            text                  -- "Topmount", "Black", "Concrete"
  sort_order       int

product_pricing_modifiers                (0..N)
  option_id        FK product_options
  trigger_value_id FK product_option_values   -- nullable for select
  trigger_int_min  int                        -- nullable for integer kind
  trigger_int_max  int
  modifier_kind    enum                       -- 'add_per_unit' | 'add_flat' | 'add_per_count' | 'multiply_unit_price'
  amount           numeric

product_materials                        (0..N — recipe rows)
  -- exactly one of: variant-pinned OR family-pinned
  catalog_variant_id   FK catalog_variants  -- pinned variant
  catalog_item_id      FK catalog_items     -- family head
  variant_selector     jsonb                -- {"color":"$option.color","mount":"$option.mount_type"} when family-pinned
  quantity_per_unit    numeric              -- per Product's pricing_unit
  scaled_by_option_id  FK product_options   -- if non-null, multiply by line.configured_options[this option]
  unit_id              FK catalog_units     -- expression unit
  notes                text
  CHECK ((catalog_variant_id IS NOT NULL) <> (catalog_item_id IS NOT NULL))
```

Worked example (Canpro's "Custom Composite Railing"):

```
products row: pricing_unit='linear_foot', base_price=$48.00

product_options:
  Mount Type      select   affects_price=false  affects_recipe=true
                  source=$design.mount_type  default=Topmount
                  values: Topmount, Sidemount
  Mount Surface   select   affects_price=true   affects_recipe=false
                  source=$design.mount_surface  default=Surface
                  values: Surface, Concrete
  Color           select   affects_price=false  affects_recipe=true
                  source=$design.color  default=Black
                  values: Black, White
  Corners         integer  affects_price=false  affects_recipe=true
                  source=$design.corners_count  default=0

product_pricing_modifiers:
  (Mount Surface = Concrete)  →  add_per_unit  +$5.00

product_materials:
  family=Composite Board     selector={color:$color}                   qty=1.05/ft
  family=Bracket             selector={color:$color, mount:$mount_type} qty=2.5/ft
  family=Picket              selector={color:$color}                   qty=4.0/ft
  family=Top Rail            selector={color:$color, mount:$mount_type} qty=1.0/ft
  family=Screws              selector={color:$color}                   qty=18/ft
  family=Corner Hardware Kit selector={color:$color, mount:$mount_type} qty=1   scaled_by=Corners
  variant=Galvanized Anchor  pinned                                    qty=4   scaled_by=Corners
```

A 24 ft / 4 corners / Topmount / Black / Concrete configuration resolves to:
- Unit price: $48 + $5 = $53/ft → 24 × $53 = $1,272 (snapshot at line item)
- Cut list (rendered into `task_materials` at install task creation):

| Variant | Qty |
|---|---|
| Composite Board — Black | 25.2 ft |
| Bracket — Black — Topmount | 60 |
| Picket — Black | 96 |
| Top Rail — Black — Topmount | 24 ft |
| Screws — Black | 432 |
| Corner Hardware Kit — Black — Topmount | 4 |
| Galvanized Anchor (pinned) | 16 |

### 3.3 Catalog tables (replace today's `inventory_*`)

```
catalog_categories        (nested — parent_id self-FK, 2-level UI max)
  id, company_id, name, parent_id (nullable), sort_order, color_hex,
  default_warning_threshold, default_critical_threshold,
  timestamps + deleted_at
  CHECK no cycles (enforced by trigger)
  RLS: company_isolation
  → INDEX on (company_id, parent_id), (company_id, deleted_at)

catalog_items             (variant families — replaces inventory_items at the family level)
  id, company_id, category_id (FK, nullable), name, description,
  default_price, default_unit_cost, default_warning_threshold, default_critical_threshold,
  default_unit_id, image_url, notes,
  is_active, timestamps + deleted_at
  RLS: company_isolation
  → INDEX on (company_id, category_id, deleted_at)

catalog_options           (the variant axes for a family — separate from product_options)
  id, catalog_item_id (FK), name, sort_order
  → INDEX on (catalog_item_id, sort_order)

catalog_option_values
  id, option_id (FK catalog_options), value, sort_order
  UNIQUE (option_id, value)

catalog_variants          (the SKUs — replaces inventory_items at the SKU level)
  id, company_id, catalog_item_id (FK), sku, quantity (numeric, double),
  price_override (numeric, nullable), unit_cost_override (numeric, nullable),
  warning_threshold (numeric, nullable, falls back to family default, then category default),
  critical_threshold (numeric, nullable, fallback chain same),
  unit_id (FK catalog_units, nullable, falls back to family default),
  is_active, timestamps + deleted_at
  RLS: company_isolation (joined via catalog_items.company_id)
  → INDEX on (catalog_item_id, deleted_at), (sku) WHERE deleted_at IS NULL

catalog_variant_option_values    (M2M — variant ↔ option_value combo)
  variant_id, option_value_id
  PRIMARY KEY (variant_id, option_value_id)

catalog_units             (renamed from inventory_units; row migration is rename + retain)
  -- existing schema preserved including dimension and abbreviation
  -- iOS DTO updated to expose dimension and abbreviation (today's bug — DTO ignores them)

catalog_tags              (renamed from inventory_tags; free-form labels)
  -- existing schema preserved (including warning_threshold + critical_threshold columns)
  -- Threshold inheritance now flows category-default → variant-override.
  -- Tag-level thresholds are no longer surfaced in the iOS UI but the columns remain
  -- so the schema doesn't lose data; effective-threshold compute ignores them.
  -- A future session may drop the columns once we confirm zero callers.

catalog_item_tags         (renamed from inventory_item_tags; M2M — variant family ↔ tag)
  -- IMPORTANT: tags now apply at the FAMILY level, not the variant level.
  -- A "Corner" family carries tags like "discontinued"; not each variant separately.

catalog_snapshots / catalog_snapshot_items (renamed from inventory_*; variant-aware)
  -- snapshot now captures (variant_id, quantity_at_time) rather than (item_id, quantity_at_time)

inventory_deductions      (existing table; FK column renamed: inventory_item_id → catalog_variant_id)
  -- audit trail unchanged otherwise
```

### 3.4 Line item snapshot

Estimates and invoices are signed contracts. Configuration must snapshot at line creation so later edits to a Product don't retroactively change the estimate.

```
line_items                (additions to existing table)
  + product_id              FK products (nullable; matches existing field)
  + configured_options      jsonb  -- {"mount_type":"<option_value_id>", "color":"<id>",
                                      "mount_surface":"<id>", "corners": 4}
  + resolved_unit_price     numeric  -- snapshot of base + applicable modifiers
  + resolved_options_label  text     -- "TM · Black · Concrete · 4 corners" (printed-estimate friendly)
```

Recipe re-resolves at install task creation time using the snapshotted `configured_options`. Pricing never re-resolves once written.

### 3.5 Drawing-driven adapter

```
company_default_products
  company_id, component_type, product_id
  PRIMARY KEY (company_id, component_type)
  RLS: company_isolation

  component_type ∈ { 'railing', 'deck_board', 'stair_set', 'gate', 'post_set' }
  -- defined in this spec; deck-builder agent inherits the vocab.
```

Reserved metadata keys in `deck_designs.drawing_data` per `component_type`:

| Component | Required metadata keys |
|---|---|
| `railing` | `linear_feet`, `corners_count`, `color`, `mount_type`, `mount_surface` |
| `deck_board` | `sqft`, `color`, `material` |
| `stair_set` | `tread_count`, `width`, `color`, `mount_type` |
| `gate` | `count`, `width`, `color`, `mount_type`, `mount_surface` |
| `post_set` | `count`, `height`, `color`, `mount_type` |

A Product's `product_options.option_default_source` references these as `$design.<key>`. The adapter, when invoked from Deck Builder's "Generate Estimate" action, walks each component, finds the company-default Product, fills options from design metadata (falling back to `default_value`), computes price + modifiers, and emits a draft `line_item` with full snapshot.

### 3.6 Order suggestions

```
catalog_orders            (NEW — for Bug e08c63a2)
  id, company_id, status (enum: 'suggested' | 'draft' | 'sent' | 'fulfilled' | 'cancelled'),
  supplier_name, supplier_contact, expected_delivery_date,
  notes, created_at, updated_at, sent_at, fulfilled_at, cancelled_at,
  created_by_id (FK users)
  RLS: company_isolation

catalog_order_items
  id, order_id, catalog_variant_id, quantity_requested,
  cost_per_unit (snapshot at order creation), notes
  PRIMARY KEY (id), INDEX on (order_id)
```

Suggested orders are computed on demand (not stored as `suggested` rows until the user opens the Orders sheet): walk all variants where `quantity < effective_warning_threshold`, group by some heuristic (preferred-supplier from a catalog_tags convention if present, else single combined order), compute restock targets (default: refill to 2× warning_threshold, configurable later).

### 3.7 Sync error isolation

Replace `InboundProcessor.fullSync`'s unprotected for-loop with per-entity isolation:

```swift
for (index, entityType) in Self.syncOrder.enumerated() {
    let stepProgress = Double(index) / totalSteps
    onProgress?(entityType, stepProgress)

    do {
        try await syncEntityType(entityType, since: nil, context: context)
    } catch {
        SyncTelemetry.logError(
            entityType: entityType,
            error: error,
            isFullSync: true,
            companyId: companyId
        )
        // Log to app_events as `sync_entity_failed`. Do NOT rethrow — one failing
        // entity must not abort the rest of the pull. The user can re-trigger sync
        // manually if it matters; the error is captured server-side for debugging.
    }
}
```

`SyncTelemetry.logError` writes to `app_events` (existing table) with `event_name='sync_entity_failed'` and properties `{entity_type, error_class, error_message, app_version, sync_phase}`. Same shape applied in `deltaSync`.

This fix is cheap (~30 lines), prerequisite to landing the catalog migration safely (so a failing catalog entity doesn't poison the rest of the pull), and almost certainly resolves Bug `2837ddae` whether the root cause is what I think or something else entirely.

## 4. iOS IA

### 4.1 CATALOG tab (replaces "Inventory" in `MainTabView`)

```
CATALOG
─────────────────────────────────────────────
[ STOCK ]  [ PRODUCTS ]                     ⋮
─────────────────────────────────────────────

STOCK
  ├─ Banner (when applicable):
  │     "// 6 ITEMS BELOW THRESHOLD [REVIEW →]"
  │     ↳ tap opens Orders sheet (Suggested view)
  ├─ View mode:  [ LIST ] [ GRID ] [ TABLE ]
  │   LIST  = today's variant-aware list (cards)
  │   GRID  = today's pinch-to-zoom grid
  │   TABLE = NEW (Bug 217c3d1f) — rows=variants, columns=family attributes
  ├─ Sort/filter: category · tags · threshold · search
  ├─ Category sections (collapsible, nested 2-level):
  │     // HARDWARE
  │       ▸ HARDWARE LEVEL
  │         • Corner — Black · 288
  │         • Corner — White · 70
  │       ▸ HARDWARE STAIR
  │     // FASTENERS
  │       • 2" Screw — Black · 3000
  └─ FAB: + add variant · + add family · + import

PRODUCTS
  ├─ Filter: type · kind · "has recipe"
  ├─ Search
  ├─ List
  │     • PICKET RAIL · $2500 · flat
  │     • Custom Composite Railing · $48/ft · 4 options · 7 recipe rows
  │     • Service Call · $150/hr · service
  └─ FAB: + quick add (3 fields) · + full setup (web)

  Product detail (iOS = view + light edits):
    ├─ Quick fields editable: name, base_price, pricing_unit, type, taxable, active
    ├─ Tags (free-form, multi-select)
    ├─ Sections collapsed if empty:
    │   ▸ Options              (read-only on iOS — author on web)
    │   ▸ Pricing modifiers    (read-only on iOS)
    │   ▸ Recipe               (read-only; rows are tappable → drill to variant)
    └─ Stats: estimates referencing · last sold

⋮ menu (grouped):
  ── STOCK ──
  • Snapshots
  • Categories…
  • Tags…
  • Units…
  • Thresholds…
  ── ORDERS ──
  • Suggested
  • Drafts
  • Sent
  ── SETUP ──
  • Defaults (component_type → product_id mapping)
  • Import…
  • Export…
```

### 4.2 Quick-add Product flow

The friction floor that makes the system usable for barebones users:

```
+ NEW PRODUCT  (FAB → "+ quick add")

  Name:    [PICKET RAIL_______________]
  Price:   [$2500.00]
  Unit:    [● flat   ○ each   ○ ft   ○ sqft   ○ hour]
  Taxable: [✓]

  [SAVE]   ← one tap. No options, no recipe, no modifiers. Total time: 8s.
```

Three required fields. Default `pricing_unit='flat_rate'`. Defaults `type=OTHER`, `kind='service'`, `is_active=true`. An `Advanced ▾` disclosure exposes type/kind/category/sku for the user who wants them; default-collapsed.

### 4.3 Line item UX adapts to product richness

Same form, different fields:

```
Pick "PICKET RAIL" (no options)
  → fields:    Name · Qty · Price · Total

Pick "Custom Composite Railing" (4 options)
  → fields:    Name · Qty (ft) · Mount Type · Mount Surface · Color · Corners · Total
                Each option pre-defaulted to its `default_value`.
                Modifiers preview ("$48 + $5 concrete = $53/ft") inline below price.
```

No mode toggle; option fields appear when the chosen Product has options. Defaults pre-fill so manual entry is mostly tap-confirm.

### 4.4 Drawing → estimate (one-click path)

```
Deck Builder  →  user taps GENERATE ESTIMATE
              ↓
For each design component:
  - Look up company_default_products[component_type]
  - For each Product option: read $design.<key> via option_default_source
  - Compute quantity from geometry (linear_feet, sqft, count)
  - Apply pricing_modifiers
  - Snapshot to line_items.configured_options + resolved_unit_price + resolved_options_label
              ↓
Draft estimate appears, fully populated.
```

If the company hasn't set a default for a component_type, the adapter logs to `app_events` and skips that component (rather than blocking estimate creation). The user reviews the draft and can add line items by hand if anything's missing.

## 5. Permissions

Rename plus split:

| Old | New | Purpose |
|---|---|---|
| `inventory.view` | `catalog.view` | Gate the CATALOG tab |
| `inventory.manage` | `catalog.manage` | Adjust quantity, edit variants, manage categories/tags/units |
| `inventory.import` | `catalog.import` | Bulk import |
| — | `catalog.products.manage` | NEW — author/edit Products (options, modifiers, recipes). Rich admin. |
| — | `catalog.orders.manage` | NEW — draft/send/fulfill orders. Operational role. |

Migration: UPDATE the 5 `role_permissions` rows that carry `inventory.*` to `catalog.*`. Add new rows for the two new keys mapped to roles that have `inventory.manage` today (Owner, Admin). Update `has_permission()` callers in iOS (`PermissionStore`) and ops-web (`auth-store`). No alias layer.

## 6. Migration plan

### 6.1 Schema migration (Supabase, runs server-side as a single transaction)

`ops-software-bible/migrations/2026-05-06-catalog-variant-model.sql`:

1. CREATE all `catalog_*` tables with RLS policies, indexes, and the cycle-prevention trigger on `catalog_categories`.
2. ALTER `products`:
   - Add `pricing_unit text NOT NULL DEFAULT 'each'`
   - Add `base_price numeric NOT NULL DEFAULT 0`
   - Backfill `base_price = default_price` (with explicit cast)
   - **Keep `default_price` column for now**, add a trigger that mirrors `base_price` ↔ `default_price` writes both directions. ops-web continues reading `default_price` until the follow-up ops-web session ships. The trigger is removed and `default_price` dropped at that follow-up.
3. ALTER `line_items`:
   - Add `configured_options jsonb NULL`
   - Add `resolved_unit_price numeric NULL`
   - Add `resolved_options_label text NULL`
4. CREATE `product_options`, `product_option_values`, `product_pricing_modifiers`, `company_default_products`, `catalog_orders`, `catalog_order_items`.
5. ALTER `product_materials`: add `catalog_variant_id`, `catalog_item_id` (one-of constraint), `variant_selector jsonb`, `scaled_by_option_id`, `unit_id`.
6. RENAME `inventory_*` tables to `catalog_*` equivalents OR keep both names (decision: rename, single source of truth — inventory_* gets dropped after data migration; backwards-compat shim is verboten).
7. Update `inventory_deductions`: the table is currently empty (0 rows globally), so no data needs migrating. Rename `inventory_item_id` column to `catalog_variant_id` and re-FK to `catalog_variants(id)`.
8. UPDATE `role_permissions` for the permission rename. INSERT new rows for `catalog.products.manage` and `catalog.orders.manage`.

### 6.2 Data migration (bespoke per company)

`ops-software-bible/migrations/2026-05-06-catalog-data-canpro-maverick.sql`:

For each of the two companies with real data, hand-crafted SQL:
- INSERT `catalog_categories` rows.
- INSERT `catalog_items` (variant families) by `lower(trim(name))` collapse.
- INSERT `catalog_options` per family. Color axis on every family that has Black/White tags (essentially all of Canpro's). Mount Type axis on families whose existing items are tagged with `Topmount` or `Side mount` (e.g., Corner, Bracket, Top Rail). Author the families and axes case-by-case; we have ~10–14 distinct families to handle, not a generic algorithm.
- INSERT `catalog_option_values` for the option axes.
- INSERT `catalog_variants` — one per existing `inventory_items` row, preserving quantity, sku, thresholds, unit_id.
- INSERT `catalog_variant_option_values` — variant ↔ option-value combos derived from each item's tag set.
- Promote tags: `Black/White/Topmount/Sidemount` → option values; `Hardware Level/Hardware Stair/Rail/Screws/Gate` (Canpro) and `White Qty/Black Qty` (Maverick) → consumed by the option promotion. Survive as tags: none for Canpro/Maverick (clean slate).
- Verification query: `sum(catalog_variants.quantity)` GROUP BY company = `sum(inventory_items.quantity)` GROUP BY company before the migration; same for variant count vs. item count.

Other companies start fresh — schema migration creates empty `catalog_*` for them; they author their first variants via the new UI.

### 6.3 iOS migration (release ordering)

1. Land Supabase schema migration (server-side; reversible).
2. Land Supabase data migration (Canpro + Maverick); audit logs in `app_events`.
3. Ship iOS update with new CATALOG tab + variant-aware DTOs + sync error isolation + permission rename.
4. Ship ops-web compatibility patch (read catalog tables via legacy view? or rewrite legacy inventory components to read catalog?). **This is the named follow-up session; not part of this work.**

### 6.4 Bible updates (same-session-as-code per CLAUDE.md)

Eight sections rewrite or add:

1. `03_DATA_ARCHITECTURE.md` § 21 (Product) — add the 9 missing fields, document recipes and configured options.
2. `03_DATA_ARCHITECTURE.md` § Inventory Models — replace with new catalog model documentation.
3. `03_DATA_ARCHITECTURE.md` add a new "Catalog Variant Model" section with full schema + RLS + DTO listing.
4. `03_DATA_ARCHITECTURE.md` add documentation for `product_materials`, `task_materials`, `line_item_materials`, `inventory_deductions`, `client_product_overrides`, `product_tax_rates`, `company_default_products`, `catalog_orders`, `catalog_order_items`.
5. `04_API_AND_INTEGRATION.md` — update tables list to include the new tables.
6. `07_SPECIALIZED_FEATURES.md` § 13 (Inventory Management) — rewrite as "Catalog Management" with variant-aware UX, table view mode, drawing adapter.
7. `09_FINANCIAL_SYSTEM.md` § Products & Services Catalog — update Product entity with new fields, document configurable Products and recipes.
8. `02_USER_EXPERIENCE_AND_WORKFLOWS.md` — rename Inventory tab to Catalog throughout, document new IA + screens.
9. `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` — document line_item snapshot fields, recipe resolution at install task creation, cut list emergence in `task_materials`.

## 7. Risks & open questions

### 7.1 Risks

- **Product DTO wire-field bug fix coordinates with ops-web.** The iOS DTO maps `unitPrice` to wire field `unit_price` — a column that doesn't exist. The actual column today is `default_price`. We add `base_price` and keep `default_price` mirrored via trigger (decision in §6.1) so ops-web continues to function unchanged. iOS DTO updates to read/write `base_price`. The mirror trigger is removed when ops-web cuts over in a follow-up session.
- **Deck Builder coordination.** The reserved component_type vocabulary + metadata keys must land in `deck_designs.drawing_data` before the adapter is useful. The deck-builder agent owns canvas; we need them to (a) tag each component with a `component_type` and (b) write the agreed metadata keys. Coordinate via a shared subset of `drawing_data`. **Risk: if they don't land it in time, one-click estimates from drawings ship as a no-op for this release.** Manual line item entry continues to work.
- **OPS-Web compatibility window.** ops-web reads/writes `inventory_*` tables today. The schema migration's table rename breaks ops-web until the follow-up session. Decision: **keep `inventory_*` tables as views over the new `catalog_*` tables** so ops-web continues to read them transparently. Writes from ops-web's existing inventory editor go through INSTEAD OF triggers that translate to `catalog_*` operations. The view layer is removed when ops-web is rewritten in the follow-up. This keeps ops-web operational with zero changes during the window.
- **Bible drift.** Eight (nine) bible sections to rewrite is a lot. If one section gets missed, the bible misleads agents in future sessions. Mitigation: explicit checklist task in the implementation plan, verified by a final review pass before commit.
- **Permission rename in iOS.** `MainTabView` gates on `inventory.view`. ops-web's route gates on `inventory.view`. Renaming breaks both clients on the wire — they call `has_permission(user_id, 'inventory.view', 'all')` and the function will return false after the UPDATE. We coordinate iOS + ops-web release with the SQL UPDATE.

### 7.2 Open questions for implementation phase

- Default unit when collapsing Canpro's items (current `unit_id` is null on every item) — pick "ea" as default at family level, or leave variants null and let the user fix per-family later?
- Threshold inheritance precedence: variant override → family default → category default → null. Confirmed in the spec, but the `effectiveThreshold()` chain needs explicit testing.
- `variant_selector` JSON schema — define a strict schema and validate at write time, or accept arbitrary JSON and validate at resolution time? Strict schema is safer.
- Cycle prevention on `catalog_categories.parent_id` — trigger or app-layer check? Trigger is canonical.
- iOS table-view-mode rendering: which columns when there are 5+ option values? Truncate or scroll horizontally? **Defer to interface-design pass.**

## 8. Testing strategy (high-level)

- **Unit (iOS):** option resolution, modifier computation, recipe resolution from `configured_options`, threshold fallback chain, sync error isolation logging.
- **Integration (iOS):** full sync with one entity throwing — verify other entities still complete and error logged. Catalog migration round-trip on Canpro fixture data.
- **SwiftData migration:** verify `catalog_*` SwiftData entity registration; verify backwards compatibility with existing local DB after schema bump (offline users opening the new build first time).
- **End-to-end:** Generate Estimate from a Canpro deck design, verify draft line items + cut list at install task creation.
- **Migration verification:** SQL queries comparing pre/post quantity sums and family/variant counts for Canpro + Maverick.
- **Bible review:** post-implementation pass confirming all nine sections updated, no stale references to `inventory_*` outside legacy notes.

## 9. Approval

Spec is rich; surface area is real. The model is correct; the IA is tight; the migration is bounded; the bible plan is explicit. Open questions are scoped to implementation-phase decisions, not architecture.

Ready for review. Once accepted, the next step is invoking `superpowers:writing-plans` to translate this into a phased implementation plan with explicit sub-tasks, verification commands, and review checkpoints.
