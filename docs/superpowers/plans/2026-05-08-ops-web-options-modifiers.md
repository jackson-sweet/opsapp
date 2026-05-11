# OPS-Web Products — Options + Modifiers Authoring (P1-2)

Codebase: `/Users/jacksonsweet/Projects/OPS/OPS-Web`
Lineage prefix: **OPS-WEB PRODUCTS - P1-2**

## Why

The iOS catalog UI has a footer note on Add Product: *"Need product options or pricing modifiers? Edit on web after saving."* The 2026-05-08 audit found that web's `/products` dashboard does NOT actually expose `ProductOption` / `ProductOptionValue` / `ProductPricingModifier` authoring — only the Admin Shop subsystem does, which is a separate eCommerce flow. iOS is pointing users at a dead end.

This plan ships a real options + modifiers authoring surface on the customer-facing web product detail page. After it lands, the iOS footer note becomes accurate (no change needed on iOS — the footer points at this surface).

## Branch

Branch off `main` — independent of the FK-writes / pickers work. Branch name: `feat/products-options-modifiers`.

## Hard constraints

Same as other OPS-Web plans:

- TypeScript strict + lint + tests pass before each commit
- Stage by explicit path
- No AI attribution
- Atomic commits
- No production schema mutations (the tables `product_options`, `product_option_values`, `product_pricing_modifiers` already exist server-side per the audit)
- Visual style per `OPS-Web/CLAUDE.md` and `.interface-design/system.md`:
  - Cake Mono Light uppercase for section headers + buttons + chips
  - JetBrains Mono for numbers + bracketed micro-text + slashes
  - Mohave for body
  - Steel-blue `#6F94B0` accent ONLY on primary CTA + focus ring (one element max per screen)
  - `.glass-dense` for modals
  - Single easing curve `cubic-bezier(0.22, 1, 0.36, 1)`
  - No emoji, no exclamation points
  - `//` prefix for panel titles, `[brackets]` for instructional micro-text

## Files to read first

