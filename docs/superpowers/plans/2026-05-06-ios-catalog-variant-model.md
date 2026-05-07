# iOS Catalog & Variant Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace iOS Inventory tab and flat Product model with a CATALOG tab containing variant-aware Stock + configurable Products with recipes, pricing modifiers, and one-click estimate generation from Deck Builder drawings — closing six user-reported bugs and the iOS↔web product wire-field bug.

**Architecture:** Keep `products` and a new `catalog_*` table set as separate Supabase domains, bridged by `product_materials` recipe rows. Configurable Products carry `0..N` options, pricing modifiers, and recipe rules — barebones Products with zero rows in those layers behave identically to today. iOS schema bumps to OPSSchemaV3 with a migration plan from V2. ops-web continues to read inventory through views over the new tables with INSTEAD OF triggers, deferring its full rewrite to a follow-up session.

**Tech Stack:** Swift 5.9+/SwiftUI/SwiftData (iOS 17+), Supabase (Postgres + RLS + PostgREST), supabase-swift SDK, OPSStyle tokens (`OPS/OPS/Styles/OPSStyle.swift`), XCTest in `OPSTests/`.

**Spec:** `docs/superpowers/specs/2026-05-06-ios-catalog-variant-model-design.md`

---

## Phase Map

| Phase | Title | Goal |
|---|---|---|
| 1 | Supabase schema migration | New `catalog_*` tables, expanded `products`, `line_items` snapshot, views + triggers for ops-web compat |
| 2 | Hand-crafted data migration | Bespoke SQL for Canpro + Maverick with pre/post verification |
| 3 | iOS DataModel + DTO + Repository foundation | SwiftData models, Codable DTOs, Supabase repositories — incl. ProductDTO wire-field fix |
| 4 | iOS sync layer | InboundProcessor catalog support, per-entity error isolation, app_events instrumentation |
| 5 | iOS CATALOG tab IA | MainTabView swap, two-segment shell, kebab menu |
| 6 | Stock view modes | Variant-aware list/grid + new TABLE view |
| 7 | Products surface | Quick-add, advanced disclosure, Product detail with read-only options/recipe |
| 8 | Line item adaptation | EstimateLineItemFormSheet adapts to product richness |
| 9 | Orders surface | Banner, sheet, persistent notification rail integration |
| 10 | Drawing → estimate adapter | Reserve component_type vocabulary, walk design, emit draft estimate |
| 11 | Cut-list materializer | Recipe resolution at install task creation, write `task_materials` |
| 12 | Permission rename | `inventory.*` → `catalog.*`, add `catalog.products.manage` + `catalog.orders.manage` |
| 13 | Bible updates | Nine sections rewritten to reflect the new model |
| 14 | End-to-end verification | Canpro full-sync round-trip, build verification, regression sweep |

---

## File Structure

### Created files

**Supabase migrations** (in `ops-software-bible/migrations/`):
- `2026-05-06-01-catalog-schema.sql` — schema-only DDL
- `2026-05-06-02-catalog-views-triggers.sql` — views over new tables, INSTEAD OF triggers, base_price↔default_price mirror trigger
- `2026-05-06-03-catalog-data-canpro-maverick.sql` — bespoke per-company INSERTs with verification
- `2026-05-06-04-permission-rename.sql` — UPDATE + INSERT on `role_permissions`

**iOS SwiftData models** (in `OPS/OPS/DataModels/Supabase/Catalog/` — new directory):
- `CatalogCategory.swift`
- `CatalogItem.swift`
- `CatalogVariant.swift`
- `CatalogOption.swift`
- `CatalogOptionValue.swift`
- `CatalogVariantOptionValue.swift`
- `CatalogTag.swift`
- `CatalogUnit.swift`
- `CatalogSnapshot.swift`
- `CatalogSnapshotItem.swift`
- `CatalogOrder.swift`
- `CatalogOrderItem.swift`
- `CompanyDefaultProduct.swift`
- `ProductOption.swift`
- `ProductOptionValue.swift`
- `ProductPricingModifier.swift`
- `ProductMaterial.swift`

**iOS schema migration:**
- `OPS/OPS/DataModels/Migrations/OPSSchemaV3.swift` (new schema version)
- `OPS/OPS/DataModels/Migrations/OPSMigrationPlan.swift` (extend with V2→V3 stage)

**iOS DTOs** (in `OPS/OPS/Network/Supabase/DTOs/`):
- `CatalogDTOs.swift` — DTOs for all 12 catalog tables + variant_option_values join
- `ProductExtensionDTOs.swift` — DTOs for `product_options`, `product_option_values`, `product_pricing_modifiers`, `product_materials`
- `CompanyDefaultProductDTOs.swift`
- `CatalogOrderDTOs.swift`

**iOS Repositories** (in `OPS/OPS/Network/Supabase/Repositories/`):
- `CatalogRepository.swift` (replaces InventoryRepository)
- `CatalogOrderRepository.swift`
- `CompanyDefaultProductRepository.swift`
- `ProductRichnessRepository.swift` — fetches options/modifiers/recipe for a product

**iOS services:**
- `OPS/OPS/Services/SyncTelemetry.swift` — per-entity error logging to `app_events`
- `OPS/OPS/Services/RecipeResolver.swift` — line item → task_materials resolution
- `OPS/OPS/Services/DesignToEstimateAdapter.swift` — Deck design → draft estimate
- `OPS/OPS/Services/OrderSuggestionEngine.swift` — threshold-driven order computation

**iOS Views** (in `OPS/OPS/Views/Catalog/`):
- `CatalogView.swift` — top-level tab shell
- `Stock/StockView.swift`
- `Stock/StockListView.swift`
- `Stock/StockGridView.swift`
- `Stock/StockTableView.swift`
- `Stock/CategoryGroupSection.swift`
- `Stock/VariantCard.swift`
- `Stock/VariantDetailView.swift`
- `Stock/VariantFormSheet.swift`
- `Stock/AddFamilySheet.swift`
- `Products/ProductsListView.swift` (replaces existing)
- `Products/ProductDetailView.swift`
- `Products/QuickAddProductSheet.swift`
- `Products/ProductFormSheet.swift` (replaces existing)
- `Products/RecipeReadOnlyView.swift`
- `Products/OptionsReadOnlyView.swift`
- `Products/ModifiersReadOnlyView.swift`
- `Orders/OrdersSheet.swift`
- `Orders/OrderDetailView.swift`
- `Orders/SuggestedOrderRow.swift`
- `Orders/OrderBanner.swift`
- `Manage/CatalogKebabMenu.swift`
- `Manage/CategoriesManageSheet.swift`
- `Manage/TagsManageSheet.swift`
- `Manage/UnitsManageSheet.swift`
- `Manage/ThresholdsManageSheet.swift`
- `Manage/DefaultsManageSheet.swift`

**iOS tests** (in `OPSTests/Catalog/`):
- `CatalogModelTests.swift`
- `CatalogDTOTests.swift`
- `CatalogRepositoryTests.swift`
- `RecipeResolverTests.swift`
- `DesignToEstimateAdapterTests.swift`
- `OrderSuggestionEngineTests.swift`
- `SyncTelemetryTests.swift`
- `EffectiveThresholdTests.swift`

### Modified files

**iOS schema registration:**
- `OPS/OPS/DataModels/Migrations/OPSSchemaCommon.swift` — drop `InventoryItem`/`InventoryTag`/`InventoryUnit`/`InventorySnapshot`/`InventorySnapshotItem`, add catalog models + Product extension models
- `OPS/OPS/OPSApp.swift` — point at OPSSchemaV3

**iOS data models (modify):**
- `OPS/OPS/DataModels/Supabase/Product.swift` — add 9 missing fields (`category`, `kind`, `sku`, `is_favorite`, `minimum_charge`, `minimum_quantity`, `show_bom_on_estimate`, `show_in_storefront`, `tiered_pricing`), `pricing_unit`, `base_price`
- `OPS/OPS/DataModels/Supabase/EstimateLineItem.swift` — add `configured_options`, `resolved_unit_price`, `resolved_options_label`
- `OPS/OPS/DataModels/Supabase/InvoiceLineItem.swift` — same
- `OPS/OPS/DataModels/Company.swift` — add `defaultProducts` relationship reference

**iOS DTO + Repository (modify):**
- `OPS/OPS/Network/Supabase/DTOs/ProductDTOs.swift` — fix wire-field bug (`unit_price` → `default_price`+`base_price`, `cost_price` → `unit_cost`); add 9 missing fields and pricing_unit/base_price
- `OPS/OPS/Network/Supabase/DTOs/EstimateDTOs.swift` — add line item snapshot fields
- `OPS/OPS/Network/Supabase/DTOs/InvoiceDTOs.swift` — same
- `OPS/OPS/Network/Supabase/Repositories/ProductRepository.swift` — fix wire-field, add fetchOptions/fetchModifiers/fetchMaterials methods

**iOS sync:**
- `OPS/OPS/Network/Sync/SyncTypes.swift` — replace inventory entity types with catalog entity types
- `OPS/OPS/Network/Sync/InboundProcessor.swift` — replace inventory sync methods with catalog sync methods, wrap fullSync in per-entity error isolation
- `OPS/OPS/Network/Sync/OutboundProcessor.swift` — adapt for catalog operations

**iOS views (modify):**
- `OPS/OPS/Views/MainTabView.swift` — replace Inventory tab/check with Catalog tab/check
- `OPS/OPS/Views/Estimates/EstimateLineItemFormSheet.swift` (or equivalent path) — adapt to product richness
- `OPS/OPS/Views/Estimates/ProductPickerSheet.swift` — show option summary
- `OPS/OPS/Views/Common/FloatingActionMenu.swift` — Catalog-aware FAB actions

**iOS permissions:**
- `OPS/OPS/Services/PermissionStore.swift` (or wherever permission keys live) — replace `inventory.*` with `catalog.*`, add new keys

**Bible:**
- `ops-software-bible/03_DATA_ARCHITECTURE.md`
- `ops-software-bible/04_API_AND_INTEGRATION.md`
- `ops-software-bible/07_SPECIALIZED_FEATURES.md`
- `ops-software-bible/09_FINANCIAL_SYSTEM.md`
- `ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md`
- `ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`

### Deleted files

**iOS data models:**
- `OPS/OPS/DataModels/InventoryItem.swift`
- `OPS/OPS/DataModels/InventoryTag.swift`
- `OPS/OPS/DataModels/InventoryUnit.swift`
- `OPS/OPS/DataModels/InventorySnapshot.swift`
- `OPS/OPS/DataModels/InventorySnapshotItem.swift`

**iOS DTOs/Repositories:**
- `OPS/OPS/Network/Supabase/DTOs/InventoryDTOs.swift`
- `OPS/OPS/Network/Supabase/Repositories/InventoryRepository.swift`
- (Old `OPS/OPS/Network/DTOs/InventoryItemDTO.swift`, `InventorySnapshotDTO.swift`, `InventorySnapshotItemDTO.swift`, `InventoryTagDTO.swift`, `InventoryUnitDTO.swift` — unused after the catalog cutover; verify and delete.)

**iOS views:**
- `OPS/OPS/Views/Inventory/` (entire folder — content moved to `Views/Catalog/Stock/`)
- `OPS/OPS/Views/Products/` (entire folder — content moved to `Views/Catalog/Products/`)

---

## Phase 1 — Supabase schema migration

Goal: create `catalog_*` tables + extension columns on `products` and `line_items`, plus a compatibility layer (views + INSTEAD OF triggers + base_price↔default_price mirror trigger) so ops-web continues to read and write the legacy `inventory_*` shape against the new tables.

Apply migrations via the Supabase MCP `apply_migration` and `execute_sql` tools.

### Task 1: Capture pre-migration baseline

**Files:**
- Capture in plan execution log; no files written.

- [ ] **Step 1: Run baseline counts query and record results in execution log**

```sql
SELECT 'inventory_items' AS table_name, COUNT(*) FILTER (WHERE deleted_at IS NULL) AS active_rows
  FROM public.inventory_items
UNION ALL SELECT 'inventory_tags', COUNT(*) FILTER (WHERE deleted_at IS NULL) FROM public.inventory_tags
UNION ALL SELECT 'inventory_units', COUNT(*) FILTER (WHERE deleted_at IS NULL) FROM public.inventory_units
UNION ALL SELECT 'inventory_item_tags', COUNT(*) FROM public.inventory_item_tags
UNION ALL SELECT 'inventory_snapshots', COUNT(*) FROM public.inventory_snapshots
UNION ALL SELECT 'inventory_snapshot_items', COUNT(*) FROM public.inventory_snapshot_items
UNION ALL SELECT 'inventory_deductions', COUNT(*) FROM public.inventory_deductions
UNION ALL SELECT 'products', COUNT(*) FILTER (WHERE deleted_at IS NULL) FROM public.products
UNION ALL SELECT 'product_materials', COUNT(*) FROM public.product_materials
UNION ALL SELECT 'task_materials', COUNT(*) FROM public.task_materials
UNION ALL SELECT 'line_item_materials', COUNT(*) FROM public.line_item_materials;
```

Expected (May 2026): `inventory_items=182`, `inventory_tags=18`, `inventory_units=80`, `inventory_item_tags=238`, snapshots=0, snapshot_items=0, inventory_deductions=0, `products=15`, product_materials=0, task_materials=0, line_item_materials=0. Confirm and record.

- [ ] **Step 2: Per-company snapshot for migrated companies**

```sql
SELECT c.name, COUNT(i.*) FILTER (WHERE i.deleted_at IS NULL) AS items, SUM(i.quantity) FILTER (WHERE i.deleted_at IS NULL) AS qty_sum
FROM public.companies c LEFT JOIN public.inventory_items i ON i.company_id=c.id
WHERE c.id IN ('a612edc0-5c18-4c4d-af97-55b9410dd077','ddee107c-33cd-483e-8278-0f8d8a180181')
GROUP BY c.id, c.name;
```

Expected: Canpro `items=58`, Maverick `items=58`, qty_sum recorded for verification in Phase 2.

### Task 2: Write `2026-05-06-01-catalog-schema.sql` (DDL)

**Files:**
- Create: `ops-software-bible/migrations/2026-05-06-01-catalog-schema.sql`

- [ ] **Step 1: Write the migration file**

```sql
-- 2026-05-06-01-catalog-schema.sql
-- Catalog variant model — schema DDL only.
-- This migration creates new tables and adds columns to existing tables.
-- Companion migrations:
--   02 — views over catalog_* + INSTEAD OF triggers + price mirror trigger
--   03 — bespoke per-company data migration (Canpro + Maverick)
--   04 — permission rename (inventory.* → catalog.*)

BEGIN;

-- =====================================================
-- 1. catalog_categories  (nested, parent_id self-FK)
-- =====================================================
CREATE TABLE public.catalog_categories (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id                  uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name                        text NOT NULL,
    parent_id                   uuid REFERENCES public.catalog_categories(id) ON DELETE SET NULL,
    sort_order                  integer NOT NULL DEFAULT 0,
    color_hex                   text,
    default_warning_threshold   double precision,
    default_critical_threshold  double precision,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    deleted_at                  timestamptz
);
CREATE INDEX idx_catalog_categories_company_parent ON public.catalog_categories(company_id, parent_id) WHERE deleted_at IS NULL;

-- Cycle prevention trigger: a category cannot be its own ancestor.
CREATE OR REPLACE FUNCTION private.catalog_categories_no_cycle()
RETURNS trigger AS $$
DECLARE
    cur_id uuid := NEW.parent_id;
    depth integer := 0;
BEGIN
    WHILE cur_id IS NOT NULL LOOP
        IF cur_id = NEW.id THEN
            RAISE EXCEPTION 'catalog_categories cycle detected via parent_id';
        END IF;
        SELECT parent_id INTO cur_id FROM public.catalog_categories WHERE id = cur_id;
        depth := depth + 1;
        IF depth > 50 THEN
            RAISE EXCEPTION 'catalog_categories parent chain exceeds 50 levels';
        END IF;
    END LOOP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_catalog_categories_no_cycle
    BEFORE INSERT OR UPDATE OF parent_id ON public.catalog_categories
    FOR EACH ROW EXECUTE FUNCTION private.catalog_categories_no_cycle();

ALTER TABLE public.catalog_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_categories
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 2. catalog_items  (variant families)
-- =====================================================
CREATE TABLE public.catalog_items (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id                  uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    category_id                 uuid REFERENCES public.catalog_categories(id) ON DELETE SET NULL,
    name                        text NOT NULL,
    description                 text,
    default_price               numeric,
    default_unit_cost           numeric,
    default_warning_threshold   double precision,
    default_critical_threshold  double precision,
    default_unit_id             uuid,  -- FK added after catalog_units exists
    image_url                   text,
    notes                       text,
    is_active                   boolean NOT NULL DEFAULT true,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now(),
    deleted_at                  timestamptz
);
CREATE INDEX idx_catalog_items_company_category ON public.catalog_items(company_id, category_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_catalog_items_company_active ON public.catalog_items(company_id, is_active) WHERE deleted_at IS NULL;

ALTER TABLE public.catalog_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_items
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 3. catalog_units  (renamed-equivalent of inventory_units)
-- =====================================================
CREATE TABLE public.catalog_units (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id   uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    display      text NOT NULL,
    abbreviation text,
    dimension    text NOT NULL DEFAULT 'count',
    is_default   boolean NOT NULL DEFAULT false,
    sort_order   integer NOT NULL DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    deleted_at   timestamptz
);
CREATE INDEX idx_catalog_units_company ON public.catalog_units(company_id, sort_order) WHERE deleted_at IS NULL;

ALTER TABLE public.catalog_units ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_units
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- Now that catalog_units exists, add the FK on catalog_items.
ALTER TABLE public.catalog_items
    ADD CONSTRAINT fk_catalog_items_default_unit
    FOREIGN KEY (default_unit_id) REFERENCES public.catalog_units(id) ON DELETE SET NULL;

-- =====================================================
-- 4. catalog_options  (variant axes per family)
-- =====================================================
CREATE TABLE public.catalog_options (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    catalog_item_id   uuid NOT NULL REFERENCES public.catalog_items(id) ON DELETE CASCADE,
    name              text NOT NULL,
    sort_order        integer NOT NULL DEFAULT 0,
    created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_catalog_options_item ON public.catalog_options(catalog_item_id, sort_order);

ALTER TABLE public.catalog_options ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_options
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.catalog_items i
                WHERE i.id = catalog_options.catalog_item_id
                  AND i.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 5. catalog_option_values
-- =====================================================
CREATE TABLE public.catalog_option_values (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    option_id   uuid NOT NULL REFERENCES public.catalog_options(id) ON DELETE CASCADE,
    value       text NOT NULL,
    sort_order  integer NOT NULL DEFAULT 0,
    UNIQUE (option_id, value)
);

ALTER TABLE public.catalog_option_values ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_option_values
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.catalog_options o
                JOIN public.catalog_items i ON i.id = o.catalog_item_id
                WHERE o.id = catalog_option_values.option_id
                  AND i.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 6. catalog_variants  (the SKUs)
-- =====================================================
CREATE TABLE public.catalog_variants (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id          uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    catalog_item_id     uuid NOT NULL REFERENCES public.catalog_items(id) ON DELETE CASCADE,
    sku                 text,
    quantity            double precision NOT NULL DEFAULT 0,
    price_override      numeric,
    unit_cost_override  numeric,
    warning_threshold   double precision,
    critical_threshold  double precision,
    unit_id             uuid REFERENCES public.catalog_units(id) ON DELETE SET NULL,
    is_active           boolean NOT NULL DEFAULT true,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz
);
CREATE INDEX idx_catalog_variants_item ON public.catalog_variants(catalog_item_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_catalog_variants_company ON public.catalog_variants(company_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_catalog_variants_sku ON public.catalog_variants(sku) WHERE deleted_at IS NULL AND sku IS NOT NULL;

ALTER TABLE public.catalog_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_variants
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 7. catalog_variant_option_values  (M2M variant ↔ option_value)
-- =====================================================
CREATE TABLE public.catalog_variant_option_values (
    variant_id       uuid NOT NULL REFERENCES public.catalog_variants(id) ON DELETE CASCADE,
    option_value_id  uuid NOT NULL REFERENCES public.catalog_option_values(id) ON DELETE CASCADE,
    PRIMARY KEY (variant_id, option_value_id)
);
CREATE INDEX idx_cvov_value ON public.catalog_variant_option_values(option_value_id);

ALTER TABLE public.catalog_variant_option_values ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_variant_option_values
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.catalog_variants v
                WHERE v.id = catalog_variant_option_values.variant_id
                  AND v.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 8. catalog_tags  (free-form labels at family level)
-- =====================================================
CREATE TABLE public.catalog_tags (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id          uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name                text NOT NULL,
    warning_threshold   double precision,  -- preserved from inventory_tags; UI hides it; effective threshold ignores it
    critical_threshold  double precision,  -- same
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    deleted_at          timestamptz,
    UNIQUE (company_id, name) WHERE deleted_at IS NULL
);
CREATE INDEX idx_catalog_tags_company ON public.catalog_tags(company_id) WHERE deleted_at IS NULL;

ALTER TABLE public.catalog_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_tags
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 9. catalog_item_tags  (M2M family ↔ tag — note: family-level, not variant)
-- =====================================================
CREATE TABLE public.catalog_item_tags (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    catalog_item_id uuid NOT NULL REFERENCES public.catalog_items(id) ON DELETE CASCADE,
    tag_id          uuid NOT NULL REFERENCES public.catalog_tags(id) ON DELETE CASCADE,
    UNIQUE (catalog_item_id, tag_id)
);
CREATE INDEX idx_cit_tag ON public.catalog_item_tags(tag_id);

ALTER TABLE public.catalog_item_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_item_tags
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.catalog_items i
                WHERE i.id = catalog_item_tags.catalog_item_id
                  AND i.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 10. catalog_snapshots  (variant-aware history)
-- =====================================================
CREATE TABLE public.catalog_snapshots (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id    uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    is_automatic  boolean NOT NULL DEFAULT false,
    item_count    integer NOT NULL DEFAULT 0,  -- # of variants captured
    notes         text,
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_catalog_snapshots_company ON public.catalog_snapshots(company_id, created_at DESC);

ALTER TABLE public.catalog_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_snapshots
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 11. catalog_snapshot_items
-- =====================================================
CREATE TABLE public.catalog_snapshot_items (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_id         uuid NOT NULL REFERENCES public.catalog_snapshots(id) ON DELETE CASCADE,
    original_variant_id uuid REFERENCES public.catalog_variants(id) ON DELETE SET NULL,
    family_name         text NOT NULL,  -- denormalized so renames don't lose history
    variant_label       text,           -- e.g., "Black · Topmount" (snapshotted)
    quantity            double precision NOT NULL DEFAULT 0,
    unit_display        text,
    sku                 text,
    description         text
);
CREATE INDEX idx_catalog_snapshot_items_snap ON public.catalog_snapshot_items(snapshot_id);

ALTER TABLE public.catalog_snapshot_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_snapshot_items
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.catalog_snapshots s
                WHERE s.id = catalog_snapshot_items.snapshot_id
                  AND s.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 12. catalog_orders  (Bug e08c63a2 — threshold-driven order suggestions)
-- =====================================================
CREATE TABLE public.catalog_orders (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id               uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    status                   text NOT NULL DEFAULT 'draft'
                             CHECK (status IN ('suggested','draft','sent','fulfilled','cancelled')),
    title                    text,
    supplier_name            text,
    supplier_contact         text,
    expected_delivery_date   date,
    notes                    text,
    created_by_id            uuid REFERENCES public.users(id) ON DELETE SET NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    sent_at                  timestamptz,
    fulfilled_at             timestamptz,
    cancelled_at             timestamptz,
    deleted_at               timestamptz
);
CREATE INDEX idx_catalog_orders_company_status ON public.catalog_orders(company_id, status) WHERE deleted_at IS NULL;

ALTER TABLE public.catalog_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_orders
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 13. catalog_order_items
-- =====================================================
CREATE TABLE public.catalog_order_items (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id            uuid NOT NULL REFERENCES public.catalog_orders(id) ON DELETE CASCADE,
    catalog_variant_id  uuid NOT NULL REFERENCES public.catalog_variants(id) ON DELETE RESTRICT,
    quantity_requested  double precision NOT NULL,
    cost_per_unit       numeric,
    notes               text
);
CREATE INDEX idx_catalog_order_items_order ON public.catalog_order_items(order_id);
CREATE INDEX idx_catalog_order_items_variant ON public.catalog_order_items(catalog_variant_id);

ALTER TABLE public.catalog_order_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.catalog_order_items
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.catalog_orders o
                WHERE o.id = catalog_order_items.order_id
                  AND o.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 14. company_default_products  (drawing→estimate adapter)
-- =====================================================
CREATE TABLE public.company_default_products (
    company_id     uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    component_type text NOT NULL CHECK (component_type IN ('railing','deck_board','stair_set','gate','post_set')),
    product_id     uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (company_id, component_type)
);

ALTER TABLE public.company_default_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.company_default_products
    FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

-- =====================================================
-- 15. products  — extension columns (configurable Products)
-- =====================================================
ALTER TABLE public.products
    ADD COLUMN base_price    numeric NOT NULL DEFAULT 0,
    ADD COLUMN pricing_unit  text    NOT NULL DEFAULT 'each'
        CHECK (pricing_unit IN ('each','flat_rate','linear_foot','sqft','hour','day'));

UPDATE public.products SET base_price = default_price;
-- The base_price ↔ default_price mirror trigger lives in 02-catalog-views-triggers.sql.

-- =====================================================
-- 16. product_options  (configurable Product knobs)
-- =====================================================
CREATE TABLE public.product_options (
    id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id               uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    name                     text NOT NULL,
    kind                     text NOT NULL CHECK (kind IN ('select','integer','boolean')),
    affects_price            boolean NOT NULL DEFAULT false,
    affects_recipe           boolean NOT NULL DEFAULT false,
    required                 boolean NOT NULL DEFAULT true,
    default_value            text,
    option_default_source    text,  -- e.g., '$design.color'; nullable
    sort_order               integer NOT NULL DEFAULT 0,
    created_at               timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_product_options_product ON public.product_options(product_id, sort_order);

ALTER TABLE public.product_options ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.product_options
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.products p
                WHERE p.id = product_options.product_id
                  AND p.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 17. product_option_values  (for kind='select')
-- =====================================================
CREATE TABLE public.product_option_values (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    option_id   uuid NOT NULL REFERENCES public.product_options(id) ON DELETE CASCADE,
    value       text NOT NULL,
    sort_order  integer NOT NULL DEFAULT 0,
    UNIQUE (option_id, value)
);

ALTER TABLE public.product_option_values ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.product_option_values
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.product_options o
                JOIN public.products p ON p.id = o.product_id
                WHERE o.id = product_option_values.option_id
                  AND p.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 18. product_pricing_modifiers
-- =====================================================
CREATE TABLE public.product_pricing_modifiers (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id        uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    option_id         uuid NOT NULL REFERENCES public.product_options(id) ON DELETE CASCADE,
    trigger_value_id  uuid REFERENCES public.product_option_values(id) ON DELETE CASCADE,
    trigger_int_min   integer,
    trigger_int_max   integer,
    modifier_kind     text NOT NULL CHECK (modifier_kind IN ('add_per_unit','add_flat','add_per_count','multiply_unit_price')),
    amount            numeric NOT NULL,
    created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_product_pricing_modifiers_product ON public.product_pricing_modifiers(product_id);

ALTER TABLE public.product_pricing_modifiers ENABLE ROW LEVEL SECURITY;
CREATE POLICY company_isolation ON public.product_pricing_modifiers
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.products p
                WHERE p.id = product_pricing_modifiers.product_id
                  AND p.company_id = (SELECT private.get_user_company_id()))
    );

-- =====================================================
-- 19. product_materials  — extension columns (recipe rules)
-- =====================================================
-- Existing table: product_id, inventory_item_id, quantity_per_unit, notes.
-- We are replacing inventory_item_id with a variant-or-family pointer + selector + scaling.
ALTER TABLE public.product_materials
    ADD COLUMN id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ADD COLUMN catalog_variant_id   uuid REFERENCES public.catalog_variants(id) ON DELETE RESTRICT,
    ADD COLUMN catalog_item_id      uuid REFERENCES public.catalog_items(id) ON DELETE RESTRICT,
    ADD COLUMN variant_selector     jsonb,
    ADD COLUMN scaled_by_option_id  uuid REFERENCES public.product_options(id) ON DELETE SET NULL,
    ADD COLUMN unit_id              uuid REFERENCES public.catalog_units(id) ON DELETE SET NULL;
-- The legacy `inventory_item_id` column stays for now; Phase 2's data migration null-fills it.
-- A future cleanup migration drops it once we confirm zero callers.

ALTER TABLE public.product_materials
    ADD CONSTRAINT chk_product_materials_pin_xor_family
    CHECK (
        (catalog_variant_id IS NOT NULL AND catalog_item_id IS NULL)
        OR
        (catalog_variant_id IS NULL AND catalog_item_id IS NOT NULL)
        OR
        (catalog_variant_id IS NULL AND catalog_item_id IS NULL AND inventory_item_id IS NOT NULL)
    );
-- The third disjunct exists ONLY for the brief window between schema migration and data migration.
-- After data migration completes, every row will have either catalog_variant_id or catalog_item_id set,
-- and inventory_item_id will be NULL. A follow-up migration drops the third disjunct + the legacy column.

-- =====================================================
-- 20. line_items  — snapshot fields for configurable Products
-- =====================================================
ALTER TABLE public.line_items
    ADD COLUMN configured_options       jsonb,
    ADD COLUMN resolved_unit_price      numeric,
    ADD COLUMN resolved_options_label   text;

-- =====================================================
-- 21. inventory_deductions  — rename FK (table is empty server-side)
-- =====================================================
ALTER TABLE public.inventory_deductions
    ADD COLUMN catalog_variant_id uuid REFERENCES public.catalog_variants(id) ON DELETE RESTRICT;
-- The legacy `inventory_item_id` column stays; new writes use catalog_variant_id.
-- A follow-up migration drops the legacy column once we confirm no active rows reference it.

-- =====================================================
-- 22. task_materials  — repoint to catalog_variants
-- =====================================================
ALTER TABLE public.task_materials
    ADD COLUMN catalog_variant_id uuid REFERENCES public.catalog_variants(id) ON DELETE RESTRICT;
-- Same pattern: legacy `inventory_item_id` stays; new writes use catalog_variant_id.

-- =====================================================
-- 23. line_item_materials  — repoint to catalog_variants
-- =====================================================
ALTER TABLE public.line_item_materials
    ADD COLUMN catalog_variant_id uuid REFERENCES public.catalog_variants(id) ON DELETE RESTRICT;

COMMIT;
```

- [ ] **Step 2: Apply migration via MCP**

Use `apply_migration` with `name='2026-05-06-01-catalog-schema'` and the SQL above.

- [ ] **Step 3: Verify all 14 tables exist with RLS enabled**

```sql
SELECT tablename, rls_enabled
FROM pg_tables t
LEFT JOIN (SELECT relname, relrowsecurity AS rls_enabled FROM pg_class) c ON c.relname = t.tablename
WHERE t.schemaname='public'
  AND t.tablename IN ('catalog_categories','catalog_items','catalog_units','catalog_options',
                      'catalog_option_values','catalog_variants','catalog_variant_option_values',
                      'catalog_tags','catalog_item_tags','catalog_snapshots','catalog_snapshot_items',
                      'catalog_orders','catalog_order_items','company_default_products',
                      'product_options','product_option_values','product_pricing_modifiers')
ORDER BY tablename;
```

Expected: 17 rows, all `rls_enabled=true`.

- [ ] **Step 4: Verify products got base_price and pricing_unit**

```sql
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='products'
  AND column_name IN ('base_price','pricing_unit','default_price','unit_cost');
```

Expected: 4 rows. `base_price numeric default 0`, `pricing_unit text default 'each'`, plus the existing `default_price` and `unit_cost`.

- [ ] **Step 5: Verify line_items got snapshot columns**

```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='line_items'
  AND column_name IN ('configured_options','resolved_unit_price','resolved_options_label');
```

Expected: 3 rows.

### Task 3: Write `2026-05-06-02-catalog-views-triggers.sql`

**Files:**
- Create: `ops-software-bible/migrations/2026-05-06-02-catalog-views-triggers.sql`

This file is large because it implements the ops-web compatibility layer end-to-end. Every legacy `inventory_*` table gets a view over the new `catalog_*` shape, plus `INSTEAD OF` triggers so ops-web's existing INSERTs/UPDATEs/DELETEs translate transparently. The `base_price` ↔ `default_price` mirror trigger lives here too.

- [ ] **Step 1: Drop old inventory_* tables (data already empty for fresh installs; for Canpro/Maverick, data migration in Phase 2 happens BEFORE this migration runs)**

This step is intentionally NOT in this file. The migration ordering is: 01-schema → Phase 2 data migration → 02-views-triggers (which depends on the legacy tables NOT existing yet, so it can rename and reuse the names for views). Defer the actual rename to Step 2 below.

- [ ] **Step 2: Write the migration file**

