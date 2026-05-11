# Catalog Perfection Plan — 2026-05-08

Branch: `catalog-variant-model`
Working dir: `/Users/jacksonsweet/Projects/OPS/ops-ios` (the parent dir is **not** a git root — only this subdirectory is).
Build: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` (device-only, never simulator).

## Why this exists

The OPS catalog UI shipped a redesigned **Add Product** flow in this session (real CatalogCategory + CatalogUnit pickers, inline "+ NEW" creation, recipe attach via ProductMaterial, unit_id + category_id FK wiring). The "Is it perfect?" honest answer was **no** — there are remaining gaps. This plan closes the ones the agent can close autonomously, and explicitly surfaces the ones that need user direction.

## Hard constraints (apply to every phase)

- **NEVER** use `git add .` / `git add -A`. Stage by explicit path. Run `git status --short` before any `git add`.
- **NEVER** include `Co-Authored-By: Claude` or AI attribution in commits.
- **Atomic commits per logical change** — each phase below is one commit unless the phase explicitly says otherwise.
- **Build after every commit.** Must end with `** BUILD SUCCEEDED **`. Pre-existing warnings tolerable; new ones not. SourceKit "Cannot find type 'X'" diagnostics are false positives — ignore them; check the actual swiftc errors in the build log.
- **All styling traces to OPSStyle tokens.** No hardcoded colors / fonts / spacing / radii.
- **Voice:** `// SECTION HEADERS`, military-tactical minimalist, sentence case for content + UPPERCASE for authority. No emoji.
- **Permission gating** via `permissionStore.can("permission_key")` — never filter by role string.
- **Schema changes need explicit user approval.** If a phase requires a Supabase migration, write the SQL into the plan/report instead of applying it; surface for user review.
- **Confirm destructive UI actions.** Anything that deletes user data must show an alert with Cancel + destructive button.

## Phase 1 — ProductDetailView edit-flow parity

**Why:** QuickAddProductSheet now uses real CatalogCategory + CatalogUnit pickers and writes both `category_id` and `unit_id` FK columns. ProductDetailView is the **edit** counterpart — if it still uses free-text inputs for category/unit, products edited from iOS will silently re-orphan from the catalog backbone.

**Tasks:**

1. Read `OPS/Views/Catalog/Products/ProductDetailView.swift` end-to-end. Note specifically:
   - Whether category is edited via TextField (free text) or a CatalogCategory picker
   - Whether unit is edited via the legacy `ProductPricingUnit` enum or a CatalogUnit picker
   - Whether the save call writes `categoryId` / `unitId` to `UpdateProductDTO`
2. Read `OPS/Network/Supabase/DTOs/ProductDTOs.swift` `UpdateProductDTO`. Confirm whether `categoryId` and `unitId` fields exist; if not, add them additively (mirror the `CreateProductDTO` pattern just landed in commits `5d08485` + `9b18f55`).
3. If ProductDetailView edits free-text → bring it to QuickAddProductSheet parity:
   - Replace category TextField with a Menu picker over `CatalogCategory` (showing existing rows + "+ NEW…" inline create that reuses `InlineCreateCategorySheet` from `QuickAddProductSheet.swift` — extract it to `Manage/CatalogManageHelpers.swift` if you need to share)
   - Replace unit Picker with same Menu pattern over `CatalogUnit` (also reuse `InlineCreateUnitSheet`)
   - On save, write both legacy free-text columns AND the FKs (matches the create-side pattern)
4. If category/unit are read-only on detail (just displayed), make them editable when `permissionStore.can("catalog.products.manage")` is true; preserve the read-only fallback.
5. Verify the price/unit display formatting still works after the change — `pricingUnit` enum might still drive display formatting downstream (see [ProductRow](OPS/Views/Catalog/Products/CatalogProductsListView.swift) `pricingUnitSuffix`). If the new picker selects a CatalogUnit, derive the legacy `pricingUnit` enum from `unit.dimension` the same way `QuickAddProductSheet.pricingUnit(for:)` does.

**Acceptance criteria:**

- A user can change a Product's category from the picker; both `category` (legacy text) and `category_id` (FK) update on save.
- Same for unit: both `unit` (text) and `unit_id` update.
- Inline "+ NEW CATEGORY…" / "+ NEW UNIT…" works from the detail edit flow.
- Build succeeds. No new warnings.
- Single commit subject: `feat(catalog): ProductDetailView edit parity with Add Product (catalog FKs)`.

## Phase 2 — Legacy category backfill SQL (DO NOT APPLY — write only)

**Why:** Existing products in production have `category` (text) populated but `category_id` NULL. A SQL backfill matches them by name + company_id and sets the FK so reads from the new code path see correct linkage.

**Tasks:**

1. Write SQL to `OPS/Migrations/2026-05-08-backfill-products-category-id.sql`:

   ```sql
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
   ```