1. `/Users/jacksonsweet/Projects/OPS/OPS-Web/CLAUDE.md`
2. `/Users/jacksonsweet/Projects/OPS/OPS-Web/.interface-design/system.md`
3. `src/app/(dashboard)/products/page.tsx` — current dashboard (you'll add a route link from here)
4. `src/app/admin/shop/products/_components/option-manager.tsx` — REFERENCE ONLY. The Admin Shop has a working OptionManager pattern. Read it for shape, but understand: it manages `shop_product_options`, NOT `product_options`. Don't copy verbatim — different table, different field names. But the data shape + interaction patterns (drag-reorder, inline rename, allowed values list) are useful prior art.
5. `src/components/ops/product-bom-editor.tsx` — REFERENCE ONLY. The recipe/BOM editor on the catalog product side. Same vibe you want for options/modifiers.
6. iOS reference (read-only — for DTO field shape):
   - `/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/DataModels/Supabase/Catalog/ProductOption.swift`
   - `/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/DataModels/Supabase/Catalog/ProductOptionValue.swift`
   - `/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/DataModels/Supabase/Catalog/ProductPricingModifier.swift`
   - `/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Network/Supabase/DTOs/ProductExtensionDTOs.swift`
   - `/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/Catalog/Products/OptionsReadOnlyView.swift`
   - `/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/Catalog/Products/ModifiersReadOnlyView.swift`

The iOS read-only views show the rendering vocabulary — match it where it fits.

## Scope

Three entities to author:

1. **ProductOption** — per-product. Fields: `id`, `product_id`, `name`, `kind` (one of `select|integer|boolean`), `affects_price` (bool), `affects_recipe` (bool), `required` (bool), `default_value` (text), `option_default_source` (text, optional), `sort_order` (int).
2. **ProductOptionValue** — per-option, only for `kind=select`. Fields: `id`, `option_id`, `value` (text), `sort_order` (int).
3. **ProductPricingModifier** — per-product. Fields: `id`, `product_id`, `option_id`, `trigger_value_id` (uuid, nullable — for select options), `trigger_int_min` / `trigger_int_max` (int, nullable — for integer options), `modifier_kind` (one of `add_per_unit|add_flat|multiply`), `amount` (numeric).

Each needs: list, create, update (rename / reorder / change kind), delete (soft if available else hard with confirmation).

## Phase 1 — API services

- `src/lib/api/services/product-options-service.ts` — list/create/update/delete for `product_options` + nested `product_option_values`. Match the existing service pattern in `product-service.ts`.
- `src/lib/api/services/product-pricing-modifiers-service.ts` — list/create/update/delete for `product_pricing_modifiers`.
- TanStack Query hooks at `src/lib/hooks/use-product-options.ts` + `use-product-pricing-modifiers.ts`.

Commit: `feat(catalog): product options + pricing modifiers services`

## Phase 2 — Route + page shell

New route: `src/app/(dashboard)/products/[id]/options/page.tsx`

Layout:
- Page header: `// PRODUCT :: <name>` + subtitle `[OPTIONS & MODIFIERS]`
- Two main sections:
  - **OPTIONS** — list of ProductOption rows. Each row shows: name, kind chip, required/affects_price/affects_recipe flags, sort handle, edit + delete buttons. Below the list: `+ ADD OPTION` button.
  - **PRICING MODIFIERS** — list of ProductPricingModifier rules. Each row shows the humanized rule (e.g. "// WHEN COLOR = RED → +$5.00 PER UNIT") + edit + delete buttons. Below: `+ ADD MODIFIER` button.
- Empty states (matching the iOS voice): `// NO OPTIONS YET — TAP + ADD OPTION` / `// NO MODIFIERS YET — TAP + ADD MODIFIER`.

Add a link/button from `(dashboard)/products/page.tsx` (in the product list row + the edit modal) that navigates to this route. Permission-gate the link on `catalog.products.manage`.

Commit: `feat(catalog): product options + modifiers route shell`

## Phase 3 — Option authoring UI

Modal/sheet for create + edit:
- Name (required text)
- Kind segmented control (SELECT / INTEGER / BOOLEAN)
- Affects price + Affects recipe + Required toggles
- Default value (text — interpretation depends on kind: for select it's an option value id, for integer it's a number, for boolean it's true/false)
- For SELECT kind: a sub-list of allowed values with add/edit/reorder/delete (mini version of the same interaction pattern)

Save calls the appropriate service method. Optimistic update on the list.

Drag-to-reorder on the parent list updates `sort_order` server-side (use a debounced batch update — the existing recipe BOM editor probably has a pattern for this).

Confirm-on-delete (per the OPS perfection standard for destructive actions).

Commit: `feat(catalog): ProductOption authoring (create + edit + delete + reorder)`

## Phase 4 — Modifier authoring UI

Modal/sheet for create + edit:
- Option picker (which option triggers this modifier — Combobox over the product's existing options)
- Trigger:
  - If selected option is `kind=select`: picker for which option value triggers
  - If `kind=integer`: min + max int range
  - If `kind=boolean`: implicit (modifier fires when value is true)
- Modifier kind segmented control (ADD PER UNIT / ADD FLAT / MULTIPLY)
- Amount (numeric input — currency for add, multiplier for multiply)

Humanize-on-save: the row label ("// WHEN COLOR = RED → +$5.00 PER UNIT") is rendered from the same data on read (see iOS `ModifiersReadOnlyView` for the exact string templates).

Confirm-on-delete.

Commit: `feat(catalog): ProductPricingModifier authoring (create + edit + delete)`

## Phase 5 — iOS footer note (now accurate, no change needed)

The iOS QuickAddProductSheet footer says "Need product options or pricing modifiers? Edit on web after saving." Once this plan ships and is deployed, that note is finally accurate. **No iOS code change required.**

If the agent has time + token budget left, surface in the report whether the footer wording could be tightened to point at the new specific URL (e.g. via deep-link), but DO NOT actually edit iOS code in this plan — that's out of scope.

## Phase 6 — Bible update

Update `ops-software-bible/03_DATA_ARCHITECTURE.md` (separate git root) — extend the catalog/products section with the options + modifiers authoring URL + flow.

Commit (in bible repo): `docs(bible): web product options + modifiers authoring`

## Reporting

Standard reporting block. List both new sections as the deliverable. Confirm the iOS footer note is now accurate (closes the loop the audit flagged).
