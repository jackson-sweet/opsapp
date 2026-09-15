# Legacy expense edge writer v5 — rollback provenance only

Source of the ACTIVE `accounting-sync-expense` v5 function that writes directly to QuickBooks/Sage. Kept solely so the pre-schema rollback path is reconstructible. It reads `SUPABASE_SERVICE_ROLE_KEY` from the runtime environment; no secret value is stored here. See `manifest.json` for hashes and the unresolved 5-byte listing discrepancy on `index.ts`. **Never redeploy this function after the atomic expense bundle has committed.**
