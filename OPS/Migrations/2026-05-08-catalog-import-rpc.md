# Catalog CSV Import — atomic RPC

**Files:**
- `2026-05-08-catalog-import-rpc.sql` — function definitions
- (companion) — this doc

**Status:** NOT APPLIED. Awaiting user approval before it touches any
database. Apply via the Supabase SQL editor or `apply_migration` only
after reading the SQL end-to-end.

## What it does

Defines two new functions on the `public` schema:

- `catalog_import_validate(p_company_id uuid, p_payload jsonb) RETURNS jsonb`
  — pure validator, never INSERTs.
- `catalog_import_apply(p_company_id uuid, p_payload jsonb) RETURNS jsonb`
  — runs the validator, then INSERTs every family + variant inside a
  single transaction. ROLLBACK on any failure.

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

See the comment block at the top of the SQL file. Two arrays
(`families`, `variants`); each row carries a 0-based `row_index` so
errors can point at the originating CSV row, and variants reference
families by `family_row_index` (server resolves that to the new family
uuid after INSERT).

## Result schema

Success:

```json
{
  "success": true,
  "created_family_ids":  {"0": "uuid", "1": "uuid"},
  "created_variant_ids": {"0": "uuid", "1": "uuid"},
  "totals": {"families": N, "variants": M}
}
```

Failure:

```json
{
  "success": false,
  "errors": [
    {"scope":"family","row_index":3,"field":"name","reason":"name is required and cannot be blank."}
  ]
}
```

`scope` is `family` | `variant` | `payload`. `row_index` is `-1` for
payload-scope errors (auth, shape, etc.). The iOS preview screen renders
each error verbatim so the user can locate the offending CSV row by
index.

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
SELECT public.catalog_import_validate(
  '00000000-0000-0000-0000-000000000000'::uuid,  -- swap for your company
  '{"families":[{"row_index":0,"name":"Test Family"}],
    "variants":[{"row_index":0,"family_row_index":0,"quantity":1}]}'::jsonb
);
```

Expected: `{"success": true, "totals": {...}}`. Re-run with `apply` to
INSERT (this writes data — only run against a scratch company).

## SKU collision policy

For v1, a SKU that already exists for an active variant in the company
is treated as a hard error. The DB has no unique constraint on SKU
(only an index), so this guard lives in the RPC. Revisit when we have a
duplicate-SKU policy and an upsert-or-error toggle on the import sheet.