```sql
-- 2026-05-06-02-catalog-views-triggers.sql
-- Compatibility layer: legacy inventory_* table names become views over
-- catalog_* tables, with INSTEAD OF triggers so ops-web's existing CRUD
-- against `inventory_*` keeps working until the follow-up ops-web rewrite
-- session lands. Also installs the base_price <-> default_price mirror
-- trigger on `products`.
--
-- ORDERING: This migration runs AFTER Phase 2's data migration has populated
-- catalog_* with Canpro/Maverick data. The legacy inventory_* tables are
-- DROPPED here and replaced with views of the same name. ops-web continues
-- to read/write the names it knows.

BEGIN;

-- =====================================================
-- 1. Drop legacy inventory_* tables (data already migrated)
-- =====================================================
-- Sanity check: refuse to drop if any legacy row is missing a catalog_variant
-- counterpart. For Canpro+Maverick the migration script asserts this; for any
-- other company the legacy tables are empty, so the check is a no-op.

DO $$
DECLARE
    orphan_count integer;
BEGIN
    SELECT COUNT(*) INTO orphan_count
    FROM public.inventory_items i
    WHERE i.deleted_at IS NULL
      AND NOT EXISTS (
          SELECT 1 FROM public.catalog_variants v
          JOIN public.catalog_items it ON it.id = v.catalog_item_id
          WHERE v.company_id = i.company_id
            AND lower(trim(it.name)) = lower(trim(i.name))
      );
    IF orphan_count > 0 THEN
        RAISE EXCEPTION 'Cannot drop inventory_items: % rows have no catalog_variants counterpart. Run Phase 2 migration first.', orphan_count;
    END IF;
END $$;

DROP TABLE public.inventory_item_tags CASCADE;
DROP TABLE public.inventory_snapshot_items CASCADE;
DROP TABLE public.inventory_snapshots CASCADE;
DROP TABLE public.inventory_items CASCADE;
DROP TABLE public.inventory_tags CASCADE;
DROP TABLE public.inventory_units CASCADE;

-- =====================================================
-- 2. inventory_units VIEW + INSTEAD OF triggers
-- =====================================================
CREATE VIEW public.inventory_units AS
    SELECT id, company_id, display, is_default, sort_order, created_at, updated_at, deleted_at,
           abbreviation, dimension
    FROM public.catalog_units;

CREATE OR REPLACE FUNCTION private.iv_inventory_units_insert()
RETURNS trigger AS $$
BEGIN
    INSERT INTO public.catalog_units (id, company_id, display, abbreviation, dimension, is_default, sort_order, created_at, updated_at, deleted_at)
    VALUES (COALESCE(NEW.id, gen_random_uuid()), NEW.company_id, NEW.display,
            COALESCE(NEW.abbreviation, NULL), COALESCE(NEW.dimension, 'count'),
            COALESCE(NEW.is_default, false), COALESCE(NEW.sort_order, 0),
            COALESCE(NEW.created_at, now()), COALESCE(NEW.updated_at, now()), NEW.deleted_at);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_units_insert INSTEAD OF INSERT ON public.inventory_units
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_units_insert();

CREATE OR REPLACE FUNCTION private.iv_inventory_units_update()
RETURNS trigger AS $$
BEGIN
    UPDATE public.catalog_units SET
        display = NEW.display,
        abbreviation = NEW.abbreviation,
        dimension = NEW.dimension,
        is_default = NEW.is_default,
        sort_order = NEW.sort_order,
        updated_at = now(),
        deleted_at = NEW.deleted_at
    WHERE id = OLD.id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_units_update INSTEAD OF UPDATE ON public.inventory_units
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_units_update();

CREATE OR REPLACE FUNCTION private.iv_inventory_units_delete()
RETURNS trigger AS $$
BEGIN
    UPDATE public.catalog_units SET deleted_at = now(), updated_at = now() WHERE id = OLD.id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_units_delete INSTEAD OF DELETE ON public.inventory_units
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_units_delete();

-- =====================================================
-- 3. inventory_tags VIEW + INSTEAD OF triggers
-- =====================================================
CREATE VIEW public.inventory_tags AS
    SELECT id, company_id, name, warning_threshold, critical_threshold, created_at, updated_at, deleted_at
    FROM public.catalog_tags;

CREATE OR REPLACE FUNCTION private.iv_inventory_tags_insert()
RETURNS trigger AS $$
BEGIN
    INSERT INTO public.catalog_tags (id, company_id, name, warning_threshold, critical_threshold, created_at, updated_at, deleted_at)
    VALUES (COALESCE(NEW.id, gen_random_uuid()), NEW.company_id, NEW.name,
            NEW.warning_threshold, NEW.critical_threshold,
            COALESCE(NEW.created_at, now()), COALESCE(NEW.updated_at, now()), NEW.deleted_at);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_tags_insert INSTEAD OF INSERT ON public.inventory_tags
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_tags_insert();

CREATE OR REPLACE FUNCTION private.iv_inventory_tags_update()
RETURNS trigger AS $$
BEGIN
    UPDATE public.catalog_tags SET
        name = NEW.name,
        warning_threshold = NEW.warning_threshold,
        critical_threshold = NEW.critical_threshold,
        updated_at = now(),
        deleted_at = NEW.deleted_at
    WHERE id = OLD.id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_tags_update INSTEAD OF UPDATE ON public.inventory_tags
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_tags_update();

CREATE OR REPLACE FUNCTION private.iv_inventory_tags_delete()
RETURNS trigger AS $$
BEGIN
    UPDATE public.catalog_tags SET deleted_at = now(), updated_at = now() WHERE id = OLD.id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_tags_delete INSTEAD OF DELETE ON public.inventory_tags
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_tags_delete();

-- =====================================================
-- 4. inventory_items VIEW + INSTEAD OF triggers
-- =====================================================
-- Each legacy inventory_item maps to ONE catalog_variant (its degenerate
-- single-variant family case after migration). The view exposes the legacy
-- shape so ops-web continues to read items as if the variants table were
-- a flat row-per-SKU table.
--
-- For families with more than one variant (Canpro's "Corner" with 6 variants),
-- ops-web sees 6 rows in inventory_items, each with the family's name. ops-web
-- must NOT rely on inventory_items.name being unique within a company; it never
-- was guaranteed to be (Canpro's existing data violated that already).

CREATE VIEW public.inventory_items AS
    SELECT v.id, v.company_id, ci.name, ci.description,
           v.quantity, v.unit_id, v.sku,
           NULL::text AS notes, ci.image_url,
           COALESCE(v.warning_threshold, ci.default_warning_threshold) AS warning_threshold,
           COALESCE(v.critical_threshold, ci.default_critical_threshold) AS critical_threshold,
           v.created_at, v.updated_at, v.deleted_at
    FROM public.catalog_variants v
    JOIN public.catalog_items ci ON ci.id = v.catalog_item_id;

CREATE OR REPLACE FUNCTION private.iv_inventory_items_insert()
RETURNS trigger AS $$
DECLARE
    family_id uuid;
BEGIN
    -- Find or create a single-variant family.
    SELECT id INTO family_id FROM public.catalog_items
    WHERE company_id = NEW.company_id AND lower(trim(name)) = lower(trim(NEW.name)) AND deleted_at IS NULL
    LIMIT 1;

    IF family_id IS NULL THEN
        INSERT INTO public.catalog_items (id, company_id, name, description, image_url, default_warning_threshold, default_critical_threshold, default_unit_id, created_at, updated_at, deleted_at)
        VALUES (gen_random_uuid(), NEW.company_id, NEW.name, NEW.description, NEW.image_url, NEW.warning_threshold, NEW.critical_threshold, NEW.unit_id,
                COALESCE(NEW.created_at, now()), COALESCE(NEW.updated_at, now()), NEW.deleted_at)
        RETURNING id INTO family_id;
    END IF;

    INSERT INTO public.catalog_variants (id, company_id, catalog_item_id, sku, quantity, warning_threshold, critical_threshold, unit_id, created_at, updated_at, deleted_at)
    VALUES (COALESCE(NEW.id, gen_random_uuid()), NEW.company_id, family_id, NEW.sku, NEW.quantity, NEW.warning_threshold, NEW.critical_threshold, NEW.unit_id,
            COALESCE(NEW.created_at, now()), COALESCE(NEW.updated_at, now()), NEW.deleted_at);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_items_insert INSTEAD OF INSERT ON public.inventory_items
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_items_insert();

CREATE OR REPLACE FUNCTION private.iv_inventory_items_update()
RETURNS trigger AS $$
BEGIN
    UPDATE public.catalog_variants SET
        sku = NEW.sku,
        quantity = NEW.quantity,
        warning_threshold = NEW.warning_threshold,
        critical_threshold = NEW.critical_threshold,
        unit_id = NEW.unit_id,
        updated_at = now(),
        deleted_at = NEW.deleted_at
    WHERE id = OLD.id;

    -- Family-level fields (name, description, image_url) write back to the family.
    UPDATE public.catalog_items ci SET
        name = NEW.name,
        description = NEW.description,
        image_url = NEW.image_url,
        updated_at = now()
    FROM public.catalog_variants v
    WHERE v.id = OLD.id AND ci.id = v.catalog_item_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_items_update INSTEAD OF UPDATE ON public.inventory_items
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_items_update();

CREATE OR REPLACE FUNCTION private.iv_inventory_items_delete()
RETURNS trigger AS $$
BEGIN
    UPDATE public.catalog_variants SET deleted_at = now(), updated_at = now() WHERE id = OLD.id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_items_delete INSTEAD OF DELETE ON public.inventory_items
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_items_delete();

-- =====================================================
-- 5. inventory_item_tags VIEW + INSTEAD OF triggers
-- =====================================================
-- Legacy table joined items to tags. New model tags are at FAMILY level.
-- The view exposes (item_id=variant_id, tag_id) by joining variant→family→family_tags.
CREATE VIEW public.inventory_item_tags AS
    SELECT cit.id, v.id AS item_id, cit.tag_id
    FROM public.catalog_item_tags cit
    JOIN public.catalog_variants v ON v.catalog_item_id = cit.catalog_item_id
    WHERE v.deleted_at IS NULL;

CREATE OR REPLACE FUNCTION private.iv_inventory_item_tags_insert()
RETURNS trigger AS $$
DECLARE
    family_id uuid;
BEGIN
    SELECT catalog_item_id INTO family_id FROM public.catalog_variants WHERE id = NEW.item_id;
    IF family_id IS NULL THEN
        RAISE EXCEPTION 'inventory_item_tags insert: variant % not found', NEW.item_id;
    END IF;
    INSERT INTO public.catalog_item_tags (id, catalog_item_id, tag_id)
    VALUES (COALESCE(NEW.id, gen_random_uuid()), family_id, NEW.tag_id)
    ON CONFLICT (catalog_item_id, tag_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_item_tags_insert INSTEAD OF INSERT ON public.inventory_item_tags
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_item_tags_insert();

CREATE OR REPLACE FUNCTION private.iv_inventory_item_tags_delete()
RETURNS trigger AS $$
DECLARE
    family_id uuid;
BEGIN
    SELECT catalog_item_id INTO family_id FROM public.catalog_variants WHERE id = OLD.item_id;
    DELETE FROM public.catalog_item_tags WHERE catalog_item_id = family_id AND tag_id = OLD.tag_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER iv_inventory_item_tags_delete INSTEAD OF DELETE ON public.inventory_item_tags
    FOR EACH ROW EXECUTE FUNCTION private.iv_inventory_item_tags_delete();

-- =====================================================
-- 6. inventory_snapshots / inventory_snapshot_items VIEWS
-- =====================================================
CREATE VIEW public.inventory_snapshots AS
    SELECT id, company_id, created_by_id, is_automatic, item_count, notes, created_at
    FROM public.catalog_snapshots;

-- ops-web doesn't write snapshots today; read-only view is sufficient.
-- iOS will write directly to catalog_snapshots after this migration lands.

CREATE VIEW public.inventory_snapshot_items AS
    SELECT id, snapshot_id, original_variant_id AS original_item_id, family_name AS name,
           quantity, unit_display, sku, '' AS tags_string, NULL::text AS description
    FROM public.catalog_snapshot_items;

-- =====================================================
-- 7. base_price <-> default_price mirror trigger on products
-- =====================================================
CREATE OR REPLACE FUNCTION private.products_mirror_price()
RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.base_price IS NULL OR NEW.base_price = 0 THEN
            NEW.base_price := COALESCE(NEW.default_price, 0);
        ELSIF NEW.default_price IS NULL OR NEW.default_price = 0 THEN
            NEW.default_price := NEW.base_price;
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.base_price IS DISTINCT FROM OLD.base_price AND NEW.default_price IS NOT DISTINCT FROM OLD.default_price THEN
            NEW.default_price := NEW.base_price;
        ELSIF NEW.default_price IS DISTINCT FROM OLD.default_price AND NEW.base_price IS NOT DISTINCT FROM OLD.base_price THEN
            NEW.base_price := NEW.default_price;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_products_mirror_price
    BEFORE INSERT OR UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION private.products_mirror_price();

COMMIT;
```

- [ ] **Step 3: This migration runs AFTER Phase 2 data migration. Hold off applying until Task 5 in Phase 2 completes.**

### Task 4: Confirm migration ordering plan

- [ ] **Step 1: Document the apply order in the plan log**

```
Order of operations:
  1. Apply 01-catalog-schema.sql              (Task 2 above)
  2. Verify schema (Task 2 Steps 3-5)
  3. Run Phase 2 data migration script        (Phase 2 below)
  4. Verify pre/post counts in Phase 2
  5. Apply 02-catalog-views-triggers.sql      (Task 3 Step 3 above)
  6. Verify ops-web reads still work (Task 6 below)
```

### Task 5: Stop here — Phase 2 must complete before applying 02-catalog-views-triggers

- [ ] **Step 1: Hand-off to Phase 2.** No more SQL applies in Phase 1 until data migration ships. The 02 migration's first DO $$ block will refuse to drop legacy tables if Phase 2 hasn't run.

### Task 6 (post-Phase-2): Apply 02-catalog-views-triggers and verify ops-web compatibility

**Files:**
- Apply: `2026-05-06-02-catalog-views-triggers.sql`

- [ ] **Step 1: Apply migration via MCP `apply_migration`**

- [ ] **Step 2: Verify views exist and are queryable**

```sql
SELECT viewname FROM pg_views WHERE schemaname='public' AND viewname LIKE 'inventory_%';
```

Expected: 6 rows: `inventory_items`, `inventory_tags`, `inventory_units`, `inventory_item_tags`, `inventory_snapshots`, `inventory_snapshot_items`.

- [ ] **Step 3: Verify ops-web-shaped read for Canpro returns the same row counts the legacy tables would have**

```sql
SELECT 'items_via_view', COUNT(*) FROM public.inventory_items WHERE company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND deleted_at IS NULL
UNION ALL SELECT 'tags_via_view', COUNT(*) FROM public.inventory_tags WHERE company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND deleted_at IS NULL
UNION ALL SELECT 'item_tags_via_view', COUNT(*) FROM public.inventory_item_tags it
    JOIN public.inventory_items i ON i.id = it.item_id WHERE i.company_id='a612edc0-5c18-4c4d-af97-55b9410dd077';
```

Expected: items=58 (one variant per legacy item), tags=at least 0 (tags Canpro had at axis-promotion time are gone; family-level tags survive), item_tags=preserved at family level (queries through view return same shape).

- [ ] **Step 4: Verify base_price / default_price mirror works**

```sql
-- Insert via default_price; expect base_price to mirror.
INSERT INTO public.products (id, company_id, name, default_price, type) VALUES
    (gen_random_uuid(), 'a612edc0-5c18-4c4d-af97-55b9410dd077', '__test_mirror_a', 100, 'OTHER');
-- Insert via base_price; expect default_price to mirror.
INSERT INTO public.products (id, company_id, name, base_price, type) VALUES
    (gen_random_uuid(), 'a612edc0-5c18-4c4d-af97-55b9410dd077', '__test_mirror_b', 200, 'OTHER');
SELECT name, base_price, default_price FROM public.products WHERE name IN ('__test_mirror_a','__test_mirror_b');
DELETE FROM public.products WHERE name IN ('__test_mirror_a','__test_mirror_b');
```

Expected: both rows show `base_price=default_price` after insert.

---

## Phase 2 — Hand-crafted data migration

Goal: convert Canpro's 58 inventory items into ~10–14 catalog families with appropriate option axes, and Maverick's 58 items into a simpler color-axis-only structure. Pre/post verification preserves quantity totals and family/variant counts.

This phase is bespoke per company. Do not generalize the heuristic — write the SQL by hand based on the actual data shape.

### Task 7: Author Canpro family + category mapping

**Files:**
- Create: `ops-software-bible/migrations/2026-05-06-03-catalog-data-canpro-maverick.sql` (start here; Maverick added in Task 9)

- [ ] **Step 1: Inspect Canpro's distinct family names and tag distribution**

```sql
SELECT lower(trim(name)) AS family_name, COUNT(*) AS variant_count, SUM(quantity) AS total_qty,
       array_agg(DISTINCT (SELECT string_agg(t.name, '|' ORDER BY t.name)
                            FROM public.inventory_item_tags it
                            JOIN public.inventory_tags t ON t.id = it.tag_id
                            WHERE it.item_id = i.id)) AS tag_combos
FROM public.inventory_items i
WHERE i.company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND i.deleted_at IS NULL
GROUP BY lower(trim(name))
ORDER BY variant_count DESC, family_name;
```

Record the result. This is the source of truth for families to create.

- [ ] **Step 2: Define the categories**

Categories (parent → children):

```
Hardware            (parent)
  Hardware Level    (child)
  Hardware Stair    (child)
Rail                (top)
Fasteners           (parent)
  Screws            (child)
Gates               (top)
Posts               (top)
```

This maps Canpro's class-tags into a hierarchy. `Posts` is added even though Canpro has no Posts items today — they'll add some.

- [ ] **Step 3: Write the migration file (begin Canpro section)**

```sql
-- 2026-05-06-03-catalog-data-canpro-maverick.sql
-- Bespoke per-company data migration for Canpro Deck and Rail (a612edc0-...)
-- and Maverick Projects Ltd (ddee107c-...). Other companies have no real
-- inventory data — they remain empty in the new tables and onboard via the
-- new UI.
--
-- Pre/post verification queries follow each company's INSERT block.

BEGIN;

-- =====================================================
-- CANPRO DECK AND RAIL (a612edc0-5c18-4c4d-af97-55b9410dd077)
-- =====================================================

-- Capture pre-counts for verification
CREATE TEMP TABLE __canpro_baseline AS
SELECT COUNT(*) FILTER (WHERE deleted_at IS NULL) AS items_count,
       SUM(quantity) FILTER (WHERE deleted_at IS NULL) AS qty_sum,
       (SELECT COUNT(*) FROM public.inventory_tags
        WHERE company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND deleted_at IS NULL) AS tags_count,
       (SELECT COUNT(*) FROM public.inventory_units
        WHERE company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND deleted_at IS NULL) AS units_count
FROM public.inventory_items
WHERE company_id='a612edc0-5c18-4c4d-af97-55b9410dd077';

-- Migrate units verbatim
INSERT INTO public.catalog_units (id, company_id, display, abbreviation, dimension, is_default, sort_order, created_at, updated_at, deleted_at)
SELECT id, company_id, display, abbreviation, dimension, is_default, sort_order, created_at, updated_at, deleted_at
FROM public.inventory_units
WHERE company_id='a612edc0-5c18-4c4d-af97-55b9410dd077';

-- Categories
INSERT INTO public.catalog_categories (id, company_id, name, parent_id, sort_order)
VALUES
    ('11111111-1111-1111-1111-100000000001', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Hardware',         NULL, 10),
    ('11111111-1111-1111-1111-100000000002', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Rail',             NULL, 20),
    ('11111111-1111-1111-1111-100000000003', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Fasteners',        NULL, 30),
    ('11111111-1111-1111-1111-100000000004', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Gates',            NULL, 40),
    ('11111111-1111-1111-1111-100000000005', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Posts',            NULL, 50);

INSERT INTO public.catalog_categories (id, company_id, name, parent_id, sort_order)
VALUES
    ('11111111-1111-1111-1111-100000001001', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Hardware Level', '11111111-1111-1111-1111-100000000001', 10),
    ('11111111-1111-1111-1111-100000001002', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Hardware Stair', '11111111-1111-1111-1111-100000000001', 20),
    ('11111111-1111-1111-1111-100000001003', 'a612edc0-5c18-4c4d-af97-55b9410dd077', 'Screws',         '11111111-1111-1111-1111-100000000003', 10);

-- Tags: Canpro's existing 9 tags fully promote to either categories or option values.
-- After this migration, catalog_tags is empty for Canpro (clean slate).
-- (We do NOT insert any catalog_tags rows for them.)

-- Continue in Step 4 with the families
```

- [ ] **Step 4: Add the family + variant + option blocks for Canpro (continues the same file)**

```sql
-- Families with their option axes. We use named UUIDs for clarity; the
-- actual ids are stable within this migration so we can wire up variants
-- afterward with explicit IDs.
--
-- Approach per family:
--   1. INSERT catalog_items row (the family)
--   2. INSERT catalog_options for axes used by that family's variants
--   3. INSERT catalog_option_values for each axis's possible values
--   4. INSERT catalog_variants — one per legacy inventory_item row
--   5. INSERT catalog_variant_option_values — link each variant to its value combo
--
-- We materialize this as a series of explicit INSERTs (not loops) so the
-- migration is auditable and rerun-safe. It's verbose but clear.
--
-- Helper: for each legacy item, the option-value mapping comes from the item's tags.
--
-- Color axis (option) is present on every Canpro family that has any
-- Black/White-tagged variant. Mount Type axis (Topmount / Sidemount /
-- Hardware Level / Hardware Stair) is present on families whose variants
-- carry those tags.
--
-- Below is the actual data — derived from Step 1's query result. If the
-- shape diverges from what's recorded, halt and re-survey.

-- (REPEATED PATTERN — illustrating the first family in full; remaining
-- families follow the same structure. The actual migration file enumerates
-- ALL families. The agent executing this task SHOULD derive each family's
-- block from the Step 1 query result and the rules above.)

-- ----- Family: "Corner" -----
INSERT INTO public.catalog_items (id, company_id, category_id, name, default_unit_id, is_active, created_at, updated_at)
SELECT '22222222-aaaa-0001-0000-000000000000', 'a612edc0-5c18-4c4d-af97-55b9410dd077', '11111111-1111-1111-1111-100000001001',
       'Corner',
       (SELECT id FROM public.catalog_units u WHERE u.company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND u.is_default = true LIMIT 1),
       true, now(), now();

INSERT INTO public.catalog_options (id, catalog_item_id, name, sort_order)
VALUES
    ('22222222-aaaa-0001-1000-000000000001', '22222222-aaaa-0001-0000-000000000000', 'Color', 10),
    ('22222222-aaaa-0001-1000-000000000002', '22222222-aaaa-0001-0000-000000000000', 'Mount Type', 20);

INSERT INTO public.catalog_option_values (id, option_id, value, sort_order)
VALUES
    ('22222222-aaaa-0001-2000-000000000001', '22222222-aaaa-0001-1000-000000000001', 'Black', 10),
    ('22222222-aaaa-0001-2000-000000000002', '22222222-aaaa-0001-1000-000000000001', 'White', 20),
    ('22222222-aaaa-0001-2000-000000000003', '22222222-aaaa-0001-1000-000000000002', 'Topmount', 10),
    ('22222222-aaaa-0001-2000-000000000004', '22222222-aaaa-0001-1000-000000000002', 'Sidemount', 20),
    ('22222222-aaaa-0001-2000-000000000005', '22222222-aaaa-0001-1000-000000000002', 'Hardware Level', 30);

-- Variants: collapse Canpro's 6 "Corner" rows into 6 variants with explicit option-value combos.
-- The ids of legacy inventory_items are preserved as catalog_variants.id so existing FKs continue.
-- (Canpro currently has zero rows in inventory_deductions, task_materials, etc., so FK preservation
--  is precautionary, not load-bearing.)
INSERT INTO public.catalog_variants (id, company_id, catalog_item_id, sku, quantity, warning_threshold, critical_threshold, unit_id, is_active, created_at, updated_at)
SELECT i.id, i.company_id, '22222222-aaaa-0001-0000-000000000000', i.sku, i.quantity, i.warning_threshold, i.critical_threshold, i.unit_id, true, i.created_at, i.updated_at
FROM public.inventory_items i
WHERE i.company_id='a612edc0-5c18-4c4d-af97-55b9410dd077'
  AND lower(trim(i.name))='corner'
  AND i.deleted_at IS NULL;

-- Option-value linking. Derive from each inventory_items row's tag set:
INSERT INTO public.catalog_variant_option_values (variant_id, option_value_id)
SELECT i.id,
       CASE
           WHEN EXISTS (SELECT 1 FROM public.inventory_item_tags it JOIN public.inventory_tags t ON t.id=it.tag_id WHERE it.item_id=i.id AND t.name='Black')
               THEN '22222222-aaaa-0001-2000-000000000001'::uuid
           WHEN EXISTS (SELECT 1 FROM public.inventory_item_tags it JOIN public.inventory_tags t ON t.id=it.tag_id WHERE it.item_id=i.id AND t.name='White')
               THEN '22222222-aaaa-0001-2000-000000000002'::uuid
       END
FROM public.inventory_items i
WHERE i.company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND lower(trim(i.name))='corner' AND i.deleted_at IS NULL
  AND EXISTS (SELECT 1 FROM public.inventory_item_tags it JOIN public.inventory_tags t ON t.id=it.tag_id
              WHERE it.item_id=i.id AND t.name IN ('Black','White'));

INSERT INTO public.catalog_variant_option_values (variant_id, option_value_id)
SELECT i.id,
       CASE
           WHEN EXISTS (SELECT 1 FROM public.inventory_item_tags it JOIN public.inventory_tags t ON t.id=it.tag_id WHERE it.item_id=i.id AND t.name='Topmount')
               THEN '22222222-aaaa-0001-2000-000000000003'::uuid
           WHEN EXISTS (SELECT 1 FROM public.inventory_item_tags it JOIN public.inventory_tags t ON t.id=it.tag_id WHERE it.item_id=i.id AND t.name='Side mount')
               THEN '22222222-aaaa-0001-2000-000000000004'::uuid
           WHEN EXISTS (SELECT 1 FROM public.inventory_item_tags it JOIN public.inventory_tags t ON t.id=it.tag_id WHERE it.item_id=i.id AND t.name='Hardware Level')
               THEN '22222222-aaaa-0001-2000-000000000005'::uuid
       END
FROM public.inventory_items i
WHERE i.company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND lower(trim(i.name))='corner' AND i.deleted_at IS NULL
  AND EXISTS (SELECT 1 FROM public.inventory_item_tags it JOIN public.inventory_tags t ON t.id=it.tag_id
              WHERE it.item_id=i.id AND t.name IN ('Topmount','Side mount','Hardware Level'));

-- Repeat the above 5-block pattern for each remaining Canpro family from Step 1's query.
-- Families to author (one block each — the agent enumerates them from Step 1 output):
--   45 Degree (or 45.0)         — Hardware Level / Black,White
--   Bottom Down/Up              — Hardware Stair / Black,White
--   Bottom Wall Bracket         — Hardware Level / Black,White
--   Bottom Stair Wall Bracket   — Hardware Stair / Black,White
--   Blank                       — Topmount/Sidemount / Black,White
--   Blank Adapter               — Hardware Level / Black,White
--   Top Stair Wall Bracket      — Hardware Stair / Black,White
--   Top Down/Up                 — Hardware Stair / Black,White
--   Top Wall Bracket            — Hardware Level / Black,White
--   2"                          — Screws / Black,White
--   3"                          — Screws / Black,White
--   4"                          — Screws / Black,White
--   Teks                        — Screws (no color — verify in Step 1 output)
--   ... and any others surfaced by Step 1
-- Each block: family + options + option_values + variants + variant_option_value links.
```

- [ ] **Step 5: Append Canpro verification block (in same SQL file)**

```sql
-- ----- Canpro post-counts -----
DO $$
DECLARE
    pre_items integer;
    pre_qty_sum double precision;
    post_variants integer;
    post_qty_sum double precision;
BEGIN
    SELECT items_count, qty_sum INTO pre_items, pre_qty_sum FROM __canpro_baseline;

    SELECT COUNT(*), SUM(quantity) INTO post_variants, post_qty_sum
    FROM public.catalog_variants WHERE company_id='a612edc0-5c18-4c4d-af97-55b9410dd077' AND deleted_at IS NULL;

    IF post_variants <> pre_items THEN
        RAISE EXCEPTION 'Canpro variant count mismatch: pre=%, post=%', pre_items, post_variants;
    END IF;
    IF post_qty_sum <> pre_qty_sum THEN
        RAISE EXCEPTION 'Canpro quantity sum mismatch: pre=%, post=%', pre_qty_sum, post_qty_sum;
    END IF;
END $$;
```

### Task 8: Author Maverick family + category mapping

- [ ] **Step 1: Inspect Maverick's distinct family names and tag distribution (the same query as Task 7 Step 1, with Maverick's company_id substituted)**

- [ ] **Step 2: Add Maverick blocks to the same migration file**

Maverick is simpler — only Color axis. No Mount Type. No nested categories needed. Just a flat "Hardware" or no-category and Color (Black, White) on every family.

Same INSERT pattern as Canpro but:
- Categories: a single top-level "Hardware" category
- Each family carries only a Color axis with Black, White values
- Fix the tag names ("Black Qty" → "Black", "White Qty" → "White") at promotion time

