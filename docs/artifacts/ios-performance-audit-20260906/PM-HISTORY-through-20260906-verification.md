# IOS PERFORMANCE — current PM status

Updated September 6, 2026, 16:09 Pacific. Parent task: `01a0779e-54bf-72a3-976c-81c692990d23`.
Status: IMPLEMENTING / FOCUSED VERIFICATION. User authorized diagnosis, private phone export, repair sessions, PM coordination and local repairs. No push, production migration, phone install/data change, deployment or iOS release authorized. Continue necessary local work before presenting any external approval. Preserve sibling WIP.

This snapshot supersedes older chronology. Full earlier decisions: `PM-HISTORY-through-20260906-1609.md` and `PM-HISTORY-through-20260906.md`. Exact task IDs/cursors/source hashes: `tasks.json`. Scope: `../../plans/2026-09-06-ios-performance-repair.md`; original audit: `REPORT.md`; all 13 acceptance mappings: `REPAIR-ACCEPTANCE.md`.

## Task ownership and current state

| Task | Scope | Current state |
|---|---|---|
| P1-1 | Database compatibility | Source integrated; 68 tests passed, 1 optional fixture skipped. All bounded coordinator/client helper reviews complete; idle. |
| P1-2 | Visit edits, continuity, stage client | Through ea5d8798 client isolation and bad6ad3a typed session guards integrated. Final small review amendment active: preserve old blank-notes semantics for resumed client-bound drafts; no build baton. |
| P1-3 | Photos, cache, all camera consumers | All source and handoff integrated; 8 media suites / 35 cases passed in core03. Idle; physical/UI proof remains. |
| P1-4 | Sync, deck, status | Earlier repairs integrated/passed core03. New driver lifetime/session validity amendment finishing; seven lifecycle regressions authored. Await atomic commit; no build baton. |
| P1-5 | Stage delivery server contract | Final source 26816f355 accepted, 34/34 local PostgreSQL tests. Idle. Migration unapplied; no production changes. |

All worker checkouts: `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-p1-N`; handoffs under each `docs/artifacts/ios-performance-p1-N/HANDOFF.md`. P1-5 is ops-web; other four are iOS. Shared iOS main last verified at audited baseline `94543f955ca8a2ccee4cc148c24c6d33de92cccc`. Shared ops-web has substantial unrelated WIP; never sweep it in.

## Integration and serial build baton

Baton: PARENT. Private copied-V25 one-test proof active in shell87292 at integration622010a0. All general compile/regression/UI streams completed; no source edits during this test. Private logs/result stay under /private/tmp/ops-ios-audit-20260906/private-proof-20260906; no raw data in repo. Only task-owned simulator boot/contact grant; no phone changes. Parent alone runs heavy iOS verification, one stream. Use short process names, never compiler arguments. Do not copy worker WIP: integrate atomic commits only.

Integration checkout: `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-integration`, branch `codex/ios-performance-integration`, latest HEAD `986e0c83`.
Latest additions: bad6ad3a → f8112d4b (typed guards), ea5d8798 → efe359cd (owned client packet), 7a49db75 → 986e0c83 (handoff). Prior full source is present, including fixture26e9936d → 7d889892, host/seed/complete Opportunity snapshot/queue cache fad0e453 → 1d276f30, new-deck needsSync93eac1ec → c8f7d53e, test gates9f6c5cdb → 321e86fd.

DerivedData: `/private/tmp/ops-ios-performance-integration-deriveddata`; package cache `.spm-local`; gitignored Secrets.xcconfig mode600. Owned simulator: `1C6A8F09-A337-41F0-AFDD-81C4F3EDFB8A` (OPS performance integration, iPhone17/iOS26.5). Keep for pending verification. Never delete all simulators; only this task-owned simulator may be removed after completion.

## Verified results

