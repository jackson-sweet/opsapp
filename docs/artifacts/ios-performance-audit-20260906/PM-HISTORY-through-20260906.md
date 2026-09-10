# IOS PERFORMANCE — PM status

Parent: `01a0779e-54bf-72a3-976c-81c692990d23` (Audit iOS app performance).

Status: IMPLEMENTING. Jackson approved repair sessions and PM coordination on September 6, 2026. Source audit baseline: `94543f955ca8a2ccee4cc148c24c6d33de92cccc`.

Plan: `/Users/jacksonsweet/Projects/OPS/ops-ios/docs/plans/2026-09-06-ios-performance-repair.md`.

## Assignments

| Title | Task ID | Ownership | State |
|---|---|---|---|
| IOS PERFORMANCE - P1-1 | `01a077ad-4e3e-7931-a8c2-0d2b3bf051c6` | Database compatibility | Dispatched; no build baton |
| IOS PERFORMANCE - P1-2 | `01a077ad-5ae0-7ef2-9651-b4d4343db0bd` | Visit edits and continuity | Dispatched; no build baton |
| IOS PERFORMANCE - P1-3 | `01a077ad-6602-7001-8cff-8f30842f0654` | Photos and cache | Dispatched; no build baton |
| IOS PERFORMANCE - P1-4 | `01a077ad-75df-7fd1-b182-679cbd60dc60` | Sync and deck responsiveness | Dispatched; no build baton |
| IOS PERFORMANCE - P1-5 | `01a077b5-2eb8-7231-9577-85b93a1734a5` | Guarded stage delivery (ops-web) | Dispatched; local tests only |

Each worktree: `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-p1-N`. Each worker handoff: `docs/artifacts/ios-performance-p1-N/HANDOFF.md` inside its own worktree. Each branch: `codex/ios-performance-p1-N`. Workers commit locally; PM reviews and integrates.

## Build baton

Holder: NONE — first storage/schema/deck regression run completed successfully. Parent schedules the next combined run. No worker may start heavy builds/tests/benchmarks. They are implementing and authoring tests. Parent will inspect live processes and disk, then use one integration build/test stream. Main's existing schema baseline failure is evidence to fix, not a test to bypass. Preserve all other active work.

## Dependency contracts

- P1-1 owns every persistent model and migration. All proposed new persistent fields flow through it.
- P1-2 owns SiteVisitPersistenceCoordinator and SiteVisitCaptureView/Model. It must publish a compatible explicit orphan-repair API to P1-4.
- P1-3 owns shared camera/media/cache helpers. Publish staged-capture/thumbnail APIs early; PM forwards them to P1-2, which alone applies the visit adapters. Camera legacy callers remain compatible until migrated.
- P1-4 owns SyncEngine/orphan recovery/inventory and deck editor. No direct coordinator or persistent-model changes.
- PM integrates Bible edits from handoffs; workers do not edit the shared Bible.

## Completion and release boundaries

Review findings 1–13 individually against actual commits and test results. Integrate schema first, then visit/media adapters together, then sync/deck after contract review. Run focused regression suites and an appropriate device-target build. Validate populated synthetic old/new store migrations, interruption-safe capture, unchanged parked work, bounded edit cost, offline/reconnect, and deck exit.

No production mutations, phone installs/data writes, push, deployment, or App Store release. Local integration is within authorization. Real-device optimized performance remains a distinct proof step, requiring an install approval if necessary.

## Private phone evidence

Jackson explicitly authorized a local full database export if useful. Export succeeded; database and WAL are retained in `/private/tmp/ops-ios-audit-20260906/private-store/` with private directory/file permissions. SQLite quick_check returned ok. Sanitized diagnostics are in `store-diagnostics.json`. Original V25 checksum matches released baseline and the new deck merge-base column is absent. There are 2,636 sync rows: 2,625 completed, 9 pending, 1 inProgress, 1 parked; 30 visits, 149 artifacts, 283 answers, 25 identity drafts, 153 drawings, 967 project photos, 484 clients. Evidence forwarded to all owners. Parent can evaluate a pure offline migration against a disposable clone later; never launch the real app with this store or drain its outbox. Raw database contents must stay in private temporary storage and never enter reports, tests, version control, or external services. Workers use synthetic fixtures and sanitized aggregate/schema facts only.