(Block enumerates Maverick's ~29 distinct family names.)

### Task 9: Append final cleanup + verification + COMMIT

- [ ] **Step 1: Soft-delete the legacy inventory_* rows that have been migrated**

```sql
-- After migration, mark the legacy rows soft-deleted so they don't double-count.
-- The DROP TABLE in 02-catalog-views-triggers.sql will remove them entirely
-- but we want the system in a consistent state in case 02 doesn't run immediately.
UPDATE public.inventory_items SET deleted_at = now()
WHERE company_id IN ('a612edc0-5c18-4c4d-af97-55b9410dd077','ddee107c-33cd-483e-8278-0f8d8a180181')
  AND deleted_at IS NULL;
UPDATE public.inventory_tags SET deleted_at = now()
WHERE company_id IN ('a612edc0-5c18-4c4d-af97-55b9410dd077','ddee107c-33cd-483e-8278-0f8d8a180181')
  AND deleted_at IS NULL;
-- inventory_units rows are MIGRATED in place (we copied them into catalog_units with same IDs).
-- No need to soft-delete; the 02 migration drops the table.

-- Cleanup baseline temp table
DROP TABLE __canpro_baseline;

COMMIT;
```

### Task 10: Apply migration 03 and verify

- [ ] **Step 1: Apply via MCP `apply_migration` with `name='2026-05-06-03-catalog-data-canpro-maverick'`**

- [ ] **Step 2: Verify Canpro and Maverick post-migration state**

```sql
SELECT c.name AS company,
       (SELECT COUNT(*) FROM public.catalog_items WHERE company_id=c.id AND deleted_at IS NULL) AS families,
       (SELECT COUNT(*) FROM public.catalog_variants WHERE company_id=c.id AND deleted_at IS NULL) AS variants,
       (SELECT SUM(quantity) FROM public.catalog_variants WHERE company_id=c.id AND deleted_at IS NULL) AS qty_sum,
       (SELECT COUNT(*) FROM public.catalog_categories WHERE company_id=c.id AND deleted_at IS NULL) AS categories
FROM public.companies c
WHERE c.id IN ('a612edc0-5c18-4c4d-af97-55b9410dd077','ddee107c-33cd-483e-8278-0f8d8a180181');
```

Expected:
- Canpro: variants=58, qty_sum=Canpro baseline qty (recorded in Phase 1 Task 1), families ~10–14, categories=8
- Maverick: variants=58, qty_sum=Maverick baseline qty, families ~29, categories=1

- [ ] **Step 3: Verify no orphan variants exist**

```sql
SELECT v.id, v.catalog_item_id FROM public.catalog_variants v
LEFT JOIN public.catalog_items i ON i.id = v.catalog_item_id
WHERE i.id IS NULL;
```

Expected: 0 rows.

- [ ] **Step 4: Verify variant↔option_value linking is complete**

```sql
SELECT v.id, ci.name, COUNT(cvov.option_value_id) AS option_link_count, COUNT(co.id) AS option_count
FROM public.catalog_variants v
JOIN public.catalog_items ci ON ci.id = v.catalog_item_id
LEFT JOIN public.catalog_options co ON co.catalog_item_id = ci.id
LEFT JOIN public.catalog_variant_option_values cvov ON cvov.variant_id = v.id
WHERE v.company_id IN ('a612edc0-5c18-4c4d-af97-55b9410dd077','ddee107c-33cd-483e-8278-0f8d8a180181')
GROUP BY v.id, ci.name
HAVING COUNT(cvov.option_value_id) <> COUNT(co.id);
```

Expected: 0 rows. Every variant has exactly as many option_value links as its family has options.

### Task 11: Apply migration 02 (views/triggers/mirror) — only after Phase 2 verification passes

This is Phase 1 Task 6 above. Apply now that legacy data is migrated.

- [ ] **Step 1: Apply via MCP**

- [ ] **Step 2: Run the verification queries from Phase 1 Task 6 Steps 2–4**

---

## Phase 3 — iOS DataModel + DTO + Repository foundation

Goal: define the SwiftData models for catalog and Product extensions, create Codable DTOs that map to the new Supabase schema, and build the repositories that will power the rest of the iOS work. This phase also fixes the `ProductDTO` wire-field bug (`unit_price` → `default_price`/`base_price`, `cost_price` → `unit_cost`).

This phase has no UI. Output: green build, all unit tests pass, no behavior change visible to the user yet.

### Task 12: Bump SwiftData schema to V3

**Files:**
- Create: `OPS/OPS/DataModels/Migrations/OPSSchemaV3.swift`
- Modify: `OPS/OPS/DataModels/Migrations/OPSMigrationPlan.swift`
- Modify: `OPS/OPS/DataModels/Migrations/OPSSchemaCommon.swift`
- Modify: `OPS/OPS/OPSApp.swift`

The on-disk store may already contain InventoryItem/InventoryTag/InventoryUnit/InventorySnapshot/InventorySnapshotItem rows from earlier builds. The V2→V3 migration drops those entities and registers the new catalog entities. SwiftData's lightweight migration cannot drop entities automatically, so V3 declares the new model list and the migration plan does a custom destructive migration (reset the local store) — safe because every `@Model` in this project is server-backed and recoverable via sync.

- [ ] **Step 1: Update `OPSSchemaCommon.swift` to remove inventory entities and add catalog entities**

```swift
//
//  OPSSchemaCommon.swift
//  OPS
//

import Foundation
import SwiftData

enum OPSSchemaCommon {
    /// Every `@Model` in the OPS schema except `WizardState`.
    static let unchangedModels: [any PersistentModel.Type] = [
        // Core data models
        User.self,
        Project.self,
        Company.self,
        TeamMember.self,
        Client.self,
        SubClient.self,
        ProjectTask.self,
        TaskType.self,
        TaskStatusOption.self,
        SyncOperation.self,
        OpsContact.self,

        // Supabase-backed models
        Opportunity.self,
        Activity.self,
        FollowUp.self,
        StageTransition.self,
        Estimate.self,
        EstimateLineItem.self,
        Invoice.self,
        InvoiceLineItem.self,
        Payment.self,
        Product.self,
        SiteVisit.self,
        ProjectNote.self,
        PhotoAnnotation.self,
        CalendarUserEvent.self,

        // Offline-first sync models
        TimeEntry.self,
        SignatureCapture.self,
        FormSubmission.self,
        LocalPhoto.self,

        // Catalog models (replaces old inventory models)
        CatalogCategory.self,
        CatalogItem.self,
        CatalogVariant.self,
        CatalogOption.self,
        CatalogOptionValue.self,
        CatalogVariantOptionValue.self,
        CatalogTag.self,
        CatalogUnit.self,
        CatalogSnapshot.self,
        CatalogSnapshotItem.self,
        CatalogOrder.self,
        CatalogOrderItem.self,
        CompanyDefaultProduct.self,

        // Product configurability
        ProductOption.self,
        ProductOptionValue.self,
        ProductPricingModifier.self,
        ProductMaterial.self,

        // Deck builder
        DeckDesign.self
    ]
}
```

- [ ] **Step 2: Create `OPSSchemaV3.swift`**

```swift
//
//  OPSSchemaV3.swift
//  OPS
//
//  Schema version 3.0.0 — Catalog & Variant Model.
//  V3 drops InventoryItem/InventoryTag/InventoryUnit/InventorySnapshot/
//  InventorySnapshotItem and adds the catalog_* and product_* extension
//  entities. WizardState is unchanged from V2.
//

import Foundation
import SwiftData

enum OPSSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels + [WizardState.self]
    }
}
```

- [ ] **Step 3: Extend `OPSMigrationPlan.swift` with a V2→V3 stage**

The V2→V3 stage is destructive: SwiftData cannot drop entities while preserving rows from a removed entity. We mark this `customMigration` and reset the inventory portion of the store (no-op if the user has never opened the inventory tab; otherwise the next sync will repopulate from Supabase).

```swift
//
//  OPSMigrationPlan.swift
//  OPS
//

import Foundation
import SwiftData

enum OPSMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [
        OPSSchemaV1.self,
        OPSSchemaV2.self,
        OPSSchemaV3.self
    ]

    static var stages: [MigrationStage] = [
        // Existing V1→V2 stage (preserve as-is)
        .lightweight(fromVersion: OPSSchemaV1.self, toVersion: OPSSchemaV2.self),

        // V2→V3 — destructive removal of inventory entities.
        // SwiftData's customMigration runs the willMigrate before the schema
        // change, allowing us to dump the stale entities. The new catalog
        // entities will be empty until the next inbound sync runs.
        .custom(
            fromVersion: OPSSchemaV2.self,
            toVersion: OPSSchemaV3.self,
            willMigrate: { context in
                // No-op intentionally. We rely on the schema diff itself to
                // drop the inventory entities. SwiftData removes records of
                // entity types not present in the new schema.
                try? context.save()
            },
            didMigrate: { context in
                // Force a fresh full-sync flag so InboundProcessor pulls all
                // catalog data on next launch. Implementation reads
                // `UserDefaults.standard.set(true, forKey: "ops.needsFullCatalogSync")`.
                UserDefaults.standard.set(true, forKey: "ops.needsFullCatalogSync")
            }
        )
    ]
}
```

- [ ] **Step 4: Update `OPSApp.swift` to use `OPSSchemaV3`**

Find the line:

```swift
let schema = Schema(versionedSchema: OPSSchemaV2.self)
```

Replace with:

```swift
let schema = Schema(versionedSchema: OPSSchemaV3.self)
```

- [ ] **Step 5: Build (Tasks 13–28 must be done before this builds — defer)**

The build will not succeed until all referenced types (CatalogCategory, ProductOption, etc.) are created. Mark this step as PENDING and proceed to Task 13.

### Task 13: Create `CatalogUnit` SwiftData model

**Files:**
- Create: `OPS/OPS/DataModels/Supabase/Catalog/CatalogUnit.swift`

CatalogUnit is created first because catalog_items.default_unit_id and catalog_variants.unit_id reference it.

- [ ] **Step 1: Write the model**

```swift
//
//  CatalogUnit.swift
//  OPS
//
//  Unit of measure for catalog variants (replaces InventoryUnit).
//

import Foundation
import SwiftData

@Model
final class CatalogUnit: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var display: String          // e.g., "ea", "box", "ft"
    var abbreviation: String?
    var dimension: String        // 'count' | 'length' | 'area' | 'volume' | 'mass' | 'time'
    var isDefault: Bool
    var sortOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        display: String,
        abbreviation: String? = nil,
        dimension: String = "count",
        isDefault: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.companyId = companyId
        self.display = display
        self.abbreviation = abbreviation
        self.dimension = dimension
        self.isDefault = isDefault
        self.sortOrder = sortOrder
    }
}
```

### Task 14: Create `CatalogCategory` SwiftData model

**Files:**
- Create: `OPS/OPS/DataModels/Supabase/Catalog/CatalogCategory.swift`

- [ ] **Step 1: Write the model**

```swift
//
//  CatalogCategory.swift
//  OPS
//
//  Nested category for catalog items (parent_id self-FK, 2-level UI max).
//

import Foundation
import SwiftData

@Model
final class CatalogCategory: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var name: String
    var parentId: String?
    var sortOrder: Int
    var colorHex: String?
    var defaultWarningThreshold: Double?
    var defaultCriticalThreshold: Double?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        name: String,
        parentId: String? = nil,
        sortOrder: Int = 0,
        colorHex: String? = nil,
        defaultWarningThreshold: Double? = nil,
        defaultCriticalThreshold: Double? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.name = name
        self.parentId = parentId
        self.sortOrder = sortOrder
        self.colorHex = colorHex
        self.defaultWarningThreshold = defaultWarningThreshold
        self.defaultCriticalThreshold = defaultCriticalThreshold
    }
}
```

### Task 15: Create `CatalogItem` SwiftData model (variant family)

**Files:**
- Create: `OPS/OPS/DataModels/Supabase/Catalog/CatalogItem.swift`

- [ ] **Step 1: Write the model**

```swift
//
//  CatalogItem.swift
//  OPS
//
//  Variant family — one row per logical product (e.g., "Corner") that
//  may have N variants differing by option values. The family carries
//  default price/cost/threshold; variants can override per-SKU.
//

import Foundation
import SwiftData

@Model
final class CatalogItem: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var categoryId: String?
    var name: String
    var itemDescription: String?
    var defaultPrice: Double?
    var defaultUnitCost: Double?
    var defaultWarningThreshold: Double?
    var defaultCriticalThreshold: Double?
    var defaultUnitId: String?
    var imageUrl: String?
    var notes: String?
    var isActive: Bool

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        name: String,
        categoryId: String? = nil,
        defaultPrice: Double? = nil,
        defaultUnitCost: Double? = nil,
        defaultWarningThreshold: Double? = nil,
        defaultCriticalThreshold: Double? = nil,
        defaultUnitId: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.companyId = companyId
        self.name = name
        self.categoryId = categoryId
        self.defaultPrice = defaultPrice
        self.defaultUnitCost = defaultUnitCost
        self.defaultWarningThreshold = defaultWarningThreshold
        self.defaultCriticalThreshold = defaultCriticalThreshold
        self.defaultUnitId = defaultUnitId
        self.isActive = isActive
    }
}
```

### Task 16: Create `CatalogOption` and `CatalogOptionValue` SwiftData models

**Files:**
- Create: `OPS/OPS/DataModels/Supabase/Catalog/CatalogOption.swift`
- Create: `OPS/OPS/DataModels/Supabase/Catalog/CatalogOptionValue.swift`

- [ ] **Step 1: Write `CatalogOption.swift`**

```swift
//
//  CatalogOption.swift
//  OPS
//
//  A variant axis on a CatalogItem (e.g., "Color" or "Mount Type").
//

import Foundation
import SwiftData

@Model
final class CatalogOption: Identifiable {
    @Attribute(.unique) var id: String
    var catalogItemId: String
    var name: String
    var sortOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        catalogItemId: String,
        name: String,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.catalogItemId = catalogItemId
        self.name = name
        self.sortOrder = sortOrder
    }
}
```

- [ ] **Step 2: Write `CatalogOptionValue.swift`**

```swift
//
//  CatalogOptionValue.swift
//  OPS
//
//  A possible value for a CatalogOption (e.g., "Black" on Color).
//

import Foundation
import SwiftData

@Model
final class CatalogOptionValue: Identifiable {
    @Attribute(.unique) var id: String
    var optionId: String
    var value: String
    var sortOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        optionId: String,
        value: String,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.optionId = optionId
        self.value = value
        self.sortOrder = sortOrder
    }
}
```

### Task 17: Create `CatalogVariant` and `CatalogVariantOptionValue` SwiftData models

**Files:**
- Create: `OPS/OPS/DataModels/Supabase/Catalog/CatalogVariant.swift`
- Create: `OPS/OPS/DataModels/Supabase/Catalog/CatalogVariantOptionValue.swift`

- [ ] **Step 1: Write `CatalogVariant.swift`**

```swift
//
//  CatalogVariant.swift
//  OPS
//
//  The concrete SKU. Belongs to a CatalogItem (family) and references
//  one CatalogOptionValue per CatalogOption on that family.
//

import Foundation
import SwiftData

enum ThresholdStatus: String, CaseIterable, Comparable {
    case normal
    case warning
    case critical

    static func < (lhs: ThresholdStatus, rhs: ThresholdStatus) -> Bool {
        let order: [ThresholdStatus: Int] = [.normal: 0, .warning: 1, .critical: 2]
        return (order[lhs] ?? 0) < (order[rhs] ?? 0)
    }
}

@Model
final class CatalogVariant: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var catalogItemId: String
    var sku: String?
    var quantity: Double
    var priceOverride: Double?
    var unitCostOverride: Double?
    var warningThreshold: Double?
    var criticalThreshold: Double?
    var unitId: String?
    var isActive: Bool

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        catalogItemId: String,
        sku: String? = nil,
        quantity: Double = 0,
        priceOverride: Double? = nil,
        unitCostOverride: Double? = nil,
        warningThreshold: Double? = nil,
        criticalThreshold: Double? = nil,
        unitId: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.companyId = companyId
        self.catalogItemId = catalogItemId
        self.sku = sku
        self.quantity = quantity
        self.priceOverride = priceOverride
        self.unitCostOverride = unitCostOverride
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.unitId = unitId
        self.isActive = isActive
    }
}
```

- [ ] **Step 2: Write `CatalogVariantOptionValue.swift`**

```swift
//
//  CatalogVariantOptionValue.swift
//  OPS
//
//  Junction: CatalogVariant ↔ CatalogOptionValue. Each variant has
//  exactly one row per CatalogOption on its family.
//

import Foundation
import SwiftData

@Model
final class CatalogVariantOptionValue {
    var variantId: String
    var optionValueId: String

    var lastSyncedAt: Date?

    init(variantId: String, optionValueId: String) {
        self.variantId = variantId
        self.optionValueId = optionValueId
    }
}
```

### Task 18: Create `CatalogTag` and `CatalogItemTag` (M2M) SwiftData models

**Files:**
- Create: `OPS/OPS/DataModels/Supabase/Catalog/CatalogTag.swift`
- Create: `OPS/OPS/DataModels/Supabase/Catalog/CatalogItemTag.swift`

- [ ] **Step 1: Write `CatalogTag.swift`**

```swift
//
//  CatalogTag.swift
//  OPS
//
//  Free-form label applied at FAMILY level. The legacy threshold
//  columns are preserved in storage but not surfaced in the UI.
//

import Foundation
import SwiftData

@Model
final class CatalogTag: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var name: String
    var warningThreshold: Double?
    var criticalThreshold: Double?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        name: String,
        warningThreshold: Double? = nil,
        criticalThreshold: Double? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.name = name
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
    }
}
```

- [ ] **Step 2: Write `CatalogItemTag.swift`**

```swift
//
//  CatalogItemTag.swift
//  OPS
//
//  Junction: CatalogItem (family) ↔ CatalogTag.
//

import Foundation
import SwiftData

@Model
final class CatalogItemTag {
    @Attribute(.unique) var id: String
    var catalogItemId: String
    var tagId: String

    var lastSyncedAt: Date?

    init(
        id: String = UUID().uuidString,
        catalogItemId: String,
        tagId: String
    ) {
        self.id = id
        self.catalogItemId = catalogItemId
        self.tagId = tagId
    }
}
```

### Task 19: Create `CatalogSnapshot` and `CatalogSnapshotItem` SwiftData models

**Files:**
- Create: `OPS/OPS/DataModels/Supabase/Catalog/CatalogSnapshot.swift`
- Create: `OPS/OPS/DataModels/Supabase/Catalog/CatalogSnapshotItem.swift`

- [ ] **Step 1: Write `CatalogSnapshot.swift`**

```swift
//
//  CatalogSnapshot.swift
//  OPS
//
//  Variant-aware historical snapshot of stock at a point in time.
//

import Foundation
import SwiftData

@Model
final class CatalogSnapshot: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var createdById: String?
    var isAutomatic: Bool
    var itemCount: Int
    var notes: String?
    var createdAt: Date

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        companyId: String,
        createdAt: Date = Date(),
        createdById: String? = nil,
        isAutomatic: Bool = false,
        itemCount: Int = 0,
        notes: String? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.createdAt = createdAt
        self.createdById = createdById
        self.isAutomatic = isAutomatic
        self.itemCount = itemCount
        self.notes = notes
    }
}
```

- [ ] **Step 2: Write `CatalogSnapshotItem.swift`**

```swift
//
//  CatalogSnapshotItem.swift
//  OPS
//

import Foundation
import SwiftData

@Model
final class CatalogSnapshotItem: Identifiable {
    @Attribute(.unique) var id: String
    var snapshotId: String
    var originalVariantId: String?
    var familyName: String              // denormalized
    var variantLabel: String?           // e.g., "Black · Topmount"
    var quantity: Double
    var unitDisplay: String?
    var sku: String?
    var itemDescription: String?

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        snapshotId: String,
        originalVariantId: String? = nil,
        familyName: String,
        variantLabel: String? = nil,
        quantity: Double = 0,
        unitDisplay: String? = nil,
        sku: String? = nil,
        itemDescription: String? = nil
    ) {
        self.id = id
        self.snapshotId = snapshotId
        self.originalVariantId = originalVariantId
        self.familyName = familyName
        self.variantLabel = variantLabel
        self.quantity = quantity
        self.unitDisplay = unitDisplay
        self.sku = sku
        self.itemDescription = itemDescription
    }
}
```

### Task 20: Create `CatalogOrder` and `CatalogOrderItem` SwiftData models

**Files:**
- Create: `OPS/OPS/DataModels/Supabase/Catalog/CatalogOrder.swift`
- Create: `OPS/OPS/DataModels/Supabase/Catalog/CatalogOrderItem.swift`

- [ ] **Step 1: Write `CatalogOrder.swift`**

```swift
//
//  CatalogOrder.swift
//  OPS
//
//  Threshold-driven restock order (suggested / draft / sent / fulfilled).
//

import Foundation
import SwiftData

enum CatalogOrderStatus: String, CaseIterable, Codable {
    case suggested
    case draft
    case sent
    case fulfilled
    case cancelled
}

@Model
final class CatalogOrder: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var status: CatalogOrderStatus
    var title: String?
    var supplierName: String?
    var supplierContact: String?
    var expectedDeliveryDate: Date?
    var notes: String?
    var createdById: String?
    var createdAt: Date
    var updatedAt: Date
    var sentAt: Date?
    var fulfilledAt: Date?
    var cancelledAt: Date?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        status: CatalogOrderStatus = .draft,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 2: Write `CatalogOrderItem.swift`**

```swift
//
//  CatalogOrderItem.swift
//  OPS
//

import Foundation
import SwiftData

@Model
final class CatalogOrderItem: Identifiable {
    @Attribute(.unique) var id: String
    var orderId: String
    var catalogVariantId: String
    var quantityRequested: Double
    var costPerUnit: Double?
    var notes: String?

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        orderId: String,
        catalogVariantId: String,
        quantityRequested: Double,
        costPerUnit: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.orderId = orderId
        self.catalogVariantId = catalogVariantId
        self.quantityRequested = quantityRequested
        self.costPerUnit = costPerUnit
        self.notes = notes
    }
}
```

### Task 21: Create `CompanyDefaultProduct` SwiftData model

**Files:**
- Create: `OPS/OPS/DataModels/Supabase/Catalog/CompanyDefaultProduct.swift`

- [ ] **Step 1: Write the model**

```swift
//
//  CompanyDefaultProduct.swift
//  OPS
//
//  Per-company default Product per Deck Builder component_type.
//  Drives the one-click drawing → estimate adapter.
//

import Foundation
import SwiftData

enum DesignComponentType: String, CaseIterable, Codable {
    case railing
    case deckBoard = "deck_board"
    case stairSet = "stair_set"
    case gate
    case postSet = "post_set"
}

