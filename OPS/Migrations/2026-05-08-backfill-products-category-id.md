# Backfill — products.category_id from legacy `category` text

**File:** `2026-05-08-backfill-products-category-id.sql`

**Status:** NOT APPLIED. Awaiting user approval before it touches any database.

## What it does

Walks every row in `products` where `category_id IS NULL` and the legacy
free-text `category` column is non-empty, and tries to match it to a row
in `catalog_categories` by case-insensitive trimmed name within the same
`company_id`. When a match is found, it sets `category_id` to that
`catalog_categories.id`.

## What it leaves alone

- Rows where `category_id` is already populated — never overwritten.
- Rows where the free-text `category` is `NULL` or empty — nothing to
  match against.
- Rows whose `category` text doesn't match any existing
  `catalog_categories` row for that company. Those products stay on the
  free-text column. The product is still readable; it just isn't linked
  to the catalog backbone yet. The user can either rename the free-text
  value to match an existing category, or create the missing
  `catalog_categories` row and run the backfill again.
- `catalog_categories` rows with a non-null `deleted_at` are excluded so
  the backfill never resurrects a soft-deleted category.

## Why this is needed

Before the `category_id` FK shipped (commit `5d08485`), products were
saved with category as a free-text column. Those rows now have
`category_id IS NULL`. The new code path on iOS reads the FK first and
falls back to the legacy text, so untouched rows still display correctly
— but they don't participate in catalog-aware queries (filter by
category, category-driven defaults, etc.). The backfill closes the gap.

## How to run

Either:

1. **Supabase SQL editor (recommended for one-off runs).** Paste the
   contents of `2026-05-08-backfill-products-category-id.sql` into the
   editor and run it. Inspect the row count returned.

2. **`apply_migration` MCP tool.** Pass the SQL block as the `query`
   argument. Idempotent — safe to re-run.

3. **`psql`** against the Supabase Postgres connection string:

       psql "$SUPABASE_DB_URL" -f OPS/Migrations/2026-05-08-backfill-products-category-id.sql

## Idempotency

The `WHERE p.category_id IS NULL` clause makes this safe to re-run. The
second run finds zero matches because the first run populated everything
matchable. New rows that show up later (created with `category` text but
no `category_id`) are picked up the next run.

## Verification

After running, eyeball the count:

    SELECT COUNT(*) FROM products WHERE category_id IS NOT NULL;
    SELECT COUNT(*) FROM products WHERE category_id IS NULL AND category IS NOT NULL AND TRIM(category) <> '';

The first should grow; the second is the backlog of unmatched rows for
the user to follow up on.
