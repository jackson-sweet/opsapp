> Local implementation and verification completed September6,2026. See `../artifacts/ios-performance-audit-20260906/REPAIR-RESULTS.md` and `PM-STATUS.md`. Production migration, phone installation/measurement and release remain approval-controlled external steps.

# iOS performance repair implementation plan

> **Execution:** Use `custom-skills:executing-plans` per OPS instructions. This is an approved repair initiative managed by the parent task; no technical-plan approval is required from Jackson.

**Goal:** Preserve installed data and captured work, make site visits responsive during online use, and verify the combined repairs without releasing them.

**Architecture:** Keep SwiftData persistence and outbox custody atomic while bounding each ordinary edit to its actual entities. Own background contexts and immutable transfer values for expensive recovery, media, and serialization work. Preserve schema history, conflict guards, parked-work decisions, local durability, and current visual patterns.

**Tech stack:** Swift, SwiftUI, SwiftData, SQLite, structured concurrency, Supabase Swift 2.54.1, XCTest, Instruments.

**Design system:** `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md`, `mobile/MOBILE.md`, and each worktree's `OPS/Styles/OPSStyle.swift`. No `.interface-design/system.md` exists. Use `OPSStyle.Colors`, `OPSStyle.Typography`, and existing spacing/layout tokens for any changed UI. No decorative redesign.