- Storage run: 69 total, 68 passed, 0 failed, 1 optional V15 copied-store fixture skipped. Synthetic V16/V25/widened migration, frozen fingerprints, merge-base custody, bootstrap failure/retry/cancel all passed. Shared `storage-repair-test-summary.json`.
- Core03 at d4ed1efb: 292 total, 287 passed, 5 failed, 0 skipped. Shared `combined-core03-summary.json`. All media, storage, coordinator, stage, sync/deck cases in that run passed. Latest visit host/client/session changes above have not run yet.
- Five failures: SiteVisitLeadCaptureTests offline queue and open-visit delivery trapped; SiteVisitContinuityTests exact same-URL markup retry read declined; SiteVisitSearchSourceTests two gate assertions/hang. Test-fixture/gate/fresh-context amendments integrated, not rerun.
- Core01 and core02 were compile failures already corrected (qualified DeckRenderer error; simplified openVisits predicate). Do not report these as customer regressions.
- P1-5: 34/34 local PostgreSQL17 tests, full guarded stage contract; production RPC absent/unapplied.
- No physical optimized online/offline latency proof, no customer-live claim.

Full core artifacts: integration `docs/artifacts/ios-performance-combined/`. Relevant crash evidence only in `core03-relevant-diagnostics/`: current stdout + 135158/135214 crash reports. Generated broad export containing unrelated historical host logs was removed; original machine logs untouched. Completed shell sessions 51270,43121,24110,27519 must not be polled as active.

## Current concrete review amendments

P1-4 root cause: prior lead fixture launched a real unstructured client drain, then dropped ModelContainer during teardown; OutboundProcessor catch read destroyed SyncOperation after network await. Production also lacked inner continuation guards before logout/reconfigure cleanup. Fix retains container, caches operation identity for cleanup, guards cancellation/session generation/exact active user+company/registered operation before post-await reads and writes; interrupted durable claims retain original retry budget. DataActor gets synchronous generation invalidation including invalidate→resume ABA. Both drivers pass real predicates to typed executor. Seven gated tests pending PM execution.

P1-2 typed guard API committed bad6ad3a: `isCurrent: () -> Bool = { true }, isolation: isolated (any Actor)? = #isolation` on executeIfHandled/uploadPendingMedia and propagation through model-bound helpers. Heavy media loading/preparation stays on background actors. Five gated typed/media invalidation regressions. Standalone strict-concurrency swiftc interface probe passed; actual app compile still pending.

P1-2 client packet committed ea5d8798: SiteVisitIdentityClientStore runs inside VM-owned coordinator transaction, atomically creating/updating Client/SubClient, explicit generic outbox and draft.clientId; only notifyDurableOperationQueued after success. No DataController shared save or global context repoint. Stable retry IDs, deduplicated emails, stopped/inProgress owners preserved, parent visibility checked before lead RPC, camelCase local field guards included with server keys. Three actual CREATE LEAD regressions cover failure/retry and unrelated caller WIP. PM latest finding: blank notes on an existing/resumed client-bound old draft must not clear established client notes. bindClient seeding alone does not cover restored drafts. P1-2 instructed to retain prior nonblank-only notes update behavior and add resumed-draft regression; contact clear tests stay intact.

Earlier cross-reviews closed in source: owned capture context must not save/rollback caller WIP, all real host/deck/seed/dimensioned/queue entry points use correct context, detached Opportunity uses complete apply snapshot including assignmentVersion, partial recoverable media works across all nonvisit consumers, exact account checked across delivery/heal/retirement. See archived decisions/handoffs for detailed contracts.

## Next actions

1. Receive/review/cherry-pick P1-4 driver lifetime commit and P1-2 blank-note compatibility correction + handoff.
2. Run one focused core04 against coherent integration. Include failed visit classes, latest host/seed/queue additions, typed outbound/media guards and new OutboundLifecycleTests plus directly adjacent retry/dependency classes. Do not repeat all passed media without changes.
3. Run existing hermetic `OPSUITests/SiteVisitContactImportUITests` on owned simulator and inspect screenshots. QA launch uses -OPS_SITE_VISIT_CAPTURE_QA, synthetic in-memory host; no production authentication/store.
4. Run generic iOS device-target compile with CODE_SIGNING_ALLOWED=NO; no phone install. Finalize all13 dispositions and Bible updates using actual evidence.
5. Integrate verified authorized local source into shared iOS main preserving unrelated artifacts/WIP. Keep ops-web server work isolated if shared checkout remains dirty; no push. Prepare concrete external approval only after local work complete.
6. Pause heartbeat only when authorized local work is done or only explicit external action remains. Do not pause now.

## Server/Bible/private data boundaries