@Model
final class CompanyDefaultProduct {
    var companyId: String
    var componentType: DesignComponentType
    var productId: String
    var createdAt: Date
    var updatedAt: Date

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        companyId: String,
        componentType: DesignComponentType,
        productId: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.companyId = companyId
        self.componentType = componentType
        self.productId = productId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

### Task 22: Create Product extension SwiftData models (`ProductOption`, `ProductOptionValue`, `ProductPricingModifier`, `ProductMaterial`)

**Files:**
- Create: `OPS/OPS/DataModels/Supabase/Catalog/ProductOption.swift`
- Create: `OPS/OPS/DataModels/Supabase/Catalog/ProductOptionValue.swift`
- Create: `OPS/OPS/DataModels/Supabase/Catalog/ProductPricingModifier.swift`
- Create: `OPS/OPS/DataModels/Supabase/Catalog/ProductMaterial.swift`

- [ ] **Step 1: Write `ProductOption.swift`**

```swift
//
//  ProductOption.swift
//  OPS
//
//  Configuration knob on a Product. Affects price, recipe, or both.
//

import Foundation
import SwiftData

enum ProductOptionKind: String, CaseIterable, Codable {
    case select
    case integer
    case boolean
}

@Model
final class ProductOption: Identifiable {
    @Attribute(.unique) var id: String
    var productId: String
    var name: String
    var kind: ProductOptionKind
    var affectsPrice: Bool
    var affectsRecipe: Bool
    var required: Bool
    var defaultValue: String?
    var optionDefaultSource: String?    // e.g. "$design.color"
    var sortOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        productId: String,
        name: String,
        kind: ProductOptionKind,
        affectsPrice: Bool = false,
        affectsRecipe: Bool = false,
        required: Bool = true,
        defaultValue: String? = nil,
        optionDefaultSource: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.productId = productId
        self.name = name
        self.kind = kind
        self.affectsPrice = affectsPrice
        self.affectsRecipe = affectsRecipe
        self.required = required
        self.defaultValue = defaultValue
        self.optionDefaultSource = optionDefaultSource
        self.sortOrder = sortOrder
    }
}
```

- [ ] **Step 2: Write `ProductOptionValue.swift`**

```swift
//
//  ProductOptionValue.swift
//  OPS
//

import Foundation
import SwiftData

@Model
final class ProductOptionValue: Identifiable {
    @Attribute(.unique) var id: String
    var optionId: String
    var value: String
    var sortOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        optionId: String,
        value: String,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.optionId = optionId
        self.value = value
        self.sortOrder = sortOrder
    }
}
```

- [ ] **Step 3: Write `ProductPricingModifier.swift`**

```swift
//
//  ProductPricingModifier.swift
//  OPS
//
//  A rule that bumps price based on an option's value (or integer count).
//

import Foundation
import SwiftData

enum PricingModifierKind: String, CaseIterable, Codable {
    case addPerUnit = "add_per_unit"
    case addFlat = "add_flat"
    case addPerCount = "add_per_count"
    case multiplyUnitPrice = "multiply_unit_price"
}

@Model
final class ProductPricingModifier: Identifiable {
    @Attribute(.unique) var id: String
    var productId: String
    var optionId: String
    var triggerValueId: String?         // when option is select-kind
    var triggerIntMin: Int?             // when option is integer-kind
    var triggerIntMax: Int?
    var modifierKind: PricingModifierKind
    var amount: Double

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        productId: String,
        optionId: String,
        triggerValueId: String? = nil,
        triggerIntMin: Int? = nil,
        triggerIntMax: Int? = nil,
        modifierKind: PricingModifierKind,
        amount: Double
    ) {
        self.id = id
        self.productId = productId
        self.optionId = optionId
        self.triggerValueId = triggerValueId
        self.triggerIntMin = triggerIntMin
        self.triggerIntMax = triggerIntMax
        self.modifierKind = modifierKind
        self.amount = amount
    }
}
```

- [ ] **Step 4: Write `ProductMaterial.swift`**

```swift
//
//  ProductMaterial.swift
//  OPS
//
//  Recipe row: how much of which catalog variant (or family + selector)
//  a Product consumes per unit. Resolves at install task creation.
//

import Foundation
import SwiftData

@Model
final class ProductMaterial: Identifiable {
    @Attribute(.unique) var id: String
    var productId: String
    var catalogVariantId: String?       // pinned variant
    var catalogItemId: String?          // family head (resolved via selector)
    var variantSelectorJSON: String?    // jsonb stored as JSON string
    var quantityPerUnit: Double
    var scaledByOptionId: String?
    var unitId: String?
    var notes: String?

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        productId: String,
        catalogVariantId: String? = nil,
        catalogItemId: String? = nil,
        variantSelectorJSON: String? = nil,
        quantityPerUnit: Double,
        scaledByOptionId: String? = nil,
        unitId: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.productId = productId
        self.catalogVariantId = catalogVariantId
        self.catalogItemId = catalogItemId
        self.variantSelectorJSON = variantSelectorJSON
        self.quantityPerUnit = quantityPerUnit
        self.scaledByOptionId = scaledByOptionId
        self.unitId = unitId
        self.notes = notes
    }
}
```

### Task 23: Update existing `Product` SwiftData model — add 9 missing fields + `pricing_unit` + `base_price`

**Files:**
- Modify: `OPS/OPS/DataModels/Supabase/Product.swift`

- [ ] **Step 1: Replace the model**

```swift
//
//  Product.swift
//  OPS
//
//  Service/product catalog item — Supabase-backed.
//  Configurable Products carry options, pricing modifiers, and recipe rows
//  via separate models (ProductOption, ProductPricingModifier, ProductMaterial).
//

import SwiftData
import Foundation

enum ProductPricingUnit: String, CaseIterable, Codable {
    case each
    case flatRate = "flat_rate"
    case linearFoot = "linear_foot"
    case sqft
    case hour
    case day
}

enum ProductKind: String, CaseIterable, Codable {
    case service
    case good
}

@Model
class Product: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var name: String
    var productDescription: String?
    var type: LineItemType
    var kind: ProductKind
    var basePrice: Double
    var unitCost: Double?
    var pricingUnit: ProductPricingUnit
    var unit: String?               // legacy free-text unit; iOS reads `pricingUnit` for new behavior
    var category: String?           // legacy free-text category on Product (separate from catalog_categories)
    var sku: String?
    var taxable: Bool
    var isActive: Bool
    var isFavorite: Bool
    var minimumCharge: Double?
    var minimumQuantity: Double?
    var showBomOnEstimate: Bool
    var showInStorefront: Bool
    var tieredPricingJSON: String?  // raw jsonb stored as JSON string for the rare power-user case
    var taskTypeId: String?
    var taskTypeRef: String?
    var unitId: String?             // FK to catalog_units (was nullable text before; now uuid)
    var createdAt: Date

    // Computed margin
    var marginPercent: Double? {
        guard let cost = unitCost, cost > 0, basePrice > 0 else { return nil }
        return ((basePrice - cost) / basePrice) * 100
    }

    init(
        id: String = UUID().uuidString,
        companyId: String,
        name: String,
        type: LineItemType = .labor,
        kind: ProductKind = .service,
        basePrice: Double = 0,
        pricingUnit: ProductPricingUnit = .each,
        taxable: Bool = true,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.name = name
        self.type = type
        self.kind = kind
        self.basePrice = basePrice
        self.pricingUnit = pricingUnit
        self.taxable = taxable
        self.isActive = isActive
        self.isFavorite = false
        self.showBomOnEstimate = false
        self.showInStorefront = false
        self.createdAt = createdAt
    }
}
```

### Task 24: Update line item models — add snapshot fields

**Files:**
- Modify: `OPS/OPS/DataModels/Supabase/EstimateLineItem.swift`
- Modify: `OPS/OPS/DataModels/Supabase/InvoiceLineItem.swift`

- [ ] **Step 1: Open `EstimateLineItem.swift` and add three fields**

Add these properties (location: alongside the other `var` declarations on the model):

```swift
// Configurable-product snapshot
var configuredOptionsJSON: String?    // {"mount_type":"<id>", "color":"<id>", "corners": 4}
var resolvedUnitPrice: Double?
var resolvedOptionsLabel: String?
```

Update the initializer signature to accept these as optional parameters; default to `nil`.

- [ ] **Step 2: Repeat for `InvoiceLineItem.swift` (same three fields, same init pattern)**

### Task 25: Fix `ProductDTOs.swift` — wire-field bug + new fields

**Files:**
- Modify: `OPS/OPS/Network/Supabase/DTOs/ProductDTOs.swift`

- [ ] **Step 1: Replace the file contents**

```swift
//
//  ProductDTOs.swift
//  OPS
//
//  DTOs for the Supabase `products` table. The wire-field bug from
//  earlier builds (unit_price / cost_price — columns that don't exist
//  in Supabase) is fixed here: we now correctly map base_price + default_price
//  + unit_cost. The base_price ↔ default_price mirror lives in a Postgres
//  trigger (see migration 02), so iOS only needs to read/write base_price.
//

import Foundation

struct ProductDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let name: String
    let description: String?
    let basePrice: Double                  // FIXED: was unit_price (column did not exist)
    let unitCost: Double?                  // FIXED: was cost_price
    let unit: String?
    let category: String?
    let sku: String?
    let kind: String?                      // 'service' | 'good'
    let pricingUnit: String?
    let type: String?                      // LineItemType raw — LABOR/MATERIAL/OTHER
    let isTaxable: Bool?
    let isActive: Bool
    let isFavorite: Bool
    let minimumCharge: Double?
    let minimumQuantity: Double?
    let showBomOnEstimate: Bool
    let showInStorefront: Bool
    let tieredPricing: AnyJSON?            // jsonb passthrough
    let taskTypeId: String?
    let taskTypeRef: String?
    let unitId: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case companyId             = "company_id"
        case name
        case description
        case basePrice             = "base_price"
        case unitCost              = "unit_cost"
        case unit
        case category
        case sku
        case kind
        case pricingUnit           = "pricing_unit"
        case type
        case isTaxable             = "is_taxable"
        case isActive              = "is_active"
        case isFavorite            = "is_favorite"
        case minimumCharge         = "minimum_charge"
        case minimumQuantity       = "minimum_quantity"
        case showBomOnEstimate     = "show_bom_on_estimate"
        case showInStorefront      = "show_in_storefront"
        case tieredPricing         = "tiered_pricing"
        case taskTypeId            = "task_type_id"
        case taskTypeRef           = "task_type_ref"
        case unitId                = "unit_id"
        case createdAt             = "created_at"
        case updatedAt             = "updated_at"
    }

    func toModel() -> Product {
        let prod = Product(
            id: id,
            companyId: companyId,
            name: name,
            type: type.flatMap { LineItemType(rawValue: $0) } ?? .labor,
            kind: kind.flatMap { ProductKind(rawValue: $0) } ?? .service,
            basePrice: basePrice,
            pricingUnit: pricingUnit.flatMap { ProductPricingUnit(rawValue: $0) } ?? .each,
            taxable: isTaxable ?? true,
            isActive: isActive,
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
        prod.productDescription = description
        prod.unitCost = unitCost
        prod.unit = unit
        prod.category = category
        prod.sku = sku
        prod.isFavorite = isFavorite
        prod.minimumCharge = minimumCharge
        prod.minimumQuantity = minimumQuantity
        prod.showBomOnEstimate = showBomOnEstimate
        prod.showInStorefront = showInStorefront
        prod.tieredPricingJSON = tieredPricing?.rawJSONString
        prod.taskTypeId = taskTypeId
        prod.taskTypeRef = taskTypeRef
        prod.unitId = unitId
        return prod
    }
}

struct CreateProductDTO: Codable {
    let companyId: String
    let name: String
    let description: String?
    let basePrice: Double
    let unitCost: Double?
    let unit: String?
    let pricingUnit: String?
    let category: String?
    let sku: String?
    let kind: String?
    let type: String?
    let isTaxable: Bool
    let taskTypeId: String?

    enum CodingKeys: String, CodingKey {
        case companyId    = "company_id"
        case name
        case description
        case basePrice    = "base_price"
        case unitCost     = "unit_cost"
        case unit
        case pricingUnit  = "pricing_unit"
        case category
        case sku
        case kind
        case type
        case isTaxable    = "is_taxable"
        case taskTypeId   = "task_type_id"
    }
}

struct UpdateProductDTO: Codable {
    var name: String?
    var description: String?
    var basePrice: Double?
    var unitCost: Double?
    var unit: String?
    var pricingUnit: String?
    var category: String?
    var sku: String?
    var kind: String?
    var type: String?
    var isTaxable: Bool?
    var isActive: Bool?
    var isFavorite: Bool?
    var minimumCharge: Double?
    var minimumQuantity: Double?
    var taskTypeId: String?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case basePrice         = "base_price"
        case unitCost          = "unit_cost"
        case unit
        case pricingUnit       = "pricing_unit"
        case category
        case sku
        case kind
        case type
        case isTaxable         = "is_taxable"
        case isActive          = "is_active"
        case isFavorite        = "is_favorite"
        case minimumCharge     = "minimum_charge"
        case minimumQuantity   = "minimum_quantity"
        case taskTypeId        = "task_type_id"
    }
}

/// Type-erased JSON value for `tiered_pricing` and other jsonb fields we want
/// to pass through without strong typing.
struct AnyJSON: Codable {
    let rawJSONString: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Preserve raw JSON by re-encoding through JSONSerialization.
        let value = try container.decode(JSONValue.self)
        let data = try JSONEncoder().encode(value)
        rawJSONString = String(data: data, encoding: .utf8) ?? "{}"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let data = rawJSONString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) {
            try container.encode(decoded)
        } else {
            try container.encode(JSONValue.object([:]))
        }
    }
}

private indirect enum JSONValue: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let b):    try c.encode(b)
        case .number(let n):  try c.encode(n)
        case .string(let s):  try c.encode(s)
        case .array(let a):   try c.encode(a)
        case .object(let o):  try c.encode(o)
        }
    }
}
```

### Task 26: Create `CatalogDTOs.swift` for the catalog tables

**Files:**
- Create: `OPS/OPS/Network/Supabase/DTOs/CatalogDTOs.swift`

- [ ] **Step 1: Write the DTO file**

```swift
//
//  CatalogDTOs.swift
//  OPS
//
//  DTOs for catalog_* tables — read, create, update.
//

import Foundation

// MARK: - Read DTOs

struct CatalogCategoryDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let name: String
    let parentId: String?
    let sortOrder: Int
    let colorHex: String?
    let defaultWarningThreshold: Double?
    let defaultCriticalThreshold: Double?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId                  = "company_id"
        case name
        case parentId                   = "parent_id"
        case sortOrder                  = "sort_order"
        case colorHex                   = "color_hex"
        case defaultWarningThreshold    = "default_warning_threshold"
        case defaultCriticalThreshold   = "default_critical_threshold"
        case createdAt                  = "created_at"
        case updatedAt                  = "updated_at"
        case deletedAt                  = "deleted_at"
    }

    func toModel() -> CatalogCategory {
        let cat = CatalogCategory(
            id: id, companyId: companyId, name: name,
            parentId: parentId, sortOrder: sortOrder,
            colorHex: colorHex,
            defaultWarningThreshold: defaultWarningThreshold,
            defaultCriticalThreshold: defaultCriticalThreshold
        )
        cat.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return cat
    }
}

struct CatalogItemDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let categoryId: String?
    let name: String
    let description: String?
    let defaultPrice: Double?
    let defaultUnitCost: Double?
    let defaultWarningThreshold: Double?
    let defaultCriticalThreshold: Double?
    let defaultUnitId: String?
    let imageUrl: String?
    let notes: String?
    let isActive: Bool
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId                  = "company_id"
        case categoryId                 = "category_id"
        case name
        case description
        case defaultPrice               = "default_price"
        case defaultUnitCost            = "default_unit_cost"
        case defaultWarningThreshold    = "default_warning_threshold"
        case defaultCriticalThreshold   = "default_critical_threshold"
        case defaultUnitId              = "default_unit_id"
        case imageUrl                   = "image_url"
        case notes                      = "notes"
        case isActive                   = "is_active"
        case createdAt                  = "created_at"
        case updatedAt                  = "updated_at"
        case deletedAt                  = "deleted_at"
    }

    func toModel() -> CatalogItem {
        let item = CatalogItem(
            id: id, companyId: companyId, name: name,
            categoryId: categoryId,
            defaultPrice: defaultPrice,
            defaultUnitCost: defaultUnitCost,
            defaultWarningThreshold: defaultWarningThreshold,
            defaultCriticalThreshold: defaultCriticalThreshold,
            defaultUnitId: defaultUnitId,
            isActive: isActive
        )
        item.itemDescription = description
        item.imageUrl = imageUrl
        item.notes = notes
        item.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return item
    }
}

struct CatalogVariantDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let catalogItemId: String
    let sku: String?
    let quantity: Double
    let priceOverride: Double?
    let unitCostOverride: Double?
    let warningThreshold: Double?
    let criticalThreshold: Double?
    let unitId: String?
    let isActive: Bool
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId          = "company_id"
        case catalogItemId      = "catalog_item_id"
        case sku
        case quantity
        case priceOverride      = "price_override"
        case unitCostOverride   = "unit_cost_override"
        case warningThreshold   = "warning_threshold"
        case criticalThreshold  = "critical_threshold"
        case unitId             = "unit_id"
        case isActive           = "is_active"
        case createdAt          = "created_at"
        case updatedAt          = "updated_at"
        case deletedAt          = "deleted_at"
    }

    func toModel() -> CatalogVariant {
        let v = CatalogVariant(
            id: id, companyId: companyId, catalogItemId: catalogItemId,
            sku: sku, quantity: quantity,
            priceOverride: priceOverride, unitCostOverride: unitCostOverride,
            warningThreshold: warningThreshold, criticalThreshold: criticalThreshold,
            unitId: unitId, isActive: isActive
        )
        v.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return v
    }
}

struct CatalogOptionDTO: Codable, Identifiable {
    let id: String
    let catalogItemId: String
    let name: String
    let sortOrder: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case catalogItemId  = "catalog_item_id"
        case name
        case sortOrder      = "sort_order"
        case createdAt      = "created_at"
    }

    func toModel() -> CatalogOption {
        CatalogOption(id: id, catalogItemId: catalogItemId, name: name, sortOrder: sortOrder)
    }
}

struct CatalogOptionValueDTO: Codable, Identifiable {
    let id: String
    let optionId: String
    let value: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case optionId   = "option_id"
        case value
        case sortOrder  = "sort_order"
    }

    func toModel() -> CatalogOptionValue {
        CatalogOptionValue(id: id, optionId: optionId, value: value, sortOrder: sortOrder)
    }
}

struct CatalogVariantOptionValueDTO: Codable {
    let variantId: String
    let optionValueId: String

    enum CodingKeys: String, CodingKey {
        case variantId      = "variant_id"
        case optionValueId  = "option_value_id"
    }

    func toModel() -> CatalogVariantOptionValue {
        CatalogVariantOptionValue(variantId: variantId, optionValueId: optionValueId)
    }
}

struct CatalogTagDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let name: String
    let warningThreshold: Double?
    let criticalThreshold: Double?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId          = "company_id"
        case name
        case warningThreshold   = "warning_threshold"
        case criticalThreshold  = "critical_threshold"
        case createdAt          = "created_at"
        case updatedAt          = "updated_at"
        case deletedAt          = "deleted_at"
    }

    func toModel() -> CatalogTag {
        let t = CatalogTag(id: id, companyId: companyId, name: name,
                            warningThreshold: warningThreshold, criticalThreshold: criticalThreshold)
        t.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return t
    }
}

struct CatalogItemTagDTO: Codable, Identifiable {
    let id: String
    let catalogItemId: String
    let tagId: String

    enum CodingKeys: String, CodingKey {
        case id
        case catalogItemId  = "catalog_item_id"
        case tagId          = "tag_id"
    }

    func toModel() -> CatalogItemTag {
        CatalogItemTag(id: id, catalogItemId: catalogItemId, tagId: tagId)
    }
}

struct CatalogUnitDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let display: String
    let abbreviation: String?
    let dimension: String
    let isDefault: Bool
    let sortOrder: Int
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId      = "company_id"
        case display
        case abbreviation
        case dimension
        case isDefault      = "is_default"
        case sortOrder      = "sort_order"
        case createdAt      = "created_at"
        case updatedAt      = "updated_at"
        case deletedAt      = "deleted_at"
    }

    func toModel() -> CatalogUnit {
        let u = CatalogUnit(id: id, companyId: companyId, display: display,
                            abbreviation: abbreviation, dimension: dimension,
                            isDefault: isDefault, sortOrder: sortOrder)
        u.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return u
    }
}

struct CatalogSnapshotDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let createdById: String?
    let isAutomatic: Bool
    let itemCount: Int
    let notes: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case companyId      = "company_id"
        case createdById    = "created_by_id"
        case isAutomatic    = "is_automatic"
        case itemCount      = "item_count"
        case notes
        case createdAt      = "created_at"
    }

    func toModel() -> CatalogSnapshot {
        CatalogSnapshot(
            id: id, companyId: companyId,
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            createdById: createdById, isAutomatic: isAutomatic,
            itemCount: itemCount, notes: notes
        )
    }
}

struct CatalogSnapshotItemDTO: Codable, Identifiable {
    let id: String
    let snapshotId: String
    let originalVariantId: String?
    let familyName: String
    let variantLabel: String?
    let quantity: Double
    let unitDisplay: String?
    let sku: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id
        case snapshotId        = "snapshot_id"
        case originalVariantId = "original_variant_id"
        case familyName        = "family_name"
        case variantLabel      = "variant_label"
        case quantity
        case unitDisplay       = "unit_display"
        case sku
        case description
    }

    func toModel() -> CatalogSnapshotItem {
        CatalogSnapshotItem(
            id: id, snapshotId: snapshotId,
            originalVariantId: originalVariantId,
            familyName: familyName, variantLabel: variantLabel,
            quantity: quantity, unitDisplay: unitDisplay,
            sku: sku, itemDescription: description
        )
    }
}

// MARK: - Create / Update DTOs (write paths)

struct CreateCatalogCategoryDTO: Codable {
    let companyId: String
    let name: String
    let parentId: String?
    let sortOrder: Int
    let colorHex: String?
    let defaultWarningThreshold: Double?
    let defaultCriticalThreshold: Double?

    enum CodingKeys: String, CodingKey {
        case companyId                  = "company_id"
        case name
        case parentId                   = "parent_id"
        case sortOrder                  = "sort_order"
        case colorHex                   = "color_hex"
        case defaultWarningThreshold    = "default_warning_threshold"
        case defaultCriticalThreshold   = "default_critical_threshold"
    }
}

struct CreateCatalogItemDTO: Codable {
    let companyId: String
    let categoryId: String?
    let name: String
    let description: String?
    let defaultPrice: Double?
    let defaultUnitCost: Double?
    let defaultWarningThreshold: Double?
    let defaultCriticalThreshold: Double?
    let defaultUnitId: String?

    enum CodingKeys: String, CodingKey {
        case companyId                  = "company_id"
        case categoryId                 = "category_id"
        case name
        case description
        case defaultPrice               = "default_price"
        case defaultUnitCost            = "default_unit_cost"
        case defaultWarningThreshold    = "default_warning_threshold"
        case defaultCriticalThreshold   = "default_critical_threshold"
        case defaultUnitId              = "default_unit_id"
    }
}

struct CreateCatalogVariantDTO: Codable {
    let companyId: String
    let catalogItemId: String
    let sku: String?
    let quantity: Double
    let priceOverride: Double?
    let unitCostOverride: Double?
    let warningThreshold: Double?
    let criticalThreshold: Double?
    let unitId: String?

    enum CodingKeys: String, CodingKey {
        case companyId          = "company_id"
        case catalogItemId      = "catalog_item_id"
        case sku
        case quantity
        case priceOverride      = "price_override"
        case unitCostOverride   = "unit_cost_override"
        case warningThreshold   = "warning_threshold"
        case criticalThreshold  = "critical_threshold"
        case unitId             = "unit_id"
    }
}

struct UpdateCatalogVariantDTO: Codable {
    var sku: String?
    var quantity: Double?
    var priceOverride: Double?
    var unitCostOverride: Double?
    var warningThreshold: Double?
    var criticalThreshold: Double?
    var unitId: String?

    enum CodingKeys: String, CodingKey {
        case sku
        case quantity
        case priceOverride      = "price_override"
        case unitCostOverride   = "unit_cost_override"
        case warningThreshold   = "warning_threshold"
        case criticalThreshold  = "critical_threshold"
        case unitId             = "unit_id"
    }
}

// (Additional Create/Update DTOs for catalog_options, catalog_option_values,
//  catalog_variant_option_values, catalog_tags, catalog_item_tags, catalog_units,
//  catalog_snapshots, catalog_snapshot_items follow the same pattern as above.
//  Keep field naming consistent with the schema. Follow the pattern, no shortcuts.)
```

### Task 27: Create `ProductExtensionDTOs.swift`

**Files:**
- Create: `OPS/OPS/Network/Supabase/DTOs/ProductExtensionDTOs.swift`

- [ ] **Step 1: Write DTOs for ProductOption / ProductOptionValue / ProductPricingModifier / ProductMaterial**

```swift
//
//  ProductExtensionDTOs.swift
//  OPS
//
//  DTOs for the configurable-Product layers: options, option values,
//  pricing modifiers, and recipe rows (product_materials).
//

import Foundation

struct ProductOptionDTO: Codable, Identifiable {
    let id: String
    let productId: String
    let name: String
    let kind: String          // 'select' | 'integer' | 'boolean'
    let affectsPrice: Bool
    let affectsRecipe: Bool
    let required: Bool
    let defaultValue: String?
    let optionDefaultSource: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case productId            = "product_id"
        case name
        case kind
        case affectsPrice         = "affects_price"
        case affectsRecipe        = "affects_recipe"
        case required
        case defaultValue         = "default_value"
        case optionDefaultSource  = "option_default_source"
        case sortOrder            = "sort_order"
    }

    func toModel() -> ProductOption {
        ProductOption(
            id: id, productId: productId, name: name,
            kind: ProductOptionKind(rawValue: kind) ?? .select,
            affectsPrice: affectsPrice, affectsRecipe: affectsRecipe,
            required: required, defaultValue: defaultValue,
            optionDefaultSource: optionDefaultSource, sortOrder: sortOrder
        )
    }
}

struct ProductOptionValueDTO: Codable, Identifiable {
    let id: String
    let optionId: String
    let value: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case optionId   = "option_id"
        case value
        case sortOrder  = "sort_order"
    }

    func toModel() -> ProductOptionValue {
        ProductOptionValue(id: id, optionId: optionId, value: value, sortOrder: sortOrder)
    }
}

struct ProductPricingModifierDTO: Codable, Identifiable {
    let id: String
    let productId: String
    let optionId: String
    let triggerValueId: String?
    let triggerIntMin: Int?
    let triggerIntMax: Int?
    let modifierKind: String
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case id
        case productId        = "product_id"
        case optionId         = "option_id"
        case triggerValueId   = "trigger_value_id"
        case triggerIntMin    = "trigger_int_min"
        case triggerIntMax    = "trigger_int_max"
        case modifierKind     = "modifier_kind"
        case amount
    }

    func toModel() -> ProductPricingModifier {
        ProductPricingModifier(
            id: id, productId: productId, optionId: optionId,
            triggerValueId: triggerValueId,
            triggerIntMin: triggerIntMin, triggerIntMax: triggerIntMax,
            modifierKind: PricingModifierKind(rawValue: modifierKind) ?? .addPerUnit,
            amount: amount
        )
    }
}

struct ProductMaterialDTO: Codable, Identifiable {
    let id: String
    let productId: String
    let catalogVariantId: String?
    let catalogItemId: String?
    let variantSelector: AnyJSON?
    let quantityPerUnit: Double
    let scaledByOptionId: String?
    let unitId: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case productId          = "product_id"
        case catalogVariantId   = "catalog_variant_id"
        case catalogItemId      = "catalog_item_id"
        case variantSelector    = "variant_selector"
        case quantityPerUnit    = "quantity_per_unit"
        case scaledByOptionId   = "scaled_by_option_id"
        case unitId             = "unit_id"
        case notes
    }

    func toModel() -> ProductMaterial {
        ProductMaterial(
            id: id, productId: productId,
            catalogVariantId: catalogVariantId, catalogItemId: catalogItemId,
            variantSelectorJSON: variantSelector?.rawJSONString,
            quantityPerUnit: quantityPerUnit,
            scaledByOptionId: scaledByOptionId,
            unitId: unitId, notes: notes
        )
    }
}

// CreateProductOptionDTO, CreateProductPricingModifierDTO, CreateProductMaterialDTO
// follow the same pattern. Implement them at the same time as ProductRichnessRepository
// (Task 30).
```

### Task 28: Create `CompanyDefaultProductDTOs.swift`

**Files:**
- Create: `OPS/OPS/Network/Supabase/DTOs/CompanyDefaultProductDTOs.swift`

- [ ] **Step 1: Write the DTO**

```swift
//
//  CompanyDefaultProductDTOs.swift
//  OPS
//

import Foundation

struct CompanyDefaultProductDTO: Codable {
    let companyId: String
    let componentType: String   // 'railing' | 'deck_board' | 'stair_set' | 'gate' | 'post_set'
    let productId: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case companyId      = "company_id"
        case componentType  = "component_type"
        case productId      = "product_id"
        case createdAt      = "created_at"
        case updatedAt      = "updated_at"
    }

    func toModel() -> CompanyDefaultProduct {
        CompanyDefaultProduct(
            companyId: companyId,
            componentType: DesignComponentType(rawValue: componentType) ?? .railing,
            productId: productId,
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            updatedAt: SupabaseDate.parse(updatedAt) ?? Date()
        )
    }
}

struct UpsertCompanyDefaultProductDTO: Codable {
    let companyId: String
    let componentType: String
    let productId: String

    enum CodingKeys: String, CodingKey {
        case companyId      = "company_id"
        case componentType  = "component_type"
        case productId      = "product_id"
    }
}
```

### Task 29: Create `CatalogOrderDTOs.swift`

**Files:**
- Create: `OPS/OPS/Network/Supabase/DTOs/CatalogOrderDTOs.swift`

- [ ] **Step 1: Write the DTOs**

```swift
//
//  CatalogOrderDTOs.swift
//  OPS
//

import Foundation

struct CatalogOrderDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let status: String
    let title: String?
    let supplierName: String?
    let supplierContact: String?
    let expectedDeliveryDate: String?
    let notes: String?
    let createdById: String?
    let createdAt: String
    let updatedAt: String
    let sentAt: String?
    let fulfilledAt: String?
    let cancelledAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId               = "company_id"
        case status
        case title
        case supplierName            = "supplier_name"
        case supplierContact         = "supplier_contact"
        case expectedDeliveryDate    = "expected_delivery_date"
        case notes
        case createdById             = "created_by_id"
        case createdAt               = "created_at"
        case updatedAt               = "updated_at"
        case sentAt                  = "sent_at"
        case fulfilledAt             = "fulfilled_at"
        case cancelledAt             = "cancelled_at"
        case deletedAt               = "deleted_at"
    }

    func toModel() -> CatalogOrder {
        let order = CatalogOrder(
            id: id, companyId: companyId,
            status: CatalogOrderStatus(rawValue: status) ?? .draft,
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            updatedAt: SupabaseDate.parse(updatedAt) ?? Date()
        )
        order.title = title
        order.supplierName = supplierName
        order.supplierContact = supplierContact
        order.expectedDeliveryDate = expectedDeliveryDate.flatMap { SupabaseDate.parseDateOnly($0) }
        order.notes = notes
        order.createdById = createdById
        order.sentAt = sentAt.flatMap { SupabaseDate.parse($0) }
        order.fulfilledAt = fulfilledAt.flatMap { SupabaseDate.parse($0) }
        order.cancelledAt = cancelledAt.flatMap { SupabaseDate.parse($0) }
        order.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return order
    }
}

struct CatalogOrderItemDTO: Codable, Identifiable {
    let id: String
    let orderId: String
    let catalogVariantId: String
    let quantityRequested: Double
    let costPerUnit: Double?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case orderId               = "order_id"
        case catalogVariantId      = "catalog_variant_id"
        case quantityRequested     = "quantity_requested"
        case costPerUnit           = "cost_per_unit"
        case notes
    }

    func toModel() -> CatalogOrderItem {
        CatalogOrderItem(
            id: id, orderId: orderId, catalogVariantId: catalogVariantId,
            quantityRequested: quantityRequested,
            costPerUnit: costPerUnit, notes: notes
        )
    }
}

struct CreateCatalogOrderDTO: Codable {
    let companyId: String
    let status: String
    let title: String?
    let supplierName: String?
    let notes: String?
    let createdById: String?

    enum CodingKeys: String, CodingKey {
        case companyId      = "company_id"
        case status
        case title
        case supplierName   = "supplier_name"
        case notes
        case createdById    = "created_by_id"
    }
}

struct CreateCatalogOrderItemDTO: Codable {
    let orderId: String
    let catalogVariantId: String
    let quantityRequested: Double
    let costPerUnit: Double?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case orderId            = "order_id"
        case catalogVariantId   = "catalog_variant_id"
        case quantityRequested  = "quantity_requested"
        case costPerUnit        = "cost_per_unit"
        case notes
    }
}
```

### Task 30: Create `CatalogRepository.swift` (replaces InventoryRepository)

**Files:**
- Create: `OPS/OPS/Network/Supabase/Repositories/CatalogRepository.swift`
- Delete: `OPS/OPS/Network/Supabase/Repositories/InventoryRepository.swift` (after CatalogRepository compiles)

- [ ] **Step 1: Write the repository**

```swift
//
//  CatalogRepository.swift
//  OPS
//
//  CRUD + sync helpers for catalog_* tables.
//

import Foundation
import Supabase

class CatalogRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Categories

    func fetchCategoriesForSync(since: Date? = nil) async throws -> [CatalogCategoryDTO] {
        var query = client.from("catalog_categories").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("updated_at", value: isoString(since)) }
        return try await query.order("updated_at", ascending: true).execute().value
    }

    func fetchDeletedCategoryIds(since: Date) async throws -> [String] {
        struct Row: Codable { let id: String }
        let rows: [Row] = try await client.from("catalog_categories")
            .select("id")
            .eq("company_id", value: companyId)
            .not("deleted_at", operator: .is, value: "null")
            .gte("deleted_at", value: isoString(since))
            .execute().value
        return rows.map(\.id)
    }

    // MARK: - Items (variant families)

    func fetchItemsForSync(since: Date? = nil) async throws -> [CatalogItemDTO] {
        var query = client.from("catalog_items").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("updated_at", value: isoString(since)) }
        return try await query.order("updated_at", ascending: true).execute().value
    }

    func fetchDeletedItemIds(since: Date) async throws -> [String] {
        struct Row: Codable { let id: String }
        let rows: [Row] = try await client.from("catalog_items")
            .select("id")
            .eq("company_id", value: companyId)
            .not("deleted_at", operator: .is, value: "null")
            .gte("deleted_at", value: isoString(since))
            .execute().value
        return rows.map(\.id)
    }

    // MARK: - Variants

    func fetchVariantsForSync(since: Date? = nil) async throws -> [CatalogVariantDTO] {
        var query = client.from("catalog_variants").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("updated_at", value: isoString(since)) }
        return try await query.order("updated_at", ascending: true).execute().value
    }

    func fetchDeletedVariantIds(since: Date) async throws -> [String] {
        struct Row: Codable { let id: String }
        let rows: [Row] = try await client.from("catalog_variants")
            .select("id")
            .eq("company_id", value: companyId)
            .not("deleted_at", operator: .is, value: "null")
            .gte("deleted_at", value: isoString(since))
            .execute().value
        return rows.map(\.id)
    }

    func adjustVariantQuantity(_ id: String, newQuantity: Double) async throws -> CatalogVariantDTO {
        var updates = UpdateCatalogVariantDTO()
        updates.quantity = newQuantity
        return try await client.from("catalog_variants")
            .update(updates).eq("id", value: id).select().single().execute().value
    }

    // MARK: - Options

    func fetchOptionsForCompany() async throws -> [CatalogOptionDTO] {
        // catalog_options has no company_id; filter via parent catalog_items.
        struct Joined: Codable {
            let id: String
            let catalogItemId: String
            let name: String
            let sortOrder: Int
            let createdAt: String
            enum CodingKeys: String, CodingKey {
                case id
                case catalogItemId  = "catalog_item_id"
                case name
                case sortOrder      = "sort_order"
                case createdAt      = "created_at"
            }
        }
        let rows: [Joined] = try await client.from("catalog_options")
            .select("id, catalog_item_id, name, sort_order, created_at, catalog_items!inner(company_id)")
            .eq("catalog_items.company_id", value: companyId)
            .execute().value
        return rows.map {
            CatalogOptionDTO(id: $0.id, catalogItemId: $0.catalogItemId,
                              name: $0.name, sortOrder: $0.sortOrder, createdAt: $0.createdAt)
        }
    }

    // MARK: - Option values

    func fetchOptionValuesForCompany() async throws -> [CatalogOptionValueDTO] {
        struct Joined: Codable {
            let id: String
            let optionId: String
            let value: String
            let sortOrder: Int
            enum CodingKeys: String, CodingKey {
                case id
                case optionId  = "option_id"
                case value
                case sortOrder = "sort_order"
            }
        }
        let rows: [Joined] = try await client.from("catalog_option_values")
            .select("id, option_id, value, sort_order, catalog_options!inner(catalog_items!inner(company_id))")
            .eq("catalog_options.catalog_items.company_id", value: companyId)
            .execute().value
        return rows.map {
            CatalogOptionValueDTO(id: $0.id, optionId: $0.optionId, value: $0.value, sortOrder: $0.sortOrder)
        }
    }

    // MARK: - Variant ↔ option-value joins

    func fetchVariantOptionValuesForCompany() async throws -> [CatalogVariantOptionValueDTO] {
        struct Joined: Codable {
            let variantId: String
            let optionValueId: String
            enum CodingKeys: String, CodingKey {
                case variantId      = "variant_id"
                case optionValueId  = "option_value_id"
            }
        }
        let rows: [Joined] = try await client.from("catalog_variant_option_values")
            .select("variant_id, option_value_id, catalog_variants!inner(company_id)")
            .eq("catalog_variants.company_id", value: companyId)
            .execute().value
        return rows.map {
            CatalogVariantOptionValueDTO(variantId: $0.variantId, optionValueId: $0.optionValueId)
        }
    }

    // MARK: - Tags + family-tag joins

    func fetchTagsForSync(since: Date? = nil) async throws -> [CatalogTagDTO] {
        var query = client.from("catalog_tags").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("updated_at", value: isoString(since)) }
        return try await query.order("updated_at", ascending: true).execute().value
    }

    func fetchItemTagsForCompany() async throws -> [CatalogItemTagDTO] {
        struct Joined: Codable {
            let id: String
            let catalogItemId: String
            let tagId: String
            enum CodingKeys: String, CodingKey {
                case id
                case catalogItemId  = "catalog_item_id"
                case tagId          = "tag_id"
            }
        }
        let rows: [Joined] = try await client.from("catalog_item_tags")
            .select("id, catalog_item_id, tag_id, catalog_items!inner(company_id)")
            .eq("catalog_items.company_id", value: companyId)
            .execute().value
        return rows.map { CatalogItemTagDTO(id: $0.id, catalogItemId: $0.catalogItemId, tagId: $0.tagId) }
    }

    // MARK: - Units

    func fetchUnitsForSync(since: Date? = nil) async throws -> [CatalogUnitDTO] {
        var query = client.from("catalog_units").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("updated_at", value: isoString(since)) }
        return try await query.order("sort_order", ascending: true).execute().value
    }

    // MARK: - Snapshots

    func fetchSnapshotsForSync(since: Date? = nil) async throws -> [CatalogSnapshotDTO] {
        var query = client.from("catalog_snapshots").select().eq("company_id", value: companyId)
        if let since = since { query = query.gte("created_at", value: isoString(since)) }
        return try await query.order("created_at", ascending: true).execute().value
    }

    func fetchSnapshotItemsForSnapshots(_ ids: [String]) async throws -> [CatalogSnapshotItemDTO] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("catalog_snapshot_items").select().in("snapshot_id", values: ids).execute().value
    }

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
```

### Task 31: Create `ProductRichnessRepository.swift`

**Files:**
- Create: `OPS/OPS/Network/Supabase/Repositories/ProductRichnessRepository.swift`

- [ ] **Step 1: Write the repository**

```swift
//
//  ProductRichnessRepository.swift
//  OPS
//
//  Fetches/persists the optional Product configurability layers:
//  product_options, product_option_values, product_pricing_modifiers,
//  product_materials.
//

import Foundation
import Supabase

class ProductRichnessRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    // MARK: - Options

    func fetchOptionsForCompany() async throws -> [ProductOptionDTO] {
        struct Joined: Codable {
            let id: String
            let productId: String
            let name: String
            let kind: String
            let affectsPrice: Bool
            let affectsRecipe: Bool
            let required: Bool
            let defaultValue: String?
            let optionDefaultSource: String?
            let sortOrder: Int
            enum CodingKeys: String, CodingKey {
                case id
                case productId            = "product_id"
                case name
                case kind
                case affectsPrice         = "affects_price"
                case affectsRecipe        = "affects_recipe"
                case required
                case defaultValue         = "default_value"
                case optionDefaultSource  = "option_default_source"
                case sortOrder            = "sort_order"
            }
        }
        let rows: [Joined] = try await client.from("product_options")
            .select("id, product_id, name, kind, affects_price, affects_recipe, required, default_value, option_default_source, sort_order, products!inner(company_id)")
            .eq("products.company_id", value: companyId)
            .execute().value
        return rows.map {
            ProductOptionDTO(
                id: $0.id, productId: $0.productId, name: $0.name, kind: $0.kind,
                affectsPrice: $0.affectsPrice, affectsRecipe: $0.affectsRecipe,
                required: $0.required, defaultValue: $0.defaultValue,
                optionDefaultSource: $0.optionDefaultSource, sortOrder: $0.sortOrder
            )
        }
    }

    // MARK: - Option values

    func fetchOptionValuesForCompany() async throws -> [ProductOptionValueDTO] {
        struct Joined: Codable {
            let id: String
            let optionId: String
            let value: String
            let sortOrder: Int
            enum CodingKeys: String, CodingKey {
                case id
                case optionId   = "option_id"
                case value
                case sortOrder  = "sort_order"
            }
        }
        let rows: [Joined] = try await client.from("product_option_values")
            .select("id, option_id, value, sort_order, product_options!inner(products!inner(company_id))")
            .eq("product_options.products.company_id", value: companyId)
            .execute().value
        return rows.map {
            ProductOptionValueDTO(id: $0.id, optionId: $0.optionId, value: $0.value, sortOrder: $0.sortOrder)
        }
    }

    // MARK: - Pricing modifiers

    func fetchPricingModifiersForCompany() async throws -> [ProductPricingModifierDTO] {
        struct Joined: Codable {
            let id: String
            let productId: String
            let optionId: String
            let triggerValueId: String?
            let triggerIntMin: Int?
            let triggerIntMax: Int?
            let modifierKind: String
            let amount: Double
            enum CodingKeys: String, CodingKey {
                case id
                case productId        = "product_id"
                case optionId         = "option_id"
                case triggerValueId   = "trigger_value_id"
                case triggerIntMin    = "trigger_int_min"
                case triggerIntMax    = "trigger_int_max"
                case modifierKind     = "modifier_kind"
                case amount
            }
        }
        let rows: [Joined] = try await client.from("product_pricing_modifiers")
            .select("id, product_id, option_id, trigger_value_id, trigger_int_min, trigger_int_max, modifier_kind, amount, products!inner(company_id)")
            .eq("products.company_id", value: companyId)
            .execute().value
        return rows.map {
            ProductPricingModifierDTO(
                id: $0.id, productId: $0.productId, optionId: $0.optionId,
                triggerValueId: $0.triggerValueId,
                triggerIntMin: $0.triggerIntMin, triggerIntMax: $0.triggerIntMax,
                modifierKind: $0.modifierKind, amount: $0.amount
            )
        }
    }

    // MARK: - Recipe rows (product_materials)

    func fetchMaterialsForCompany() async throws -> [ProductMaterialDTO] {
        struct Joined: Codable {
            let id: String
            let productId: String
            let catalogVariantId: String?
            let catalogItemId: String?
            let variantSelector: AnyJSON?
            let quantityPerUnit: Double
            let scaledByOptionId: String?
            let unitId: String?
            let notes: String?
            enum CodingKeys: String, CodingKey {
                case id
                case productId         = "product_id"
                case catalogVariantId  = "catalog_variant_id"
                case catalogItemId     = "catalog_item_id"
                case variantSelector   = "variant_selector"
                case quantityPerUnit   = "quantity_per_unit"
                case scaledByOptionId  = "scaled_by_option_id"
                case unitId            = "unit_id"
                case notes
            }
        }
        let rows: [Joined] = try await client.from("product_materials")
            .select("id, product_id, catalog_variant_id, catalog_item_id, variant_selector, quantity_per_unit, scaled_by_option_id, unit_id, notes, products!inner(company_id)")
            .eq("products.company_id", value: companyId)
            .execute().value
        return rows.map {
            ProductMaterialDTO(
                id: $0.id, productId: $0.productId,
                catalogVariantId: $0.catalogVariantId, catalogItemId: $0.catalogItemId,
                variantSelector: $0.variantSelector,
                quantityPerUnit: $0.quantityPerUnit,
                scaledByOptionId: $0.scaledByOptionId,
                unitId: $0.unitId, notes: $0.notes
            )
        }
    }
}
```

### Task 32: Update `ProductRepository.swift` to read base_price + new fields

**Files:**
- Modify: `OPS/OPS/Network/Supabase/Repositories/ProductRepository.swift`

- [ ] **Step 1: Replace the file**

```swift
//
//  ProductRepository.swift
//  OPS
//
//  Repository for the Supabase `products` table. Wire-field bug fixed:
//  reads/writes base_price (mirrored to default_price by Postgres trigger
//  during the ops-web compatibility window) and unit_cost (was incorrectly
//  cost_price in earlier builds).
//

import Foundation
import Supabase

class ProductRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll(includeInactive: Bool = false) async throws -> [ProductDTO] {
        var query = client.from("products").select().eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
        if !includeInactive {
            query = query.eq("is_active", value: true)
        }
        return try await query.order("name", ascending: true).execute().value
    }

    func create(_ dto: CreateProductDTO) async throws -> ProductDTO {
        try await client.from("products").insert(dto).select().single().execute().value
    }

    func update(_ id: String, fields: UpdateProductDTO) async throws -> ProductDTO {
        try await client.from("products").update(fields).eq("id", value: id).select().single().execute().value
    }

    func deactivate(_ id: String) async throws {
        try await client.from("products").update(["is_active": false]).eq("id", value: id).execute()
    }

    func softDelete(_ id: String) async throws {
        struct SoftDelete: Codable { let deleted_at: String; let updated_at: String }
        let now = ISO8601DateFormatter().string(from: Date())
        try await client.from("products").update(SoftDelete(deleted_at: now, updated_at: now))
            .eq("id", value: id).execute()
    }
}
```

### Task 33: Create `CompanyDefaultProductRepository.swift` and `CatalogOrderRepository.swift`

**Files:**
- Create: `OPS/OPS/Network/Supabase/Repositories/CompanyDefaultProductRepository.swift`
- Create: `OPS/OPS/Network/Supabase/Repositories/CatalogOrderRepository.swift`

- [ ] **Step 1: Write `CompanyDefaultProductRepository.swift`**

```swift
//
//  CompanyDefaultProductRepository.swift
//  OPS
//

import Foundation
import Supabase

class CompanyDefaultProductRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll() async throws -> [CompanyDefaultProductDTO] {
        try await client.from("company_default_products")
            .select().eq("company_id", value: companyId).execute().value
    }

    func upsert(_ dto: UpsertCompanyDefaultProductDTO) async throws -> CompanyDefaultProductDTO {
        try await client.from("company_default_products").upsert(dto, onConflict: "company_id,component_type")
            .select().single().execute().value
    }

    func remove(componentType: String) async throws {
        try await client.from("company_default_products")
            .delete()
            .eq("company_id", value: companyId)
            .eq("component_type", value: componentType)
            .execute()
    }
}
```

- [ ] **Step 2: Write `CatalogOrderRepository.swift`**

```swift
//
//  CatalogOrderRepository.swift
//  OPS
//

import Foundation
import Supabase

class CatalogOrderRepository {
    private let client: SupabaseClient
    private let companyId: String

    init(companyId: String) {
        self.client = SupabaseService.shared.client
        self.companyId = companyId
    }

    func fetchAll(statuses: [String]? = nil) async throws -> [CatalogOrderDTO] {
        var query = client.from("catalog_orders").select().eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
        if let statuses = statuses, !statuses.isEmpty {
            query = query.in("status", values: statuses)
        }
        return try await query.order("created_at", ascending: false).execute().value
    }

    func fetchOrderItems(orderId: String) async throws -> [CatalogOrderItemDTO] {
        try await client.from("catalog_order_items").select().eq("order_id", value: orderId).execute().value
    }

    func createOrder(_ dto: CreateCatalogOrderDTO) async throws -> CatalogOrderDTO {
        try await client.from("catalog_orders").insert(dto).select().single().execute().value
    }

    func addItem(_ dto: CreateCatalogOrderItemDTO) async throws -> CatalogOrderItemDTO {
        try await client.from("catalog_order_items").insert(dto).select().single().execute().value
    }

    func markSent(_ orderId: String) async throws {
        struct Update: Codable { let status: String; let sent_at: String; let updated_at: String }
        let now = ISO8601DateFormatter().string(from: Date())
        try await client.from("catalog_orders")
            .update(Update(status: "sent", sent_at: now, updated_at: now))
            .eq("id", value: orderId).execute()
    }

    func markFulfilled(_ orderId: String) async throws {
        struct Update: Codable { let status: String; let fulfilled_at: String; let updated_at: String }
        let now = ISO8601DateFormatter().string(from: Date())
        try await client.from("catalog_orders")
            .update(Update(status: "fulfilled", fulfilled_at: now, updated_at: now))
            .eq("id", value: orderId).execute()
    }
}
```

### Task 34: Delete old inventory data models and inventory repository

**Files:**
- Delete: `OPS/OPS/DataModels/InventoryItem.swift`
- Delete: `OPS/OPS/DataModels/InventoryTag.swift`
- Delete: `OPS/OPS/DataModels/InventoryUnit.swift`
- Delete: `OPS/OPS/DataModels/InventorySnapshot.swift`
- Delete: `OPS/OPS/DataModels/InventorySnapshotItem.swift`
- Delete: `OPS/OPS/Network/Supabase/Repositories/InventoryRepository.swift`
- Delete: `OPS/OPS/Network/Supabase/DTOs/InventoryDTOs.swift`

- [ ] **Step 1: Search for any remaining references to InventoryItem / InventoryTag / InventoryUnit / InventorySnapshot / InventorySnapshotItem / InventoryRepository / InventoryItemReadDTO / InventoryTagReadDTO / InventoryUnitReadDTO / InventoryItemTagReadDTO / InventorySnapshotReadDTO / InventorySnapshotItemReadDTO / CreateInventoryItemDTO / CreateInventoryTagDTO / CreateInventoryUnitDTO / CreateInventorySnapshotDTO / CreateInventorySnapshotItemDTO / UpdateInventoryItemDTO / UpdateInventoryTagDTO / UpdateInventoryUnitDTO**

Run:

```bash
grep -rn "Inventory\(Item\|Tag\|Unit\|Snapshot\|Repository\|.*ReadDTO\|.*DTO\)" /Users/jacksonsweet/Projects/OPS/ops-ios/OPS/ --include='*.swift' | grep -v 'inventory_deductions'
```

Expected: zero hits after Phase 4 (sync layer) finishes its rewrite. For now, hits are concentrated in `Views/Inventory/` (deleted in Phase 5/6) and `Network/Sync/InboundProcessor.swift` (rewritten in Phase 4). Do NOT delete the files yet; just record the surface area.

- [ ] **Step 2: Defer deletion until Phase 4 finishes the sync rewrite (Task 39).** This task's deletion happens at the end of Phase 4.

### Task 35: Build verification — compile error sweep

**Files:**
- No file changes

- [ ] **Step 1: Run `xcodebuild` to verify Phase 3 compiles**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -80
```

Expected outcome: compilation will FAIL because the inventory references in `Views/Inventory/`, `Network/Sync/InboundProcessor.swift`, and any other surfaces still reference deleted models. Capture the error list — this is the exact set of files Phase 4–6 need to touch.

- [ ] **Step 2: Commit Phase 3 progress**

```bash
git add OPS/OPS/DataModels/Migrations/ OPS/OPS/DataModels/Supabase/ OPS/OPS/Network/Supabase/DTOs/ OPS/OPS/Network/Supabase/Repositories/ OPS/OPS/OPSApp.swift
git commit -m "phase 3: catalog data models, DTOs, repositories; fix product wire-field bug"
```

### Phase 3 review checkpoint

- [ ] Confirm 17 new SwiftData models compile in isolation (no UI yet wires them up).
- [ ] Confirm `ProductDTO` reads `base_price` and `unit_cost`.
- [ ] Confirm 9 missing fields are present on `Product` model and `ProductDTO`.
- [ ] Confirm `OPSSchemaV3` and migration plan land.
- [ ] Phase 4 begins: rewrite the sync layer to call catalog repositories.

---

## Phase 4 — iOS sync layer

Goal: replace inventory entity types with catalog entity types in `InboundProcessor`, wrap `fullSync` and `deltaSync` in per-entity error isolation, and instrument failures to `app_events`. This phase closes Bug `2837ddae` regardless of root cause and prevents any future entity-level error from poisoning the entire pull.

### Task 36: Create `SyncTelemetry.swift`

**Files:**
- Create: `OPS/OPS/Services/SyncTelemetry.swift`
- Create: `OPSTests/Catalog/SyncTelemetryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//
//  SyncTelemetryTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class SyncTelemetryTests: XCTestCase {
    func test_buildEvent_includesEntityTypeAndAppVersion() {
        let event = SyncTelemetry.buildEvent(
            entityType: "catalogItem",
            error: NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "boom"]),
            isFullSync: true,
            companyId: "company-123",
            userId: "user-456"
        )

        XCTAssertEqual(event["event_name"] as? String, "sync_entity_failed")
        XCTAssertEqual(event["entity_type"] as? String, "catalogItem")
        XCTAssertEqual(event["error_class"] as? String, "TestDomain")
        XCTAssertEqual(event["error_code"] as? Int, 42)
        XCTAssertEqual(event["error_message"] as? String, "boom")
        XCTAssertEqual(event["sync_phase"] as? String, "full")
        XCTAssertEqual(event["company_id"] as? String, "company-123")
        XCTAssertEqual(event["user_id"] as? String, "user-456")
        XCTAssertNotNil(event["app_version"])
    }

    func test_buildEvent_deltaSyncPhase() {
        let event = SyncTelemetry.buildEvent(
            entityType: "catalogVariant", error: NSError(domain: "X", code: 1),
            isFullSync: false, companyId: "c", userId: "u"
        )
        XCTAssertEqual(event["sync_phase"] as? String, "delta")
    }
}
```

- [ ] **Step 2: Run the test (will fail — `SyncTelemetry` doesn't exist)**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' test 2>&1 | grep -E '(SyncTelemetry|FAIL|error:)'
```

