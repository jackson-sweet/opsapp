# Catalog CSV Import — 2026-05-08

Branch: `catalog-variant-model`
Working dir: `/Users/jacksonsweet/Projects/OPS/ops-ios`
Build: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` (device-only, never simulator)
Lineage prefix: **CATALOG IMPORT - P1-<n>**

## Why this exists

`CatalogImportStub` shipped as `[Coming in Phase 8]` placeholder in [`FloatingActionMenu.swift`](OPS/Views/Components/FloatingActionMenu.swift). For Canpro and similar customers with existing inventory in spreadsheets, hand-typing each family + variant is unreasonable — they need bulk load. Replace the stub with a real flow.

## Hard constraints

- **NEVER** `git add .` / `-A`. Stage by explicit path. `git status --short` before every `git add`.
- **NEVER** include `Co-Authored-By: Claude` or AI attribution.
- **Atomic commits per logical change** (see commit map below).
- **Build between commits.** Must end with `** BUILD SUCCEEDED **`. SourceKit "Cannot find type" diagnostics are false positives — check actual swiftc errors.
- **All styling traces to OPSStyle tokens.** Voice: `// SECTION HEADERS`, military-tactical, no emoji.
- **Permission gating** via `permissionStore.can("catalog.import")` — this permission already exists.
- **Schema changes need explicit user approval.** Write SQL into the plan/report; do not apply via `apply_migration` or `execute_sql`.
- **Dry-run before any destructive write.** Atomic apply means: validate every row first, fail-fast on the first error with per-row context, only commit if every row passes.

## Scope

Two import targets, in priority order:

