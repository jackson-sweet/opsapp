-- Backfill phase 2 — create missing catalog_categories rows, then link products.
-- Phase 1 (2026-05-08-backfill-products-category-id.sql) only matched existing
-- catalog_categories by name. It updated 0 rows in production because every
-- legacy product points at a category name with NO matching catalog row.
--
-- Phase 2 closes the gap in two steps inside a single transaction:
--   STEP A — INSERT one catalog_categories row per distinct
--            (company_id, lower(trim(category))) where no live match exists.
--            sort_order = max(existing sort_order in company) + 1, NULLs default
--            to 0. Thresholds left NULL (matches phase 1 fallback semantics).
--   STEP B — Re-run the phase 1 update so the new categories link the legacy
--            products. Idempotent — second run is a no-op.
--
-- Run after phase 1. Safe to re-run; both steps are guarded against duplicates.

BEGIN;

-- STEP A — Create missing catalog_categories rows.
WITH legacy_categories AS (
    SELECT DISTINCT
        p.company_id,
        TRIM(p.category) AS category_name
    FROM products p
    WHERE p.category IS NOT NULL
      AND TRIM(p.category) <> ''
      AND p.category_id IS NULL
      AND p.deleted_at IS NULL
),
missing AS (
    SELECT lc.company_id, lc.category_name
    FROM legacy_categories lc
    WHERE NOT EXISTS (
        SELECT 1
        FROM catalog_categories c
        WHERE c.company_id = lc.company_id
          AND LOWER(TRIM(c.name)) = LOWER(lc.category_name)
          AND c.deleted_at IS NULL
    )
),
next_sort AS (
    SELECT
        m.company_id,
        m.category_name,
        COALESCE((
            SELECT MAX(c.sort_order) + 1
            FROM catalog_categories c
            WHERE c.company_id = m.company_id
              AND c.deleted_at IS NULL
        ), 0) AS sort_order
    FROM missing m
)
INSERT INTO catalog_categories (
    id, company_id, name, sort_order, created_at, updated_at
)
SELECT
    gen_random_uuid(),
    ns.company_id,
    ns.category_name,
    ns.sort_order,
    NOW(),
    NOW()
FROM next_sort ns;

-- STEP B — Re-link products to their (now-existing) catalog_categories row.
-- This is the same update as phase 1.
UPDATE products p
SET category_id = c.id
FROM catalog_categories c
WHERE p.company_id = c.company_id
  AND p.category IS NOT NULL
  AND TRIM(p.category) <> ''
  AND p.category_id IS NULL
  AND LOWER(TRIM(p.category)) = LOWER(TRIM(c.name))
  AND c.deleted_at IS NULL;

COMMIT;
