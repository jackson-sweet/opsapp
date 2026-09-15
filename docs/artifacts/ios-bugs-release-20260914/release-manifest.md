# iOS bug batch release reconciliation — 2026-09-14

This is a release preparation record, not a release or an all-bugs-fixed claim. Inspected iOS main `95bfaf20`, web main `134be2424`. No builds, simulators, cache restoration, phone interaction, production migrations, provider transactions, environment changes, pushes or releases were performed during this reconciliation.

## Verified local stack

| Repair | Local implementation | Existing proof |
|---|---|---|
| Expense approval, reimbursement and provider delivery (P5; `96a4a0ad`) | iOS `c19c8906`; web `23cc8e0ff` contained in `134be2424` | 60 iOS tests; 284 web tests in 22 files; 123 accounting SQL assertions + 7 concurrency graphs; 17 payroll assertions + 2 rejection checks |
| Reopen an archived job when scheduling active work (P6; `facfecfe`) | iOS `5d0e6da1`; web `2a7f6ff3d` | 159 combined iOS tests; 30 SQL assertions |
| Report permanent sync errors automatically (P6; `39654ecf`) | iOS `5d0e6da1` | Same 159-test combined run; allowlisted scoped dedupe, transient exclusion; in-memory delivery and no semantic matching of manual reports remain explicit limits |
| Correct and return crew expenses with before/after feedback (P7; `c381520d`) | iOS `3353ecce`; web `134be2424` | 115 iOS tests, 3 inspected renders; 69 correction SQL assertions + 7 concurrency checks + 123 existing accounting assertions + 2 rejection checks |

Current source independently matches every retained P6 hash (27 files) and P7 hash (13 files). These are source checks against previous passing runs, not newly executed runtime tests.

Evidence: [P6 verification](../ios-bugs-p6-20260914/verification.md), [P7 verification](../ios-bugs-p7-20260914/verification.md), [live preflight](preflight.json). P5 provider and database proof are in OPS-Web `docs/artifacts/2026-09-12-expense-provider-contract.md` and `2026-09-14-expense-accounting-database-proof.md`.

## Exact pending migration stack

Files are in OPS-Web `supabase/migrations/`. None of these five ledger versions were present in the live database at 2026-09-14T22:27Z.

| Order | Migration | SHA256 |
|---|---|---|
| 1 | `20260912012607_expense_decision_company_authority.sql` | `93f4d57097e05cda31b993d84445356bde43d21a44cb20acdf9575524d04b939` |
| 2 | `20260912203328_expense_accounting_lifecycle.sql` | `713b56128ac1ce2632ae62ecdb3d90dc5eb2ed09bbdc5db1f235cc0d00523eff` |
| 3 | `20260914200910_expense_payroll_reimbursement_projection.sql` | `78db2cee099061cd5d31be11a8de4c174cbb6022a0c66c590f08feb53902dc0b` |
| 4 | `20260914210950_project_task_reopen_receipts.sql` | `9ea711a3a2de58ed18607fa8f30804bf19d116615c527e74aa8a5d1b176fa6c6` |
| 5 | `20260914214748_expense_admin_correction_review.sql` | `f5a6d66815c8e9468817fc28d24a5fe1d7caa68dcb671b3b379a1ad227b5f015` |

Expense authority → accounting lifecycle → payroll compatibility → correction is a strict dependency chain. Project reopening is independent and can be installed separately; its plain CREATE statements must not be blindly replayed.

P4 multiple-choice prerequisites are already installed: ledger `20260912213224 site_visit_single_choice_v2` and `20260912213347 site_visit_mcp_choice_coexistence`. Earlier bug notes saying these remain unapplied have been explicitly superseded. This ledger read does not establish physical-phone acceptance.

## Coordinated accounting release requirement

Applying the lifecycle migration begins capturing and queuing new expense decisions for connected, sync-enabled push/bidirectional connections. One such connection existed at 22:30Z. There is no expense-specific provider-delivery switch, and global accounting gates affect other accounting entities.

Before any authorized cutover, resolve the deployed worker/edge versions and current write-gate state. Keep old delivery paths from consuming new expense events during the schema/runtime transition. The matching runtime must contain both expense-aware QuickBooks/Sage push-queue handlers, their expense processor/provider services, the expense-settings/expense-issues routes and corresponding mapping/recovery UI, plus the forwarding-only Supabase `accounting-sync-expense` edge function including `handler.ts`. Preserve its recorded `verify_jwt:false` gateway setting: the forwarded Firebase bearer is authenticated by the RPC.

