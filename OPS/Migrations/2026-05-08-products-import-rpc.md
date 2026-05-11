# Products CSV Import — atomic RPC

**Files:**
- `2026-05-08-products-import-rpc.sql` — function definitions
- (companion) — this doc

**Status:** NOT APPLIED. Awaiting user approval before it touches any
database. Apply via the Supabase SQL editor or `apply_migration` only
after reading the SQL end-to-end.

## What it does

Defines two new functions on the `public` schema:

- `products_import_validate(p_company_id uuid, p_payload jsonb) RETURNS jsonb`
  — pure validator, never INSERTs.
- `products_import_apply(p_company_id uuid, p_payload jsonb) RETURNS jsonb`
  — runs the validator, then INSERTs every product row inside a single
  transaction. ROLLBACK on any failure.

Both are SECURITY DEFINER and bound to `authenticated`. Callers must own
`p_company_id` (verified against `private.get_user_company_id()`).

## Why an RPC instead of a client-side bulk insert

- One round-trip. iOS posts the parsed payload, server walks every row
  inside one transaction, returns a structured success/failure shape.
- Atomic per call. The client never sees a half-imported state. If row
  37 has a typo, rows 0-36 do not survive — nothing is created.
- Same validation in preview + apply. The dry-run (`validate`) and the
  real apply share the same plpgsql block — there's only one source of
  truth for "what counts as a valid row," so the user never sees a
  preview that succeeds and an apply that fails (or vice versa).

## Payload schema

See the comment block at the top of the SQL file. One array (`products`);
each row carries a 0-based `row_index` so errors can point at the
originating CSV row.

## Result schema

Success:

```json
{
  "success": true,
  "created_product_ids": {"0": "uuid", "1": "uuid"},
  "totals": {"products": N}
}
```

Failure:

```json
{
  "success": false,
  "errors": [
    {"scope":"product","row_index":3,"field":"name","reason":"name is required and cannot be blank."}
  ]
}
```

`scope` is `product` | `payload`. `row_index` is `-1` for payload-scope
errors (auth, shape, etc.). The iOS preview screen renders each error
verbatim so the user can locate the offending CSV row by index.

## Schema notes

`products` table has the following relevant NOT-NULL columns with defaults:

- `base_price numeric NOT NULL DEFAULT 0`
- `pricing_unit text NOT NULL DEFAULT 'each'`
- `kind text NOT NULL DEFAULT 'service'`
- `type text NOT NULL DEFAULT 'LABOR'`

The RPC requires `base_price` in the payload (per the validation rules),
but the apply path falls back to safe defaults for `pricing_unit`, `kind`,
and `type` when omitted — matching what `INSERT INTO products` would do
if you elided the column. `default_price` is mirrored from `base_price`
via a Postgres trigger, so the RPC writes only `base_price` and the
trigger handles the rest.

## How to run

1. **Supabase SQL editor (recommended for one-off review).** Paste the
   SQL into the editor, run it, confirm both functions appear under
   Database → Functions.
2. **`apply_migration` MCP tool.** Pass the SQL block as the `query`.
   Idempotent — re-runs are safe because both definitions use
   `CREATE OR REPLACE FUNCTION`.

## Verification

After applying, you can smoke-test from psql / SQL editor:

```sql
SELECT public.products_import_validate(
  '00000000-0000-0000-0000-000000000000'::uuid,  -- swap for your company
  '{"products":[{"row_index":0,"name":"Test Product","base_price":10}]}'::jsonb
);
```

Expected: `{"success": true, "totals": {"products": 1}}`. Re-run with
`apply` to INSERT (this writes data — only run against a scratch company).

## SKU policy

Unlike the catalog import RPC, `products_import_*` does not enforce SKU
uniqueness. The `products` table has no unique SKU constraint (per audit),
and the user explicitly opted out of a soft-fail check. SKU is passed
through verbatim. If duplicate-SKU policy ever lands, revisit here.