1. **Catalog families + variants** (the big one — Canpro's real ask). One CSV row = one variant. Variants get grouped into families by a `family_name` column.
2. **Products** (smaller; nice-to-have for completeness). One CSV row = one Product.

Phase 1 below ships #1. Phase 6 covers #2 if there's time + scope budget.

## Phase 1 — Repository layer (server-side)

**Goal:** Atomic-apply API. The iOS client uploads a parsed payload; server validates + writes in a transaction; returns either `success: true, created_*` ids OR `success: false, errors: [...]` (no partial writes).

**Tasks:**

1. **Decide between Edge Function vs RPC.** RPC is simpler (pure Postgres function, no JS deploy) but limits to what plpgsql can validate. Edge Function gives JSON parsing flexibility. **Choose RPC** for v1 — JSON validation in plpgsql is acceptable for this scope; Edge Function adds infra and observability burden.

2. **Write SQL for an RPC** at `OPS/Migrations/2026-05-08-catalog-import-rpc.sql`. Function signature:

   ```sql
   CREATE OR REPLACE FUNCTION public.catalog_import_apply(
     p_company_id uuid,
     p_payload jsonb       -- { "families": [...], "variants": [...] }
   ) RETURNS jsonb         -- { "success": bool, "created_family_ids": [...], "created_variant_ids": [...], "errors": [...] }
   ```

   - SECURITY DEFINER, bound to a role with INSERT on catalog_items / catalog_variants for the caller's company.
   - Validates: `p_company_id` matches the auth.uid()'s company (read from `private.current_user_company_id()` or equivalent — verify via existing patterns in the bible / migrations).
   - Per-row validation: family name non-empty, variant SKU optional but unique within the company if set, quantity >= 0, price/cost >= 0 if set, category_id (if provided) belongs to the same company, unit_id (if provided) belongs to the same company.
   - On any validation failure: return `{success: false, errors: [{row_index, field, reason}, ...]}` and ROLLBACK.
   - On success: INSERT all families first, capture the id mapping, INSERT all variants pointing at the new family ids, return `{success: true, created_family_ids: {row_index → uuid}, created_variant_ids: {row_index → uuid}}`.
   - Document the JSON schema for `p_payload` inline.

3. Write the SQL into the file. **Do not apply.** Document at the top of the file: "USER MUST APPROVE AND RUN."

4. Mirror the dry-run path: a sibling RPC `catalog_import_validate(p_company_id uuid, p_payload jsonb) RETURNS jsonb` that runs the same checks but never INSERTs. Same error array shape. Used by the iOS preview screen.

**Acceptance:**
- File created at the path above with both RPCs.
- File is staged + committed: `docs(catalog): RPC SQL for catalog_import (NOT applied)`.
- The `.md` companion doc explains how to apply (Supabase SQL editor or `apply_migration`) and the JSON schema for `p_payload`.

## Phase 2 — iOS repository wrapper

**Tasks:**
1. Add a new repository at `OPS/Network/Supabase/Repositories/CatalogImportRepository.swift`:
   - `init(companyId: String)`
   - `func validate(_ payload: CatalogImportPayload) async throws -> CatalogImportResult` (calls `catalog_import_validate`)
   - `func apply(_ payload: CatalogImportPayload) async throws -> CatalogImportResult` (calls `catalog_import_apply`)
2. DTOs in `OPS/Network/Supabase/DTOs/CatalogImportDTOs.swift`:
   - `CatalogImportPayload` — encodes the `{families, variants}` JSON
   - `CatalogImportFamily` — name, description?, categoryId?, defaultUnitId?, defaultPrice?, etc.
   - `CatalogImportVariant` — familyRowIndex (refers to a family in the same payload), sku?, quantity, priceOverride?, unitCostOverride?
   - `CatalogImportResult` — success, createdFamilyIds, createdVariantIds, errors

**Acceptance:**
- Build clean.
- Commit: `feat(catalog): CatalogImportRepository + DTOs for atomic import`.

## Phase 3 — CSV parser

**Tasks:**
1. New file `OPS/Services/CSVParser.swift`. Pure-function parser:
   - Handles RFC 4180 (quoted fields, embedded commas, embedded quotes via `""`, CRLF + LF + CR line endings).
   - Header row required.
   - Returns `[[String: String]]` (one dict per row, keyed by header).
   - Trims whitespace on header names.
   - Surfaces line numbers in errors so the import preview can point at the right row.
2. Companion file `OPS/Services/CatalogCSVMapper.swift`:
   - Takes `[[String: String]]` + a column-mapping config + the company's existing `[CatalogCategory]` and `[CatalogUnit]`.
   - Produces a `CatalogImportPayload`.
   - Per-row validation:
     - family_name non-empty
     - quantity is a number (default 0 if blank)
     - price/cost are numbers if present
     - category (if column mapped) resolves to a CatalogCategory by case-insensitive name match within the company; missing match → flag as "create new category" and let the user decide via UI
     - unit (if column mapped) resolves to a CatalogUnit similarly

**Acceptance:**
- Unit tests if there's a test target — find with `find OPSTests -type d`. Test files: at least one happy-path import (5 families, 10 variants), one with embedded quotes, one with missing required columns. If no test target, skip and note.
- Commit: `feat(catalog): CSV parser + CatalogCSVMapper for catalog import`.

## Phase 4 — Import sheet UI

**Tasks:**

Build under new directory `OPS/Views/Catalog/Import/`. Three screens stitched into one navigation flow:

1. **`CatalogImportSheet.swift`** (the entry sheet)
   - Step 0: file picker (`.fileImporter`) for `.csv` files. Single file at a time.
   - Step 1: column mapping — for each required column (family_name, sku, quantity, etc.) and each optional (description, category, unit, price, cost, threshold), let the user pick which CSV column maps to it. Auto-suggest based on header name fuzzy match.
   - Step 2: dry-run preview — call `validate(payload)`. If errors, show the per-row error list (scrollable) with "FIX & RETRY" (back to step 1) and "CANCEL" buttons. If success, show count summary ("// READY: 27 FAMILIES + 58 VARIANTS") with "APPLY" + "CANCEL" buttons.
   - Step 3: apply — call `apply(payload)`. Shows progress spinner. On success, fires success haptic + dismisses to a confirmation sheet. On failure (network/server), shows error inline with "RETRY" button (the RPC is atomic so re-applying is safe — same payload either re-fails-the-same-way or succeeds).

2. **Layout pattern:**
   - Match `QuickAddProductSheet`'s shell: `OPSStyle.Colors.backgroundGradient` background, NavigationStack, `.presentationDetents([.large])` (large is appropriate — this is a multi-step flow).
   - Top progress indicator showing 4 steps (PICK → MAP → PREVIEW → APPLY) as a tactical chip strip.
   - Each step is a child View; use a `@State private var step: Step` enum to switch between them.

3. **FAB wiring:**
   - Replace the existing `showingCatalogImport = true → CatalogImportStub()` in `FloatingActionMenu.swift` with `CatalogImportSheet()`.
   - Re-add the kebab "Import…" entry in `CatalogView.swift` now that import is real (mirror the existing kebab pattern; gate on `permissionStore.can("catalog.import")`).

**Acceptance:**
- Build clean.
- Test the dry-run preview doesn't write anything (verify by `SELECT COUNT(*) FROM catalog_items WHERE company_id = ...` before/after a dry-run).
- Commits (split if helpful):
  - `feat(catalog): CatalogImportSheet — file pick + column mapping`
  - `feat(catalog): import preview + atomic apply`
  - `feat(catalog): wire CatalogImportSheet into FAB + kebab; remove CatalogImportStub`

## Phase 5 — Documentation

**Tasks:**
- Update `ops-software-bible/03_DATA_ARCHITECTURE.md` (separate git root): document the import RPC + payload schema.
- Update or add `ops-software-bible/07_SPECIALIZED_FEATURES.md`: brief section on the catalog import flow (entry points, validation rules, what gets created vs skipped).

**Acceptance:**
- Commit in the bible repo: `docs(bible): catalog CSV import RPC + flow`.

## Phase 6 — Products import (only if scope allows)

If Phases 1–5 ship cleanly with time + token budget remaining, extend to products. Same RPC pattern but a new function `products_import_apply` + a new DTO + a second tab in the import sheet ("STOCK" vs "PRODUCTS"). Otherwise skip and surface as a follow-up.

## Reporting (final agent message)

- **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED
- **Lineage:** CATALOG IMPORT - P1-1
- **Phases attempted:** list each + completed/partial/skipped with reason
- **Commits:** SHA + subject for each, in order
- **Files changed by commit**
- **Build verification:** last 3 lines of device build output
- **`git status --short`** showing only expected deltas
- **RPC SQL file path** + the explicit "USER MUST APPROVE AND RUN" callout
- **Concerns / judgment calls** — anything you punted, choices that felt brittle, etc.
- **What needs user direction next** — backfill of legacy rows, products import (if not done in Phase 6), etc.
