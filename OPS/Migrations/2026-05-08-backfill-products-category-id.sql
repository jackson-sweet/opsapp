-- Backfill products.category_id from the legacy free-text category column.
-- Matches by exact name within the same company. Idempotent: only updates
-- rows where category_id is currently NULL.
--
-- Run after the add_category_id_fk_to_products migration. Safe to run
-- multiple times.

UPDATE products p
SET category_id = c.id
FROM catalog_categories c
WHERE p.company_id = c.company_id
  AND p.category IS NOT NULL
  AND TRIM(p.category) <> ''
  AND p.category_id IS NULL
  AND LOWER(TRIM(p.category)) = LOWER(TRIM(c.name))
  AND c.deleted_at IS NULL;