2. Write a small Markdown note alongside it explaining:
   - What rows it updates (and what rows it leaves alone — categories that don't have a matching `catalog_categories` row stay on the free-text column)
   - How to run it (Supabase SQL editor or `apply_migration`)
   - That the file is **NOT** auto-applied — user must approve and run it manually
3. **DO NOT** call `apply_migration` or `execute_sql`. The agent does not have schema-mutation authority. Surface the file path in the final report so the user can choose to run it.

**Acceptance criteria:**

- File created at the path above with the SQL block + the doc note.
- File is staged and committed: `docs(catalog): backfill SQL for products.category_id (NOT applied)`.
- Final report includes the file path and the explicit "user must approve and run" callout.

## Phase 3 — Bible update

**Why:** `ops-software-bible/` is the single source of truth for architecture per `CLAUDE.md`. Two things shipped this session that need documentation:
- The `category_id` FK on products
- The on-iOS recipe-attach flow (RecipeManageSheet + ProductMaterial create/delete)

**Tasks:**

1. Read `ops-software-bible/03_DATA_ARCHITECTURE.md` and `ops-software-bible/07_SPECIALIZED_FEATURES.md` to find the existing catalog/products section.
2. Update `03_DATA_ARCHITECTURE.md`:
   - In the products table description, add `category_id uuid REFERENCES catalog_categories(id) ON DELETE SET NULL` alongside the existing `unit_id` reference.
   - Note the legacy `category` text column stays in place for backwards compat; new writes populate both.
3. Update wherever the recipe / ProductMaterial flow is documented (likely `07_SPECIALIZED_FEATURES.md` if there's a catalog section, otherwise the data architecture doc):
   - Add a brief "Recipe authoring on iOS" subsection: RecipeManageSheet entry from ProductDetailView, AddProductMaterialSheet for individual rows, no row-edit (delete + re-add), advanced family-pinned recipes still web-only.
4. If neither doc has a catalog section, add a small one to `03_DATA_ARCHITECTURE.md` summarizing the layers (catalog backbone → product → estimate/invoice → install task → cut list).

**Acceptance criteria:**

- Doc edits are factual (verify table names + column names against what was actually shipped).
- Single commit: `docs(bible): document category_id FK + on-iOS recipe authoring`.

## Phase 4 — Sheet polish (multi-commit OK)

**Why:** Five smaller QoL gaps from the "Is it perfect" honest list. Each is independently shippable.

**Tasks (separate commit per item):**

4a. **Save-and-add-another on QuickAddProductSheet.**
   - Add a checkbox/toggle below the SAVE button: "// SAVE AND ADD ANOTHER" (default off, persist via `@AppStorage("catalog.product.saveAndAddAnother")`).
   - On save: if toggle is on, after success, reset the form fields (keep category + unit selections, clear name/price/sku/description), do NOT dismiss, refocus the name field.
   - On save: if toggle is off, behave as today (dismiss).
   - Commit: `feat(catalog): save-and-add-another on Add Product sheet`.

4b. **Live margin readout.**
   - In QuickAddProductSheet's Advanced disclosure, when both `priceString` and `unitCostString` parse to numbers and price > 0, show a small `MARGIN: 35%` line below the unit cost field. Compute `((price - cost) / price) * 100`. Hide when either is missing or invalid.
   - Use `OPSStyle.Typography.metadata` and tertiary text color, JetBrains Mono on the percentage. Tabular lining + slashed zero per OPS number rules.
   - Commit: `feat(catalog): live margin readout in Add Product advanced section`.

4c. **Keyboard dismiss on tap-outside.**
   - Add a `.onTapGesture { hideKeyboard() }` on the ScrollView's outer ZStack (or the form VStack) in QuickAddProductSheet. Implement `hideKeyboard()` as a small View extension if not already present (`UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)`).
   - Apply same fix to the new `RecipeManageSheet` and `AddProductMaterialSheet` for consistency.
   - Commit: `feat(catalog): tap-outside dismisses keyboard on catalog form sheets`.

4d. **Retry button on save failure.**
   - In QuickAddProductSheet's body, when `errorMessage` is non-nil, render a small "RETRY" button next to the error text that re-fires `Task { await save() }`.
   - Commit: `feat(catalog): retry button on Add Product save failure`.

4e. **Name uniqueness pre-check.**
   - In QuickAddProductSheet, before save, check `@Query private var allProducts: [Product]` for any company-owned active product with the same trimmed name (case-insensitive). If found, set `errorMessage = "// NAME ALREADY USED — pick a different name or edit the existing product"` and bail out with an error haptic; do not call the repo.
   - Commit: `feat(catalog): name uniqueness check before product create`.

**Acceptance criteria per item:**

- Build succeeds after each commit.
- Each commit is independently revertable.
- The 5 commits land in the order above.

## Phase 5 — ProductMaterial update path

**Why:** RecipeManageSheet currently supports add + delete. To edit a recipe row's quantity or notes, the user has to delete and re-add — losing context.

**Tasks:**

1. Add `UpdateProductMaterialDTO` to `OPS/Network/Supabase/DTOs/ProductExtensionDTOs.swift` with optional fields for `quantityPerUnit`, `notes`, `unitId`, `scaledByOptionId` (the only mutable fields — id, productId, catalogVariantId, catalogItemId, variantSelector are identity).
2. Add `updateMaterial(_ id: String, fields: UpdateProductMaterialDTO) async throws -> ProductMaterialDTO` to `OPS/Network/Supabase/Repositories/ProductRichnessRepository.swift`. PostgREST update pattern matches the existing `update*` methods elsewhere in the repo layer.
3. Modify `RecipeManageSheet` (in `OPS/Views/Catalog/Products/RecipeManageSheet.swift`) so each row has an "EDIT" affordance (small button or tap-row → bottom sheet). Reuse `AddProductMaterialSheet` if its layout fits, OR add an `editingMaterial: ProductMaterial?` param and have the same sheet render in either create or edit mode (preferred — less new UI surface).
4. On save in edit mode, call `repo.updateMaterial(id, fields:)` instead of `createMaterial`. Update the local SwiftData row in place. Fire a success haptic.

**Acceptance criteria:**

- Tapping an existing recipe row's edit affordance → quantity/notes editable → save updates server + local.
- Build clean.
- Commit: `feat(catalog): edit existing recipe rows in RecipeManageSheet`.

## Phase 6 — Inline family/variant create from Recipe sheet

**Why:** When `AddProductMaterialSheet` opens against an empty inventory (no `CatalogItem` rows for this company), the family picker is disabled with a "// NO FAMILIES YET" message. User has to dismiss → STOCK tab → FAB → Add Family → Add Variant → return → reopen. Same dead-end UX as the category/unit picker had pre-fix.

**Tasks:**

1. In `AddProductMaterialSheet`, when the family Menu is open AND `companyFamilies.isEmpty`, show a single "+ NEW FAMILY…" Menu item that opens `AddFamilySheet` (already exists at `OPS/Views/Catalog/Stock/AddFamilySheet.swift`). On dismiss, the @Query reactively picks up the new family and the user can select it.
2. When a family IS selected but it has zero variants, show "+ NEW VARIANT…" in the variant Menu opening `VariantFormSheet` (already exists at `OPS/Views/Catalog/Stock/VariantFormSheet.swift`). Same reactive update on dismiss.
3. Whether the "+ NEW…" item shows always (like the category picker pattern) or only on empty states is a judgment call. **Choose: only on empty states** (less menu clutter when inventory is healthy) and document the choice in a comment.

**Acceptance criteria:**

- Open AddProductMaterialSheet on a brand-new company (zero families) → "+ NEW FAMILY…" present in the family picker → tap opens AddFamilySheet → save returns to AddProductMaterialSheet with the new family selectable.
- Same for variant when family has none.
- Build clean.
- Commit: `feat(catalog): inline family/variant create from recipe attach sheet`.

## Out of scope (return to user — DO NOT attempt)

- **CSV bulk import** (replaces the Phase-8 `CatalogImportStub`). Big enough to need its own plan: file picker, column mapping UI, dry-run preview, atomic apply, error reporting per row. **Tell the user it's deferred and ask if they want a separate plan written for it.**
- **OPS-Web /products audit.** Different repo (`/Users/jacksonsweet/Projects/OPS/OPS-Web`). Surface in the final report that this should be a separate session.
- **Image / thumbnail field on Product.** Requires schema decision (new column? Storage bucket policy?). Surface as a question.
- **Real-device test.** The agent can't run on a physical device; only the user can. Final report should remind the user to test on device before merging.
- **Replace `pricingUnit` enum entirely with FK to CatalogUnit everywhere.** Big refactor across estimates, invoices, deck builder, line item display. Surface as a future cleanup.

## Reporting (final agent message)

- **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED
- **Lineage:** CATALOG SYNC - P1-3
- **Phases attempted:** list each phase number + "completed / partial / skipped (with reason)"
- **Commits:** SHA + subject for each, in order
- **Files changed by commit**
- **Build verification:** last 3 lines of the device build output (must include `** BUILD SUCCEEDED **`)
- **`git status --short`** showing only expected deltas
- **Phase 2 SQL file path** + the explicit "user must approve and run" callout
- **What's deferred to user direction:** the items in "Out of scope" + anything you punted within phases
- **Any concerns** — places the design felt under-specified, decisions you made on judgment calls, anything you noticed that wasn't in the plan but seemed worth flagging