## PM next actions

1. All four sessions were independently verified active using wait_threads. Continue using compact snapshots with cursors.
2. Export and sanitized schema/aggregate inspection completed. Keep the raw copy private; remove it after the diagnostic/migration verification purpose is finished.
3. Early P1-2/P1-3/P1-4 handoffs reviewed and contracts forwarded. Continue checking implementation against agreed contracts.
4. Review the first schema repair, integrate locally in one dedicated checkout, and grant/hold the serial build baton explicitly.
5. Continue until all accepted repairs are integrated and verified or only an explicit external action remains. Keep updates quiet while no meaningful state changed.

## Continued coordination

Heartbeat `ios-performance-pm` is active every 10 minutes on this parent task. It resumes PM work and remains quiet for unchanged state. It must be paused once only an explicit external action remains or the authorized work is complete.

## Contracts approved and forwarded at startup

- P1-2 keeps `commit(completing:mutation:)` compatibility and explicit `recoverOrphanedWrites(siteVisitIds: Set<String>? = nil)`; P1-4 discovers candidates in background and revalidates exact graphs before repair. PM specifically required regression for unrelated PRE-EXISTING UNSAVED changes in the same ModelContext, not only stored needsSync flags.
- P1-3 `CameraBatchView(owner:onStagedUpload:)` async Bool callback; typed `StagedCaptureOwner`, `StagedCaptureBatch`, `StagedCaptureItem`; stable item ID equals artifact ID for replay dedupe. `DurableCaptureStore.recover(owner:)` only for exact user/company/context; acknowledge only AFTER local model/outbox commit. Photo bytes remain owned by persisted artifacts/outbox after journal acknowledgement.
- P1-3 `PhotoThumbnailRequest` / `PhotoThumbnailLoader` and `.photoThumbnailSourceChanged` contract is in its handoff and forwarded to P1-2. P1-2 alone edits visit adapters.
- P1-4 may add narrow `OutboundProcessor` support for editor holds. Both outbound drivers enforce the hold; preserve version guards for already-in-flight sends, release on actual editor disappearance/process restart, retain durable autosaves.
- P1-2 draft/completion coherence approved: all incomplete work remains savable; only applicable required answers gate actual completion. Explicit fresh intent and deliberate resume remain distinct; preserve existing resume deep links. No broad workflow redesign.

## Verification state

Four tasks confirmed active. All four worktrees exist at assigned branch names. Heartbeat file readback confirms ACTIVE, ten-minute interval, and this parent task ID. Private export folder mode 0700, files mode 0600. Main source remains unchanged; existing unrelated `docs/artifacts/task-groups/` preserved. No worker has the iOS build baton; the parent may own it as recorded above.

## Finding 13 server dependency

P1-2 live read-only inspection confirmed legacy move_opportunity_stage lacks command-key idempotency and expected revision. A blind retry after an ambiguous outcome can overwrite a newer stage; no such fallback is permitted. PM authorized P1-2 ownership of SiteVisitSyncOperation.swift/SiteVisitOutboundSync.swift and coordinated their ownership with P1-4. PM verified the live RPC inventory and local guarded lifecycle function; existing lifecycle/email guards have specialized authority and cannot be casually reused for a manual stage change.

P1-5 task `01a077b5-2eb8-7231-9577-85b93a1734a5` is launched for a narrow additive guarded stage-command server contract in ops-web worktree `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-p1-5`, branch `codex/ios-performance-p1-5`, baseline `bcd252e55c6af94a603a04d4d08ad88e7518a34a`. Exact details are appended to the plan. It owns local migration/RPC/private receipt storage if needed and meaningful synthetic transaction/security tests, not production writes. Publish its API immediately to P1-2. Server deployment approval remains a separate final gate, and the new iOS stage delivery must not ship before server readiness is verified.

This fifth assignment is a dependency of the existing stage-save finding, not a general server rewrite. It may run narrow existing local SQL tests without iOS build contention; no heavy runtime downloads/containers without PM coordination. Shared ops-web is heavily dirty and must remain untouched.

## Stage revision and reuse review