Source gates are `ACCOUNTING_WRITE_ENABLED`, `SAGE_WRITE_ENABLED`, `SAGE_PRODUCTION_WRITE_ENABLED` and the exact Sage sandbox business allowlist. No production values were read or changed here. Authorizing a migration alone does not authorize changing these gates or a real provider transaction.

Read-only production checks completed:

- No mixed-company expense/batch links, no historical expense export evidence, and no nonterminal accounting claims at 22:30:56Z. These are point-in-time counts, not locks or permission to replay data.
- Payroll readiness MD5 is the expected original `c3e517bcc781f6866601c5966fa0b58d`.
- P7's three guarded authority/placement MD5s match their captured originals; exact definitions and execution ACLs are in preflight.json.
- Correction/history/reopen/accounting-request RPCs and the new reimbursement column were absent.
- UUID expense/company identities, text allocation project IDs, queue acceptance fields, and project status_version were confirmed in live schema.

Before applying, repeat these checks and complete the deployment-specific preflight: compare expense save/recalculation/revision triggers and project status/identity/outbox helpers against captured baselines; check partial installs, constraints, dependencies, grants and authenticated private-schema usage; inspect live worker/edge revisions, running claims and configuration presence without exposing credentials. Provider activation additionally needs exact company/environment/account/employee/project/tax/currency mapping review and explicit canary authorization. These deployment checks were not completed in this read-only reconciliation.

After an authorized release, independently read back schema/functions/grants and deployed commit identities, then perform the authorized phone acceptance flows. Original-phone offline/reconnect/conflict/media custody and real provider tax/reconciliation acceptance remain unproven.

## Remaining gaps and older ownership

The live backlog contains 66 unresolved iOS reports (55 bug, 3 UI issue, 1 crash, 6 feature request, 1 other) and 3 unresolved iOS QA rows. These counts are not a count of unfixed code defects.

- **Comment attachment removal (`f5f57917`) has a missing live server prerequisite.** iOS fixes `9eac1406`/`82a01604` and render harness `c3ee720c` are ancestors of main. The app sends `p_attachments` when changing media, but production exposes only the four-argument `update_project_note_mentions(uuid,text,text[],uuid)` (MD5 `9d16ec64ff2d15da9e00fe1fbeb1adc4`), so the changed-media call cannot resolve. The September4 staged artifact is unchanged. A guarded successor, `20260914224026_project_note_mentions_attachments.sql`, is prepared on local OPS-Web main `7ccb38e84`, with 62 SQL plus 24 concurrency/migration-adversarial checks independently passed. It is independent of the five migrations above and still needs separately authorized application. The related mixed-edit cancellation repair is now integrated on local iOS main as `b1cdc644`, after all 118 focused simulator tests passed, including all 13 new regressions. Entire app, test and project trees match the passing checkout `7ef35203`; independent review found no actionable issues. [Current photo repair evidence](photo-attachments.md). Text-only calls retain the four-argument shape. Original photos owner preserved; original-phone acceptance and release remain unproven.
- **Missing-project photo report (`bf2a75fb`):** app repairs `4e051cd5`/`b881a350` are ancestors of main. Production `project_server_state` now returns `unknown` when company identity cannot resolve (MD5 `79c400ac93cecf1dea2e15b451341f4e`), preserving retry custody rather than asserting absence. The stale Bible contract was corrected. This does not prove delivery of the original four photos.
- **Completed visit → estimate follow-up (`8cd86c31`):** no matching fix was found. PipelineViewModel's YOUR MOVE classification at lines599–694 uses correspondence/manual ownership/due follow-up, without a completed-visit/missing-estimate condition. Completion saves the visit and optional stage intent; it does not establish estimate follow-up ownership in the inspected source. A visit can remain WAITING. Live-trigger outcome was not reproduced. Existing September3 ownership and Lead Details exclusion remain.
- **Travel-aware meeting suggestions (`2e958111`):** the existing draft schedule context `8439c0514` reads customer bookings and company day counts; it does not supply event locations, attendee intervals, route durations or candidate ranking. This is partial implementation, not a completed fix.
- Vinyl contingency/combine-cuts and broad calendar-import/lifecycle requests still lack completion evidence. Six feature-request rows remain their own scoped work. Lead Details and LeadDeckScreen reports remain excluded from this task.

## Bug-record evidence updates

Guarded updates added verified local proof to `facfecfe`, `39654ecf` and `c381520d`, and appended current release/proof information to `1995a554` and `96a4a0ad`. All five read back exactly. Replaying both guards changed zero rows. Fixed/resolved timestamps remain null; no report was closed. No customer business record was altered.