**Required skills:** `custom-skills:executing-plans`, `superpowers:systematic-debugging`, `superpowers:verification-before-completion`; add `custom-skills:ops-design`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`, and `custom-skills:audit-design-system` for UI/copy. Use animation architect/platform skills only if motion changes.

## Authority and evidence

Jackson authorized repair sessions and delegated project management to the parent task `01a0779e-54bf-72a3-976c-81c692990d23`. He separately authorized a local full-phone-database export if useful. The parent alone handles that export; never copy real database contents into git, artifacts, tests, or other services. Workers receive aggregate/schema evidence and use synthetic fixtures. No pushes, deployments, phone installs/data writes, releases, or production mutations are authorized. Atomic local commits and local integration are authorized by the repair request.

Audit: `/Users/jacksonsweet/Projects/OPS/ops-ios/docs/artifacts/ios-performance-audit-20260906/REPORT.md`. Baseline source: `94543f955ca8a2ccee4cc148c24c6d33de92cccc`. Existing schema compatibility test freshly failed: V16–V25 drift, V1–V15 match. Other audit findings are traced source paths; their individual frame-time costs are not measured yet. Recheck every finding; don't preserve a mistaken hypothesis.

## Isolation and ownership

Four sessions use `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-p1-{1,2,3,4}` at the audited baseline. The saved OPS project is a parent folder, not a repository, so the parent prepared these real child-repo worktrees manually. Do not create nested worktrees. Do not edit shared main or other worktrees. Each worker writes its own `docs/artifacts/ios-performance-p1-N/HANDOFF.md` and commits its work. The parent alone writes the shared PM ledger and integrates.

Only one expensive iOS build/test/profiling process may run at once. **Workers have no build baton initially.** Source reading, editing, test authoring, lightweight static checks, and commits are allowed. Do not run xcodebuild, swift build/test, package resolution, simulator launch, or expensive data/image benchmarks until the parent grants the baton. At readiness, report `READY FOR BUILD BATON` with exact commands and commit IDs. The parent will normally run combined focused tests from one integration checkout to conserve the Mac's 85 GiB free space. No background child agents or extra sessions without parent coordination.

All new persistent model fields or migration changes belong to P1-1. If another worker needs persistence, consult P1-1 through the parent first; prefer existing durable outbox or a separately versioned file journal where appropriate. Keep line endings. Preserve parent-child order, idempotency, UUID normalization, exact ownership, offline safety, deletion custody, and retry/decline decisions. Be careful with SwiftData predicates: see the documented empty SyncOperation table trap; do not blindly substitute a trapping predicate for the broad fetch.

## IOS PERFORMANCE - P1-1: installed database compatibility

Own audit finding 1. Files: `OPS/DataModels/Migrations/`, `OPS/DataModels/DeckDesign.swift`, `OPS/OPSApp.swift`, new storage-bootstrap helpers/recovery UI if needed, and relevant migration tests/fixtures. No deck editor or sync-engine edits.

1. Reproduce the released-schema identity mismatch from the existing test/output and trace the September 4 change.
2. Add regression coverage that preserves released shapes, upgrades a populated synthetic prior-version store, retains unsent drawing/capture data, and opens idempotently. Cover the widened shape already used by the current debug build if metadata supports it. Never overwrite old checksum fixtures to bless drift.
3. Freeze historical models and introduce a valid adjacent schema/migration boundary. Retain merge-base semantics introduced by syncedDrawingJSON.
4. Make database-open failure survivable where feasible without deleting/resetting the installed store or silently replacing it with an empty store. Any recovery UI must honestly preserve data and use existing tokens/copy patterns.
5. Commit and provide focused test selectors plus precise schema contracts. Parent reviews and tests this first.

## IOS PERFORMANCE - P1-2: bounded visit edits and continuity

Own findings 2, 3, 6, 10, 11, 13 and site-visit adapters for findings 5/12. Files: `OPS/Services/SiteVisitPersistenceCoordinator.swift`, `OPS/Views/SiteVisits/SiteVisitCaptureView.swift`, `SiteVisitCaptureViewModel.swift`, new visit-specific helpers, and `OPSTests/SiteVisits/` coverage. Coordinate repository changes if necessary. No shared media utility or SyncEngine/RecoveryInventory edits.

1. Add synthetic multi-visit fixtures proving an edit scales with changed records and cannot revive unrelated parked/declined operations. Preserve graph atomicity on failed saves and rollback rematerialization.
2. Implement scoped changed-entity enqueue with indexed per-transaction lookup and unchanged-content guards. Preserve a compatible separate explicit orphan-repair entry point for P1-4.
3. Use one content policy so answers, notes, and partial identity edits prevent empty-draft deletion. Make new-visit intent distinct from resuming an interrupted visit; retain existing valid navigation behavior.
4. Load local client suggestions immediately, refresh leads independently, and bound exact visit/deck lookup. Prevent late search responses from overwriting active edits.
5. Preserve drafts regardless of required fields. Make draft versus completion semantics coherent with current product rules; confirm true taste/scope forks with the PM, not technical mechanics with Jackson.
6. Separate durable local save acknowledgement from remote stage delivery. Do not simulate successful stage change; ensure retry survives interruption and cannot double-deliver. Coordinate any new persistent shape with P1-1; keep network writes mocked in tests.
7. P1-3 publishes durable photo and async thumbnail contracts. You alone own the visit view/model adapters; do not keep the expensive legacy route as the final visit implementation. Parent coordinates cross-worktree imports before compilation.
8. Commit coherent slices; include focused persistence, handoff, content-policy, search, and stage-delivery tests. Spell out adapters waiting on P1-3 rather than pretending done.

## IOS PERFORMANCE - P1-3: photo durability and cache cost

Own shared-media portions of findings 5, 7, 12. Files: `OPS/Views/Components/Images/CameraBatchView.swift`, `OPS/Services/LeadImageService.swift`, `OPS/Utilities/PhotoPrefetchService.swift`, `StorageProfiler.swift`, `ImageFileManager.swift`, new media-staging/thumbnail helpers, and narrowly relevant camera/cache tests. No edits to SiteVisitCaptureView/Model; P1-2 owns those adapters.

1. Publish a small typed API contract for durable staged capture and async bounded thumbnails early through your handoff. Parent forwards it to P1-2. Preserve compatibility for other camera callers until their migration is complete.
2. Stage accepted shots durably as they arrive, with a recoverable batch manifest; bounded thumbnail work and encoding/file writes must not block main. Keep originals, orientation, annotation precedence, error custody, and per-item retry. Cancellation of uncommitted nonempty capture must be deliberate. Ensure no orphaned bytes are deleted while still owned by a pending capture.
3. Replace repeated full-cache walks per download with a background snapshot plus incremental reservations/accounting, including concurrent downloads/cancellation/failure. Keep budget, Wi-Fi/cellular policy, and unsent-file protection.
4. Provide an async size-specific thumbnail loader with local/markup precedence, remote fallback, cancellation, deduplication, and cache-arrival refresh. P1-2 wires the eager packet into an appropriate lazy view.
5. Remove equivalent main-thread staging from lead images without breaking existing API consumers. Test disk failures, partial batch success, process interruption/reopen, budget reservations, and thumbnail fallback using synthetic files/network fakes.
6. Commit and publish API contracts and exact integration instructions. Do not run expensive capture or rendering tests without the baton.

## IOS PERFORMANCE - P1-4: online sync and deck responsiveness

Own findings 4, 8, 9 and small adjacent no-op invalidation/instrumentation items supported by evidence. Files: `OPS/Network/Sync/SyncEngine.swift`, `SiteVisitOrphanRecovery.swift`, `RecoveryInventory.swift`, `OPS/Views/Components/Sync/SyncStatusIndicator.swift`, `OPS/Views/MainTabView.swift`, `OPS/DeckBuilder/DeckBuilderViewModel.swift`, `OPS/DeckBuilder/Views/DeckBuilderView.swift`, relevant DataActor helpers/tests. No coordinator, persistent-model, site-visit capture, or shared photo utility edits.

1. Trace repair/drain scheduling, then separate broad recovery from ordinary upload wakeups. Use owned background contexts and exact candidates; do not move live main-context model instances across actors. Verify parent-child dependency, cancellations, retries, deletion reconciliation, and parked-work semantics.
2. Preserve a compatibility adapter to P1-2's explicit orphan-recovery API; ordinary edits must not trigger another company-wide repair scan.
3. Compute compact recovery status once from relevant IDs away from interaction, diff results, and avoid a full inventory just to show a pill. Preserve 500 ms debounce/default-runloop fallback and all actionable recovery detail.
4. Remove duplicate deck serialization on exit, preserve immediate local save failure reporting and mid-session crash durability, move safe thumbnail preparation off interaction paths, and coalesce deferred pushes. Honor the intended editor-session cloud boundary without losing durable revisions. Some rendering is UI-bound; don't claim Task.yield changes executor.
5. Preserve calendar/tab caches, geometry/revision guards and Supabase 2.54.1. Gate unchanged visit notifications only when semantics prove safe.
6. Add bounded instrumentation/fixtures for interaction cost and online/offline drains. No broad metrics platform or unrelated redesign. Commit and provide focused selectors and explicit unmeasured device claims.

## Parent integration and acceptance

Parent owns all handoff contracts, reviews, conflict resolution, shared bible edits, build scheduling, and final reporting. Workers put proposed bible updates in their handoffs; the parent updates the actual bible in this initiative to avoid overlapping edits. Integrate P1-1 first; P1-2/P1-3 adapters together; P1-4 after checking coordinator and media contracts. Use one isolated integration checkout; don't modify shared main while sibling work is dirty. Local merge only after focused tests and review pass.

Validate existing released checksums and populated synthetic migrations; exact changed-entity queue behavior and stopped-work preservation; checklist/identity-only resume; interrupted photos and partial failures; local-first search; completion/stage retry; cache budget and thumbnail fallback; deck autosave/exit; online drains and status refresh. Run appropriate focused suites and a device-target build as allowed by repo rules. Keep tests network-isolated: never send real pending phone operations from a test fixture.

Profile a known optimized build using the scripted new visit → checklist → ten photos → notes → representative deck → return → save/reopen flow, with online/offline/slow-network/reconnect conditions and long-lived synthetic workloads based on measured aggregate counts. A phone install or customer-data mutation is a separate approval gate. Do not claim actual device or customer-live performance solely from synthetic tests.

Completion requires every audit finding dispositioned (fixed, disproved with evidence, or an explicit remaining external validation/action), no missing integration adapter, focused tests passing, and bible current. Report local verification separately from release/device proof. Do not push or release without Jackson's explicit request.

## IOS PERFORMANCE - P1-5: idempotent site-visit stage delivery

Added by PM after P1-2 verified the current live move_opportunity_stage RPC lacks command idempotency and expected revision. Existing guarded lifecycle/email functions are limited to specific autonomous workflows; do not repurpose their approval or AI-decision authority for a manual visit action. This is the narrow server dependency of finding 13, not a new product initiative.

Own an isolated ops-web worktree at `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-p1-5`, branch `codex/ios-performance-p1-5`, baseline `bcd252e55c6af94a603a04d4d08ad88e7518a34a`. Shared ops-web is heavily dirty and must not be edited/staged/reset. Own only the narrow new stage-command migration/function/private receipt storage if necessary, contract tests, and handoff. No general lifecycle refactor, UI, or change to the legacy RPC used by other clients.

1. Read live function definitions, exact opportunity/site-visit columns, stage-transition behavior, triggers, actor/company resolution, permission scopes and RLS using read-only Supabase MCP on verified ops-app project `ijeekuhbatykdomumfjx`. Consult Bible and current source. Reuse a safe existing endpoint only if its full authorization/replay/expected-revision semantics match this manual visit action.
2. Publish an exact typed request/result contract promptly to P1-2 via PM: stable command UUID, visit and opportunity binding, actor resolved from trusted auth, company ownership, target stage, expected prior stage/revision, outcomes applied/already-applied/conflict/not-ready as appropriate. Derive revisions from exact server data; preserve full timestamp precision and null semantics. Do not invent persistent client fields. P1-2 owns the Swift payload and SiteVisitOutboundSync adapter.
3. Implement atomic command deduplication and row-locked expected-revision checks. Exact replay returns the original receipt even after a later stage change, without reapplying. Command-key reuse with altered payload fails. Competing commands and concurrent stage edits cannot overwrite newer state. Preserve manual-stage ownership, terminal/won/conversion guards, transitions, attribution and canonical side effects. Do not accept arbitrary caller identity or company; Firebase bridge auth.uid() caveat applies.
4. Keep receipt tables private/no broad Data API access, RLS and minimal grants, fixed search_path where needed, no anon execute. Verify caller/entity permissions with canonical helpers. Avoid widening legacy behavior. The old RPC remains source compatible and untouched unless a proven bug requires a separately reviewed slice.
5. Prepare locally only. No production DDL/DML/apply_migration, push, deployment, or release. A server migration approval is a release gate; do not apply to live for verification. Use synthetic fixtures in disposable local Postgres or existing isolated SQL harness. No Docker/large environment downloads or broad builds without checking with PM. Lightweight source/SQL checks and narrow existing tests allowed.
6. Cover exact replay after later move, payload mismatch, two concurrent calls, stale prior revision, same-stage ambiguity, cross-company/cross-user denial, forbidden target, deleted/archived or converted entity, permission loss, rollback atomicity, and missing-server capability. P1-2 must fail closed on unsupported transport rather than replay unguarded; the combined iOS release depends on deploying/verifying this server guard first.
7. Commit locally, and write `docs/artifacts/ios-performance-p1-5/HANDOFF.md` with migration path, contract, test evidence, exact deploy/revert/readback needs and proposed Bible update. PM owns actual shared Bible integration. Keep any SQL schema/definition evidence free of customer row contents.

P1-2 may edit `OPS/Network/Sync/SiteVisitSyncOperation.swift` and `SiteVisitOutboundSync.swift`; P1-4 owns any narrow DataActor/OutboundProcessor dispatch adapter. These owners must coordinate via PM. Local source preparation and tests continue while production migration approval remains pending. PM must not call the stage feature customer-ready until backend and client contract are deployed/verified under explicit release approval.
