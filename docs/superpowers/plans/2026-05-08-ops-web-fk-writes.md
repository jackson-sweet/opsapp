# OPS-Web Products — FK Writes for category_id and unit_id (P0)

Codebase: `/Users/jacksonsweet/Projects/OPS/OPS-Web` (separate repo from `ops-ios`)
Lineage prefix: **OPS-WEB PRODUCTS - P0-1**

## Why this is P0

The iOS app now writes `category_id` (FK to `catalog_categories`) and `unit_id` (FK to `catalog_units`) on every product create + edit — alongside the legacy free-text `category` and `unit` columns for read-fallback compat. The web app at `/products` does **not**: every product created on web ships with `category_id` and `unit_id` NULL.

Result: products created on web are FK-orphaned and diverge from products created on iOS. Until this lands, the two surfaces produce different rows in the same `products` table — a data-quality wedge that gets harder to close the longer it runs. **Ship-blocking.**

Reference: `OPS-Web/docs/audit-2026-05-08-products.md` § "P0 — Ship-blocking" item 1.

## Scope

This plan ships **only the wire-level FK writes**. The user-facing pickers (turning category/unit into FK-backed selectors with "+ NEW…" inline create) are P0-2 and P0-3 in the audit's recommended sequence. **Do NOT** ship those here — they're separate plans the user will authorize sequentially after this one.

What changes here:
- TypeScript Product type gains `categoryId?: string` and `unitId?: string`
- ProductService maps both fields on read + write
- The existing free-text inputs continue to write the legacy columns; this plan adds the FK writes when the value happens to match a `catalog_categories` / `catalog_units` row by exact name (case-insensitive). When no match exists, the FK column is left NULL — same behavior the iOS-side legacy backfill already produces.

This makes web products as good as iOS products for the **subset of category/unit values that already correspond to catalog rows.** Full parity (real pickers + inline create) lands in P0-2.

## Hard constraints

- Branch: create a new branch off `main` (or whatever the OPS-Web default is — verify with `git -C /Users/jacksonsweet/Projects/OPS/OPS-Web branch --show-current`). Do NOT commit on `main` directly.
- **NEVER** `git add .` / `-A`. Stage by explicit path. `git status --short` before every `git add`.
- **NEVER** include `Co-Authored-By: Claude` or AI attribution.
- **Atomic commits per logical change** (see commit map below).
- **No production Supabase mutations.** No `apply_migration`, no `execute_sql`. The `category_id` and `unit_id` columns already exist server-side — no schema work needed.
- **TypeScript strict** must continue to pass. Run `pnpm tsc --noEmit` (or `npm` / `yarn` — whichever the repo uses; check `package.json`) before each commit.
- **Lint must pass** if there's a configured linter. Run `pnpm lint` (or equivalent).
- **Tests must continue to pass.** If there's a test for ProductService or the products page, run it. If you change behavior covered by tests, update the tests in the same commit as the behavior change.
- **Style:** match the existing codebase. Don't introduce new CSS classes or token systems. Cake Mono / JetBrains Mono / Mohave font triad per `OPS-Web/CLAUDE.md`. Steel-blue accent only on primary CTA.

## Files to read first

In order:

1. `OPS-Web/CLAUDE.md` — project conventions (fonts, design tokens, state management, services pattern)
2. `OPS-Web/docs/audit-2026-05-08-products.md` — your audit context, specifically §§ 1, 7, "P0 — Ship-blocking"
3. `OPS-Web/src/lib/types/pipeline.ts` — Product interface; will need `categoryId` + `unitId` added
4. `OPS-Web/src/lib/api/services/product-service.ts` — ProductService.mapProductToDb (lines ~38-56 per audit) + read mapper; will need both fields wired in
5. `OPS-Web/src/app/(dashboard)/products/page.tsx` — the product form modal (lines ~305-456 per audit); the create/edit submission paths must include the new fields
6. `OPS-Web/src/lib/hooks/use-products.ts` — TanStack Query hooks; verify the mutation invalidation list still covers the products query key

Cross-reference (read-only — these are in the iOS repo):
- `/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Network/Supabase/DTOs/ProductDTOs.swift` — iOS DTO field set + Postgres column names. The web TypeScript should align field-by-field.
- `/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/Catalog/Products/QuickAddProductSheet.swift` — iOS save() reference: writes both legacy text AND FK lockstep.

## Phase 1 — TypeScript types

**Goal:** Add `categoryId?: string` and `unitId?: string` to the canonical Product interface so downstream code can hold the FK values.

**Tasks:**

1. Open `src/lib/types/pipeline.ts`. Find the `Product` interface.
2. Add two optional fields:
   ```ts
   categoryId?: string;  // FK to catalog_categories.id; nullable for legacy rows
   unitId?: string;      // FK to catalog_units.id; nullable for legacy rows
   ```
3. If there's a separate `CreateProductInput` or `UpdateProductInput` type, mirror the additions there.
4. Run `pnpm tsc --noEmit`. There may be exhaustiveness checks elsewhere that fail; fix them in this same commit (`Pick<Product, ...>` references, etc.).

**Acceptance:** TypeScript compiles. No new lint warnings.
**Commit:** `feat(products): add categoryId and unitId to Product type`

## Phase 2 — Service layer FK mapping

**Goal:** ProductService reads + writes both columns.

**Tasks:**

