# OPS-Web Products — Kind/Type Pickers + DTO Drift (P1-1)

Codebase: `/Users/jacksonsweet/Projects/OPS/OPS-Web`
Lineage prefix: **OPS-WEB PRODUCTS - P1-1**

## Why

The iOS↔web divergence still has a gap. The 2026-05-08 audit found:
- Web's product form has no `kind` (Service/Good) or `type` (LABOR/MATERIAL/OTHER) pickers (P1-1 finding).
- The web `Product` TS interface is missing many fields the iOS DTO carries: `pricingUnit`, `sku`, `thumbnailUrl`, `minimumCharge`, `minimumQuantity`, `showBomOnEstimate`, `showInStorefront`, `tieredPricing`, `isFavorite`, `taskTypeRef`.

Result: a product authored on iOS with thumbnail + sku + minimum charge round-trips through web edits losing all of them, because web's Product type doesn't model them. Even though the DB columns exist, the form doesn't read/write them.

This plan closes that gap. After it lands, web's Product type matches the iOS DTO field-set, and the form exposes the missing user-facing controls (kind, type, SKU, thumbnail-display-only, minimum charge/quantity, favorite toggle).

## Branch

`cd /Users/jacksonsweet/Projects/OPS/OPS-Web && git worktree add /Users/jacksonsweet/Projects/OPS/ops-web-kind-type feat/products-fk-writes` — branch off the FK-writes branch (PR #38 base) since this work builds on the FK type additions. Then `cd /Users/jacksonsweet/Projects/OPS/ops-web-kind-type && git checkout -b feat/products-kind-type-dto-drift`.

**Use a dedicated worktree** — do NOT work in the main `OPS-Web` checkout. The P0-2 + P1-2 parallel agents had branch-flip issues sharing a single worktree. Branch protection through worktree isolation is the cleaner pattern.

If the worktree at `/Users/jacksonsweet/Projects/OPS/ops-web-kind-type` already exists (leftover from a prior attempt), reuse it. If `/Users/jacksonsweet/Projects/OPS/ops-web-options-modifiers` exists, leave it alone — that's PR #40's home.

## Hard constraints

- TypeScript strict + lint + tests must pass before each commit. Commands: `npx tsc --noEmit`, `npx next lint`, `npx vitest run` (this repo uses `npm`/`npx`, NOT pnpm).
- Stage by explicit path; no `git add .` / `-A`.
- No AI attribution in commits.
- Atomic commits.
- No production schema mutations.
- Visual: Cake Mono Light uppercase, JetBrains Mono numerals + `//` prefix, Mohave body, steel-blue `#6F94B0` accent ONLY on primary CTA + focus ring (one per screen).
- No emoji, no exclamation points.

## Files to read first

1. `OPS-Web/CLAUDE.md`
2. `OPS-Web/.interface-design/system.md`
3. `OPS-Web/src/lib/types/pipeline.ts` — current Product interface
4. `OPS-Web/src/lib/api/services/product-service.ts` — mapProductToDb + read mapper
5. `OPS-Web/src/app/(dashboard)/products/page.tsx` — current form (will need additions)
6. iOS reference (read-only): `/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Network/Supabase/DTOs/ProductDTOs.swift` — canonical DTO field set. The web TypeScript type should match field-for-field.
7. iOS reference for UI patterns: `/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/Catalog/Products/QuickAddProductSheet.swift` — see the Advanced disclosure for the kind / line item type / taxable / minimum-charge layout.

## Phase 1 — TypeScript Product type expansion

In `src/lib/types/pipeline.ts`, add to the Product interface:

```ts
pricingUnit?: string | null;       // "flat_rate" | "each" | "linear_foot" | "sqft" | "hour" | "day"
sku?: string | null;
thumbnailUrl?: string | null;      // Supabase Storage public URL
kind?: "service" | "good" | null;
type?: "LABOR" | "MATERIAL" | "OTHER" | null;
minimumCharge?: number | null;
minimumQuantity?: number | null;
showBomOnEstimate?: boolean;
showInStorefront?: boolean;
isFavorite?: boolean;
tieredPricing?: unknown;           // jsonb passthrough
taskTypeRef?: string | null;       // FK to task_types, separate from taskTypeId (legacy)
```

Update any `Omit<Product, ...>` consumers if TypeScript surfaces drift. Run `npx tsc --noEmit` to find them.

Commit: `feat(products): expand Product type to match iOS DTO field set`

## Phase 2 — ProductService read + write mapping

In `src/lib/api/services/product-service.ts`:

- Add each new field to `mapProductToDb()` (write mapper). Snake-case the column names: `pricing_unit`, `sku`, `thumbnail_url`, `kind`, `type`, `minimum_charge`, `minimum_quantity`, `show_bom_on_estimate`, `show_in_storefront`, `is_favorite`, `tiered_pricing`, `task_type_ref`.
- Add each to the read mapper (`mapDbToProduct` or wherever).
- Sparse-update pattern: in `update`, only send fields present in the input — don't force-write NULL.

Commit: `feat(products): wire new Product fields through ProductService read + write`

## Phase 3 — Kind + Type pickers in the form

In `src/app/(dashboard)/products/page.tsx`, add to the form modal's Advanced section (or create one if it doesn't exist):