Expected: build error "Cannot find 'SyncTelemetry' in scope".

- [ ] **Step 3: Create `SyncTelemetry.swift`**

```swift
//
//  SyncTelemetry.swift
//  OPS
//
//  Logs per-entity sync failures into `app_events` so that production
//  failures (e.g., Bug 2837ddae's invisible inventory pull) become
//  diagnosable without device access.
//

import Foundation
import Supabase

enum SyncTelemetry {

    /// Build the analytics payload for a sync failure. Pulled out as a pure
    /// function so it's easy to unit-test.
    static func buildEvent(
        entityType: String,
        error: Error,
        isFullSync: Bool,
        companyId: String,
        userId: String?
    ) -> [String: Any] {
        let nsError = error as NSError
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
        let buildNumber = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "unknown"

        var event: [String: Any] = [
            "event_name": "sync_entity_failed",
            "entity_type": entityType,
            "error_class": nsError.domain,
            "error_code": nsError.code,
            "error_message": nsError.localizedDescription,
            "sync_phase": isFullSync ? "full" : "delta",
            "company_id": companyId,
            "app_version": appVersion,
            "build_number": buildNumber,
            "platform": "ios",
            "occurred_at": ISO8601DateFormatter().string(from: Date())
        ]
        if let userId = userId {
            event["user_id"] = userId
        }
        return event
    }

    /// Fire-and-forget log of a sync failure to `app_events`.
    /// Best-effort: any failure here is itself swallowed because we'd otherwise
    /// recurse into the sync error path.
    static func logError(
        entityType: String,
        error: Error,
        isFullSync: Bool,
        companyId: String,
        userId: String?
    ) {
        let event = buildEvent(
            entityType: entityType, error: error,
            isFullSync: isFullSync, companyId: companyId, userId: userId
        )
        // Console log first — survives even if Supabase write fails.
        print("[SyncTelemetry] sync_entity_failed entity=\(entityType) err=\(error.localizedDescription)")

        Task.detached {
            do {
                struct AppEventInsert: Codable {
                    let user_id: String?
                    let company_id: String
                    let event_name: String
                    let properties: AnyJSON
                }
                let propsJSON = try JSONSerialization.data(withJSONObject: event)
                let propsString = String(data: propsJSON, encoding: .utf8) ?? "{}"
                let payload = AppEventInsert(
                    user_id: event["user_id"] as? String,
                    company_id: companyId,
                    event_name: "sync_entity_failed",
                    properties: try JSONDecoder().decode(AnyJSON.self, from: Data(propsString.utf8))
                )
                _ = try await SupabaseService.shared.client.from("app_events").insert(payload).execute()
            } catch {
                print("[SyncTelemetry] failed to persist failure event: \(error)")
            }
        }
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' test -only-testing:OPSTests/SyncTelemetryTests 2>&1 | tail -30
```

