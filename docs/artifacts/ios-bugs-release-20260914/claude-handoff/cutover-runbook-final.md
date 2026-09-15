# Expense release cutover — final operator runbook (IOS BUGS P9-4)

Status: prepared and reviewed, **not executed**. Requires Jackson's explicit backend release approval for the exact scope in the last section. This runbook is the day-of procedure; `cutover-analysis.md` is the underlying analysis and `runbook-review.md` is the independent review whose six required changes are folded in here.

## Fixed identities

| Item | Value |
|---|---|
| Supabase project | `ijeekuhbatykdomumfjx` |
| Vercel project / team / domain | `prj_hglAp4p8MWheqpQn0UDTygVwlziU` / `team_zxfRqTDMWynswbBaqX7OQxOY` / `app.opsapp.co` |
| Production today | deployment `dpl_138EdNzoYSP4peM1qg9Yk5H7rWdF`, commit `b5b0cb59275f0addf923db608b1daeac4afca844` |
| Hold build | OPS-Web `e6336445f54b8f3a1a38489fc5d4c50dae7449f7`, branch `release/p9-expense-compatibility-hold`, worktree `.worktrees/ios-bugs-p9-accounting-hold` |
| Candidate | OPS-Web `d2d7457f19c594d20701e480ca9f0ed211656222`, branch `release/p9-expense-candidate`, worktree `.worktrees/ios-bugs-p9-expense-release` |
| Edge adapter | candidate `supabase/functions/accounting-sync-expense/index.ts` (SHA256 `34db00f0…`) and `handler.ts` (`6565c864…`); gateway `verify_jwt=false` |
| Legacy edge v5 (rollback provenance only) | `legacy-edge-v5/` holds all three deployed files captured read-only; deployed bundle (eszip) SHA256 `0135ba82e5fff4165e7eab7ea90d42afa70833c3388b5583859ffaeaa9849048`; the function is not in any repo tree. `index.ts` capture is 12975 bytes against a 12970-byte listing (unresolved), so re-capture on the day before any redeploy |
| Atomic bundle | `atomic-install/expense-release-atomic.sql`, SHA256 `4d53da61929337ab783070818f387ac1e8650cd900230fd7685418a32c543d22`, 146738 bytes; guard `0c7f1fd8…` |
| Worker schedule (UTC) | QBO push `14-59/20 13-23,0-4`, Sage push `34-59/20 13-23,0-4`; both routes `maxDuration=300`; no worker runs 05:00–12:59 UTC |

Standing rules for the whole procedure:

- After the bundle commits, **v5 is never redeployed under any rollback**. Rollback from then on means keeping the adapter and the hold or candidate build.
- The four constituent migrations are never applied individually. The bundle is applied exactly once.
- `EXPENSE_ACCOUNTING_WRITE_ENABLED` is not set at any point in this release.
- OPS-Web `main` is not pushed or merged as part of this release. After stage 4, any push to `main` is itself a customer release that must carry the candidate's 71 paths and needs its own approval.
- Every check below is read-only unless it is the stage's single named action. No cron is invoked as a probe; no expense is created or approved to generate evidence; no claim or acceptance marker is cleared.

## Stage 0 — Preflight (same session, all read-only except the two unaliased builds)

1. `vercel whoami` → confirm the OPS team. Copy `ops-web/.vercel/project.json` (gitignored) into both worktrees so the CLI targets `ops-web`.
2. `vercel env ls production` → record a names-only listing. Assert: `EXPENSE_ACCOUNTING_WRITE_ENABLED` absent; `SAGE_WRITE_ENABLED` and `SAGE_PRODUCTION_WRITE_ENABLED` absent; `ACCOUNTING_WRITE_ENABLED` present. No values are read into evidence.
3. Supabase read-only, within 30 minutes of stage 1: `expense-preflight-readonly.sql` (48 function fingerprints, absence, claims, legacy evidence) and `atomic-install/baseline-preflight-readonly.sql` both pass; ledger shows none of the five prepared versions; queue shows zero `expense` rows and the two known nonterminal QuickBooks rows unchanged; `accounting-sync-expense` is still v5 with `verify_jwt=false`. Any drift stops the release.
4. Confirm in the Supabase dashboard that no GitHub migrations integration is enabled for this project (it would otherwise discover the constituent files). Record the confirmation.
   Also re-capture the complete v5 source read-only (`get_edge_function accounting-sync-expense`: `index.ts`, `_shared/supabase-client.ts`, `_shared/cors.ts`), write the three files programmatically into `legacy-edge-v5/`, and diff against the existing capture. This is the only authoritative v5 rollback source; without it, the pre-bundle rollback for stage 2 is to keep the adapter serving (it fails closed with a bounded 404 and loses no data).