1. Open `src/lib/api/services/product-service.ts`.
2. In `mapProductToDb()` (or the equivalent write-path mapper):
   - Add `category_id: input.categoryId ?? null` to the column dict.
   - Add `unit_id: input.unitId ?? null`.
   - Keep the legacy `category` and `unit` mappings exactly as they are.
3. In the read-path mapper (look for `mapDbToProduct` or wherever DB rows become Product objects):
   - Map `row.category_id → categoryId` and `row.unit_id → unitId`.
4. If there's a single `mapProduct` used both ways, ensure both directions handle the new fields.
5. The `update` method should pass through `categoryId`/`unitId` if the caller provides them. If the existing pattern uses sparse objects (only sends fields that changed), continue that pattern — don't force-write NULL on every update.

**Acceptance:**
- `pnpm tsc --noEmit` passes.
- `pnpm lint` passes.
- Run any existing ProductService tests (`find . -name "product-service*test*" -not -path "*/node_modules/*"`).

**Commit:** `feat(products): write category_id and unit_id columns from ProductService`

## Phase 3 — Form submission wiring (best-effort name → FK match)

**Goal:** When a user creates or edits a product on the dashboard, if the typed `category` or `unit` happens to match an existing `catalog_categories` / `catalog_units` row by exact name (case-insensitive, trimmed), write the FK alongside the legacy text. Otherwise leave the FK NULL.

This is a stopgap. The full fix is real pickers (P0-2) — but in the interim, this gets web's existing free-text inputs to populate FKs correctly when the user types something the catalog already knows about.

**Tasks:**

1. Open `src/app/(dashboard)/products/page.tsx`.
2. Find where the form's submit handler builds the payload sent to ProductService.
3. Before the call, fetch (or read from existing TanStack Query cache) the company's `catalog_categories` and `catalog_units` rows. There should already be a hook or service for these — check `src/lib/api/services/` and `src/lib/hooks/` for `catalog-categories`, `catalog-units`, or similar names. If none exists, add a lightweight hook in `src/lib/hooks/use-catalog-lookups.ts` that fetches both and returns `{ categories, units }`. Filter by `company_id` and `deleted_at IS NULL`.
4. Resolve the typed `category` string to a `categoryId`:
   ```ts
   const trimmed = (formCategory ?? "").trim().toLowerCase();
   const matched = trimmed ? categories.find(c => c.name.trim().toLowerCase() === trimmed) : undefined;
   const categoryId = matched?.id ?? undefined;
   ```
5. Same for `unit` → `unitId`.
6. Pass both into the ProductService create/update call. The legacy `category` and `unit` strings keep being passed exactly as before.
7. **Do NOT** make this opinionated yet — if no match, just submit without the FK. This is the minimum-viable parity for the data-divergence P0. The picker UX is P0-2.

**Acceptance:**
- Creating a product with `category: "Hardware"` (and a matching `catalog_categories` row exists) → DB row has `category_id` populated.
- Creating a product with `category: "asdf"` (no match) → DB row has `category_id NULL`. Legacy `category` still says `"asdf"`.
- Same logic for unit.
- Edit flow follows the same matching.
- `pnpm tsc --noEmit` passes; `pnpm lint` passes; existing tests pass.

**Commit(s):**
- If you needed to add a catalog-lookups hook: `feat(catalog): use-catalog-lookups hook for category + unit FKs`
- Form wiring: `feat(products): resolve category and unit text to FK ids on form submit`

## Phase 4 — Verification queries (don't run, write into report)

**Goal:** Hand the user 3-4 SQL queries they can run after deploying this to verify FK writes are landing.

**Tasks:**

1. In your final report, include a "verification SQL" section with these queries:
   ```sql
   -- How many products have FK populated vs not (per company)
   SELECT
     company_id,
     COUNT(*) AS total,
     COUNT(*) FILTER (WHERE category_id IS NOT NULL) AS with_category_fk,
     COUNT(*) FILTER (WHERE unit_id IS NOT NULL) AS with_unit_fk
   FROM products
   WHERE deleted_at IS NULL
   GROUP BY company_id;

   -- Recently created products: did the FK get written?
   SELECT id, name, category, category_id, unit, unit_id, created_at
   FROM products
   WHERE deleted_at IS NULL AND created_at > now() - interval '24 hours'
   ORDER BY created_at DESC;
   ```
2. Don't apply them. The user runs after deploy.

## Reporting (final agent message)

- **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED
- **Lineage:** OPS-WEB PRODUCTS - P0-1
- **Branch:** the new branch you created (e.g. `feat/products-fk-writes`)
- **Commits:** SHA + subject for each, in order
- **Files changed by commit**
- **Verification:** TypeScript + lint + tests all pass — paste the success lines
- **`git status --short`** showing only expected deltas
- **Verification SQL** (Phase 4) for the user to run after deploy
- **What's deferred:**
  - **OPS-WEB PRODUCTS - P0-2:** real FK-backed pickers (Menu/Combobox over `catalog_categories` / `catalog_units`)
  - **OPS-WEB PRODUCTS - P0-3:** inline "+ NEW CATEGORY…" / "+ NEW UNIT…" affordances
  - **OPS-WEB PRODUCTS - P1-1:** kind/type pickers
  - **OPS-WEB PRODUCTS - P1-2:** options + modifiers authoring on dashboard (this closes the iOS "edit on web" footer-note loop)
- **Concerns / judgment calls:** anything that didn't fit, places the codebase felt under-specified

## Begin

Read the files. Phase 1 first. TypeScript + lint between commits. Report when done.