P1-2 requested stable command/visit/opportunity IDs, nonterminal target stage, expected prior stage plus exact revision, and applied/already_applied/conflict with authoritative opportunity state. OpportunityDTO currently loses the original PostgreSQL microsecond string by converting to Date. P1-5 must publish an opaque server revision or another exact contract; do not round timestamps or reacquire a fresh expected revision at retry time.

PM traced DaySheetCache/MilestoneWriteQueue through LeadMilestoneCommitter: it calls the legacy RPC after a separate prior-stage preflight, explicitly without a server receipt. It is not the missing safe primitive. This conclusion was forwarded to P1-2 and P1-5. Keep the visit command in its atomic SyncOperation graph. The adjacent milestone race is noted for audit completeness; do not silently broaden the current guarded visit contract or present the existing queue as idempotency proof.

## P1-5 test allowance

PM explicitly approved one disposable local PostgreSQL17 cluster using already-installed binaries, Unix-socket-only, synthetic data, unique temporary directory/port, and at most two SQL sessions for meaningful race tests. No real credentials/data, TCP listener, downloads, Docker, or production connections. This is a narrow LOCAL SQL TEST allowance, not an iOS build baton. P1-5 must stop only its own cluster on completion.

Proposed revision direction accepted in principle: private monotonic stage revision advanced atomically by all relevant legacy/current stage writers; private receipts; read-only snapshot RPC plus guarded apply RPC. Initial revision creation, trigger ordering, concurrent edits and exact replay-after-later-change must be proven. Full typed contract still pending handoff file publication.

## Stage contract v1 accepted and forwarded

Full contract is P1-5 HANDOFF.md. `read_site_visit_stage_snapshot(p_opportunity_id)` returns version1 capability, stage and opaque `stage_revision`. Capture it during lead context loading, never block local save or manufacture/refresh expected state during retry. `apply_site_visit_stage_command` takes stable command/visit/opportunity IDs, nonterminal target and expected stage/revision; waits for remotely completed visit. Outcomes applied/already_applied/conflict/not_ready. Historical receipts must not overwrite fresh lead state. Missing capability/permission failure fails closed with truthful recovery custody. Offline without a previously captured token requires a later deliberate stage decision, not automatic rebasing. P1-2 must retain and enforce original actor/company even before first delivery, including same-company account changes.

P1-5 corrected earlier shorthand: private opaque UUID token rotation, not a client-facing arithmetic counter. Relevant stage/ownership/lifecycle changes rotate it atomically; unrelated notes/completion activity do not. PM accepted v1 and directed P1-2 to implement.

P1-4's narrow SiteVisitRecoveryVault async header-only identity adapter approved; unreadable or failed-integrity packets must not be treated as absent. P1-1 early source diff reviewed: preserved old checksums, V26 boundary, unknown dirty merge bases, auth/data-controller gating on successful bootstrap; compile/runtime verification still unrun.

## Integration checkout preparation

Parent prepared `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-integration`, branch `codex/ios-performance-integration`, at audited baseline. Worktree-local gitignored Secrets.xcconfig copied privately; no secret contents printed. No build/dependency resolution started. Integrate only worker commits after readiness/review; do not copy uncommitted worker WIP. Main remains untouched. Use one dedicated DerivedData and worktree-local `.spm-local` when verification starts; never share active compiler/package writers.

## Stage identity amendment and journal-aware cleanup

PM approved an amendment to the unreleased v1 stage contract: required `p_expected_actor_id` and `p_expected_company_id` UUID assertions checked against trusted JWT-derived context BEFORE receipt lookup or mutation, and included in exact command identity. Snapshot returns trusted `actor_id`/`company_id`. These values constrain authority; they never grant it. This closes the account-switch race between client preflight and first Supabase request. P1-2 keeps original-context preflight and P1-5 owns server assertions/tests. Both were notified.

P1-2 may remove automatic apparent-empty-visit cleanup entirely: a visit without database artifacts can still own an unacknowledged durable photo journal. Absence of model rows is not proof of emptiness. Preserve draft/resume access and bound future entry queries rather than deleting uncertain custody.

## First integration and test start