P1-5 unapplied migration: `.worktrees/ios-performance-p1-5/supabase/migrations/20260906171832_site_visit_stage_commands.sql`. Exact final contract in its handoff and Bible03/04/10. Opaque private revision + immutable command receipts; original validated snapshot frozen at operator choice; historical receipt never overwrites newer Opportunity. already_satisfied is eligible same-target no-op with no fake causality or notification. Firebase identity bridge, exact actor/company/visit/permission guards, lock order/NOWAIT. 34 local tests; no production provider-fanout proof. Apply/read back exact migration only with explicit later approval before dependent client release. No Vercel deployment needed for database-only contract.

Bible repo `/Users/jacksonsweet/Projects/OPS/ops-software-bible`: local commits d9734d5,6d52e8a,0ba0298 document prepared storage/server/media/sync. Preserve pre-existing dirty .DS_Store,07_SPECIALIZED_FEATURES.md and untracked .worktrees/specs/future. Still update prepared P1-2 owned-context/client/session contracts and final proof. Change current schema to V26 only after local source integration; never claim released.

Authorized private phone export: `/private/tmp/ops-ios-audit-20260906/private-store/`, mode700/files600, V25 store85,245,952bytes/WAL0/quick_checkok; checksum oDrDy3ePGUW2ZiuwOISzdvuUZ8yf5LtXt42AFLxtTrs=. 2636 operations (2625 complete,11 unresolved),30visits,149artifacts,283answers,25drafts,153decks,967photos. No raw rows in repo/external tools. Never launch app or drain raw store. Optional existing copied-device fixture is V15 and incompatible with this V25 export; synthetic V25 migration is proven. Delete private export when purpose complete. No phone writes authorized/performed. Sanitized shape/device evidence lives beside this ledger.

Heartbeat `ios-performance-pm`: ACTIVE every10minutes, parent task, quiet unchanged. Automation TOML `/Users/jacksonsweet/.codex/automations/ios-performance-pm/automation.toml`. Keep current fields/prompt when updating.

## Core04 active

Latest corrections integrated: P1-4 a021ab0a → d544051b (both driver lifetimes +7 tests), P1-2 blank-notes2ef96911 →03b8b9d4 and handofffec9073c →8ef739cd. Source review found no remaining blocker before compilation. Core04 uses new typed outbound/media guard suites, failed visit classes and latest host/seed/client/queue/lifecycle coverage plus adjacent retry/dependency/deck/mention classes. `docs/artifacts/ios-performance-combined/run-core-tests-04.py`, log/core-tests-04.log, result/core-tests-04.xcresult. Await actual completion/summary before marking verified.

## Core04 result and UI check

Core04:309total,306passed,3failed,0skipped. All five old core03 failures now PASS; all new P1-2 client/notes/typed-guard cases pass. Shared summary combined-core04-summary.json. Remaining failures assigned: P1-2 ClientLeadAutocreateQueuePolicyTests/testDeliveryBindsSiteVisitDraftAndVisit nil binding/commit timestamp (investigate stale old-context assertion vs actual loss); P1-4 OutboundLifecycleTests/testInvalidationBeforeSyntheticStoreResetNeverTouchesDestroyedOperation trap and ProjectNoteMentionEditTests/testLongLivedDataActorRefreshesMainContextDispatchRetarget different dependsOn UUID. Other6 lifecycle tests pass.

Current stdout integration artifacts/combined/core04-relevant-diagnostics/test-stdout.txt: reset trap is 'Container does not have any data stores' at SwiftData/ModelContext324, likely fixture constructing ModelContext after deleteAllData destroys stores; verify without weakening callback cancellation. Mention test starts real network push just before comparison, investigate fixture race. No current OPS ips found in bundle export; only current stdout retained, broad temporary export removed. Detail JSON files queue-policy-04-details,lifecycle-reset-04-details,mention-retarget-04-details beside result.

Contact UI script run-final-verification.py ui prepared/started after booting owned simulator (it had shut down after test run). Contact access granted only there. Shell17131 covers boot+grant+UI script; inspect completion before declaring UI run begun/passed. Result contact-ui-01.xcresult/log. Device unsigned Release script also prepared with argument device, not started. Bible local e680356 records prepared capture/session contracts and verified35media cases; latest core04 evidence will need updating after remaining repairs.

Contact UI verified:2/2passed,0skipped. Parent inspected after-import and after-cancel screenshots: visit remains presented, imported name/company/email/address retained; cancelled picker returns to intact unlinked visit. Shared artifacts contact-ui-summary.json, contact-import-preserved.png,contact-cancel-preserved.png. No optimized speed claim. UI at8ef739cd; expected remaining amendments test-only, verify hashes before deciding whether repeat necessary.

