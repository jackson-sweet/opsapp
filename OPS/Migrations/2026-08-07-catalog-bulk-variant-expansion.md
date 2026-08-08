# Catalog bulk variant expansion

## Purpose

Adds the atomic backend boundary for **Catalog → Stock → Bulk Add Variants**. One request can add a real option axis (for example, `Top profile`) and its existing/new values across many existing families without a spreadsheet or repeated family edits.

## Safety contract

- Requires the signed-in user’s company to match `p_company_id`.
- Requires `catalog.manage` with `all` scope.
- Locks the company expansion lane, selected families, and active source variants before validation.
- Compares the client’s complete clone-relevant source snapshot with current server state before any write.
- Rejects incomplete pins, multiple values per option, duplicate combinations, duplicate axes, and stale catalogs before mutation.
- Preserves every existing variant ID, SKU, quantity, thresholds, pricing, unit, stock unit, and history row.
- Adds the existing value to current variants only when the option axis is new.
- Clones only variants carrying the selected existing value when the axis already exists.
- New variants start at quantity `0` and SKU `NULL`; safe unit/pricing/cost/threshold/active settings are copied.
- Never copies `catalog_stock_units`, inventory history, or quantity.
- Stores the complete authoritative response by company + idempotency key so retries cannot duplicate work, and rejects reuse of that key with a different payload.
- Returns all active options, values, variants, and joins for affected families so iOS can reconcile immediately.

## Release order

1. Apply this migration to Supabase and verify the function/table grants and RLS policies.
2. Exercise a non-production fixture with new-axis, existing-axis, stale-preview, retry, and mixed-family cases.
3. Release the matching iOS build.

The iOS flow must remain unavailable until this migration is confirmed in the target environment. Do not loop existing single-family APIs as a fallback; that would break the all-or-nothing guarantee.

## Rollback

```sql
revoke execute on function public.catalog_bulk_expand_variants(uuid, text, jsonb) from authenticated;
drop function if exists public.catalog_bulk_expand_variants(uuid, text, jsonb);
drop table if exists public.catalog_bulk_variant_requests;
```

Rolling back the function does not undo catalog variants already created by successful requests.