P1-1 completed cleanly with source commits `28be9966`, `9b5c0d92`, handoff `48912895`. Parent reviewed source and cherry-picked to integration as `cbf69ec6`, `257203c2`, `5697e384`. No shared-main source integration yet. Parent holds iOS BUILD BATON. No active xcodebuild/swift-frontend was present before scheduling; idle SWBBuildService alone was observed. Free space ~81 GiB. Worktree-local `.spm-local` is an APFS clone of existing locked SourcePackages; no shared dependency writer or downloads requested. Parent is starting focused AppUpdateMigration, DeckMergeBaseMigration, StorageBootstrap, SiteVisitMigration, DrawingDataCache, DeckDesignSync and ServerMerge tests on one isolated simulator. No phone install or raw store replay.

Completed parent xcodebuild exec session: `51270`, exit0. Do not resume it or treat it as an active build. Simulator: `1C6A8F09-A337-41F0-AFDD-81C4F3EDFB8A` (OPS performance integration, iPhone17/iOS26.5), created by PM and safe to remove only after all initiative testing completes. DerivedData: `/private/tmp/ops-ios-performance-integration-deriveddata`. Log: integration `docs/artifacts/ios-performance-p1-1/storage-tests-01.log`; result bundle same directory `storage-tests-01.xcresult`. Verify process completion and parse results; a quiet log is not success. Preserve caches while workers/tests remain active.

P1-5 confirmed the amended v1 handoff/SQL now includes trusted snapshot actor/company and required expected-context assertions before locks/receipts/state. PM forwarded publication confirmation to P1-2. Its disposable local PostgreSQL initialization hit a sandbox failure; owner is inspecting exact stderr and may request narrowly scoped escalation under the already granted local-only SQL-test allowance. This is not a production approval or a known SQL implementation failure.

## Media completion and stage-lane integration requirements

P1-3 will add `pendingContextIDs(companyID:userID:) async throws -> Set<String>` using one exact-account manifest scan, including prepared and failed/unprepared owned bytes. P1-2 enriches draft resume metadata asynchronously; unknown/corrupt manifests are never proof of empty visits.

PM found the proposed legacy void-camera fallback would retain uniquely scoped protected journals with no recovery entry point indefinitely. P1-3 must resolve this before completion. Narrow ownership expanded to non-visit CameraBatchView consumers in LeadDetailView, DaySheetLeadCard, ProjectDetailsView, ProjectActionBar, ProjectFormSheet plus necessary host photo adapters. Production paths need explicit custody transfer, recovery and cleanup; project creation binds to draft identity. P1-3 may commit core helpers first, then dependent adapters in the same session. SiteVisitCaptureView/Model remain exclusively P1-2. Shared schema and outbound ownership gates still apply.

P1-2 implemented operationType `siteVisitStageMove`, entityType `siteVisit`. Existing both outbound drivers reach executeIfHandled, so no new dispatch switch is needed. Excluded from generic CRUD/completion/coordinator orphan ownership; completion precedes stage. No snapshot creates an atomically parked command; retry never reacquires expected state. Applied/replay receipts settle only, not current Opportunity projection. PM forwarded to P1-4: broad recovery must preserve this command lane and never revive or reinterpret it as CRUD.

First storage test build is confirmed actively compiling Swift, not stuck resolving packages. No success/typecheck/test-result claim yet.

P1-3 core commits: `e2a71a7e` cache/thumb, `ce8ffb72` camera journal, `3f6e14f2` lead staging, `c528e1b0` one-scan exact-account pending context index. Index API was forwarded to P1-2. Remaining non-visit production custody adapters are still active; don't call the full media slice complete based on these core commits.

P1-5 first local SQL run passed 26/26 in 10.36s; disposable cluster stopped. Subsequent final lock audit discovered legacy booking opportunity→company inversion. New apply acquires visit/opportunity FOR UPDATE NOWAIT and returns SQL55P03; owner is adding exact inversion proof and rerunning before final commit. P1-2 was directed to retry 55P03/40P01/40001 with unchanged identity/revision. No final server test count or live-readiness claim until updated proof lands.

## Current review findings