- **Kind** segmented control: `SERVICE | GOOD`. Default to current `kind` value, fall back to `service`.
- **Type** segmented control: `LABOR | MATERIAL | OTHER`. Default to current `type`, fall back to `LABOR`.

Use a Radix Tabs or simple button-group with the design system tokens. Match the iOS visual: light borders, Cake Mono Light labels, steel-blue fill for the selected option (but remember — accent is ONLY on the primary save CTA; segmented selection uses a subdued highlight).

On form submit, pass `kind` + `type` through to ProductService. Read-back loads them.

Commit: `feat(products): kind + type segmented pickers on product form`

## Phase 4 — SKU input + minimum-charge/quantity fields

Add to the same Advanced section:

- **SKU**: text input, uppercase auto-cap, autocorrect disabled (mirrors iOS).
- **Minimum charge**: numeric input with `$` prefix, optional.
- **Minimum quantity**: numeric input, optional.

All three are optional; nullable on save. Validation: minimum_charge / minimum_quantity must parse to a number ≥ 0 if non-empty.

Commit: `feat(products): SKU + minimum-charge + minimum-quantity inputs on product form`

## Phase 5 — Thumbnail display (read-only on web for v1)

The thumbnail-upload UX is iOS-only for now (Phase 4 of the thumbnail plan didn't include web upload). But web should at least DISPLAY a thumbnail when one exists — both in the products list row and in the edit modal.

In the product list:
- If `product.thumbnailUrl` exists, render a small 40x40 image leading the row (Next.js `<Image>` with proper width/height).
- Otherwise, render a small placeholder rectangle with `// NO IMAGE` text or just a subdued border.

In the edit modal:
- Show a 96x96 preview at the top of the modal if `thumbnailUrl` exists.
- Below, add a small read-only note: `// THUMBNAIL UPLOAD AVAILABLE ON iOS`. (Web upload is a separate scope.)

Commit: `feat(products): display thumbnail in list row + edit modal (read-only)`

## Phase 6 — isFavorite + showBomOnEstimate toggles

Two small toggles in the Advanced section:

- **Favorite** — pin to top of the list view (mirrors iOS). Quick toggle on the row + form.
- **Show BOM on estimate** — when true, the product's recipe materials appear on customer-facing estimates. Default false.

`showInStorefront` is shop-system only; do NOT expose it on the catalog form (the audit confirmed `/admin/shop` is the storefront authoring surface).

Commit: `feat(products): favorite + show-bom-on-estimate toggles on form`

## Phase 7 — Tests

If there are tests for the form or the service, update them. Otherwise add minimum coverage:

- `tests/unit/services/product-service.test.ts` — read + write round-trip for the new fields
- Skip if test scaffold is too narrow to extend without scope creep

Commit (if added): `test(products): cover new Product fields in service mapping`

## Reporting (final agent message)

- **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED
- **Lineage:** OPS-WEB PRODUCTS - P1-1
- **Branch:** `feat/products-kind-type-dto-drift`
- **Worktree path:** `/Users/jacksonsweet/Projects/OPS/ops-web-kind-type`
- **Commits:** SHA + subject in order
- **Files changed by commit**
- **Verification:** type-check + lint + tests results
- **Suggested PR title + body** + `gh pr create` command (base = `feat/products-fk-writes` since this stacks)
- **What's deferred:** thumbnail UPLOAD on web (currently iOS-only; if you want web upload too, that's a separate plan); options/modifiers authoring (already shipped on PR #40); storefront fields (shop-system scope)
- **Conflict surface** with PR #39 (`feat/products-fk-pickers`) and PR #40 (`feat/products-options-modifiers`) — note that all three PRs touch `(dashboard)/products/page.tsx` and merging will need to reconcile imports + form modal additions

## Begin

`git worktree add /Users/jacksonsweet/Projects/OPS/ops-web-kind-type feat/products-fk-writes && cd /Users/jacksonsweet/Projects/OPS/ops-web-kind-type && git checkout -b feat/products-kind-type-dto-drift`. Read the plan. Phase 1 first. Type-check + lint between commits. Report when done.