5. Build both deployments now, without aliasing, so later stages are promotions: from each worktree `vercel deploy --prod --skip-domain --yes`. Record `HOLD_DEPLOY_ID` and `CANDIDATE_DEPLOY_ID`, their URLs and build logs; `vercel inspect <id>` must show the expected commit. Production builds use production env, which is why step 2 matters. Neither deployment serves customers yet.
6. Pick the window. Stages 1–4 take roughly 20 minutes of waiting. Prefer a slot inside 13:00–04:59 UTC and time stage 4 so a QBO worker minute (:14/:34/:54) follows it within 20 minutes, which lets the post-release smoke be observed if a customer approves an expense. Avoid applying the bundle during :14–:19, :34–:39, :54–:59 (worker windows). If the release runs 05:00–12:59 UTC, say so in the record: an empty worker log is then expected and is not evidence.

## Stage 1 — Hold build in service

- **Action:** `vercel promote HOLD_DEPLOY_ID`. Record **T1** as the moment `vercel inspect` shows the production alias on `HOLD_DEPLOY_ID`.
- **Verify:** `app.opsapp.co` serves; the alias points at `HOLD_DEPLOY_ID`. Scheduled crons follow the alias.
- **Drain:** wait at least 300 seconds after T1. Read-only: Vercel runtime logs for `dpl_138…` show no push-queue invocation starting after T1; the queue has no claimed rows older than the last worker minute. Before stage 3 no expense row can exist, so this bound is conservative by design.
- **Rollback (this stage only):** `vercel rollback dpl_138EdNzoYSP4peM1qg9Yk5H7rWdF`. Safe: nothing has changed in the database.

## Stage 2 — Retire the direct-provider edge writer

- **Action:** deploy the adapter with the approved Supabase `deploy_edge_function` call: name `accounting-sync-expense`, the two candidate files, `verify_jwt=false`. Read back with `list_edge_functions`: version incremented past 5, source bytes match the candidate hashes. Record **T2** as that readback time.
- **Confirm serving without touching an expense:** `curl -s -i -X POST https://ijeekuhbatykdomumfjx.supabase.co/functions/v1/accounting-sync-expense -H 'apikey: <anon key>' -H 'Content-Type: application/json' -d '{}'` (no bearer). Expect HTTP 401 with body `{"error":"Authentication required."}`. v5 cannot produce that response (it throws `Unauthorized`), so this uniquely identifies the adapter.
- **Drain:** wait at least 400 seconds after T2 (hosted worker wall-clock limit). Read-only: `query_logs` on `function_edge_logs` from T2 onward grouped by the invocation's version attribute must show only the new version; if this project's log schema exposes no version attribute on the day, fall back to gateway `edge_logs` for path `/functions/v1/accounting-sync-expense` and inspect response shapes (only 401/404 adapter shapes are acceptable). Note: in the 24 hours before preparation there were zero edge-function invocations of any kind in this project, so an empty result is expected and is not failure. Any v5-shaped response after T2 restarts the drain from a corrected T2; if version retirement cannot be established, stop before stage 3.
- **Rollback:** only while the bundle has **not** committed, v5 may be redeployed from the same-day capture in `legacy-edge-v5/` (all three files, `verify_jwt=false`). If that capture was not made, leave the adapter serving; it is a safe pre-bundle state. From the moment stage 3 commits, redeploying v5 is closed permanently.

