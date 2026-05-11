# iOS Catalog Products Import — 2026-05-08

Branch: `catalog-variant-model`
Working dir: `/Users/jacksonsweet/Projects/OPS/ops-ios`
Build: `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` (device-only)
Lineage prefix: **CATALOG IMPORT - P1-2**

## Why

The CSV import flow (CATALOG IMPORT - P1-1) shipped Stock import (families + variants). Products import was Phase 6 in that plan and was deferred. Closes that loop: a second tab in `CatalogImportSheet` lets users bulk-load `Product` rows the same way they bulk-loaded inventory.

The RPC SQL was NOT written for products in P1-1; that's part of this scope.

## Hard constraints

- **NEVER** `git add .` / `-A`. Stage by explicit path.
- **NEVER** AI attribution in commits.
- Build between commits.
- All styling via OPSStyle tokens.
- **No production migrations.** Write the products RPC SQL to a file; do NOT call `apply_migration` / `execute_sql`. The user will run.
- Mirror the catalog import RPC pattern verbatim — same validation shape, same error format, same SECURITY DEFINER + GRANT TO authenticated.

## Phase 1 — Products import RPC SQL

Write to `OPS/Migrations/2026-05-08-products-import-rpc.sql`:

- `products_import_validate(p_company_id uuid, p_payload jsonb) RETURNS jsonb`
- `products_import_apply(p_company_id uuid, p_payload jsonb) RETURNS jsonb`

Payload shape:
```json
{ "products": [
  { "row_index": 0,
    "name": "Composite deck install",
    "description": "...",
    "base_price": 25.00,
    "unit_cost": 12.00,
    "category_id": "uuid-or-null",
    "unit_id": "uuid-or-null",
    "category": "Hardware",   // legacy text alongside FK
    "unit": "sqft",            // legacy text alongside FK
    "pricing_unit": "sqft",
    "sku": "DECK-INST",
    "kind": "service",         // 'service' | 'good'
    "type": "LABOR",           // LineItemType raw
    "is_taxable": true
  }
] }
```

Validation rules:
- name required + non-blank
- base_price required, numeric, >= 0
- unit_cost optional, numeric, >= 0
- category_id, unit_id if set must belong to caller's company + active
- kind in ('service','good') if set, else nil
- type in LineItemType enum if set, else nil
- pricing_unit free text (legacy enum); accept any string
- sku optional, no uniqueness check (Products table has no unique SKU constraint per audit; just pass through)

Companion `.md` doc explains the file. **DO NOT APPLY.**

Commit: `docs(catalog): products import RPC SQL (NOT applied)`

## Phase 2 — Repository + DTOs

- New `OPS/Network/Supabase/Repositories/ProductsImportRepository.swift` — same shape as `CatalogImportRepository`. Two methods: `validate(_:)` + `apply(_:)`.
- New `OPS/Network/Supabase/DTOs/ProductsImportDTOs.swift` — `ProductsImportPayload`, `ProductsImportProduct`, `ProductsImportResult`.

Commit: `feat(catalog): ProductsImportRepository + DTOs for atomic products import`

## Phase 3 — CSV mapper

- New `OPS/Services/ProductsCSVMapper.swift` — takes `[[String: String]]` (output of existing `CSVParser`) + `[CatalogCategory]` + `[CatalogUnit]` + a column-mapping config + `companyId` → produces `ProductsImportPayload`.
- Resolves the typed category/unit text to FK ids by exact case-insensitive name match within the company. Same fallback iOS QuickAddProductSheet uses.
- Per-row validation: name non-empty, base_price numeric, unit_cost numeric if present.
- Reuse `CSVParser` from the catalog import work — it's pure-function and already tested.
- Add XCTests at `OPSTests/Catalog/ProductsCSVMapperTests.swift`: one happy path, one with embedded quotes, one with FK fallbacks (typed category that matches vs doesn't).

Commit: `feat(catalog): ProductsCSVMapper for products import`

## Phase 4 — UI: second tab in CatalogImportSheet

Modify `OPS/Views/Catalog/Import/CatalogImportSheet.swift`:

- Add a tab strip at the top: `STOCK | PRODUCTS`. Default to STOCK (preserves existing behavior).
- Each tab renders the same 4-step flow (PICK → MAP → PREVIEW → APPLY) but uses the appropriate parser/mapper/repository for its target.
- The column-mapping step's required + optional column list differs per tab (Stock: family_name, sku, quantity, etc.; Products: name, base_price, unit_cost, category, unit, sku, etc.).
- Preserve all the polish from P1-1: tap-outside dismiss, error inline, retry on apply failure.

Commit: `feat(catalog): products tab in CatalogImportSheet`

## Phase 5 — Bible

Update `ops-software-bible/03_DATA_ARCHITECTURE.md` (separate git root) — extend the catalog import section with the products RPC schema + tab UI note.

Commit (in bible repo): `docs(bible): products import RPC + flow`

## Reporting

Standard reporting block. Surface the products RPC SQL file path with "USER MUST APPROVE AND RUN" callout.
