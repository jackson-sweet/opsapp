# OPS-Web Products — FK-backed Pickers + Inline Create (P0-2 + P0-3)

Codebase: `/Users/jacksonsweet/Projects/OPS/OPS-Web`
Lineage prefix: **OPS-WEB PRODUCTS - P0-2**

## Why

P0-1 (FK-writes branch `feat/products-fk-writes`, PR #38) made web write `category_id` + `unit_id` when the typed text matches an existing catalog row. But the inputs are still free-text TextField + a hardcoded UNIT_OPTIONS dropdown — users have no visibility into what categories/units already exist, and no path to create new ones without leaving the form.

This plan replaces both inputs with real FK-backed pickers (Combobox over `catalog_categories` / `catalog_units`) and adds inline "+ NEW CATEGORY…" / "+ NEW UNIT…" sheets that mirror the iOS pattern from `QuickAddProductSheet.InlineCreateCategorySheet` / `InlineCreateUnitSheet`.

P0-2 (pickers) and P0-3 (inline create) are scoped together because they're tightly coupled — you can't ship the picker without giving users a way to create new entries when their value isn't there.

## Branch

Branch off `feat/products-fk-writes` (NOT `main`). The pickers reuse the `useCatalogLookups` hook from P0-1; building on `main` would force you to re-add it. New branch name: `feat/products-fk-pickers`.

## Hard constraints

- TypeScript strict + lint + tests must pass before each commit.
- Stage by explicit path. No `git add .` / `-A`.
- No AI attribution.
- Atomic commits.
- No production schema mutations.
- Style:
  - `font-cakemono font-light` for uppercase labels
  - `font-mono` for numerical / micro-label text + `//` prefixes + `[brackets]`
  - Steel-blue accent `#6F94B0` ONLY on focus ring + primary CTA. No accent on links/toggles/nav.
  - Glass surface for the dialog: `rgba(18,18,20,0.78) + backdrop-blur(28px) + 1px solid rgba(255,255,255,0.09)` (`.glass-dense` token).
  - No emoji. No exclamation points.
  - Single easing curve `cubic-bezier(0.22, 1, 0.36, 1)` for all motion.

## Files to read first

1. `/Users/jacksonsweet/Projects/OPS/OPS-Web/CLAUDE.md` — design tokens + conventions
2. `/Users/jacksonsweet/Projects/OPS/OPS-Web/.interface-design/system.md` — canonical visual spec
3. `src/app/(dashboard)/products/page.tsx` — current form (lines ~305-456)
4. `src/lib/hooks/use-catalog-lookups.ts` — the hook P0-1 added (returns `categories` + `units`)
5. `src/components/ui/` — find any existing Combobox / Select / Dialog primitives. Reuse, don't reinvent.
6. iOS reference (read-only): `/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/Catalog/Products/QuickAddProductSheet.swift` — `InlineCreateCategorySheet` + `InlineCreateUnitSheet` patterns

## Phase 1 — Catalog services with create methods

The `useCatalogLookups` hook reads. P0-3 needs writes. Add minimal services:

- `src/lib/api/services/catalog-category-service.ts` — `create({ name, sortOrder, companyId })` → returns the new CatalogCategory.
- `src/lib/api/services/catalog-unit-service.ts` — `create({ display, dimension, sortOrder, companyId })` → returns the new CatalogUnit.

Both should match the iOS DTO field set (see `ops-ios/OPS/Network/Supabase/DTOs/CatalogDTOs.swift` for `CreateCatalogCategoryDTO` + `CreateCatalogUnitDTO`):
- Category: `name` (required), `parent_id` nullable (default null), `sort_order` (default = max + 1), `color_hex` nullable, threshold pair nullable
- Unit: `display` (required), `abbreviation` nullable, `dimension` (required, one of count/length/area/volume/mass/time), `is_default` default false, `sort_order` (default = max + 1)

After insert, invalidate the `useCatalogLookups` query key so the picker reactively refreshes.

Commit: `feat(catalog): catalog-category-service + catalog-unit-service create methods`

## Phase 2 — Picker components

Two new components under `src/components/ops/` (or wherever the existing pattern puts feature components):

- `category-picker.tsx` — Combobox/Menu over `categories` from `useCatalogLookups`. Props: `value: string | undefined` (categoryId), `onChange: (id: string | undefined, name: string | undefined) => void` (passes both so the form can keep writing the legacy `category` text alongside the FK). Renders the selected category's name (or "Select category" placeholder) in the trigger; opens a popover with searchable list + a divider + "+ NEW CATEGORY…" item that fires a callback.
- `unit-picker.tsx` — same pattern over `units`. Same dual-callback shape.

Both reuse whatever Combobox primitive the codebase already has (Radix? cmdk? a custom component?). If nothing fits, build a small one using the design tokens — don't pull in a new dependency.

Behavior:
- Type-to-search filters the list.
- Empty inventory state: list is empty → still show the "+ NEW…" item.
- Keyboard navigation (arrow up/down, enter to select, esc to close).
- Touch target minimum 44px height for accessibility (the design system spec).

Commit: `feat(catalog): CategoryPicker + UnitPicker components`

## Phase 3 — Inline create dialogs

Two new components:

- `inline-create-category-dialog.tsx` — opens when the picker fires its "+ NEW…" callback. Single field (name). Save calls `catalogCategoryService.create`, on success returns the new id+name to the picker which selects it.
- `inline-create-unit-dialog.tsx` — display + dimension picker (count/length/area/volume/mass/time). Save calls `catalogUnitService.create`.

Match the visual treatment of existing dialogs — use the project's Dialog primitive (Radix probably). `.glass-dense` background. Cake Mono Light for the title (`// NEW CATEGORY` / `// NEW UNIT`). JetBrains Mono for any micro-labels. Steel-blue accent on the primary save button only.

Commit: `feat(catalog): InlineCreateCategoryDialog + InlineCreateUnitDialog`

## Phase 4 — Wire into product form

Modify `src/app/(dashboard)/products/page.tsx`:

- Replace the free-text category TextField with `<CategoryPicker value={form.categoryId} onChange={(id, name) => { form.categoryId = id; form.category = name ?? form.category }} />`. The form keeps writing both fields lockstep (matches what P0-1 set up).
- Replace the UNIT_OPTIONS dropdown with `<UnitPicker value={form.unitId} onChange={(id, display) => { form.unitId = id; form.unit = display ?? form.unit }} />`.
- Drop the `resolveCategoryId` / `resolveUnitId` helpers from P0-1's form submit — they're no longer needed since the picker hands you the FK directly. Keep the matching logic available as a fallback, or just remove (cleaner).

After this commit, every product creation/edit on web goes through the same picker UX iOS uses. The "free-text fallback" path P0-1 added becomes vestigial — it still works for backward compat (e.g. legacy data flowing through the form's edit path) but new writes always have FKs.

Commit: `feat(catalog): wire CategoryPicker + UnitPicker into product form`

## Phase 5 — Tests

If there are tests for the products page, update them. If not, add minimum coverage:
- `tests/unit/components/category-picker.test.tsx` — renders, opens, selects, fires inline-create
- `tests/unit/components/unit-picker.test.tsx` — same

Skip if the project has no test scaffold for components and adding one is out of scope.

Commit (if tests added): `test(catalog): unit tests for category + unit pickers`

## Reporting

Standard reporting block. Surface the new branch name + open PR command for the user.
