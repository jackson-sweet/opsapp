# Backfill — phase 2 — create missing catalog_categories, then link products

**File:** `2026-05-10-backfill-products-category-id-phase-2.sql`

**Status:** NOT APPLIED. Awaiting user approval before it touches the
database. This file is a write — it INSERTs new rows into
`catalog_categories` and UPDATEs `products.category_id`.

## Why this exists

Phase 1 (`2026-05-08-backfill-products-category-id.sql`) only updated
products whose legacy `category` text already had a matching row in
`catalog_categories`. When phase 1 ran in production it updated **0
rows** — 15 legacy products have category text ("Materials", "Labor",
"Fasteners", "Lumber") that does not match any existing catalog row in
their company.

Those 15 products are still stuck on the free-text column. They render
fine in the legacy code path, but they don't participate in catalog-aware
queries (filter by category, category-driven defaults, future tightening
of the FK).

Phase 2 closes that gap.

## What it does

Wrapped in a single `BEGIN; ... COMMIT;` for atomicity.

**STEP A — INSERT one `catalog_categories` row per distinct
`(company_id, trim(category))` pair where no live match already exists.**

- Distinct on `(company_id, trim(category_name))` — multiple products
  with the same category name in the same company collapse to one row.
- Match comparison is case-insensitive (`LOWER(TRIM(...))`) so
  "Materials" and "materials" become one row, but the inserted row
  preserves the original casing from the trimmed product text.
- Skips companies where a live (non-deleted) `catalog_categories` row
  with that name already exists.
- `sort_order` is `MAX(existing sort_order in company) + 1`, falling
  back to `0` when the company has no categories yet. Each new row
  appended to the end of the company's list.
- `default_warning_threshold` and `default_critical_threshold` left
  `NULL` — matches the empty-state default that the iOS Add Category
  sheet uses today.
- `color_hex`, `parent_id` also `NULL`. Users can rename / recolor /
  reparent these rows in the catalog UI after the backfill.
- `id` is fresh UUID; `created_at` and `updated_at` are `NOW()`.

**STEP B — Re-run the phase 1 UPDATE.** Same SQL as
`2026-05-08-backfill-products-category-id.sql`. With the new rows now
in place, this will link the 15 products to their categories.

## What it leaves alone

- Products whose `category_id` is already populated. The `WHERE
  p.category_id IS NULL` guard protects them.
- Products with `NULL` or empty `category` text. Nothing to match.
- Soft-deleted products (`deleted_at IS NOT NULL`) are excluded — no
  point creating a category for a deleted row.
- Soft-deleted `catalog_categories` rows are not resurrected. If a
  company once had a "Materials" row that got soft-deleted, the
  backfill will create a fresh, live row instead of un-deleting the
  old one.

## Idempotency

Both steps are guarded:

- STEP A uses `WHERE NOT EXISTS (...)` against live catalog rows, so a
  second run inserts zero new categories.
- STEP B uses `WHERE p.category_id IS NULL`, so a second run updates
  zero products.

Safe to re-run on a schedule, or after new legacy data is imported.

## How to run

The user should run this themselves — agents are not authorized to
mutate production data.

1. **Supabase SQL editor (recommended).** Open the project
   `ijeekuhbatykdomumfjx` in the Supabase dashboard, go to SQL editor,
   paste the contents of the `.sql` file, and run. Inspect the row
   counts returned.

2. **`apply_migration` MCP tool.** Pass the SQL block as the `query`
   argument once the user explicitly authorizes the mutation.

3. **`psql`** against the Supabase Postgres connection string:

       psql "$SUPABASE_DB_URL" -f OPS/Migrations/2026-05-10-backfill-products-category-id-phase-2.sql

## Verification

Before:

    SELECT COUNT(*) FROM products
    WHERE category_id IS NULL
      AND category IS NOT NULL
      AND TRIM(category) <> ''
      AND deleted_at IS NULL;
    -- Expected: 15 (at time of writing)

After:

    SELECT COUNT(*) FROM products
    WHERE category_id IS NULL
      AND category IS NOT NULL
      AND TRIM(category) <> ''
      AND deleted_at IS NULL;
    -- Expected: 0

    SELECT name, company_id, sort_order
    FROM catalog_categories
    WHERE created_at > NOW() - INTERVAL '5 minutes'
    ORDER BY company_id, sort_order;
    -- Expected: the new rows, one per distinct legacy category.

## Risk

Low. The transaction is bounded; the row count is small (15 legacy
products, single-digit number of new category rows). The new categories
are visible to users immediately — they may want to recolor / rename /
reorder them in the catalog UI afterward, but the rows themselves are
clean.

## Follow-up (separate, not in this file)

Once this runs and the legacy text column is fully shadowed by the FK,
we can plan a future migration to drop the free-text `products.category`
column. That is out of scope here — keeping the column nullable for
backward iOS-app-version compatibility (see project memory:
`project_ios_supabase_sync_constraint.md`).