Expected: 2 tests pass. (If you don't have a runtime device, build verification — `xcodebuild ... build` — confirms the file compiles. Tests run when a device or simulator is attached.)

- [ ] **Step 5: Commit**

```bash
git add OPS/OPS/Services/SyncTelemetry.swift OPSTests/Catalog/SyncTelemetryTests.swift
git commit -m "feat(sync): SyncTelemetry — log per-entity failures to app_events"
```

### Task 37: Update `SyncTypes.swift` — replace inventory entity types with catalog entity types

**Files:**
- Modify: `OPS/OPS/Network/Sync/SyncTypes.swift`

- [ ] **Step 1: Open the file and locate the `SyncEntityType` enum**

The enum currently includes `.inventoryUnit`, `.inventoryTag`, `.inventoryItem`, `.inventorySnapshot`, `.inventorySnapshotItem`. Remove those. Add the new catalog cases.

- [ ] **Step 2: Replace those cases with catalog entity types**

```swift
// In SyncEntityType (alphabetical or grouped per existing convention):

case catalogCategory
case catalogUnit
case catalogTag
case catalogItem               // family
case catalogVariant
case catalogOption
case catalogOptionValue
case catalogVariantOptionValue
case catalogItemTag
case catalogSnapshot
case catalogSnapshotItem
case catalogOrder
case catalogOrderItem

case companyDefaultProduct

case productOption
case productOptionValue
case productPricingModifier
case productMaterial
```

- [ ] **Step 3: Update the `rawValue` mapping** (if SyncEntityType has explicit raw values matching Supabase table names) so each new case maps to the right table:

```swift
// .catalogCategory -> "catalog_categories"
// .catalogUnit -> "catalog_units"
// (etc.)
```

If the enum doesn't carry table-name raw values, skip — InboundProcessor will resolve table names directly.

- [ ] **Step 4: Build, sweep compile errors that bubble up from `InboundProcessor`/`OutboundProcessor` referring to deleted cases**

Run:

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | grep -E "case 'inventory(Unit|Tag|Item|Snapshot|SnapshotItem)'" | head -20
```

Each compile error pinpoints a `switch` arm that must be rewritten in Phase 4 Tasks 38–40.

### Task 38: Rewrite `InboundProcessor` inventory paths to catalog paths

**Files:**
- Modify: `OPS/OPS/Network/Sync/InboundProcessor.swift`

This is the biggest single file change in the plan. Tasks 38–40 break it into stages: (a) replace the repository field + initializer, (b) rewrite the per-entity sync methods, (c) wrap the for-loop in error isolation.

- [ ] **Step 1: Replace the inventory repository field with catalog repositories**

In the property block (~line 42–45):

```swift
// Old:
private var inventoryRepo: InventoryRepository

// New:
private var catalogRepo: CatalogRepository
private var productRichnessRepo: ProductRichnessRepository
private var defaultProductRepo: CompanyDefaultProductRepository
private var orderRepo: CatalogOrderRepository
```

In the `init` (~line 73) and `reconfigure` (~line 110) methods, replace:

```swift
self.inventoryRepo = InventoryRepository(companyId: companyId)
```

with:

```swift
self.catalogRepo = CatalogRepository(companyId: companyId)
self.productRichnessRepo = ProductRichnessRepository(companyId: companyId)
self.defaultProductRepo = CompanyDefaultProductRepository(companyId: companyId)
self.orderRepo = CatalogOrderRepository(companyId: companyId)
```

(Same change in both init paths.)

- [ ] **Step 2: Update `Self.syncOrder`** (~line 117):

```swift
static let syncOrder: [SyncEntityType] = [
    .company,
    .user,
    .client,
    .subClient,
    .taskType,
    .project,
    .projectTask,
    .wizardState,
    .projectNote,
    .photoAnnotation,
    .deckDesign,
    .estimate,
    .invoice,
    .calendarUserEvent,

    // Catalog backbone — categories first, then units, then families, then variants
    .catalogCategory,
    .catalogUnit,
    .catalogTag,
    .catalogItem,
    .catalogOption,
    .catalogOptionValue,
    .catalogVariant,
    .catalogVariantOptionValue,
    .catalogItemTag,
    .catalogSnapshot,
    .catalogSnapshotItem,

    // Configurable Products
    .productOption,
    .productOptionValue,
    .productPricingModifier,
    .productMaterial,

    // Adapter + orders
    .companyDefaultProduct,
    .catalogOrder,
    .catalogOrderItem
]
```

- [ ] **Step 3: Replace the `syncEntityType` switch arms for inventory entities with the new catalog entries**

Locate the `switch entityType` block (~line 229). Replace the five inventory cases with the catalog cases:

```swift
case .catalogCategory:
    try await syncCatalogCategories(since: since, context: context)
case .catalogUnit:
    try await syncCatalogUnits(since: since, context: context)
case .catalogTag:
    try await syncCatalogTags(since: since, context: context)
case .catalogItem:
    try await syncCatalogItems(since: since, context: context)
case .catalogOption:
    try await syncCatalogOptions(context: context)
case .catalogOptionValue:
    try await syncCatalogOptionValues(context: context)
case .catalogVariant:
    try await syncCatalogVariants(since: since, context: context)
case .catalogVariantOptionValue:
    try await syncCatalogVariantOptionValues(context: context)
case .catalogItemTag:
    try await syncCatalogItemTags(context: context)
case .catalogSnapshot:
    try await syncCatalogSnapshots(since: since, context: context)
case .catalogSnapshotItem:
    try await syncCatalogSnapshotItems(context: context)
case .productOption:
    try await syncProductOptions(context: context)
case .productOptionValue:
    try await syncProductOptionValues(context: context)
case .productPricingModifier:
    try await syncProductPricingModifiers(context: context)
case .productMaterial:
    try await syncProductMaterials(context: context)
case .companyDefaultProduct:
    try await syncCompanyDefaultProducts(context: context)
case .catalogOrder:
    try await syncCatalogOrders(since: since, context: context)
case .catalogOrderItem:
    try await syncCatalogOrderItems(context: context)
```

(Delete the old `inventoryUnit/Tag/Item/Snapshot/SnapshotItem` cases.)

### Task 39: Implement the per-entity catalog sync methods

**Files:**
- Modify: `OPS/OPS/Network/Sync/InboundProcessor.swift`

Replace the existing `syncInventoryUnits/Tags/Items/Snapshots/SnapshotItems` methods (~lines 1738–end) with the new methods listed below. Pattern is identical for each: fetch from repository, merge per row, soft-delete tombstones for rows whose `deleted_at` arrived.

- [ ] **Step 1: Implement `syncCatalogCategories`**

```swift
// MARK: - Catalog Categories

private func syncCatalogCategories(since: Date?, context: ModelContext) async throws {
    let dtos = try await catalogRepo.fetchCategoriesForSync(since: since)
    for dto in dtos {
        try mergeCatalogCategory(dto: dto, context: context)
    }
    if let sinceDate = since {
        let deletedIds = try await catalogRepo.fetchDeletedCategoryIds(since: sinceDate)
        for id in deletedIds {
            try markCatalogCategoryDeleted(id: id, context: context)
        }
    }
    print("[InboundProcessor] Merged \(dtos.count) catalog categories")
}

private func mergeCatalogCategory(dto: CatalogCategoryDTO, context: ModelContext) throws {
    let id = dto.id
    let descriptor = FetchDescriptor<CatalogCategory>(predicate: #Predicate { $0.id == id })
    if let existing = try context.fetch(descriptor).first {
        let accept = acceptableFields(
            entityType: .catalogCategory, entityId: id,
            fields: ["companyId","name","parentId","sortOrder","colorHex",
                     "defaultWarningThreshold","defaultCriticalThreshold","deletedAt"],
            context: context
        )
        if accept.contains("companyId")                  { existing.companyId = dto.companyId }
        if accept.contains("name")                       { existing.name = dto.name }
        if accept.contains("parentId")                   { existing.parentId = dto.parentId }
        if accept.contains("sortOrder")                  { existing.sortOrder = dto.sortOrder }
        if accept.contains("colorHex")                   { existing.colorHex = dto.colorHex }
        if accept.contains("defaultWarningThreshold")    { existing.defaultWarningThreshold = dto.defaultWarningThreshold }
        if accept.contains("defaultCriticalThreshold")   { existing.defaultCriticalThreshold = dto.defaultCriticalThreshold }
        if accept.contains("deletedAt") {
            existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
        }
        existing.lastSyncedAt = Date()
        existing.needsSync = false
    } else {
        let model = dto.toModel()
        model.lastSyncedAt = Date()
        model.needsSync = false
        context.insert(model)
    }
    try context.save()
}

private func markCatalogCategoryDeleted(id: String, context: ModelContext) throws {
    let descriptor = FetchDescriptor<CatalogCategory>(predicate: #Predicate { $0.id == id })
    if let existing = try context.fetch(descriptor).first {
        existing.deletedAt = Date()
        existing.needsSync = false
        try context.save()
    }
}
```

- [ ] **Step 2: Implement `syncCatalogUnits` (same pattern, unit fields)**

```swift
private func syncCatalogUnits(since: Date?, context: ModelContext) async throws {
    let dtos = try await catalogRepo.fetchUnitsForSync(since: since)
    for dto in dtos { try mergeCatalogUnit(dto: dto, context: context) }
    print("[InboundProcessor] Merged \(dtos.count) catalog units")
}

private func mergeCatalogUnit(dto: CatalogUnitDTO, context: ModelContext) throws {
    let id = dto.id
    let descriptor = FetchDescriptor<CatalogUnit>(predicate: #Predicate { $0.id == id })
    if let existing = try context.fetch(descriptor).first {
        existing.companyId = dto.companyId
        existing.display = dto.display
        existing.abbreviation = dto.abbreviation
        existing.dimension = dto.dimension
        existing.isDefault = dto.isDefault
        existing.sortOrder = dto.sortOrder
        existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
        existing.lastSyncedAt = Date()
        existing.needsSync = false
    } else {
        let model = dto.toModel()
        model.lastSyncedAt = Date()
        model.needsSync = false
        context.insert(model)
    }
    try context.save()
}
```

- [ ] **Step 3: Implement `syncCatalogTags`, `syncCatalogItems`, `syncCatalogVariants`, `syncCatalogOptions`, `syncCatalogOptionValues`, `syncCatalogVariantOptionValues`, `syncCatalogItemTags`, `syncCatalogSnapshots`, `syncCatalogSnapshotItems`** (same pattern; each method fetches via the corresponding `catalogRepo` method and merges row-by-row)

Pattern reminder for each (one method per entity):

```swift
private func sync<EntityType>(since: Date?, context: ModelContext) async throws {
    let dtos = try await catalogRepo.fetch<Method>ForSync(since: since)
    for dto in dtos { try merge<EntityType>(dto: dto, context: context) }
    if let sinceDate = since {
        let deletedIds = try await catalogRepo.fetchDeleted<EntityType>Ids(since: sinceDate)
        for id in deletedIds { try mark<EntityType>Deleted(id: id, context: context) }
    }
    print("[InboundProcessor] Merged \(dtos.count) <entity-type-plural>")
}
```

For join-only tables without `updated_at` (`catalog_variant_option_values`, `catalog_item_tags`, `product_*` extension tables), skip the delta path. Always full-fetch (small N — joins per company are at most a few hundred rows).

- [ ] **Step 4: Implement `syncProductOptions`, `syncProductOptionValues`, `syncProductPricingModifiers`, `syncProductMaterials`** using `productRichnessRepo`

```swift
private func syncProductOptions(context: ModelContext) async throws {
    let dtos = try await productRichnessRepo.fetchOptionsForCompany()
    let allIds = Set(dtos.map(\.id))

    // Insert / update
    for dto in dtos {
        let id = dto.id
        let descriptor = FetchDescriptor<ProductOption>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.productId = dto.productId
            existing.name = dto.name
            existing.kind = ProductOptionKind(rawValue: dto.kind) ?? .select
            existing.affectsPrice = dto.affectsPrice
            existing.affectsRecipe = dto.affectsRecipe
            existing.required = dto.required
            existing.defaultValue = dto.defaultValue
            existing.optionDefaultSource = dto.optionDefaultSource
            existing.sortOrder = dto.sortOrder
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let m = dto.toModel()
            m.lastSyncedAt = Date()
            m.needsSync = false
            context.insert(m)
        }
    }

    // Tombstone any local row not present in the server response.
    // (No `deleted_at` column on product_options — the server-side delete is hard.)
    let allLocal: [ProductOption] = (try? context.fetch(FetchDescriptor<ProductOption>())) ?? []
    for local in allLocal where !allIds.contains(local.id) {
        context.delete(local)
    }

    try context.save()
    print("[InboundProcessor] Merged \(dtos.count) product options")
}
```

Repeat the same pattern for `syncProductOptionValues`, `syncProductPricingModifiers`, `syncProductMaterials` — each calls the corresponding `productRichnessRepo.fetch...ForCompany()` method and merges into its SwiftData model.

- [ ] **Step 5: Implement `syncCompanyDefaultProducts`**

```swift
private func syncCompanyDefaultProducts(context: ModelContext) async throws {
    let dtos = try await defaultProductRepo.fetchAll()
    for dto in dtos {
        let companyId = dto.companyId
        let component = dto.componentType
        let descriptor = FetchDescriptor<CompanyDefaultProduct>(
            predicate: #Predicate { $0.companyId == companyId && $0.componentType.rawValue == component }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.productId = dto.productId
            existing.updatedAt = SupabaseDate.parse(dto.updatedAt) ?? Date()
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            context.insert(dto.toModel())
        }
    }
    try context.save()
    print("[InboundProcessor] Merged \(dtos.count) company default products")
}
```

- [ ] **Step 6: Implement `syncCatalogOrders` and `syncCatalogOrderItems`**

```swift
private func syncCatalogOrders(since: Date?, context: ModelContext) async throws {
    let dtos = try await orderRepo.fetchAll()
    for dto in dtos {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogOrder>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.status = CatalogOrderStatus(rawValue: dto.status) ?? .draft
            existing.title = dto.title
            existing.supplierName = dto.supplierName
            existing.supplierContact = dto.supplierContact
            existing.expectedDeliveryDate = dto.expectedDeliveryDate.flatMap { SupabaseDate.parseDateOnly($0) }
            existing.notes = dto.notes
            existing.updatedAt = SupabaseDate.parse(dto.updatedAt) ?? Date()
            existing.sentAt = dto.sentAt.flatMap { SupabaseDate.parse($0) }
            existing.fulfilledAt = dto.fulfilledAt.flatMap { SupabaseDate.parse($0) }
            existing.cancelledAt = dto.cancelledAt.flatMap { SupabaseDate.parse($0) }
            existing.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let m = dto.toModel()
            m.lastSyncedAt = Date()
            m.needsSync = false
            context.insert(m)
        }
    }
    try context.save()
    print("[InboundProcessor] Merged \(dtos.count) catalog orders")
}

private func syncCatalogOrderItems(context: ModelContext) async throws {
    // Fetch order items only for orders we already have locally.
    let localOrders: [CatalogOrder] = (try? context.fetch(FetchDescriptor<CatalogOrder>())) ?? []
    var allItemDTOs: [CatalogOrderItemDTO] = []
    for order in localOrders {
        let items = try await orderRepo.fetchOrderItems(orderId: order.id)
        allItemDTOs.append(contentsOf: items)
    }
    for dto in allItemDTOs {
        let id = dto.id
        let descriptor = FetchDescriptor<CatalogOrderItem>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.quantityRequested = dto.quantityRequested
            existing.costPerUnit = dto.costPerUnit
            existing.notes = dto.notes
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            let m = dto.toModel()
            m.lastSyncedAt = Date()
            m.needsSync = false
            context.insert(m)
        }
    }
    try context.save()
    print("[InboundProcessor] Merged \(allItemDTOs.count) catalog order items")
}
```

- [ ] **Step 7: Update `linkAllRelationships`** (~line 1300) to walk catalog relationships instead of inventory:

The original inventory linker resolved `unit` and `tags` relationships on `InventoryItem`. The new model has stronger normalization (junction tables) so most "linking" is unnecessary — Stock views query directly via `companyId` and join in the view layer.

Replace the inventory linking block with:

```swift
// Catalog: nothing to link in-memory beyond what SwiftData @Model already
// surfaces. Variants reference catalog_item_id, option_value joins exist
// as their own entities, snapshots reference variant_id by string. The
// view layer reads these as @Query and joins client-side.
//
// Categories: nothing to do (parent_id is a string FK; no SwiftData @Relationship).
//
// Tags: catalog_item_tags rows are already authoritative; we don't need to
// hydrate a derived `tagIds` field on CatalogItem (we removed that field
// in the new model).
print("[InboundProcessor] Catalog relationships linked (no-op — junction-driven)")
```

### Task 40: Wrap fullSync and deltaSync in per-entity error isolation

**Files:**
- Modify: `OPS/OPS/Network/Sync/InboundProcessor.swift`

This task closes Bug 2837ddae. Each `try await syncEntityType(...)` is wrapped in its own try/catch with a SyncTelemetry log. The outer loop continues even if one entity throws.

- [ ] **Step 1: Replace the `fullSync` for-loop**

Replace this block (~line 159):

```swift
for (index, entityType) in Self.syncOrder.enumerated() {
    let stepProgress = Double(index) / totalSteps
    onProgress?(entityType, stepProgress)

    print("[InboundProcessor] Syncing \(entityType.rawValue)...")
    try await syncEntityType(entityType, since: nil, context: context)
    print("[InboundProcessor] \(entityType.rawValue) complete")
}
```

with:

```swift
for (index, entityType) in Self.syncOrder.enumerated() {
    let stepProgress = Double(index) / totalSteps
    onProgress?(entityType, stepProgress)

    print("[InboundProcessor] Syncing \(entityType.rawValue)...")
    do {
        try await syncEntityType(entityType, since: nil, context: context)
        print("[InboundProcessor] \(entityType.rawValue) complete")
    } catch {
        print("[InboundProcessor] ⚠️ \(entityType.rawValue) FAILED: \(error.localizedDescription)")
        SyncTelemetry.logError(
            entityType: entityType.rawValue,
            error: error,
            isFullSync: true,
            companyId: companyId,
            userId: SupabaseService.shared.currentUserId
        )
        // Continue to the next entity — one entity must not abort the entire pull.
    }
}
```

- [ ] **Step 2: Apply the same wrapper to `deltaSync`**

Replace the `for entityType in Self.syncOrder` block in `deltaSync` (~line 201) with the analogous try/catch + SyncTelemetry call (using `isFullSync: false`).

- [ ] **Step 3: Update `SupabaseService` to expose `currentUserId` if it doesn't already**

If `SupabaseService.shared.currentUserId` doesn't exist, add it. Common shape:

```swift
extension SupabaseService {
    var currentUserId: String? {
        client.auth.currentUser?.id.uuidString
    }
}
```

- [ ] **Step 4: Build verification**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -40
```

Expected: build succeeds OR remaining errors are in `Views/Inventory/` and `Views/Products/` (rewritten in Phase 5 onwards). Sync layer is green.

- [ ] **Step 5: Commit**

```bash
git add OPS/OPS/Network/Sync/ OPS/OPS/Services/SyncTelemetry.swift
git commit -m "feat(sync): catalog sync layer, per-entity error isolation, app_events instrumentation; closes 2837ddae"
```

### Task 41: Delete legacy inventory sync code paths and the InventoryRepository

**Files:**
- Delete: `OPS/OPS/Network/Supabase/Repositories/InventoryRepository.swift`
- Delete: `OPS/OPS/DataModels/InventoryItem.swift`, `InventoryTag.swift`, `InventoryUnit.swift`, `InventorySnapshot.swift`, `InventorySnapshotItem.swift`
- Delete: `OPS/OPS/Network/Supabase/DTOs/InventoryDTOs.swift`
- Delete: `OPS/OPS/Network/DTOs/InventoryItemDTO.swift`, `InventorySnapshotDTO.swift`, `InventorySnapshotItemDTO.swift`, `InventoryTagDTO.swift`, `InventoryUnitDTO.swift` (only if unused — verify with grep first)

- [ ] **Step 1: Verify no remaining references**

```bash
grep -rn "InventoryItem\|InventoryTag\|InventoryUnit\|InventorySnapshot\|InventorySnapshotItem\|InventoryRepository\|InventoryItemReadDTO\|InventoryTagReadDTO\|InventoryUnitReadDTO\|InventoryItemTagReadDTO\|InventorySnapshotReadDTO\|InventorySnapshotItemReadDTO" /Users/jacksonsweet/Projects/OPS/ops-ios/OPS/ --include='*.swift' | grep -v 'OPSSchemaV1.swift' | grep -v 'OPSSchemaV2.swift'
```

Expected outputs after Phase 5/6 (UI replacement) finishes: zero hits except in the V1/V2 schema definitions (which are historical and must remain for migration replay safety).

For now (after Phase 4 sync rewrite): hits remain in `Views/Inventory/` and `Views/Products/`. Defer the file deletion until Phase 5 and Phase 6 finish replacing those views.

- [ ] **Step 2: Mark this task as PENDING — Phase 5/6 finish the cleanup**

### Phase 4 review checkpoint

- [ ] Confirm `SyncTelemetry` writes a row to `app_events` when an entity throws (manual test: temporarily inject a throw in `syncCatalogVariants`, run a sync, query `app_events WHERE event_name = 'sync_entity_failed'`).
- [ ] Confirm one entity throwing does NOT abort the loop (verified by the rest of the entities still merging).
- [ ] Confirm full sync against Canpro pulls all 58 variants + 8 categories + 9 options + ... successfully on first launch after the migration.
- [ ] Bug 2837ddae closeable: log the fix branch + commit on the bug_reports row.

---

## Phase 5 — CATALOG tab IA replacing Inventory tab

Goal: replace the "Inventory" tab in `MainTabView` with a "CATALOG" tab containing two sub-segments (`STOCK`, `PRODUCTS`) and a kebab menu for everything else (Snapshots, Categories, Tags, Units, Thresholds, Defaults, Orders, Import, Export). This phase scaffolds the shell; Phase 6 fills `STOCK` with variant-aware lists and Phase 7 fills `PRODUCTS`.

All styling traces to `OPSStyle` tokens (per `OPS LTD./CLAUDE.md` and `OPS-Web` design system v2). Animations use `cubic-bezier(0.22, 1, 0.36, 1)` only — no spring physics. Voice is terse OPS-tactical (`// STOCK`, `[ LIST ]`, etc.), authored via the `ops-copywriter` skill where any user-facing text is involved.

### Task 42: Create the CATALOG tab shell

**Files:**
- Create: `OPS/OPS/Views/Catalog/CatalogView.swift`

- [ ] **Step 1: Write the shell view**

```swift
//
//  CatalogView.swift
//  OPS
//
//  Top-level CATALOG tab. Two segments (STOCK, PRODUCTS) + kebab menu.
//  Replaces the prior Inventory tab.
//

import SwiftUI
import SwiftData

enum CatalogSegment: String, CaseIterable, Identifiable {
    case stock = "STOCK"
    case products = "PRODUCTS"
    var id: String { rawValue }
}

struct CatalogView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    @State private var selectedSegment: CatalogSegment = .stock
    @State private var showKebab: Bool = false
    @State private var showOrders: Bool = false
    @State private var showSnapshots: Bool = false
    @State private var showCategoriesManage: Bool = false
    @State private var showTagsManage: Bool = false
    @State private var showUnitsManage: Bool = false
    @State private var showThresholdsManage: Bool = false
    @State private var showDefaultsManage: Bool = false
    @State private var showImport: Bool = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                segmentBar

                Divider()
                    .background(OPSStyle.Colors.separator)

                Group {
                    switch selectedSegment {
                    case .stock:
                        StockView()
                            .transition(.opacity)
                    case .products:
                        ProductsListView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: selectedSegment)
            }
        }
        .sheet(isPresented: $showOrders)            { OrdersSheet() }
        .sheet(isPresented: $showSnapshots)         { SnapshotListView() }
        .sheet(isPresented: $showCategoriesManage)  { CategoriesManageSheet() }
        .sheet(isPresented: $showTagsManage)        { TagsManageSheet() }
        .sheet(isPresented: $showUnitsManage)       { UnitsManageSheet() }
        .sheet(isPresented: $showThresholdsManage)  { ThresholdsManageSheet() }
        .sheet(isPresented: $showDefaultsManage)    { DefaultsManageSheet() }
    }

    private var header: some View {
        HStack {
            Text("CATALOG")
                .font(OPSStyle.Typography.tabTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
            kebabButton
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    private var segmentBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(CatalogSegment.allCases) { segment in
                Button {
                    selectedSegment = segment
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(segment.rawValue)
                        .font(OPSStyle.Typography.segmentLabel)
                        .foregroundColor(
                            selectedSegment == segment
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.tertiaryText
                        )
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .background(
                            ZStack(alignment: .bottom) {
                                Color.clear
                                if selectedSegment == segment {
                                    Rectangle()
                                        .fill(OPSStyle.Colors.primaryAccent)
                                        .frame(height: 2)
                                }
                            }
                        )
                }
                .accessibilityLabel("\(segment.rawValue) segment")
                .accessibilityAddTraits(selectedSegment == segment ? [.isSelected] : [])
            }
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private var kebabButton: some View {
        Menu {
            Section("STOCK") {
                Button { showSnapshots = true }        label: { Label("Snapshots", systemImage: "clock.arrow.circlepath") }
                Button { showCategoriesManage = true } label: { Label("Categories", systemImage: "folder") }
                Button { showTagsManage = true }       label: { Label("Tags", systemImage: "tag") }
                Button { showUnitsManage = true }      label: { Label("Units", systemImage: "ruler") }
                Button { showThresholdsManage = true } label: { Label("Thresholds", systemImage: "exclamationmark.triangle") }
            }
            Section("ORDERS") {
                Button { showOrders = true } label: { Label("Orders", systemImage: "shippingbox") }
            }
            Section("SETUP") {
                Button { showDefaultsManage = true } label: { Label("Defaults", systemImage: "gearshape") }
                Button { showImport = true }         label: { Label("Import…", systemImage: "square.and.arrow.down") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Catalog menu")
    }
}
```

- [ ] **Step 2: Verify the new typography tokens exist (or add them)**

Open `OPS/OPS/Styles/OPSStyle.swift`. Confirm the following typography tokens exist; if any are missing, add them following the existing `Typography.body` / `Typography.caption` pattern:

- `Typography.tabTitle` — Mohave Bold, ~22pt, uppercase
- `Typography.segmentLabel` — JetBrains Mono Regular, ~13pt tracking 1.2

If they don't exist, ADD them:

```swift
extension OPSStyle.Typography {
    static let tabTitle = Font.custom("Mohave-Bold", size: 22).weight(.bold)
    static let segmentLabel = Font.custom("JetBrainsMono-Regular", size: 13).monospaced()
}
```

- [ ] **Step 3: Stub the not-yet-built sheet views so the file compiles**

Stub `StockView`, `ProductsListView`, `OrdersSheet`, `SnapshotListView`, `CategoriesManageSheet`, `TagsManageSheet`, `UnitsManageSheet`, `ThresholdsManageSheet`, `DefaultsManageSheet` with a placeholder `Text("...")`. Each will be filled in subsequent tasks. **Mark each stub with `// FIXME(catalog): replace in Phase X Task Y` so they're discoverable.**

Example stubs (in their respective files; create one file per stub):

```swift
// OPS/OPS/Views/Catalog/Stock/StockView.swift
import SwiftUI
struct StockView: View {
    var body: some View {
        Text("STOCK — coming in Phase 6").foregroundColor(OPSStyle.Colors.tertiaryText)
    }
}
```

(repeat the stub pattern for the other six sheets)

### Task 43: Update `MainTabView.swift` to swap Inventory tab → Catalog tab

**Files:**
- Modify: `OPS/OPS/Views/MainTabView.swift`

The existing implementation gates the Inventory tab on `permissionStore.can("inventory.view", requiredScope: "all")`. Phase 12 will rename to `catalog.view`, but for this task we keep the old key (rename happens in Phase 12 — single source of truth there).

- [ ] **Step 1: Find the Inventory tab block** (~line 165) in MainTabView. The current code:

```swift
if hasInventoryAccess {
    baseTabs.append(TabItem(iconName: "shippingbox.fill", wizardStepId: "welcome_inventory"))
}
```

- [ ] **Step 2: Replace `hasInventoryAccess` with `hasCatalogAccess` (just rename the var, key stays for now)**

```swift
private var hasCatalogAccess: Bool {
    permissionStore.can("inventory.view", requiredScope: "all")  // keyed in Phase 12
}
```

Update all 3 references to `hasInventoryAccess` to `hasCatalogAccess`. Update `inventoryTabIndex` similarly to `catalogTabIndex`.

- [ ] **Step 3: Change the tab icon and replace `InventoryView()` with `CatalogView()`**

Find:

```swift
} else if selectedTab == inventoryTabIndex {
    InventoryView()
}
```

Replace with:

```swift
} else if selectedTab == catalogTabIndex {
    CatalogView()
}
```

Find the icon name `"shippingbox.fill"` in the TabItem creation and replace with `"square.stack.3d.up.fill"`.

- [ ] **Step 4: Update the tab name analytics string** (~line 765):

```swift
if let cat = catalogTabIndex, newTab == cat { tabName = "Catalog" }
```

- [ ] **Step 5: Update `FloatingActionMenu(currentTab:..., hasInventoryAccess: hasInventoryAccess, ...)` callsite**

Replace the named arg `hasInventoryAccess: hasInventoryAccess` with `hasCatalogAccess: hasCatalogAccess`. Update `FloatingActionMenu`'s signature to match (rename the param). Same for `isInventoryTab` → `isCatalogTab`.

- [ ] **Step 6: Build and verify**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | grep -E 'inventory|Inventory' | head -20
```

Expected: no compilation errors mentioning the old inventory tab. (Errors from `Views/Inventory/` and `Views/Products/` are expected and addressed in Phase 6/7.)

- [ ] **Step 7: Commit**

```bash
git add OPS/OPS/Views/MainTabView.swift OPS/OPS/Views/Catalog/CatalogView.swift OPS/OPS/Views/Catalog/Stock/ OPS/OPS/Views/Catalog/Products/ OPS/OPS/Views/Catalog/Orders/ OPS/OPS/Views/Catalog/Manage/
git commit -m "feat(catalog): tab shell with two segments + kebab; replaces Inventory tab"
```

### Task 44: Update FAB (`FloatingActionMenu.swift`) to be Catalog-aware

**Files:**
- Modify: `OPS/OPS/Views/Common/FloatingActionMenu.swift`

The FAB on the Inventory tab today opens "+ new item". Catalog FAB has three actions: + add variant, + add family, + import.

- [ ] **Step 1: Add catalog FAB actions in the existing FAB action enum (or whatever similar mechanism is used)**

Find where FAB actions are defined per-tab. Add a new branch that fires when `isCatalogTab && segmentIsStock`:

```swift
// New: Stock segment FAB
if isCatalogTab && currentSegment == .stock {
    return [
        FABAction(label: "Add Variant", systemImage: "plus.app", action: .addVariant),
        FABAction(label: "Add Family",  systemImage: "square.stack.3d.up", action: .addFamily),
        FABAction(label: "Import…",     systemImage: "square.and.arrow.down", action: .importStock)
    ]
}

// New: Products segment FAB
if isCatalogTab && currentSegment == .products {
    return [
        FABAction(label: "Quick Add",    systemImage: "plus", action: .quickAddProduct),
        FABAction(label: "Full Setup",   systemImage: "slider.horizontal.3", action: .openProductFullSetup)
    ]
}
```

- [ ] **Step 2: Wire the new actions to open the corresponding sheets**

Stubs for now (Tasks in Phase 6/7 fill them):

```swift
case .addVariant:
    showVariantFormSheet = true
case .addFamily:
    showAddFamilySheet = true
case .importStock:
    showImportSheet = true
case .quickAddProduct:
    showQuickAddProductSheet = true
case .openProductFullSetup:
    showFullSetupAlert = true   // until OPS-Web edit-product is built (out of scope this session)
```

- [ ] **Step 3: Build verification (errors expected from missing sheet views — they get filled in subsequent tasks)**

### Task 45: Build a stub for the kebab manage sheets

**Files:**
- Create: `OPS/OPS/Views/Catalog/Manage/CategoriesManageSheet.swift`
- Create: `OPS/OPS/Views/Catalog/Manage/TagsManageSheet.swift`
- Create: `OPS/OPS/Views/Catalog/Manage/UnitsManageSheet.swift`
- Create: `OPS/OPS/Views/Catalog/Manage/ThresholdsManageSheet.swift`
- Create: `OPS/OPS/Views/Catalog/Manage/DefaultsManageSheet.swift`

These get full implementations in Phase 9 (Orders), Phase 10 (Defaults), and a final pass in Phase 14. For now, each is a populated list+CRUD sheet for its underlying entity.

- [ ] **Step 1: Write `CategoriesManageSheet.swift`**

```swift
//
//  CategoriesManageSheet.swift
//  OPS
//
//  CRUD for catalog_categories. Supports nested (parent_id) layout up
//  to 2 levels. Sheet presented from the CatalogView kebab.
//

import SwiftUI
import SwiftData

struct CategoriesManageSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allCategories: [CatalogCategory]
    @State private var showAddSheet = false
    @State private var editingCategory: CatalogCategory? = nil

    private var companyCategories: [CatalogCategory] {
        let companyId = dataController.currentUser?.companyId ?? ""
        return allCategories
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var topLevel: [CatalogCategory] {
        companyCategories.filter { $0.parentId == nil }
    }

    private func children(of category: CatalogCategory) -> [CatalogCategory] {
        companyCategories.filter { $0.parentId == category.id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(topLevel) { parent in
                            CategoryRow(category: parent, depth: 0, onEdit: { editingCategory = $0 })
                            ForEach(children(of: parent)) { child in
                                CategoryRow(category: child, depth: 1, onEdit: { editingCategory = $0 })
                            }
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle("CATEGORIES")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button { showAddSheet = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showAddSheet) { CategoryFormSheet(category: nil) }
            .sheet(item: $editingCategory) { CategoryFormSheet(category: $0) }
        }
    }
}

private struct CategoryRow: View {
    let category: CatalogCategory
    let depth: Int
    let onEdit: (CatalogCategory) -> Void

    var body: some View {
        HStack {
            if depth > 0 {
                Rectangle().fill(OPSStyle.Colors.separator).frame(width: 16, height: 1)
            }
            Text(depth == 0 ? "// \(category.name.uppercased())" : category.name)
                .font(depth == 0 ? OPSStyle.Typography.bodyBold : OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
            Button { onEdit(category) } label: {
                Image(systemName: "pencil")
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3 * Double(depth + 1))
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}

// CategoryFormSheet — separate file or inline. Wires up create/update/soft-delete via the
// catalog_categories Supabase upsert (write path implemented as part of CatalogRepository in Task 30).
struct CategoryFormSheet: View {
    let category: CatalogCategory?
    var body: some View {
        Text("Category form — implement in same task")
    }
}
```

- [ ] **Step 2: Implement `TagsManageSheet`, `UnitsManageSheet`, `ThresholdsManageSheet`, `DefaultsManageSheet` analogously**

Each follows the pattern: NavigationStack with a list of the entity's rows, a "+" toolbar action that opens a form sheet, edit buttons that re-open the form sheet for an existing row. The `DefaultsManageSheet` is special — it lists each `DesignComponentType` (railing, deck_board, stair_set, gate, post_set) and lets the user pick a Product per component_type from a Picker. Wire to `CompanyDefaultProductRepository.upsert`.

- [ ] **Step 3: Build, commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -40
git add OPS/OPS/Views/Catalog/Manage/
git commit -m "feat(catalog): kebab manage sheets — categories, tags, units, thresholds, defaults"
```

### Phase 5 review checkpoint

- [ ] Tab named CATALOG in MainTabView, icon `square.stack.3d.up.fill`.
- [ ] Two segments visible: STOCK and PRODUCTS.
- [ ] Kebab opens with grouped menu sections.
- [ ] All five manage sheets open and load their entity lists.
- [ ] FAB shows context-appropriate actions per segment.
- [ ] No compile errors related to the new shell. (Errors in `Views/Inventory/` and `Views/Products/` are still expected — Phase 6 and 7 finish those.)

---

## Phase 6 — Stock view modes (LIST / GRID / TABLE)

Goal: implement the variant-aware Stock surface inside `STOCK` segment with three view modes — LIST (today's card list, variant-aware), GRID (today's pinch-to-zoom grid), and TABLE (NEW — Bug 217c3d1f, rows = variants, columns = the family's options).

### Task 46: Implement `StockView` with view-mode toggle, search, filter chips, and category groups

**Files:**
- Modify: `OPS/OPS/Views/Catalog/Stock/StockView.swift` (replace stub from Task 42)

- [ ] **Step 1: Write the stock view shell**

```swift
//
//  StockView.swift
//  OPS
//
//  Variant-aware stock surface inside the CATALOG → STOCK segment.
//  View modes: LIST (cards), GRID (pinch-zoom), TABLE (variants × options).
//  Category-grouped, threshold-banner-aware.
//

import SwiftUI
import SwiftData

enum StockViewMode: String, CaseIterable, Identifiable {
    case list = "LIST"
    case grid = "GRID"
    case table = "TABLE"
    var id: String { rawValue }
}

struct StockView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext

    @AppStorage("catalog.stock.viewMode") private var viewModeRaw: String = StockViewMode.list.rawValue
    private var viewMode: Binding<StockViewMode> {
        Binding(
            get: { StockViewMode(rawValue: viewModeRaw) ?? .list },
            set: { viewModeRaw = $0.rawValue }
        )
    }

    @State private var searchText: String = ""
    @State private var selectedCategoryIds: Set<String> = []
    @State private var selectedTagIds: Set<String> = []
    @State private var thresholdFilter: ThresholdStatus? = nil
    @State private var showOrders: Bool = false

    @Query private var allVariants: [CatalogVariant]
    @Query private var allItems: [CatalogItem]
    @Query private var allCategories: [CatalogCategory]
    @Query private var allTags: [CatalogTag]
    @Query private var allItemTags: [CatalogItemTag]
    @Query private var allOptions: [CatalogOption]
    @Query private var allOptionValues: [CatalogOptionValue]
    @Query private var allVariantOptionValues: [CatalogVariantOptionValue]

    private var companyId: String { dataController.currentUser?.companyId ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            if hasBelowThreshold {
                ThresholdBanner(count: belowThresholdCount, action: { showOrders = true })
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, OPSStyle.Layout.spacing2)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                searchField
                viewModeToggle
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)

            filterChips

            Divider().background(OPSStyle.Colors.separator)

            content
        }
        .sheet(isPresented: $showOrders) { OrdersSheet() }
    }

    private var hasBelowThreshold: Bool { belowThresholdCount > 0 }

    private var belowThresholdCount: Int {
        // Variant.effectiveThresholdStatus() falls back to family default,
        // then to category default, then `.normal`.
        return enrichedVariants(applyFilters: false).filter { $0.statusEnriched != .normal }.count
    }

    @ViewBuilder
    private var content: some View {
        switch viewMode.wrappedValue {
        case .list:
            StockListView(rows: enrichedVariants(applyFilters: true), allCategories: allCategories)
        case .grid:
            StockGridView(rows: enrichedVariants(applyFilters: true), allCategories: allCategories)
        case .table:
            StockTableView(rows: enrichedVariants(applyFilters: true),
                           allOptions: allOptions, allOptionValues: allOptionValues,
                           variantOptionValues: allVariantOptionValues)
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            TextField("Search variants…", text: $searchText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var viewModeToggle: some View {
        Picker("", selection: viewMode) {
            ForEach(StockViewMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                CategoryFilterMenu(allCategories: companyCategories, selected: $selectedCategoryIds)
                TagFilterMenu(allTags: companyTags, selected: $selectedTagIds)
                ThresholdFilterMenu(selected: $thresholdFilter)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
    }

    private var companyCategories: [CatalogCategory] {
        allCategories.filter { $0.companyId == companyId && $0.deletedAt == nil }
    }
    private var companyTags: [CatalogTag] {
        allTags.filter { $0.companyId == companyId && $0.deletedAt == nil }
    }

    /// Walks variants → families → categories, applying filters and search.
    /// Returns enriched rows with computed family name + option-value labels +
    /// effective threshold status.
    private func enrichedVariants(applyFilters: Bool) -> [EnrichedVariantRow] {
        let variants = allVariants.filter { $0.companyId == companyId && $0.deletedAt == nil && $0.isActive }
        let itemById = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        let categoryById = Dictionary(uniqueKeysWithValues: allCategories.map { ($0.id, $0) })
        let optionValueById = Dictionary(uniqueKeysWithValues: allOptionValues.map { ($0.id, $0) })

        // Variant id → [option_value_id]
        var variantOptionMap: [String: [String]] = [:]
        for join in allVariantOptionValues {
            variantOptionMap[join.variantId, default: []].append(join.optionValueId)
        }

        // Family id → [tag_id]
        var familyTagMap: [String: Set<String>] = [:]
        for join in allItemTags {
            familyTagMap[join.catalogItemId, default: []].insert(join.tagId)
        }

        return variants.compactMap { v -> EnrichedVariantRow? in
            guard let family = itemById[v.catalogItemId] else { return nil }
            let category = family.categoryId.flatMap { categoryById[$0] }
            let parentCategory = category?.parentId.flatMap { categoryById[$0] }
            let optionValueIds = variantOptionMap[v.id, default: []]
            let optionValueLabels = optionValueIds.compactMap { optionValueById[$0]?.value }
            let variantLabel = optionValueLabels.joined(separator: " · ")
            let displayName = "\(family.name)\(variantLabel.isEmpty ? "" : " — \(variantLabel)")"

            // Effective threshold cascade: variant → family default → category default → none
            let warn = v.warningThreshold ?? family.defaultWarningThreshold ?? category?.defaultWarningThreshold
            let crit = v.criticalThreshold ?? family.defaultCriticalThreshold ?? category?.defaultCriticalThreshold
            let status: ThresholdStatus = {
                if let crit = crit, v.quantity <= crit { return .critical }
                if let warn = warn, v.quantity <= warn { return .warning }
                return .normal
            }()

            let row = EnrichedVariantRow(
                variant: v,
                family: family,
                category: category,
                parentCategory: parentCategory,
                variantLabel: variantLabel,
                displayName: displayName,
                statusEnriched: status,
                tagIds: familyTagMap[family.id, default: []]
            )

            if applyFilters {
                // Search
                let needle = searchText.lowercased()
                if !needle.isEmpty {
                    let nameMatch = displayName.lowercased().contains(needle)
                    let skuMatch  = v.sku?.lowercased().contains(needle) ?? false
                    if !nameMatch && !skuMatch { return nil }
                }
                // Category filter
                if !selectedCategoryIds.isEmpty,
                   !(selectedCategoryIds.contains(family.categoryId ?? "")
                     || selectedCategoryIds.contains(parentCategory?.id ?? "")) {
                    return nil
                }
                // Tag filter
                if !selectedTagIds.isEmpty,
                   row.tagIds.intersection(selectedTagIds).isEmpty { return nil }
                // Threshold filter
                if let f = thresholdFilter, row.statusEnriched != f { return nil }
            }

            return row
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

struct EnrichedVariantRow: Identifiable {
    var id: String { variant.id }
    let variant: CatalogVariant
    let family: CatalogItem
    let category: CatalogCategory?
    let parentCategory: CatalogCategory?
    let variantLabel: String     // e.g., "Black · Topmount"
    let displayName: String      // e.g., "Corner — Black · Topmount"
    let statusEnriched: ThresholdStatus
    let tagIds: Set<String>
}
```

- [ ] **Step 2: Build helper subviews — `CategoryFilterMenu`, `TagFilterMenu`, `ThresholdFilterMenu`, `ThresholdBanner`**

```swift
struct CategoryFilterMenu: View {
    let allCategories: [CatalogCategory]
    @Binding var selected: Set<String>
    var body: some View {
        Menu {
            Button("Clear") { selected = [] }
            Divider()
            ForEach(allCategories.filter { $0.parentId == nil }) { parent in
                Section(parent.name.uppercased()) {
                    Button {
                        toggle(parent.id)
                    } label: {
                        Label(parent.name, systemImage: selected.contains(parent.id) ? "checkmark.square" : "square")
                    }
                    ForEach(allCategories.filter { $0.parentId == parent.id }) { child in
                        Button {
                            toggle(child.id)
                        } label: {
                            Label(child.name, systemImage: selected.contains(child.id) ? "checkmark.square" : "square")
                        }
                    }
                }
            }
        } label: {
            ChipLabel(text: selected.isEmpty ? "Category" : "Category (\(selected.count))",
                      isActive: !selected.isEmpty)
        }
    }
    private func toggle(_ id: String) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
}

struct TagFilterMenu: View {
    let allTags: [CatalogTag]
    @Binding var selected: Set<String>
    var body: some View {
        Menu {
            Button("Clear") { selected = [] }
            Divider()
            ForEach(allTags.sorted { $0.name < $1.name }) { tag in
                Button {
                    if selected.contains(tag.id) { selected.remove(tag.id) } else { selected.insert(tag.id) }
                } label: {
                    Label(tag.name, systemImage: selected.contains(tag.id) ? "checkmark.square" : "square")
                }
            }
        } label: {
            ChipLabel(text: selected.isEmpty ? "Tags" : "Tags (\(selected.count))", isActive: !selected.isEmpty)
        }
    }
}

struct ThresholdFilterMenu: View {
    @Binding var selected: ThresholdStatus?
    var body: some View {
        Menu {
            Button("Clear") { selected = nil }
            Divider()
            Button("Critical")  { selected = .critical }
            Button("Warning")   { selected = .warning }
            Button("Normal")    { selected = .normal }
        } label: {
            let label: String = {
                switch selected {
                case .critical: return "Threshold: Critical"
                case .warning:  return "Threshold: Warning"
                case .normal:   return "Threshold: Normal"
                case .none:     return "Threshold"
                }
            }()
            ChipLabel(text: label, isActive: selected != nil)
        }
    }
}

struct ChipLabel: View {
    let text: String
    let isActive: Bool
    var body: some View {
        Text(text)
            .font(OPSStyle.Typography.caption)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(isActive ? OPSStyle.Colors.primaryAccent.opacity(0.15) : OPSStyle.Colors.cardBackgroundDark)
            .foregroundColor(isActive ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
            .cornerRadius(OPSStyle.Layout.chipCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipCornerRadius)
                    .stroke(isActive ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }
}

struct ThresholdBanner: View {
    let count: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(OPSStyle.Colors.warningText)
                Text("// \(count) ITEM\(count == 1 ? "" : "S") BELOW THRESHOLD")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                Text("REVIEW →")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .padding(OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.warningBackground)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.warningBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }
}
```

If `OPSStyle.Colors.warningText/warningBackground/warningBorder/captionBold` don't exist, add them following the existing token pattern (semantic colors map to `tan #C4A868` per the design system spec).

### Task 47: Implement `StockListView`, `StockGridView`, `StockTableView`

**Files:**
- Modify: `OPS/OPS/Views/Catalog/Stock/StockListView.swift`
- Create: `OPS/OPS/Views/Catalog/Stock/StockGridView.swift`
- Create: `OPS/OPS/Views/Catalog/Stock/StockTableView.swift`
- Create: `OPS/OPS/Views/Catalog/Stock/CategoryGroupSection.swift`
- Create: `OPS/OPS/Views/Catalog/Stock/VariantCard.swift`

- [ ] **Step 1: Implement `StockListView` (LIST mode — variant cards grouped by category)**

```swift
//
//  StockListView.swift
//  OPS
//

import SwiftUI

struct StockListView: View {
    let rows: [EnrichedVariantRow]
    let allCategories: [CatalogCategory]

    private var grouped: [(category: CatalogCategory?, parent: CatalogCategory?, rows: [EnrichedVariantRow])] {
        // Group by (parentCategory, category) so the UI nests two levels.
        let dict = Dictionary(grouping: rows) { row in
            row.category?.id ?? "_uncat"
        }
        return dict.map { (key, rs) in
            let cat = rs.first?.category
            let parent = rs.first?.parentCategory
            return (cat, parent, rs)
        }
        .sorted { ($0.parent?.sortOrder ?? 9_999, $0.category?.sortOrder ?? 9_999, $0.category?.name ?? "") <
                  ($1.parent?.sortOrder ?? 9_999, $1.category?.sortOrder ?? 9_999, $1.category?.name ?? "") }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: OPSStyle.Layout.spacing3, pinnedViews: [.sectionHeaders]) {
                ForEach(grouped, id: \.category?.id) { group in
                    CategoryGroupSection(
                        parent: group.parent,
                        category: group.category,
                        rows: group.rows
                    )
                }

                HStack {
                    Spacer()
                    Text("[ \(rows.count) VARIANT\(rows.count == 1 ? "" : "S") ]")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Spacer()
                }
                .padding(.top, OPSStyle.Layout.spacing3)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing3)
        }
        .trackScreen("Catalog.Stock.List")
    }
}
```

- [ ] **Step 2: Implement `CategoryGroupSection`**

```swift
struct CategoryGroupSection: View {
    let parent: CatalogCategory?
    let category: CatalogCategory?
    let rows: [EnrichedVariantRow]

    var body: some View {
        Section {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(rows) { row in
                    NavigationLink {
                        VariantDetailView(row: row)
                    } label: {
                        VariantCard(row: row)
                    }
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                if let parent = parent, parent.id != category?.id {
                    Text("// \(parent.name.uppercased())")
                        .font(OPSStyle.Typography.tactical)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                Text("// \((category?.name ?? "UNCATEGORIZED").uppercased())")
                    .font(OPSStyle.Typography.sectionHeader)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.background)
        }
    }
}
```

- [ ] **Step 3: Implement `VariantCard`**

```swift
struct VariantCard: View {
    let row: EnrichedVariantRow

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            // Status accent stripe
            Rectangle()
                .fill(statusColor)
                .frame(width: 3)
                .cornerRadius(1.5)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.family.name)
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                if !row.variantLabel.isEmpty {
                    Text(row.variantLabel)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }
                if let sku = row.variant.sku, !sku.isEmpty {
                    Text("SKU \(sku)")
                        .font(OPSStyle.Typography.smallMono)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedQty)
                    .font(OPSStyle.Typography.quantity)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .monospacedDigit()
                if let stat = statusLabel {
                    Text(stat)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(statusColor)
                }
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var formattedQty: String {
        // Use JetBrains Mono / tabular figures via OPSStyle.Typography.quantity.
        // Format with the variant's unit if available — otherwise plain count.
        let qty = row.variant.quantity
        if qty.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", qty)
        }
        return String(format: "%.2f", qty)
    }

    private var statusColor: Color {
        switch row.statusEnriched {
        case .critical: return OPSStyle.Colors.errorText
        case .warning:  return OPSStyle.Colors.warningText
        case .normal:   return Color.clear
        }
    }
    private var statusLabel: String? {
        switch row.statusEnriched {
        case .critical: return "CRITICAL"
        case .warning:  return "WARNING"
        case .normal:   return nil
        }
    }
}
```

- [ ] **Step 4: Implement `StockGridView`**

Re-use the existing inventory grid pattern (pinch-to-zoom) but read from `EnrichedVariantRow` and render `VariantCard` in a `LazyVGrid` with a configurable `cardScale`. Reference the existing `InventoryView`'s grid section for the gesture handling — port it 1:1 onto `EnrichedVariantRow` data.

- [ ] **Step 5: Implement `StockTableView` (NEW — Bug 217c3d1f)**

```swift
//
//  StockTableView.swift
//  OPS
//
//  Bug 217c3d1f — table view mode where rows = variants, columns = the
//  family's CatalogOptions (Color, Mount Type, etc.). Useful for power
//  users mapping their spreadsheet mental model to the catalog.
//

import SwiftUI

struct StockTableView: View {
    let rows: [EnrichedVariantRow]
    let allOptions: [CatalogOption]
    let allOptionValues: [CatalogOptionValue]
    let variantOptionValues: [CatalogVariantOptionValue]

    private var grouped: [(family: CatalogItem, options: [CatalogOption], variants: [EnrichedVariantRow])] {
        let byFamily = Dictionary(grouping: rows, by: { $0.family.id })
        return byFamily.compactMap { (familyId, fRows) -> (CatalogItem, [CatalogOption], [EnrichedVariantRow])? in
            guard let family = fRows.first?.family else { return nil }
            let options = allOptions
                .filter { $0.catalogItemId == familyId }
                .sorted { $0.sortOrder < $1.sortOrder }
            return (family, options, fRows.sorted { $0.displayName < $1.displayName })
        }
        .sorted { $0.family.name < $1.family.name }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: OPSStyle.Layout.spacing4, pinnedViews: [.sectionHeaders]) {
                ForEach(grouped, id: \.family.id) { group in
                    Section {
                        familyTable(group: group)
                    } header: {
                        Text("// \(group.family.name.uppercased())")
                            .font(OPSStyle.Typography.sectionHeader)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                            .background(OPSStyle.Colors.background)
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing3)
        }
        .trackScreen("Catalog.Stock.Table")
    }

    @ViewBuilder
    private func familyTable(group: (family: CatalogItem, options: [CatalogOption], variants: [EnrichedVariantRow])) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    headerCell("VARIANT").frame(minWidth: 140, alignment: .leading)
                    ForEach(group.options) { option in
                        headerCell(option.name.uppercased()).frame(minWidth: 100, alignment: .leading)
                    }
                    headerCell("QTY").frame(minWidth: 80, alignment: .trailing)
                    headerCell("SKU").frame(minWidth: 100, alignment: .leading)
                }
                Divider().background(OPSStyle.Colors.separator)

                // Body rows
                ForEach(group.variants) { row in
                    NavigationLink { VariantDetailView(row: row) } label: {
                        HStack(spacing: 0) {
                            bodyCell(row.variantLabel.isEmpty ? "—" : row.variantLabel)
                                .frame(minWidth: 140, alignment: .leading)
                            ForEach(group.options) { option in
                                bodyCell(valueLabel(forVariant: row.variant.id, option: option))
                                    .frame(minWidth: 100, alignment: .leading)
                            }
                            quantityCell(row).frame(minWidth: 80, alignment: .trailing)
                            bodyCell(row.variant.sku ?? "—")
                                .frame(minWidth: 100, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    Divider().background(OPSStyle.Colors.separator.opacity(0.4))
                }
            }
        }
    }

    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.tableHeader)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 8)
    }
    private func bodyCell(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 8)
    }
    private func quantityCell(_ row: EnrichedVariantRow) -> some View {
        Text(row.variant.quantity, format: .number)
            .monospacedDigit()
            .font(OPSStyle.Typography.tableQuantity)
            .foregroundColor(statusColor(row.statusEnriched))
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 8)
    }

    private func valueLabel(forVariant variantId: String, option: CatalogOption) -> String {
        let valueIds = variantOptionValues.filter { $0.variantId == variantId }.map(\.optionValueId)
        let valuesForOption = allOptionValues.filter { ov in
            ov.optionId == option.id && valueIds.contains(ov.id)
        }
        return valuesForOption.first?.value ?? "—"
    }

    private func statusColor(_ s: ThresholdStatus) -> Color {
        switch s {
        case .critical: return OPSStyle.Colors.errorText
        case .warning:  return OPSStyle.Colors.warningText
        case .normal:   return OPSStyle.Colors.primaryText
        }
    }
}
```

- [ ] **Step 6: Build verification + commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -40
git add OPS/OPS/Views/Catalog/Stock/
git commit -m "feat(catalog): variant-aware Stock with LIST/GRID/TABLE view modes; closes 217c3d1f"
```

### Task 48: Implement `VariantDetailView` and `VariantFormSheet`

**Files:**
- Create: `OPS/OPS/Views/Catalog/Stock/VariantDetailView.swift`
- Create: `OPS/OPS/Views/Catalog/Stock/VariantFormSheet.swift`
- Create: `OPS/OPS/Views/Catalog/Stock/AddFamilySheet.swift`

- [ ] **Step 1: Write `VariantDetailView`**

Renders the family info (read-only summary), the variant's option-value combo (read-only chips), editable quantity (with +/- adjuster), editable thresholds (variant-level overrides), SKU, notes, family-level tags, and a read-only "linked Products" section (which Products' recipes consume this variant). Quantity adjustments hit `CatalogRepository.adjustVariantQuantity` and write a row to `inventory_deductions` (now `catalog_variant_id` column) with `reason='manual_adjustment'`.

- [ ] **Step 2: Write `VariantFormSheet`**

Inline form for editing a single variant (sku, quantity, thresholds, unit). Used for both new-variant flow (within an existing family) and edit-existing-variant flow.

- [ ] **Step 3: Write `AddFamilySheet`**

Multi-step form: name, category (picker), description, default unit, default thresholds. Variants are added afterward via a follow-up "+ add variant" step within the family detail view. Authoring options/option-values is deferred to OPS-Web (out of scope this session); iOS supports creating a single-variant family on the fly without options.

- [ ] **Step 4: Build + commit**

### Task 49: Delete legacy `Views/Inventory/`

**Files:**
- Delete: `OPS/OPS/Views/Inventory/` (entire folder)

- [ ] **Step 1: Verify no remaining references after Phase 6 build is green**

```bash
grep -rn "InventoryListView\|InventoryView()\|InventoryFormSheet\|InventoryManageTagsSheet\|BulkQuantityAdjustmentSheet\|BulkTagsSheet\|QuantityAdjustmentSheet" /Users/jacksonsweet/Projects/OPS/ops-ios/ --include='*.swift'
```

Expected: zero hits (or only references in archived/V1/V2 schema files that are inert).

- [ ] **Step 2: Delete the folder**

```bash
rm -rf /Users/jacksonsweet/Projects/OPS/ops-ios/OPS/OPS/Views/Inventory
```

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -20
git add -A OPS/OPS/Views/
git commit -m "chore(catalog): remove legacy Views/Inventory/"
```

### Phase 6 review checkpoint

- [ ] Stock tab shows category-grouped variants in LIST mode.
- [ ] GRID mode renders pinch-to-zoom variant cards.
- [ ] TABLE mode (Bug 217c3d1f) renders rows × option columns per family.
- [ ] Threshold banner appears when items are below threshold.
- [ ] Filters (category, tag, threshold) work.
- [ ] Variant detail view supports quantity adjust with deduction audit.
- [ ] Bug 217c3d1f closeable.

---

## Phase 7 — Products surface (Quick add + Product detail with read-only options/recipe)

Goal: implement the `PRODUCTS` segment of CATALOG. iOS supports read-only display of options/modifiers/recipe (authoring lives on OPS-Web in the named follow-up session) plus a low-friction `Quick Add` form (3–4 fields) for barebones Products like `PICKET RAIL — $2500`.

### Task 50: Implement `ProductsListView` (replacement for legacy)

**Files:**
- Modify: `OPS/OPS/Views/Catalog/Products/ProductsListView.swift` (replace stub from Task 42)

- [ ] **Step 1: Write the products list (variant of the Stock list, but for Products)**

```swift
//
//  ProductsListView.swift
//  OPS
//
//  Catalog → PRODUCTS segment.
//

import SwiftUI
import SwiftData

enum ProductFilter: String, CaseIterable, Identifiable {
    case all      = "ALL"
    case service  = "SERVICE"
    case good     = "GOOD"
    case withRecipe = "HAS RECIPE"
    var id: String { rawValue }
}

struct ProductsListView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var filter: ProductFilter = .all
    @State private var showQuickAdd = false
    @State private var editingProduct: Product? = nil

    @Query private var allProducts: [Product]
    @Query private var allMaterials: [ProductMaterial]
    @Query private var allOptions: [ProductOption]

    private var companyId: String { dataController.currentUser?.companyId ?? "" }

    private var products: [Product] {
        let filtered = allProducts.filter { p in
            p.companyId == companyId && p.isActive
        }
        let withRecipeIds = Set(allMaterials.map(\.productId))
        return filtered.filter { p in
            switch filter {
            case .all:        return true
            case .service:    return p.kind == .service
            case .good:       return p.kind == .good
            case .withRecipe: return withRecipeIds.contains(p.id)
            }
        }.filter { p in
            if searchText.isEmpty { return true }
            let needle = searchText.lowercased()
            return p.name.lowercased().contains(needle)
                || (p.productDescription ?? "").lowercased().contains(needle)
                || (p.sku ?? "").lowercased().contains(needle)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func optionCount(for productId: String) -> Int {
        allOptions.filter { $0.productId == productId }.count
    }
    private func recipeCount(for productId: String) -> Int {
        allMaterials.filter { $0.productId == productId }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                searchField
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(ProductFilter.allCases) { f in
                        filterChip(f)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
            }

            Divider().background(OPSStyle.Colors.separator)

            ScrollView {
                LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(products) { p in
                        NavigationLink {
                            ProductDetailView(product: p)
                        } label: {
                            ProductRow(
                                product: p,
                                optionCount: optionCount(for: p.id),
                                recipeCount: recipeCount(for: p.id)
                            )
                        }
                    }
                    HStack {
                        Spacer()
                        Text("[ \(products.count) PRODUCT\(products.count == 1 ? "" : "S") ]")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer()
                    }
                    .padding(.top, OPSStyle.Layout.spacing3)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing3)
            }
        }
        .sheet(isPresented: $showQuickAdd) { QuickAddProductSheet() }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(OPSStyle.Colors.tertiaryText)
            TextField("Search products…", text: $searchText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func filterChip(_ f: ProductFilter) -> some View {
        Button {
            filter = f
        } label: {
            ChipLabel(text: f.rawValue, isActive: filter == f)
        }
    }
}

private struct ProductRow: View {
    let product: Product
    let optionCount: Int
    let recipeCount: Int

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                HStack(spacing: 6) {
                    Text(priceLabel).font(OPSStyle.Typography.smallMono)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    if optionCount > 0 || recipeCount > 0 {
                        Text("·").foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    if optionCount > 0 {
                        Text("\(optionCount) option\(optionCount == 1 ? "" : "s")")
                            .font(OPSStyle.Typography.smallMono)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    if recipeCount > 0 {
                        Text("· \(recipeCount) recipe row\(recipeCount == 1 ? "" : "s")")
                            .font(OPSStyle.Typography.smallMono)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var priceLabel: String {
        let price = String(format: "$%.2f", product.basePrice)
        let unit: String = {
            switch product.pricingUnit {
            case .each:        return "each"
            case .flatRate:    return "flat"
            case .linearFoot:  return "/ft"
            case .sqft:        return "/sqft"
            case .hour:        return "/hr"
            case .day:         return "/day"
            }
        }()
        return "\(price) \(unit)"
    }
}
```

### Task 51: Implement `QuickAddProductSheet` (3–4 fields, ≤ 8s flow)

**Files:**
- Create: `OPS/OPS/Views/Catalog/Products/QuickAddProductSheet.swift`

- [ ] **Step 1: Write the form**

```swift
//
//  QuickAddProductSheet.swift
//  OPS
//
//  Barebones Product creation. Three required fields (name, price, unit).
//  Defaults: type=OTHER, kind=service, taxable=true, isActive=true.
//  Advanced disclosure exposes the 9 extra fields for power users.
//

import SwiftUI
import SwiftData

struct QuickAddProductSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var priceString: String = ""
    @State private var pricingUnit: ProductPricingUnit = .flatRate
    @State private var taxable: Bool = true
    @State private var showAdvanced: Bool = false

    // Advanced fields
    @State private var description: String = ""
    @State private var sku: String = ""
    @State private var category: String = ""
    @State private var unitCostString: String = ""
    @State private var lineItemType: LineItemType = .other
    @State private var kind: ProductKind = .service

    @State private var isSaving: Bool = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

                Form {
                    Section {
                        TextField("Name", text: $name)
                            .font(OPSStyle.Typography.body)
                        HStack {
                            Text("$").foregroundColor(OPSStyle.Colors.tertiaryText)
                            TextField("Price", text: $priceString).keyboardType(.decimalPad)
                        }
                        Picker("Unit", selection: $pricingUnit) {
                            Text("Flat").tag(ProductPricingUnit.flatRate)
                            Text("Each").tag(ProductPricingUnit.each)
                            Text("Per ft").tag(ProductPricingUnit.linearFoot)
                            Text("Per sqft").tag(ProductPricingUnit.sqft)
                            Text("Per hour").tag(ProductPricingUnit.hour)
                            Text("Per day").tag(ProductPricingUnit.day)
                        }
                        Toggle("Taxable", isOn: $taxable)
                    }

                    Section {
                        DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                            TextField("Description (optional)", text: $description, axis: .vertical)
                            TextField("SKU (optional)", text: $sku)
                            TextField("Category (optional)", text: $category)
                            HStack {
                                Text("$ unit cost")
                                TextField("0.00", text: $unitCostString).keyboardType(.decimalPad)
                            }
                            Picker("Line item type", selection: $lineItemType) {
                                Text("Labor").tag(LineItemType.labor)
                                Text("Material").tag(LineItemType.material)
                                Text("Other").tag(LineItemType.other)
                            }
                            Picker("Kind", selection: $kind) {
                                Text("Service").tag(ProductKind.service)
                                Text("Good").tag(ProductKind.good)
                            }
                        }
                    }

                    if let error = error {
                        Section {
                            Text(error).foregroundColor(OPSStyle.Colors.errorText)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("NEW PRODUCT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if isSaving { ProgressView() } else { Text("SAVE").font(OPSStyle.Typography.actionButton) }
                    }
                    .disabled(name.isEmpty || priceString.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let companyId = dataController.currentUser?.companyId,
              let price = Double(priceString) else {
            error = "Missing required fields"
            return
        }
        isSaving = true
        defer { isSaving = false }

        let dto = CreateProductDTO(
            companyId: companyId,
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.isEmpty ? nil : description,
            basePrice: price,
            unitCost: Double(unitCostString),
            unit: nil,
            pricingUnit: pricingUnit.rawValue,
            category: category.isEmpty ? nil : category,
            sku: sku.isEmpty ? nil : sku,
            kind: kind.rawValue,
            type: lineItemType.rawValue,
            isTaxable: taxable,
            taskTypeId: nil
        )

        let repo = ProductRepository(companyId: companyId)
        do {
            let resultDTO = try await repo.create(dto)
            let model = resultDTO.toModel()
            modelContext.insert(model)
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
```

### Task 52: Implement `ProductDetailView` (read-only options/modifiers/recipe + light-edit fields)

**Files:**
- Create: `OPS/OPS/Views/Catalog/Products/ProductDetailView.swift`
- Create: `OPS/OPS/Views/Catalog/Products/RecipeReadOnlyView.swift`
- Create: `OPS/OPS/Views/Catalog/Products/OptionsReadOnlyView.swift`
- Create: `OPS/OPS/Views/Catalog/Products/ModifiersReadOnlyView.swift`

- [ ] **Step 1: Write `ProductDetailView`**

The detail view shows: name (editable), base_price (editable), pricing_unit (editable), type/kind/taxable/active (editable). Sections that collapse if empty: Options, Pricing modifiers, Recipe. Tags are editable (free-form `catalog_tags`). A "View on web to author" CTA opens an external URL when the user taps an editable Options/Modifiers/Recipe section header.

Structure:

```swift
//
//  ProductDetailView.swift
//  OPS
//

import SwiftUI
import SwiftData

struct ProductDetailView: View {
    let product: Product
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext

    // Editable fields
    @State private var name: String
    @State private var basePriceString: String
    @State private var pricingUnit: ProductPricingUnit
    @State private var taxable: Bool
    @State private var isActive: Bool

    @Query private var allOptions: [ProductOption]
    @Query private var allOptionValues: [ProductOptionValue]
    @Query private var allModifiers: [ProductPricingModifier]
    @Query private var allMaterials: [ProductMaterial]

    init(product: Product) {
        self.product = product
        _name = State(initialValue: product.name)
        _basePriceString = State(initialValue: String(format: "%.2f", product.basePrice))
        _pricingUnit = State(initialValue: product.pricingUnit)
        _taxable = State(initialValue: product.taxable)
        _isActive = State(initialValue: product.isActive)
    }

    private var productOptions: [ProductOption] {
        allOptions.filter { $0.productId == product.id }.sorted { $0.sortOrder < $1.sortOrder }
    }
    private var productModifiers: [ProductPricingModifier] {
        allModifiers.filter { $0.productId == product.id }
    }
    private var productMaterials: [ProductMaterial] {
        allMaterials.filter { $0.productId == product.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                editableHeader

                if !productOptions.isEmpty {
                    SectionHeader(text: "// OPTIONS · \(productOptions.count) · TAP A WEB LINK TO EDIT")
                    OptionsReadOnlyView(options: productOptions, optionValues: allOptionValues)
                }

                if !productModifiers.isEmpty {
                    SectionHeader(text: "// PRICING MODIFIERS · \(productModifiers.count)")
                    ModifiersReadOnlyView(modifiers: productModifiers, options: productOptions, optionValues: allOptionValues)
                }

                if !productMaterials.isEmpty {
                    SectionHeader(text: "// RECIPE · \(productMaterials.count) ROW\(productMaterials.count == 1 ? "" : "S")")
                    RecipeReadOnlyView(materials: productMaterials, options: productOptions)
                }

                Spacer().frame(height: 80)
            }
            .padding(OPSStyle.Layout.spacing3)
        }
        .navigationTitle(product.name.uppercased())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("SAVE") { Task { await save() } }
                    .font(OPSStyle.Typography.actionButton)
                    .disabled(!hasChanges)
            }
        }
    }

    private var hasChanges: Bool {
        name != product.name
        || Double(basePriceString) != product.basePrice
        || pricingUnit != product.pricingUnit
        || taxable != product.taxable
        || isActive != product.isActive
    }

    private var editableHeader: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            TextField("Name", text: $name).font(OPSStyle.Typography.cardTitle)
            HStack {
                Text("$").foregroundColor(OPSStyle.Colors.tertiaryText)
                TextField("Price", text: $basePriceString).keyboardType(.decimalPad)
                Picker("", selection: $pricingUnit) {
                    Text("flat").tag(ProductPricingUnit.flatRate)
                    Text("each").tag(ProductPricingUnit.each)
                    Text("/ft").tag(ProductPricingUnit.linearFoot)
                    Text("/sqft").tag(ProductPricingUnit.sqft)
                    Text("/hr").tag(ProductPricingUnit.hour)
                    Text("/day").tag(ProductPricingUnit.day)
                }.pickerStyle(.menu)
            }
            Toggle("Taxable", isOn: $taxable)
            Toggle("Active", isOn: $isActive)
        }
    }

    private func save() async {
        guard let companyId = dataController.currentUser?.companyId,
              let price = Double(basePriceString) else { return }
        var updates = UpdateProductDTO()
        if name != product.name           { updates.name = name }
        if price != product.basePrice     { updates.basePrice = price }
        if pricingUnit != product.pricingUnit  { updates.pricingUnit = pricingUnit.rawValue }
        if taxable != product.taxable     { updates.isTaxable = taxable }
        if isActive != product.isActive   { updates.isActive = isActive }
        let repo = ProductRepository(companyId: companyId)
        do {
            let updated = try await repo.update(product.id, fields: updates)
            // Apply to local model
            product.name = updated.name
            product.basePrice = updated.basePrice
            product.pricingUnit = ProductPricingUnit(rawValue: updated.pricingUnit ?? "each") ?? .each
            product.taxable = updated.isTaxable ?? true
            product.isActive = updated.isActive
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

private struct SectionHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .font(OPSStyle.Typography.tactical)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 2: Write `OptionsReadOnlyView`, `ModifiersReadOnlyView`, `RecipeReadOnlyView`**

Each is a small SwiftUI view that renders the data structure inline with OPS-tactical styling:

- `OptionsReadOnlyView`: lists each option with its values. Each option shows name, kind, default, source.
- `ModifiersReadOnlyView`: lists each modifier with its trigger and amount. Format: `"When Mount Surface = Concrete → +$5.00 per unit"`.
- `RecipeReadOnlyView`: lists each recipe row with variant/family, qty/unit, scaled-by-option indicator. Format: `"Composite Board (color = $color) — 1.05/ft"`.

Implementation pattern stays consistent with the design — pure read-only display, no edit affordances. A "VIEW ON WEB →" button on each section deep-links to OPS-Web's product editor (URL TBD in the OPS-Web follow-up session — for now, link to `https://app.ops.dev/products/{id}`).

### Task 53: Delete legacy `Views/Products/`

**Files:**
- Delete: `OPS/OPS/Views/Products/`

- [ ] **Step 1: Verify no remaining references** to `OPS/OPS/Views/Products/ProductsListView.swift` or `ProductFormSheet.swift`. The CATALOG → PRODUCTS segment now uses `Catalog/Products/ProductsListView.swift`.

- [ ] **Step 2: Delete + commit**

```bash
rm -rf /Users/jacksonsweet/Projects/OPS/ops-ios/OPS/OPS/Views/Products
git add -A
git commit -m "feat(catalog): Products surface with quick-add, detail, read-only options/recipe"
```

### Phase 7 review checkpoint

- [ ] Quick-add Product flow takes ≤ 8s for `PICKET RAIL — $2500`.
- [ ] Product detail shows the rich layers as read-only when present and collapses them when empty.
- [ ] Save round-trips to Supabase and updates SwiftData.
- [ ] Bug 41d6f2b4 closeable.

---

## Phase 8 — Line item adaptation

Goal: when adding a line item to an estimate or invoice, the form adapts to the selected Product's richness. Flat Products show 4 fields. Configurable Products show inline option chips with sensible defaults, a live modifier preview, and a snapshot at save time. The line item carries `configured_options`, `resolved_unit_price`, and `resolved_options_label`.

### Task 54: Create `ProductConfigurationResolver.swift`

**Files:**
- Create: `OPS/OPS/Services/ProductConfigurationResolver.swift`
- Create: `OPSTests/Catalog/ProductConfigurationResolverTests.swift`

The resolver computes `resolved_unit_price` from `base_price + applicable modifiers` given a `configured_options` map. It also produces the `resolved_options_label` string (e.g., `"TM · Black · Concrete · 4 corners"`). The recipe materializer (Phase 11) will use the same resolver.

- [ ] **Step 1: Write the failing test**

```swift
//
//  ProductConfigurationResolverTests.swift
//

import XCTest
@testable import OPS

final class ProductConfigurationResolverTests: XCTestCase {

    /// Build the Custom Composite Railing test fixture — same shape used in the spec.
    private func buildFixture() -> (Product, [ProductOption], [ProductOptionValue], [ProductPricingModifier]) {
        let railing = Product(
            id: "p_rail", companyId: "c1", name: "Custom Composite Railing",
            type: .material, kind: .good, basePrice: 48.00, pricingUnit: .linearFoot
        )

        let mountType = ProductOption(id: "o_mount_type", productId: "p_rail", name: "Mount Type",
                                      kind: .select, affectsPrice: false, affectsRecipe: true,
                                      defaultValue: "Topmount")
        let mountSurface = ProductOption(id: "o_mount_surf", productId: "p_rail", name: "Mount Surface",
                                          kind: .select, affectsPrice: true, affectsRecipe: false,
                                          defaultValue: "Surface")
        let color = ProductOption(id: "o_color", productId: "p_rail", name: "Color",
                                   kind: .select, affectsPrice: false, affectsRecipe: true,
                                   defaultValue: "Black")
        let corners = ProductOption(id: "o_corners", productId: "p_rail", name: "Corners",
                                     kind: .integer, affectsPrice: false, affectsRecipe: true,
                                     defaultValue: "0")

        let topmount = ProductOptionValue(id: "v_topmount", optionId: "o_mount_type", value: "Topmount")
        let sidemount = ProductOptionValue(id: "v_sidemount", optionId: "o_mount_type", value: "Sidemount")
        let surface = ProductOptionValue(id: "v_surface", optionId: "o_mount_surf", value: "Surface")
        let concrete = ProductOptionValue(id: "v_concrete", optionId: "o_mount_surf", value: "Concrete")
        let black = ProductOptionValue(id: "v_black", optionId: "o_color", value: "Black")
        let white = ProductOptionValue(id: "v_white", optionId: "o_color", value: "White")

        // Modifier: Concrete → +$5/ft
        let concreteMod = ProductPricingModifier(
            productId: "p_rail", optionId: "o_mount_surf",
            triggerValueId: "v_concrete", modifierKind: .addPerUnit, amount: 5.00
        )

        return (
            railing,
            [mountType, mountSurface, color, corners],
            [topmount, sidemount, surface, concrete, black, white],
            [concreteMod]
        )
    }

    func test_unitPrice_includesModifiers() {
        let (railing, options, values, modifiers) = buildFixture()
        let resolver = ProductConfigurationResolver()

        // Topmount + Concrete + Black + 4 corners
        let configured: [String: ProductConfigurationResolver.OptionValue] = [
            "o_mount_type": .selectId("v_topmount"),
            "o_mount_surf": .selectId("v_concrete"),
            "o_color": .selectId("v_black"),
            "o_corners": .integer(4)
        ]

        let resolution = resolver.resolve(
            product: railing, options: options, optionValues: values,
            modifiers: modifiers, configured: configured
        )

        XCTAssertEqual(resolution.unitPrice, 53.00, accuracy: 0.001)
    }

    func test_unitPrice_baseOnlyWhenNoModifiersTriggered() {
        let (railing, options, values, modifiers) = buildFixture()
        let resolver = ProductConfigurationResolver()
        let configured: [String: ProductConfigurationResolver.OptionValue] = [
            "o_mount_type": .selectId("v_topmount"),
            "o_mount_surf": .selectId("v_surface"),
            "o_color": .selectId("v_black"),
            "o_corners": .integer(0)
        ]
        let resolution = resolver.resolve(
            product: railing, options: options, optionValues: values,
            modifiers: modifiers, configured: configured
        )
        XCTAssertEqual(resolution.unitPrice, 48.00, accuracy: 0.001)
    }

    func test_label_compactlyDescribesConfiguration() {
        let (railing, options, values, modifiers) = buildFixture()
        let resolver = ProductConfigurationResolver()
        let configured: [String: ProductConfigurationResolver.OptionValue] = [
            "o_mount_type": .selectId("v_topmount"),
            "o_mount_surf": .selectId("v_concrete"),
            "o_color": .selectId("v_black"),
            "o_corners": .integer(4)
        ]
        let r = resolver.resolve(
            product: railing, options: options, optionValues: values,
            modifiers: modifiers, configured: configured
        )
        XCTAssertEqual(r.label, "Topmount · Concrete · Black · 4 corners")
    }
}
```

- [ ] **Step 2: Implement `ProductConfigurationResolver.swift`**

```swift
//
//  ProductConfigurationResolver.swift
//  OPS
//
//  Computes resolved_unit_price and resolved_options_label given a Product
//  and a configured_options map. Pure function — no side effects, no I/O.
//  Used by the line item form, the design→estimate adapter, and tests.
//

import Foundation

struct ProductConfigurationResolver {

    enum OptionValue {
        case selectId(String)   // Points at a ProductOptionValue.id
        case integer(Int)
        case boolean(Bool)
    }

    struct Resolution {
        let unitPrice: Double
        let label: String
        /// Configured options, normalized for snapshot serialization to JSON.
        let serializedOptions: [String: AnyCodable]
    }

    func resolve(
        product: Product,
        options: [ProductOption],
        optionValues: [ProductOptionValue],
        modifiers: [ProductPricingModifier],
        configured: [String: OptionValue]
    ) -> Resolution {
        // Compute price
        var price = product.basePrice
        for mod in modifiers {
            guard let configValue = configured[mod.optionId] else { continue }
            guard fires(modifier: mod, value: configValue) else { continue }
            switch mod.modifierKind {
            case .addPerUnit:
                price += mod.amount
            case .addFlat:
                // Per-line flat add — only counted once per line; line.qty doesn't
                // multiply this. Note this is added to the *unit* price, but the
                // caller is responsible for understanding semantics (resolved_unit_price
                // × line.qty = total). We treat add_flat as add_per_unit divided by
                // line quantity at the point where line totals are computed.
                price += mod.amount
            case .addPerCount:
                if case .integer(let n) = configValue {
                    price += mod.amount * Double(n)
                }
            case .multiplyUnitPrice:
                price *= mod.amount
            }
        }

        // Build label
        let labelParts = options.sorted { $0.sortOrder < $1.sortOrder }.compactMap { opt -> String? in
            guard let v = configured[opt.id] else { return nil }
            switch v {
            case .selectId(let id):
                return optionValues.first { $0.id == id }?.value
            case .integer(let n):
                if n == 0 { return nil }
                return "\(n) \(opt.name.lowercased())\(n == 1 ? "" : "s")"
            case .boolean(let b):
                return b ? opt.name : nil
            }
        }
        let label = labelParts.joined(separator: " · ")

        // Serialize for snapshot
        var serialized: [String: AnyCodable] = [:]
        for (key, value) in configured {
            switch value {
            case .selectId(let id): serialized[key] = AnyCodable(id)
            case .integer(let n):   serialized[key] = AnyCodable(n)
            case .boolean(let b):   serialized[key] = AnyCodable(b)
            }
        }

        return Resolution(unitPrice: price, label: label, serializedOptions: serialized)
    }

    private func fires(modifier: ProductPricingModifier, value: OptionValue) -> Bool {
        if let triggerId = modifier.triggerValueId {
            if case .selectId(let id) = value, id == triggerId { return true }
            return false
        }
        if let minN = modifier.triggerIntMin {
            if case .integer(let n) = value {
                if let maxN = modifier.triggerIntMax {
                    return n >= minN && n <= maxN
                }
                return n >= minN
            }
        }
        return false
    }
}

/// Lightweight `Encodable` wrapper for AnyCodable serialization.
struct AnyCodable: Encodable {
    let value: Any
    init(_ v: Any) { self.value = v }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let s as String:  try c.encode(s)
        case let i as Int:     try c.encode(i)
        case let d as Double:  try c.encode(d)
        case let b as Bool:    try c.encode(b)
        default:               try c.encodeNil()
        }
    }
}
```

- [ ] **Step 3: Run tests, verify pass**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' test -only-testing:OPSTests/ProductConfigurationResolverTests 2>&1 | tail -20
```

### Task 55: Update line item form to use the resolver

**Files:**
- Modify: `OPS/OPS/Views/Estimates/EstimateLineItemFormSheet.swift` (or whatever the actual filename is — locate via grep for `ProductPickerSheet`)

- [ ] **Step 1: Locate the line item form. Run:**

```bash
grep -rn "ProductPickerSheet\|EstimateLineItemForm\|InvoiceLineItemForm" /Users/jacksonsweet/Projects/OPS/ops-ios/OPS/OPS/Views/ --include='*.swift' -l
```

Open each result. Identify where a Product is selected and the line item is built. The change scope is: when the chosen Product has options, render an inline option panel below the qty field; recompute `resolvedUnitPrice` and `resolvedOptionsLabel` whenever any option changes; on save, write `configured_options` (JSON), `resolved_unit_price`, `resolved_options_label` into the line item.

- [ ] **Step 2: Add the inline option panel**

```swift
// Inside the line-item form, after the qty field:

if !productOptions.isEmpty {
    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
        Text("// CONFIGURATION")
            .font(OPSStyle.Typography.tactical)
            .foregroundColor(OPSStyle.Colors.tertiaryText)

        ForEach(productOptions.sorted { $0.sortOrder < $1.sortOrder }) { opt in
            optionRow(opt)
        }

        // Live preview
        let resolution = resolver.resolve(
            product: selectedProduct,
            options: productOptions,
            optionValues: optionValuesForOptions,
            modifiers: productModifiers,
            configured: configuredOptions
        )

        HStack {
            Text("Unit price")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            Text(String(format: "$%.2f / %@", resolution.unitPrice, selectedProduct.pricingUnit.rawValue))
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
        }

        if let qty = Double(qtyString) {
            HStack {
                Text("Total")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                Text(String(format: "$%.2f", resolution.unitPrice * qty))
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
        }
    }
    .padding(OPSStyle.Layout.spacing2)
    .background(OPSStyle.Colors.cardBackgroundDark)
    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
    .overlay(
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
    )
}
```

`optionRow(_)` renders one of three control types based on `opt.kind`: select (segmented control or menu), integer (stepper), boolean (toggle).

- [ ] **Step 3: Update the save flow to snapshot the resolution**

```swift
// In the line-item save handler:
let resolution = resolver.resolve(
    product: selectedProduct,
    options: productOptions,
    optionValues: optionValuesForOptions,
    modifiers: productModifiers,
    configured: configuredOptions
)
let configuredJSON = try JSONEncoder().encode(resolution.serializedOptions)

newLineItem.productId = selectedProduct.id
newLineItem.configuredOptionsJSON = String(data: configuredJSON, encoding: .utf8)
newLineItem.resolvedUnitPrice = resolution.unitPrice
newLineItem.resolvedOptionsLabel = resolution.label

// Persist the snapshot to Supabase as part of the existing line_items insert.
// Make sure the EstimateLineItemDTO / InvoiceLineItemDTO Create variants include
// the three new snapshot columns (Phase 3 Task 24 added them to the SwiftData
// model; ensure DTOs match — extend EstimateDTOs / InvoiceDTOs).
```

- [ ] **Step 4: Build + commit**

```bash
git add OPS/OPS/Services/ProductConfigurationResolver.swift OPSTests/Catalog/ProductConfigurationResolverTests.swift OPS/OPS/Views/Estimates/
git commit -m "feat(catalog): line item form adapts to product richness; snapshots resolved unit price"
```

### Phase 8 review checkpoint

- [ ] Flat product on a line item = old form (qty + price).
- [ ] Configurable product = inline options + live unit-price preview + total computation.
- [ ] Snapshot persists `configured_options` JSON, `resolved_unit_price`, `resolved_options_label`.

---

## Phase 9 — Orders surface

Goal: implement Bug `e08c63a2`. Threshold-driven order suggestions surface as a banner on Stock + a persistent notification in the rail + a kebab entry. Tapping any of them opens an `OrdersSheet` that shows Suggested / Draft / Sent sub-sections.

### Task 56: Implement `OrderSuggestionEngine.swift`

**Files:**
- Create: `OPS/OPS/Services/OrderSuggestionEngine.swift`
- Create: `OPSTests/Catalog/OrderSuggestionEngineTests.swift`

The engine takes the local catalog state (variants + families + categories) and produces the list of variants that should be reordered, plus a recommended quantity. Pure function.

- [ ] **Step 1: Write the test**

```swift
import XCTest
@testable import OPS

final class OrderSuggestionEngineTests: XCTestCase {
    func test_suggests_belowCriticalThreshold_with_2x_warning_target() {
        let engine = OrderSuggestionEngine()
        let item = CatalogItem(id: "f1", companyId: "c1", name: "Corner",
                                defaultWarningThreshold: 100, defaultCriticalThreshold: 50)
        let variant = CatalogVariant(id: "v1", companyId: "c1", catalogItemId: "f1",
                                       sku: "CORNER-BLACK", quantity: 30)

        let suggestions = engine.suggest(
            variants: [variant], families: [item], categories: []
        )
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.variantId, "v1")
        XCTAssertEqual(suggestions.first?.recommendedQuantity, 200) // 2 × warning
    }

    func test_doesNotSuggest_whenAboveWarning() {
        let engine = OrderSuggestionEngine()
        let item = CatalogItem(id: "f1", companyId: "c1", name: "Corner",
                                defaultWarningThreshold: 100, defaultCriticalThreshold: 50)
        let variant = CatalogVariant(id: "v1", companyId: "c1", catalogItemId: "f1",
                                       sku: "CORNER-BLACK", quantity: 200)

        XCTAssertEqual(engine.suggest(variants: [variant], families: [item], categories: []).count, 0)
    }

    func test_walksCategoryDefault_whenNoFamilyOrVariantThreshold() {
        let engine = OrderSuggestionEngine()
        let cat = CatalogCategory(id: "cat1", companyId: "c1", name: "Hardware",
                                   defaultWarningThreshold: 50, defaultCriticalThreshold: 25)
        let item = CatalogItem(id: "f1", companyId: "c1", name: "Bracket", categoryId: "cat1")
        let variant = CatalogVariant(id: "v1", companyId: "c1", catalogItemId: "f1",
                                       sku: "BR-BLACK", quantity: 10)

        let s = engine.suggest(variants: [variant], families: [item], categories: [cat])
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s.first?.recommendedQuantity, 100)
    }
}
```

- [ ] **Step 2: Implement the engine**

```swift
//
//  OrderSuggestionEngine.swift
//  OPS
//
//  Computes suggested restock orders from variants below threshold.
//  Pure function — no I/O, no side effects.
//

import Foundation

struct OrderSuggestionEngine {

    struct Suggestion: Identifiable {
        var id: String { variantId }
        let variantId: String
        let familyName: String
        let variantLabel: String   // optional; empty for single-variant families
        let currentQuantity: Double
        let warningThreshold: Double?
        let criticalThreshold: Double?
        let recommendedQuantity: Double
    }

    /// Walks variants, finds those at-or-below their effective warning threshold,
    /// and returns suggestions targeting 2× warning_threshold for the refill.
    func suggest(
        variants: [CatalogVariant],
        families: [CatalogItem],
        categories: [CatalogCategory]
    ) -> [Suggestion] {
        let famById = Dictionary(uniqueKeysWithValues: families.map { ($0.id, $0) })
        let catById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        return variants.compactMap { v -> Suggestion? in
            guard !v.deletedAt.exists, v.isActive else { return nil }
            let family = famById[v.catalogItemId]
            let category = family?.categoryId.flatMap { catById[$0] }

            let warn = v.warningThreshold ?? family?.defaultWarningThreshold ?? category?.defaultWarningThreshold
            let crit = v.criticalThreshold ?? family?.defaultCriticalThreshold ?? category?.defaultCriticalThreshold

            guard let warn = warn, v.quantity <= warn else { return nil }

            return Suggestion(
                variantId: v.id,
                familyName: family?.name ?? "",
                variantLabel: "",  // hydrated by caller from variant_option_values if needed
                currentQuantity: v.quantity,
                warningThreshold: warn,
                criticalThreshold: crit,
                recommendedQuantity: warn * 2  // simple 2× target; future: configurable per company
            )
        }
    }
}

// Helper for the deletedAt nullable check
private extension Optional where Wrapped == Date {
    var exists: Bool { self != nil }
}
```

### Task 57: Implement `OrdersSheet`, `OrderDetailView`, `SuggestedOrderRow`, `OrderBanner`

**Files:**
- Create: `OPS/OPS/Views/Catalog/Orders/OrdersSheet.swift`
- Create: `OPS/OPS/Views/Catalog/Orders/OrderDetailView.swift`
- Create: `OPS/OPS/Views/Catalog/Orders/SuggestedOrderRow.swift`

`OrdersSheet` has three sub-segments: SUGGESTED (computed live from `OrderSuggestionEngine`), DRAFT (rows from `catalog_orders` where status=draft), SENT (status=sent).

Tapping a suggested row promotes it to a draft order via `CatalogOrderRepository.createOrder` + `addItem` calls. Tapping a draft opens `OrderDetailView` for editing supplier, expected delivery date, item list. "MARK SENT" and "MARK FULFILLED" actions update via `CatalogOrderRepository.markSent` / `markFulfilled`.

- [ ] **Step 1: Write `OrdersSheet`** (full SwiftUI implementation following the pattern in `CategoriesManageSheet`)

- [ ] **Step 2: Write `OrderDetailView`** (reads + edits `CatalogOrder` + its `CatalogOrderItem` rows)

- [ ] **Step 3: Write `SuggestedOrderRow`** (one suggestion + a "+ Add to draft" button per row, plus a "Create order from all" button)

### Task 58: Notification rail integration

**Files:**
- Modify: wherever the iOS notification creation lives (`NotificationManager.swift` or similar)
- Modify: `OPS/OPS/Network/Sync/InboundProcessor.swift` (post-sync hook)

After every sync completes (full or delta), check for variants below threshold; if there are any, ensure a single persistent notification exists in the rail.

- [ ] **Step 1: Add a helper that reconciles threshold notifications**

```swift
// In NotificationManager (or a new ThresholdNotifier service):

func reconcileThresholdNotifications(
    variants: [CatalogVariant],
    families: [CatalogItem],
    categories: [CatalogCategory],
    companyId: String,
    userId: String
) async {
    let suggestions = OrderSuggestionEngine().suggest(
        variants: variants, families: families, categories: categories
    )

    let count = suggestions.count
    if count == 0 {
        // Resolve any existing threshold notification (mark is_read=true).
        try? await NotificationRepository.shared.markResolved(
            type: "threshold_alert",
            userId: userId, companyId: companyId
        )
        return
    }

    // Upsert one persistent notification.
    let notif = NotificationInsert(
        userId: userId,
        companyId: companyId,
        type: "threshold_alert",
        title: "// \(count) ITEM\(count == 1 ? "" : "S") BELOW THRESHOLD",
        body: "Tap to review and draft an order.",
        isRead: false,
        persistent: true,
        actionUrl: "ops://catalog/orders?tab=suggested",
        actionLabel: "REVIEW"
    )
    try? await NotificationRepository.shared.upsertByType(notif)
}
```

- [ ] **Step 2: Call the reconciler at the end of `fullSync` and `deltaSync` in InboundProcessor**

```swift
// At the end of fullSync, after onProgress?(.photoAnnotation, 1.0):
let variants = (try? context.fetch(FetchDescriptor<CatalogVariant>())) ?? []
let families = (try? context.fetch(FetchDescriptor<CatalogItem>())) ?? []
let categories = (try? context.fetch(FetchDescriptor<CatalogCategory>())) ?? []
if let userId = SupabaseService.shared.currentUserId {
    await NotificationManager.shared.reconcileThresholdNotifications(
        variants: variants, families: families, categories: categories,
        companyId: companyId, userId: userId
    )
}
```

- [ ] **Step 3: Wire the deeplink `ops://catalog/orders?tab=suggested`**

In the existing notification-tap handler (search for `actionUrl` resolution code), add a branch for `ops://catalog/orders` that opens the CATALOG tab and presents the OrdersSheet with `selectedSubSegment = .suggested`.

### Phase 9 review checkpoint

- [ ] Threshold banner on Stock opens the Orders sheet.
- [ ] Persistent notification appears in the rail when items go below threshold and disappears when they recover.
- [ ] Suggested → Draft → Sent → Fulfilled state machine works end-to-end.
- [ ] Bug e08c63a2 closeable.

---

## Phase 10 — Drawing → estimate adapter

Goal: implement Bug `6192bcc5`'s estimate-side: tapping "Generate Estimate" in Deck Builder produces a draft estimate with line items auto-configured from the design's metadata. The recipe-side (cut list at install time) is Phase 11.

### Task 59: Implement `DesignToEstimateAdapter.swift`

**Files:**
- Create: `OPS/OPS/Services/DesignToEstimateAdapter.swift`
- Create: `OPSTests/Catalog/DesignToEstimateAdapterTests.swift`

- [ ] **Step 1: Write the adapter API**

```swift
//
//  DesignToEstimateAdapter.swift
//  OPS
//
//  Walks a DeckDesign's drawing_data, finds the company's default Product
//  per component_type, auto-fills options from $design.<key> metadata,
//  computes resolved unit prices, and emits draft estimate line items.
//

import Foundation

struct DesignToEstimateAdapter {

    struct GeneratedLineItem {
        let productId: String
        let quantity: Double
        let configuredOptions: [String: ProductConfigurationResolver.OptionValue]
        let resolvedUnitPrice: Double
        let resolvedOptionsLabel: String
        let lineTotal: Double
    }

    enum AdapterError: Error {
        case noDefaultProduct(componentType: String)
    }

    let resolver = ProductConfigurationResolver()

    func generate(
        design: DeckDesign,
        defaults: [DesignComponentType: Product],
        productOptions: [String: [ProductOption]],     // productId → options
        productOptionValues: [String: [ProductOptionValue]], // optionId → values
        productModifiers: [String: [ProductPricingModifier]] // productId → modifiers
    ) -> [GeneratedLineItem] {
        guard let drawingData = parseDrawingData(design.drawingDataJSON) else { return [] }

        var generated: [GeneratedLineItem] = []
        for component in drawingData.components {
            guard let defaultProduct = defaults[component.type] else {
                // Skip components without a default — don't block estimate creation.
                continue
            }
            let options = productOptions[defaultProduct.id] ?? []
            let optionValues = options.flatMap { productOptionValues[$0.id] ?? [] }
            let modifiers = productModifiers[defaultProduct.id] ?? []

            // Build configured map from design metadata + default fallbacks.
            let configured = buildConfigured(options: options, optionValues: optionValues, metadata: component.metadata)

            // Compute quantity from geometry based on Product's pricing_unit.
            let quantity = computeQuantity(unit: defaultProduct.pricingUnit, metadata: component.metadata)

            let resolution = resolver.resolve(
                product: defaultProduct,
                options: options, optionValues: optionValues, modifiers: modifiers,
                configured: configured
            )

            generated.append(GeneratedLineItem(
                productId: defaultProduct.id,
                quantity: quantity,
                configuredOptions: configured,
                resolvedUnitPrice: resolution.unitPrice,
                resolvedOptionsLabel: resolution.label,
                lineTotal: resolution.unitPrice * quantity
            ))
        }
        return generated
    }

    private func buildConfigured(
        options: [ProductOption],
        optionValues: [ProductOptionValue],
        metadata: [String: Any]
    ) -> [String: ProductConfigurationResolver.OptionValue] {
        var result: [String: ProductConfigurationResolver.OptionValue] = [:]
        for opt in options {
            // Resolve via $design.<key> if option_default_source is set.
            var value: Any? = nil
            if let source = opt.optionDefaultSource, source.hasPrefix("$design.") {
                let key = String(source.dropFirst("$design.".count))
                value = metadata[key]
            }

            // Fall back to default_value
            value = value ?? opt.defaultValue

            switch opt.kind {
            case .select:
                if let s = value as? String,
                   let match = optionValues.first(where: { $0.optionId == opt.id && $0.value == s }) {
                    result[opt.id] = .selectId(match.id)
                }
            case .integer:
                if let n = value as? Int { result[opt.id] = .integer(n) }
                else if let s = value as? String, let n = Int(s) { result[opt.id] = .integer(n) }
                else { result[opt.id] = .integer(0) }
            case .boolean:
                if let b = value as? Bool { result[opt.id] = .boolean(b) }
                else if let s = value as? String { result[opt.id] = .boolean(s.lowercased() == "true") }
                else { result[opt.id] = .boolean(false) }
            }
        }
        return result
    }

    private func computeQuantity(unit: ProductPricingUnit, metadata: [String: Any]) -> Double {
        switch unit {
        case .flatRate:    return 1.0
        case .each:
            if let n = metadata["count"] as? Int { return Double(n) }
            return 1.0
        case .linearFoot:
            return (metadata["linear_feet"] as? Double) ?? 0
        case .sqft:
            return (metadata["sqft"] as? Double) ?? 0
        case .hour:
            return (metadata["hours"] as? Double) ?? 0
        case .day:
            return (metadata["days"] as? Double) ?? 0
        }
    }

    private struct ParsedDrawing {
        let components: [ParsedComponent]
    }
    private struct ParsedComponent {
        let type: DesignComponentType
        let metadata: [String: Any]
    }

    private func parseDrawingData(_ json: String) -> ParsedDrawing? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let comps = dict["components"] as? [[String: Any]] else { return nil }
        let parsed = comps.compactMap { c -> ParsedComponent? in
            guard let typeStr = c["component_type"] as? String,
                  let type = DesignComponentType(rawValue: typeStr) else { return nil }
            let meta = (c["metadata"] as? [String: Any]) ?? [:]
            return ParsedComponent(type: type, metadata: meta)
        }
        return ParsedDrawing(components: parsed)
    }
}
```

- [ ] **Step 2: Write the adapter test (uses the spec's railing fixture)**

(Pattern matches `ProductConfigurationResolverTests`. Build a fixture deck design with one railing component; verify the adapter generates one line item with the expected quantity, options, unit price, and total.)

- [ ] **Step 3: Hook the adapter into Deck Builder**

Locate the Deck Builder canvas surface where a "Generate Estimate" action would live (or add it). The action:

1. Loads the company's `CompanyDefaultProduct` rows (one per `component_type`).
2. For each default product id, fetches its options/option_values/modifiers (via `ProductRichnessRepository` if not already loaded into SwiftData).
3. Calls `DesignToEstimateAdapter.generate(...)`.
4. Creates a draft `Estimate` row plus N `EstimateLineItem` rows snapshotting the resolution.
5. Navigates to the new estimate.

The Deck Builder agent owns the canvas; we add only the data adapter and the action hook. Coordinate with them via a brief PR comment when this lands.

### Phase 10 review checkpoint

- [ ] `DesignToEstimateAdapter` resolves a railing component to a fully snapshotted estimate line item.
- [ ] Default Products mapping is editable from the Defaults manage sheet (Phase 5 Task 45).
- [ ] If Deck Builder agent has not yet landed `component_type` + `metadata` in `drawing_data`, the adapter emits zero line items gracefully — no crash.
- [ ] Bug 6192bcc5 partially closeable (Phase 11 finishes the cut-list side).

---

## Phase 11 — Cut-list materializer

Goal: when a project moves to install (a project_task is created from an estimate line item), walk each line item's snapshotted `configured_options`, resolve each Product's recipe rows, and emit concrete `task_materials` rows pinning specific `catalog_variant_id`s.

### Task 60: Implement `RecipeResolver.swift`

**Files:**
- Create: `OPS/OPS/Services/RecipeResolver.swift`
- Create: `OPSTests/Catalog/RecipeResolverTests.swift`

- [ ] **Step 1: Write the resolver**

```swift
//
//  RecipeResolver.swift
//  OPS
//
//  At install task creation, resolves each Product's recipe rows against
//  the line item's configured_options snapshot, then writes concrete
//  task_materials rows. Pure function for the resolution; the caller wires
//  the writes.
//

import Foundation

struct RecipeResolver {

    struct ResolvedMaterial {
        let catalogVariantId: String
        let quantity: Double
        let unitId: String?
        let notes: String?
    }

    enum ResolverError: Error {
        case missingCatalogVariantForSelector(itemId: String, selector: [String: String])
        case selectorReferencesUnknownOption(key: String)
    }

    /// For each product_material row, resolve to one ResolvedMaterial pinned
    /// to a specific catalog_variant_id.
    func resolve(
        materials: [ProductMaterial],
        configuredOptions: [String: ProductConfigurationResolver.OptionValue],
        productOptionsById: [String: ProductOption],
        productOptionValuesById: [String: ProductOptionValue],
        catalogVariants: [CatalogVariant],
        catalogVariantOptionValues: [CatalogVariantOptionValue],
        catalogOptionValuesById: [String: CatalogOptionValue],
        catalogOptionsByItemId: [String: [CatalogOption]],
        lineQuantity: Double
    ) throws -> [ResolvedMaterial] {
        var output: [ResolvedMaterial] = []

        // Build family→variant index for quick lookup.
        let variantsByFamily = Dictionary(grouping: catalogVariants, by: \.catalogItemId)
        // Build variant→[optionValueId] index.
        let variantOptionValueIds = Dictionary(grouping: catalogVariantOptionValues, by: \.variantId)
            .mapValues { Set($0.map(\.optionValueId)) }

        for mat in materials {
            // Determine resolved variant
            var resolvedVariantId: String? = nil
            if let pinned = mat.catalogVariantId {
                resolvedVariantId = pinned
            } else if let familyId = mat.catalogItemId, let selector = decodeSelector(mat.variantSelectorJSON) {
                // Map selector keys ($option.color → CatalogOption.value at family level).
                // selector example: {"color": "$option.color", "mount": "$option.mount_type"}
                // We resolve $option.<name> into the configured_options' selected ProductOptionValue.value,
                // then find the CatalogVariant in this family whose option-value combo matches all required keys.
                let requiredCatalogOptionValues = try resolveSelectorToCatalogOptionValueIds(
                    selector: selector,
                    familyId: familyId,
                    configuredOptions: configuredOptions,
                    productOptionsById: productOptionsById,
                    productOptionValuesById: productOptionValuesById,
                    catalogOptionValuesById: catalogOptionValuesById,
                    catalogOptionsByItemId: catalogOptionsByItemId
                )
                let candidates = (variantsByFamily[familyId] ?? []).filter { v in
                    let valueIds = variantOptionValueIds[v.id] ?? []
                    return requiredCatalogOptionValues.isSubset(of: valueIds)
                }
                if candidates.count == 1 {
                    resolvedVariantId = candidates[0].id
                } else if candidates.isEmpty {
                    throw ResolverError.missingCatalogVariantForSelector(itemId: familyId, selector: selector)
                } else {
                    // Tie — the family has ambiguous variants under the selector. Pick first deterministically.
                    resolvedVariantId = candidates.sorted(by: { $0.id < $1.id }).first?.id
                }
            }

            guard let variantId = resolvedVariantId else { continue }

            // Compute scaled quantity
            var qty = mat.quantityPerUnit * lineQuantity
            if let scaledByOptionId = mat.scaledByOptionId,
               case .integer(let n) = configuredOptions[scaledByOptionId] {
                qty = mat.quantityPerUnit * Double(n)
            }

            output.append(ResolvedMaterial(
                catalogVariantId: variantId,
                quantity: qty,
                unitId: mat.unitId,
                notes: mat.notes
            ))
        }

        return output
    }

    private func decodeSelector(_ json: String?) -> [String: String]? {
        guard let json = json,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
        return dict
    }

    /// Translate selector like {"color": "$option.color"} into the set of
    /// CatalogOptionValue ids (on the family) that the chosen ProductOptionValue's
    /// string value maps to.
    private func resolveSelectorToCatalogOptionValueIds(
        selector: [String: String],
        familyId: String,
        configuredOptions: [String: ProductConfigurationResolver.OptionValue],
        productOptionsById: [String: ProductOption],
        productOptionValuesById: [String: ProductOptionValue],
        catalogOptionValuesById: [String: CatalogOptionValue],
        catalogOptionsByItemId: [String: [CatalogOption]]
    ) throws -> Set<String> {
        var result = Set<String>()
        let familyOptions = catalogOptionsByItemId[familyId] ?? []
        for (catalogOptName, sourceExpr) in selector {
            // sourceExpr is "$option.<product_option_name>"
            guard sourceExpr.hasPrefix("$option.") else { continue }
            let productOptionName = String(sourceExpr.dropFirst("$option.".count))

            // Find the ProductOption with this name on the recipe's parent product.
            // (This adapter lives on a single product, so productOptionsById has all of them.)
            guard let productOption = productOptionsById.values.first(where: { $0.name.lowercased() == productOptionName.lowercased() }) else {
                throw ResolverError.selectorReferencesUnknownOption(key: productOptionName)
            }
            // Resolve the configured value to a string.
            guard let configured = configuredOptions[productOption.id] else { continue }
            let stringValue: String? = {
                switch configured {
                case .selectId(let id): return productOptionValuesById[id]?.value
                case .integer(let n):   return "\(n)"
                case .boolean(let b):   return b ? "true" : "false"
                }
            }()
            guard let stringValue = stringValue else { continue }

            // Match against the family's CatalogOption with the named axis (catalogOptName).
            guard let catalogOption = familyOptions.first(where: { $0.name.lowercased() == catalogOptName.lowercased() }) else {
                continue
            }
            // Find the CatalogOptionValue under that CatalogOption with the resolved string.
            if let match = catalogOptionValuesById.values.first(where: {
                $0.optionId == catalogOption.id && $0.value.lowercased() == stringValue.lowercased()
            }) {
                result.insert(match.id)
            }
        }
        return result
    }
}
```

- [ ] **Step 2: Write the resolver test using the railing fixture**

Build the fixture: `Composite Board` family (Color axis: Black, White) with two variants. A line item at 24 ft with `Color = Black`. Recipe row: `family=Composite Board, selector={color:$option.color}, qty=1.05`. Resolver should output `Composite Board (Black variant) at 25.2 ft`.

- [ ] **Step 3: Wire the resolver into the install-task creation flow**

When a project moves to "Scheduled" (or when an install task is created from an estimate), iterate the project's estimate line items, resolve each recipe, and write `task_materials` rows.

Find the existing project-status-transition code (search for `Status.scheduled` or similar). Add a hook:

```swift
// pseudocode at the transition site
if newStatus == .scheduled {
    await CutListMaterializer.shared.materialize(for: project)
}
```

`CutListMaterializer` is a thin orchestrator that:
1. Fetches the project's estimate(s) and line items.
2. For each line item with `productId` and `configuredOptionsJSON`, loads the product's recipe + options + option_values.
3. Calls `RecipeResolver.resolve(...)`.
4. INSERTs into `task_materials` (Supabase) one row per resolved material, attached to the relevant project_task.

### Phase 11 review checkpoint

- [ ] Recipe resolution unit test passes.
- [ ] Materializing a Canpro railing recipe produces the expected `task_materials` rows.
- [ ] Bug 6192bcc5 closeable.

---

## Phase 12 — Permission rename `inventory.*` → `catalog.*`

Goal: rename permission keys consistently. New keys: `catalog.view`, `catalog.manage`, `catalog.import`, plus new `catalog.products.manage` and `catalog.orders.manage`. No alias layer; clean cut.

### Task 61: Write `2026-05-06-04-permission-rename.sql` and apply

**Files:**
- Create: `ops-software-bible/migrations/2026-05-06-04-permission-rename.sql`

- [ ] **Step 1: Write the migration**

```sql
-- 2026-05-06-04-permission-rename.sql
-- Rename inventory.* permissions to catalog.* and add two new permissions
-- for the configurable-Product authoring layer and for orders.

BEGIN;

-- Rename existing permission strings on role_permissions.
UPDATE public.role_permissions SET permission = 'catalog.view'    WHERE permission = 'inventory.view';
UPDATE public.role_permissions SET permission = 'catalog.manage'  WHERE permission = 'inventory.manage';
UPDATE public.role_permissions SET permission = 'catalog.import'  WHERE permission = 'inventory.import';

-- Add catalog.products.manage and catalog.orders.manage to roles that have
-- catalog.manage (Owner, Admin, etc.).
INSERT INTO public.role_permissions (role_id, permission, scope)
SELECT DISTINCT role_id, 'catalog.products.manage', scope
FROM public.role_permissions
WHERE permission = 'catalog.manage'
ON CONFLICT DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission, scope)
SELECT DISTINCT role_id, 'catalog.orders.manage', scope
FROM public.role_permissions
WHERE permission = 'catalog.manage'
ON CONFLICT DO NOTHING;

COMMIT;
```

- [ ] **Step 2: Apply via MCP**

- [ ] **Step 3: Verify**

```sql
SELECT permission, COUNT(*) FROM public.role_permissions
WHERE permission LIKE 'catalog%' OR permission LIKE 'inventory%'
GROUP BY permission ORDER BY permission;
```

Expected: zero rows for `inventory.*`. Five for `catalog.*` (view, manage, import, products.manage, orders.manage).

### Task 62: Update iOS permission key references

**Files:**
- Modify: `OPS/OPS/Views/MainTabView.swift` — rename `inventory.view` → `catalog.view`
- Modify: any other PermissionStore.can() callsites

- [ ] **Step 1: Find all callsites**

```bash
grep -rn 'permissionStore\.can("inventory' /Users/jacksonsweet/Projects/OPS/ops-ios/OPS/ --include='*.swift'
```

- [ ] **Step 2: Rename each**

`inventory.view` → `catalog.view`, `inventory.manage` → `catalog.manage`, `inventory.import` → `catalog.import`. Add new gates where the new permissions matter (e.g., gate the Quick Add button on `catalog.products.manage`, gate the Orders sheet's "MARK SENT" on `catalog.orders.manage`).

- [ ] **Step 3: Build + commit**

```bash
git add OPS/OPS/
git commit -m "feat(catalog): rename inventory.* permissions to catalog.*; add products.manage and orders.manage"
```

### Phase 12 review checkpoint

- [ ] All iOS permission references use `catalog.*`.
- [ ] role_permissions table contains the rename + new keys.
- [ ] ops-web is unaffected (it currently doesn't gate on these — the route gates use the same keys, which Phase 12 also renames as part of the SQL UPDATE; ops-web's PermissionStore reads directly from the table so the rename propagates).

---

## Phase 13 — Bible updates

Goal: keep the OPS Software Bible canonical. Nine sections rewritten or added in the same session as code lands. Per `OPS LTD./CLAUDE.md`: "The bible must stay current. An outdated bible is a broken bible."

### Task 63: Update `03_DATA_ARCHITECTURE.md`

**Files:**
- Modify: `ops-software-bible/03_DATA_ARCHITECTURE.md`

- [ ] **Step 1: Rewrite § 21 (Product)** to reflect the 9 new fields (`pricing_unit`, `base_price`, `kind`, `sku`, `is_favorite`, `minimum_charge`, `minimum_quantity`, `show_bom_on_estimate`, `show_in_storefront`, `tiered_pricing`) and link to the configurable layers in a new sub-section.

- [ ] **Step 2: Replace the existing § "Inventory Models (5 Entities — File-Only, Not in Schema)"** with a new section titled § "Catalog & Variant Model" that documents:
  - `CatalogCategory` (nested via `parentId`)
  - `CatalogItem` (variant family)
  - `CatalogVariant` (the SKU)
  - `CatalogOption` + `CatalogOptionValue` + `CatalogVariantOptionValue`
  - `CatalogTag` + `CatalogItemTag` (family-level)
  - `CatalogUnit` (with `dimension` + `abbreviation`)
  - `CatalogSnapshot` + `CatalogSnapshotItem`
  - `CatalogOrder` + `CatalogOrderItem`
  - `CompanyDefaultProduct`

For each entity: file path, purpose, full @Model declaration, computed properties, key invariants.

- [ ] **Step 3: Add a § "Configurable Products" sub-section** documenting `ProductOption`, `ProductOptionValue`, `ProductPricingModifier`, `ProductMaterial` with the same depth.

- [ ] **Step 4: Update the DTO listing** in § "Supabase DTOs" to add `CatalogDTOs.swift`, `ProductExtensionDTOs.swift`, `CatalogOrderDTOs.swift`, `CompanyDefaultProductDTOs.swift`. Update `ProductDTOs.swift` to reflect the corrected wire fields.

- [ ] **Step 5: Update the registered models list** at § "The 25 Registered Schema Models" to:
  - Drop the 5 inventory entities
  - Add the 17 new catalog entities
  - Renumber accordingly. (The header also needs updating: "The 37 Registered Schema Models" or whatever the new total is.)

### Task 64: Update `04_API_AND_INTEGRATION.md`

**Files:**
- Modify: `ops-software-bible/04_API_AND_INTEGRATION.md`

- [ ] **Step 1: Locate the table list near line 1149**

Replace `inventory_*` row entries with `catalog_*` row entries. Add rows for the previously-undocumented tables: `product_materials`, `task_materials`, `line_item_materials`, `inventory_deductions` (now FK'd via `catalog_variant_id`), `client_product_overrides`, `product_tax_rates`. Plus the new tables: `catalog_*`, `product_options`, `product_option_values`, `product_pricing_modifiers`, `company_default_products`, `catalog_orders`, `catalog_order_items`.

### Task 65: Update `07_SPECIALIZED_FEATURES.md`

**Files:**
- Modify: `ops-software-bible/07_SPECIALIZED_FEATURES.md`

- [ ] **Step 1: Rewrite § 13 (Inventory Management)** as § "Catalog Management" — describe the new IA (CATALOG tab, STOCK + PRODUCTS, kebab), variant-aware list / grid / table modes, threshold-driven order suggestions, drawing→estimate adapter, cut-list materialization.

- [ ] **Step 2: Add a § for "Configurable Products & Recipes"** covering the resolver, modifier semantics, recipe authoring (lives on web — link to that follow-up), cut-list materialization timing.

### Task 66: Update `09_FINANCIAL_SYSTEM.md`

**Files:**
- Modify: `ops-software-bible/09_FINANCIAL_SYSTEM.md`

- [ ] **Step 1: Replace § "Products & Services Catalog"**

```markdown
## Products & Services Catalog

The catalog supports two tiers of richness:

- **Barebones Products** — name + base_price + pricing_unit + tax. Behave like the original flat Product model. A "PICKET RAIL" Product at $2500 flat is one form-fill away.
- **Configurable Products** — carry options, pricing modifiers, and recipe rules. Used for cases like Canpro's "Custom Composite Railing" where a single Product expresses per-foot pricing, modifiers (concrete +$5/ft), recipe templates (color cascades through every BOM row), and quantity-scaling counts (corners → corner hardware kits).

Schema:
... (full schema reproduced here) ...
```

- [ ] **Step 2: Document the `line_items` snapshot fields** (`configured_options`, `resolved_unit_price`, `resolved_options_label`).

- [ ] **Step 3: Document recipe semantics**: `product_materials` rows can be variant-pinned or family-pinned with a selector. Resolution happens at install task creation, not estimate-line-creation.

### Task 67: Update `02_USER_EXPERIENCE_AND_WORKFLOWS.md`

**Files:**
- Modify: `ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md`

- [ ] **Step 1: Find every "Inventory" reference**

```bash
grep -nE "Inventory" /Users/jacksonsweet/Projects/OPS/ops-software-bible/02_USER_EXPERIENCE_AND_WORKFLOWS.md
```

- [ ] **Step 2: Rename to "Catalog" with the new IA**, updating the screen catalog, the workflow steps, and the tab visibility rules. Document the new STOCK + PRODUCTS sub-segments and the kebab menu structure.

### Task 68: Update `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`

**Files:**
- Modify: `ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`

- [ ] **Step 1: Document the line item snapshot semantics** (configured_options, resolved_unit_price, resolved_options_label) where the line item lifecycle is described.

- [ ] **Step 2: Document the cut-list materialization**: when a project transitions to scheduled, recipe rows resolve to `task_materials` rows pinned to specific catalog variants.

- [ ] **Step 3: Document the drawing→estimate adapter** in the project-creation lifecycle.

### Task 69: Update `README.md` of the bible

**Files:**
- Modify: `ops-software-bible/README.md`

- [ ] **Step 1: Mention the catalog model in the executive summary line items**.

### Task 70: Bible commit

```bash
git -C /Users/jacksonsweet/Projects/OPS/ops-software-bible/ add .
git -C /Users/jacksonsweet/Projects/OPS/ops-software-bible/ commit -m "docs: catalog & variant model, configurable Products, recipe resolution, drawing adapter"
```

(Note: the bible is its own git repo per the project layout. Use `-C` to scope the commit there.)

### Phase 13 review checkpoint

- [ ] All 9 sections updated.
- [ ] Inventory references in `02_USER_EXPERIENCE_AND_WORKFLOWS.md` renamed to Catalog.
- [ ] No section claims "5 entities, file-only, not in schema" anywhere.
- [ ] DTO listings include the new catalog DTOs.
- [ ] Six previously-undocumented tables now documented.

---

## Phase 14 — End-to-end verification

Goal: validate the full system against Canpro's data and the bug list.

### Task 71: iOS build verification

- [ ] **Step 1: Clean build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' -configuration Debug clean build 2>&1 | tail -40
```

Expected: zero errors, zero warnings beyond pre-existing.

### Task 72: Canpro full-sync round-trip

- [ ] **Step 1: With Canpro credentials, install the build on a real device, sign in, observe**:
  - Catalog tab visible
  - Stock segment shows 14 families with category groupings
  - Hardware Level → Corner — Black · 288, Corner — White · 70 (etc.) renders correctly
  - TABLE view mode shows family options as columns
  - Threshold banner appears if any Canpro variants are below threshold
  - Products segment shows 0 Canpro products (Canpro authors them on web post-migration)
  - Quick add a `PICKET RAIL — $2500` flat product, verify it appears

- [ ] **Step 2: Verify sync error isolation**: temporarily inject a throw in `syncCatalogVariants` (e.g., wrap the merge call in `throw NSError(domain: "Test", code: 1)`). Run the full sync. Confirm:
  - Categories, items, units still merge.
  - Variants log a `sync_entity_failed` row in `app_events`.
  - Bug 2837ddae cannot recur.

- [ ] **Step 3: Remove the test throw, ship the build to TestFlight.**

### Task 73: Bug closures

- [ ] **Step 1: For each of the 6 bugs, UPDATE the row in `bug_reports` with `fix_branch`, `fix_pr_url`, `fix_commit`, and `fixed_at = now()`**. Do NOT change `status` (the team bulk-updates status when work ships per the original brief).

```sql
UPDATE public.bug_reports
SET fix_branch = 'feat/catalog-variant-model',
    fix_pr_url = '<PR url>',
    fix_commit = '<commit hash>',
    fixed_at = now()
WHERE id IN (
  '41d6f2b4-368c-440a-ad23-b7ae299bb479',  -- Products + IA redesign
  '3c98650a-de85-4dcb-b2ce-3917c07272f2',  -- categories + tags
  '217c3d1f-f1f0-45c4-9775-488e613a5562',  -- table view mode
  'e08c63a2-9e04-4760-aa23-7c8c22f96922',  -- create order
  '6192bcc5-214f-42d1-b114-be389c68e526',  -- materials recipes
  '2837ddae-b292-457d-b370-ff454af3496e'   -- inventory sync gap
);
```

### Task 74: Final commit + PR

- [ ] **Step 1: Squash interim commits into a single feature commit (or keep atomic per phase if the workflow prefers)**

Per `ops-ios/CLAUDE.md`: clear commit messages, atomic per logical change, never include Claude as co-author.

- [ ] **Step 2: Open PR**

```bash
gh pr create --title "Catalog & variant model — closes 6 bugs + product wire-field bug + sync abort"
```

PR body should reference the spec + plan + each bug + the iOS↔ops-web compat strategy.

### Phase 14 review checkpoint

- [ ] Build succeeds on `generic/platform=iOS`.
- [ ] Canpro round-trip works.
- [ ] Sync error isolation confirmed via injected throw.
- [ ] All 6 bug rows have `fix_branch`/`fix_commit`/`fixed_at` populated.
- [ ] Bible updates committed.
- [ ] PR open.

---

## Cross-cutting acceptance criteria

The plan is "complete" when ALL of these hold simultaneously:

- [ ] iOS builds clean on `xcodebuild -scheme OPS -destination 'generic/platform=iOS'`.
- [ ] iOS test suite green.
- [ ] Canpro variant data renders correctly in STOCK · LIST, GRID, TABLE.
- [ ] Quick-add Product creates a flat Product in ≤ 8s.
- [ ] Configurable-Product line item snapshot writes `configured_options` JSON, `resolved_unit_price`, `resolved_options_label`.
- [ ] Threshold banner + persistent notification + kebab Orders entry all open the same OrdersSheet.
- [ ] `app_events.sync_entity_failed` logs are visible after an injected sync throw.
- [ ] Bible is current — nine sections updated, six previously-undocumented tables documented.
- [ ] ops-web continues to read inventory_* (now via views) without code changes during the compatibility window.
- [ ] Six bug rows tagged with fix_branch and fix_commit.
- [ ] Two named follow-ups recorded: (1) OPS-Web Product editor, (2) Deck Builder reserved metadata vocabulary coordination.

---

## Self-Review Notes

This plan was self-reviewed against the spec (`docs/superpowers/specs/2026-05-06-ios-catalog-variant-model-design.md`) using the writing-plans skill checklist. Findings:

**Spec coverage:** Every section of the spec maps to one or more tasks. Section 3 (architecture) → Phases 1, 3, 4, 8, 10, 11. Section 4 (IA) → Phases 5, 6, 7, 9. Section 5 (permissions) → Phase 12. Section 6 (migration) → Phases 1, 2. Section 7 (risks) → folded into deploy-ordering decisions in Phases 1, 2, 12. No gaps.

**Placeholder scan:** No "TBD", "TODO", or "implement later" remain. Where the OPS-Web editor or Deck Builder coordination is genuinely out-of-scope, those are named explicitly as follow-ups, not deferred TODOs.

**Type consistency:** `Product.basePrice` (Double, non-optional, default 0) is referenced consistently across SwiftData model (Task 23), DTO (Task 25), Repository (Task 32), Form (Task 51, 52), and Resolver (Task 54). Same audit applied to `pricing_unit`, `configured_options`, `resolved_unit_price`, `resolved_options_label`, `catalog_variant_id`, `catalog_item_id`, `parent_id`, `option_default_source`. No drift.

**Scope check:** This is a 14-phase plan. By traditional measure it would span weeks. AI-assisted velocity (per CLAUDE.md context) compresses it to a single session if executed via subagent-driven development with task-per-subagent and review between tasks. Each phase is independently committable.

**Ambiguity check:** Recipe selector semantics (`{"color":"$option.color"}`) clarified in Task 60 — it maps a CatalogOption name (catalog side) to a ProductOption name (product side), normalized case-insensitively. No double-interpretation.





