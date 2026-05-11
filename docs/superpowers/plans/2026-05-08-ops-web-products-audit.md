# OPS-Web /products Audit — 2026-05-08

Codebase: `/Users/jacksonsweet/Projects/OPS/OPS-Web` (separate repo from `ops-ios`)
Lineage prefix: **OPS-WEB PRODUCTS - P1-<n>**

## Why this exists

The iOS catalog UX got a deep audit + redesign this week. The OPS-Web `/products` page is the OTHER source of truth for product authoring — and per the iOS app's own messaging, it's where users go for "options, modifiers, and pricing modifiers" (the layers iOS doesn't author yet). If the web flow is also broken (free-text category instead of FK, no inline category create, etc.), users hit the same disconnects on a bigger screen.

This is a **read-only audit** + **fix proposal**. Do not implement fixes without explicit user approval afterward.

## Hard constraints

- **READ ONLY for this session.** No file edits, no commits. The point is to surface gaps so the user can decide what to fix.
- Branch must remain clean. If you touch files accidentally, restore them before reporting.
- Don't apply Supabase migrations or run `execute_sql` against production.
- Cite specific file paths + line numbers in the report so the user can verify.

## Working directory

Run from `/Users/jacksonsweet/Projects/OPS/OPS-Web`. This is a Next.js + TypeScript project. Do not `cd ops-ios/...` — entirely different codebase.

## What to audit

The product authoring surface lives at:
- `src/app/(dashboard)/products/` — list + detail page (user-facing)
- `src/app/admin/shop/products/` — admin variant (owner-only?)
- `src/app/api/admin/shop/products/` — API routes
- Any sheet / modal / form components used by those pages (likely under `src/components/products/` or similar — find via grep)

**For each surface, evaluate:**

1. **Catalog FK writes.**
   - When the user creates a product, does the form write `category_id` (FK to catalog_categories) and `unit_id` (FK to catalog_units)? Or is it still on the legacy `category` and `unit` text columns?
   - The migration `add_category_id_fk_to_products` (applied 2026-05-08) added the FK. Web should write to it on every create + edit.

2. **Picker UX.**
   - Is the category input a real picker over `catalog_categories` rows for the current company? Or a free-text TextField?
   - Same question for unit — `catalog_units` picker or hardcoded enum dropdown?
   - Does the picker support inline "+ NEW CATEGORY…" / "+ NEW UNIT…" so users don't dead-end?

3. **Recipe authoring.**
   - Can users attach a recipe (ProductMaterial rows) from web? iOS just got this; web has historically been the "full setup" target so it should already work — verify.
   - Is the recipe UI usable? Family → variant cascading picker? Quantity scaling clear?

4. **Options + modifiers.**
   - Web is supposed to be the source of truth for ProductOption + ProductOptionValue + ProductPricingModifier. Verify each can be authored, edited, deleted.
   - Edge cases: required options, default values, integer ranges on modifiers, scaledByOptionId on materials.

5. **List view.**
   - Can users filter by category? Search by name / SKU?
   - Empty state UX?

6. **Permission gating.**
   - Does the page respect `catalog.products.view` / `catalog.products.manage`? (These are the permission strings used on iOS.)
   - Are admin-only surfaces actually gated server-side, not just client-side hidden?

7. **Cross-surface consistency.**
   - Compare the web Add Product form with the iOS QuickAddProductSheet (`OPS/Views/Catalog/Products/QuickAddProductSheet.swift` in the ops-ios repo). Where do they diverge in field set, validation, defaults? Each divergence is a UX risk for users who switch between platforms.

8. **Thumbnail / image field.**
   - Does the web product editor support uploading a product thumbnail today? (iOS doesn't yet — separate plan.) If it does, what bucket / column is used?

## Output format

Write a markdown report to `/Users/jacksonsweet/Projects/OPS/OPS-Web/docs/audit-2026-05-08-products.md` (create the `docs/` dir if it doesn't exist). Structure:

```
# OPS-Web /products Audit — 2026-05-08

## Surfaces audited
- [List of files + line refs]

## Per-surface findings

### Public dashboard /products
**Status:** Solid / Functional but rough / Broken / Stub
- Specific issues with file:line refs

### Admin /admin/shop/products
[same structure]

### API routes
[same structure]

## Cross-cutting findings

### FK writes (category_id, unit_id)
[per surface]

### Picker UX
[per surface]

### Recipe authoring
[per surface]

### Options + modifiers
[per surface]

### Permissions
[per surface]

### iOS ↔ Web divergence
[concrete list]

## Severity-ranked fix list

P0 — ship-blocking by perfection standard:
- [...]

P1 — high-leverage:
- [...]

P2 — polish:
- [...]

## Suggested next sessions
[grouping the P0/P1 items into separate plans the user can authorize one by one]
```

Do not stage or commit the report. Leave it untracked. The user will read, then decide which fixes to spawn separate plans for.

## Reporting (final agent message)

- **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED
- **Lineage:** OPS-WEB PRODUCTS - P1-1
- **Audit report file path:** absolute path
- **Top 3 P0 findings** restated in the chat message (so the user sees them without opening the file)
- **Concerns / judgment calls** — anything you couldn't audit (e.g. server-side RPC bodies you couldn't read, CI configs that hide policy enforcement)
- **Next session candidates** — list of separate fix plans, each one-sentence

## Begin

Read the OPS-Web codebase end-to-end on the products surface. Do not write code. Produce the audit report. Report back.