Release-device compile started using run-final-verification.py device; artifact device-release-01.log/.xcresult/-scope.json. CODE_SIGNING_ALLOWED=NO, generic/platform=iOS, Release, jobs4; no install/upload. Worker amendments expected test-only; compare source before deciding repeat coverage. P1-2 queue policy diagnosed stale fixture refs; strengthens actual live queue callback integration test and fresh exact-ID readbacks. P1-4 synthetic reset finalreadback used destroyed store, mention fixture raced real connectivity; bounded test fixes in progress. Do not waive until focused rerun passes.

## Reviewed test-only corrections awaiting integration

P1-2 4c889f09 + bf51f8a8: queue policy exact-ID fresh reader verifies visit/draft binding and exact commit timestamp; open-VM test now executes real queue cache/bind/notification with only remote response mocked. P1-4 245ac1b7: retains synthetic reset plus awaited CancellationError, removes invalid post-destruction new ModelContext; mention harness/relaunch gets always-offline connectivity, explicitly requires pending unclaimed dispatch, fresh-store dependency readback then unchanged actor-refresh check. Parent reviewed diffs; no production changes. Integrate only after active Release compile ends, then rerun full OutboundLifecycleTests,ProjectNoteMentionEditTests,ClientLeadAutocreateQueuePolicyTests,SiteVisitLeadCaptureTests. Existing UI/device source proof remains applicable if these are only test/doc changes.

## Bounded copied-phone compatibility proof

PM requested P1-1 add one OPTIONAL real copied-V25 migration test alongside existing optional V15 test, using OPS_V25_STORE_FIXTURE_DIR, fresh private copy + frozenV25→currentV26→reopen, aggregate/digest custody assertions only. No user values/IDs/content in logs or committed fixtures. Never wire raw container to DataController/SyncEngine/repositories; no network/drain/phonewrites. Concrete unresolved concern: actual exported V25 phone store and historical opening crashes; synthetic V25 passed but full real-copy upgrade not yet tested. P1-1 authors test/handoff only; PM provides private fixture to one test invocation and cleans copies. This remains local authorized work; no new user permission needed for isolated copy. No build baton to worker.

## Final general verification passed

Unsigned generic iOS Release build passed at8ef739cd,0errors,204warnings,854seconds. Mach-Oarm64,platformiphoneos,3.0.5 label; not installed/signed/uploaded. Build warnings remain in codebase; do not claim warning-free. Full build-results and summary in integration artifacts; shared device-release-summary.json. Subsequent changes are TEST/DOC ONLY (git diff --name-only8ef739cdHEAD verified).

Integrated reviewed corrections:4c889f09→4622a3fe,bf51f8a8→5384ffde,245ac1b7→f1ad1bf5,27c9f4a→73e00ff7,9a753816→622010a0. Test build-for-testing shell6355 passed19.6seconds. Core05 shell57191 passed12.4seconds:127total,127passed,0failed,0skipped across OutboundLifecycleTests,ProjectNoteMentionEditTests,ClientLeadAutocreateQueuePolicyTests,SiteVisitLeadCaptureTests. All three core04 failures now closed with preserved/stronger assertions. No remaining general regression failure. Shared combined-core05-summary.json; all selectors/heads in integration artifacts. UI2/2passed and production-source optimized compile remain applicable because final changes only tests/docs.

Private copied-V25 proof is now running alone (shell87292) using compiled xctestrun copied to private mode700directory and exact OPSTests environment key. Its config replaces __TESTROOT__ with original BuildProducts path and includes only OPSTests. Selector testCopiedDeviceV25StoreMigratesToCurrentPreservingCustody; must verify1executedpass/0skip. Test copies original export into its disposable own temp folder, checks16groups using per-run private keyed HMAC, no values/digests logged; runner independently hashes original bytes before/after and prints only unchanged boolean. First attempt never launched XCTest due Python3.9 missing hashlib.file_digest; helper corrected to streamingSHA256 before actual invocation. No source/export bytes changed by that harness error. Private result/log not copied broadly to repo; sanitize summary only. Cleanup private original/export/test residuals after accepted proof, preserving only aggregate result and no rawstore.