PM independently read P1-5 test-results.txt: 27/27 passed in 9.664s, including reverse booking lock-order proof. Source review then requested company-scoped visit row locking before FOR UPDATE NOWAIT, preserving access denial for a foreign-company visit even if another session holds its row. This prevents acquiring/probing a foreign-row lock; P1-5 is adding the focused case before final handoff. No production apply.

P1-4 may add the narrow LEAD STAGE detailed RecoveryInventory/SyncStatusCopy classification and exact-stage custody safeguards. Deleted-parent repair parks the command for lead review; automatic rearm requires original snapshot plus exact actor/company. Off-main thumbnail work must decode its own drawing from immutable serialized JSON because DeckDrawingData contains reference caches; value-type wrapping alone did not isolate those caches.

## Verified storage milestone

Parent independently parsed the completed result bundle: **69 total, 68 passed, 0 failed, 1 skipped**. Existing `testDeclaredSchemaChecksumsStayImmutable` passed. Only skipped test: `AppUpdateMigrationTests/testCopiedDeviceV15StoreMigratesToCurrentWithoutLosingRows`, the optional external private-fixture case; synthetic populated V16/V25/widened-debug upgrades, first-save unsent preservation, bootstrap recovery/retry/concurrent open and existing deck/visit regression selectors ran successfully. No raw phone rows used. Summary copied to shared audit `storage-repair-test-summary.json`; full tree/results remain in integration artifacts. P1-1 notified; no repair needed from this run. iOS BUILD BATON released to NONE. Keep one integration simulator/cache for remaining slices, not four concurrent test copies.

Device-target compile, rendered storage UI/large-type proof, optimized physical-device performance and actual phone installation remain unrun. Prefer the next combined iOS verification once the remaining commits/adapters are coherent rather than recompiling the same unchanged slice. No shared-main source merge, push, deployment or release yet.

P1-3 approved adjacent ImageSyncManager delivery hook: original/journal release follows canonical delivery plus durable local healing, with exact account/photo identity. Five non-visit camera consumers now require typed custody/recovery; project creation reserves and reuses its exact account-scoped draft project UUID. P1-4 notified to avoid that file.

P1-5 commit `caec2dfa` is initial local SQL implementation; final tenant-lock follow-up and 28-test run still pending. Do not integrate/report the server slice final from initial commit alone. Stage completion on a new_lead can itself trigger new_lead→qualifying via activity; the old captured token then conflicts honestly and requires a deliberate new stage decision. P1-2 was notified; no silent rebase.

## Bible and server completion milestone

Bible `03_DATA_ARCHITECTURE.md` now records the verified LOCAL V26 repair, immutable historical shapes, gated bootstrap, exact code commits and 68/0/1 test evidence with explicit unreleased/device-proof limits. Atomic local Bible commit `d9734d5`; only that file was staged. Pre-existing `.DS_Store`, `07_SPECIALIZED_FEATURES.md`, `.worktrees/`, `specs/future/` remain untouched. Other workstream Bible updates still required after their code/contract verification.

P1-5 reports READY FOR PM INTEGRATION: code `caec2dfae3c4adfe4ce5bc987b5d0bd9d4e498d1` + tenant-lock follow-up `e95d12a0650cd09f5095c4e5cd20534f0e1a93d9`. Final 28/28 synthetic PostgreSQL17 tests pass in4.213s, original legacy function MD5 unchanged `34ce4987e8411de6bfbe8d93dcec7afa`. Local cluster stopped. Migration `supabase/migrations/20260906171832_site_visit_stage_commands.sql` remains unapplied. No production or provider fan-out proof claimed. Documentation commit was finishing; verify final handoff commit and clean status before integration. P1-2 still depends on this backend being applied/verified before new client release.

P1-5 final acceptance: parent independently read final 28/28 proof, reviewed tenant-scoped lock follow-up and complete handoff, verified clean worktree and documentation commit `f0022f8054a4c850f0b03b70234263a79707777e`. Local server implementation accepted. No remaining local PostgreSQL process; no live SQL changes. Combined client contract verification and explicit production migration/readback remain. Parent will document locally prepared schema/API/lifecycle in Bible03/04/10, not the worker's suggested financial/notification chapters. Do not put unapplied SQL into Bible's archive of applied production migrations. Exact SQL remains in the isolated ops-web worktree until integration/release coordination.
