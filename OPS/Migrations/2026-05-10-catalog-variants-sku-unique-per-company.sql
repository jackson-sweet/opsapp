-- catalog_variants — case-insensitive SKU uniqueness per company.
--
-- Applied 2026-05-10. Decision driver: needed a definitive answer to
-- "what happens when an import or a manual create tries to use a SKU
-- that already exists on another active variant in the same company?"
-- Four options were on the table:
--
--   A. Keep the catalog_import_validate RPC's soft-check as the only
--      guardrail (status quo). Hard error during dry-run; no DB-level
--      enforcement, so a race between two devices can still land a
--      duplicate.
--   B. Soft-skip in the RPC (return warnings, continue with non-colliding
--      rows). Friendly but quiet — silent skips invite confusion.
--   C. Overwrite-on-collision via UPDATE in the RPC. Powerful but
--      dangerous in a multi-device tenant: device A's CSV import could
--      overwrite device B's manual edits.
--   D. Enforce uniqueness in Postgres via a partial unique index. DB is
--      the source of truth; the RPC's preview-time check remains as a
--      UX nicety but the invariant is locked.
--
-- Picked D. Pre-flight verified zero existing duplicates in
-- catalog_variants (SELECT ... GROUP BY LOWER(TRIM(sku)) HAVING
-- COUNT(*) > 1 returned empty).
--
-- Partial index conditions:
--   * deleted_at IS NULL — soft-deleted rows shouldn't block re-creation
--     of a variant that previously had the same SKU.
--   * sku IS NOT NULL AND TRIM(sku) <> '' — SKU is optional; many
--     variants have none. The partial filter lets multiple NULL/empty
--     rows coexist.
--   * LOWER(TRIM(sku)) — case-insensitive + whitespace-tolerant match,
--     consistent with the RPC's existing comparison.
--
-- The catalog_import_validate RPC was NOT changed. It still surfaces
-- SKU collisions during dry-run preview, which is better UX than
-- letting the user click APPLY and then seeing a PostgREST constraint
-- violation. The two checks are now belt-and-suspenders.

CREATE UNIQUE INDEX IF NOT EXISTS catalog_variants_sku_unique_per_company
  ON catalog_variants (company_id, LOWER(TRIM(sku)))
  WHERE deleted_at IS NULL AND sku IS NOT NULL AND TRIM(sku) <> '';

COMMENT ON INDEX catalog_variants_sku_unique_per_company IS
  'Enforces case-insensitive SKU uniqueness within a company for active variants. Partial index excludes NULL/empty SKUs and soft-deleted rows.';