## Stage 3 — Apply the atomic bundle once

- **Preconditions:** T1+300 s and T2+400 s both satisfied; stage 0 step 3 re-run within the last 10 minutes; not inside a worker window.
- **Action:** exactly one approved Supabase `apply_migration` call whose `query` is the byte-exact bundle (146738 bytes, SHA256 above) and whose name is `expense_release_atomic`. Record the returned version and the wall-clock time as **T3**.
- **Verify:** read back `supabase_migrations.schema_migrations` → exactly one new row, name/version as returned; run `atomic-install/postconditions-production.sql` (read-only transaction; the fixture postconditions minus the synthetic seeded batch) → passes; run `baseline-preflight-readonly.sql` → now rejects with `source baseline changed`, as proven locally for an installed database. Record both outputs.
- **Failure handling:** an error from the call means nothing installed (single transaction, proven locally including a late failure); re-run the read-only guard to confirm the baseline is intact before any retry. A DDL lock wait rolls back cleanly. If the result is uncertain (timeout, transport), read the ledger and schema before doing anything else; never retry blind.
- **Legacy interval reconciliation:** run `cutover-legacy-interval-readonly.sql` with T2 and T3. Record the result set. Those approvals have no ledger event and are not auto-queued; handling them is an explicit operator decision under the later activation approval, never a replay.
- **Rollback:** none is reversible and none is needed. Keep the hold build and the adapter serving. Never drop the new relations; they hold captured events.

## Stage 4 — Candidate in service (within 20 minutes of T3)

- **Preconditions:** `vercel env ls production` re-listed → `EXPENSE_ACCOUNTING_WRITE_ENABLED` still absent (record).
- **Action:** `vercel promote CANDIDATE_DEPLOY_ID`. Record **T4** when the alias shows it.
- **Verify:** `vercel inspect` shows commit `d2d7457f1`; unauthenticated GET `/api/integrations/accounting/expense-issues` returns 401 (route exists); env re-listed, gate absent; `list_edge_functions` still shows the adapter version.
- **Smoke, conditional and read-only:** if a customer approves an expense after T3, after the next QBO worker minute confirm the queue row is `blocked`, `last_error='Expense accounting sync is paused.'`, `locked_by is null`, `attempts=1`, one `accounting_sync` notification per eligible admin, and the settings expense-issues list shows PAUSED with no Retry. Do not create an expense to force this.
- **Rollback:** `vercel promote HOLD_DEPLOY_ID`. Never `dpl_138…`: plain production with the schema installed would route expense rows through the generic QuickBooks path, refreshing tokens and retrying a `TypeError` five times before blocking (no provider write, but wrong). The hold with the schema is compatible; its one known gap is that the "Expense sync needs review" notification link lands on the accounting tab without the paused list until the candidate is promoted again.

## Stage 5 — Canonicalize (local, same day, before any other migration command)

1. In the candidate worktree and in `ops-web/.worktrees/main-integrate`: move the four constituent files unchanged to `docs/artifacts/expense-release/constituents/`; add `supabase/migrations/<returned_version>_expense_release_atomic.sql` byte-identical to the submitted payload; add a supersession record mapping the four prepared versions to the returned one; update the three `scripts/test-expense-*-postgres.sh` paths; run the SQL harness; commit.
2. Bible: move the three expense pending mirrors and the payroll mirror to the applied archive under the returned version; record the ledger row in `03_DATA_ARCHITECTURE.md`.
3. Append deployment evidence to the three bug reports with a guarded update; do not close them (phone acceptance and provider activation remain open).

## Exact approval scope requested from Jackson

1. Promote the hold build `e6336445f` to production.
2. Deploy the queue-only adapter over the legacy expense edge function.
3. Apply the atomic expense bundle once (schema install; expense decisions start being captured; provider delivery stays paused).
4. Promote the candidate `d2d7457f1` to production with the expense gate absent.

Not included and needing separate approval: enabling provider expense delivery for any company; the independent project-reopen migration (`18845d0b…`, can be approved alongside or later); any iOS build, phone install or App Store release; any push to OPS-Web `main`.
