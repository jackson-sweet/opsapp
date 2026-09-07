# DataActor Runtime Startup Implementation Plan

> Execute with custom-skills:executing-plans. PM owns the serial build/test baton and phone installation; this worker prepares code, tests, and source-only checks.

**Goal:** Keep DataActor's actual SwiftData transactions off the main thread while making configuration and startup cleanup an explicit prerequisite of first sync.

**Architecture:** Create the production context on a private serial dispatch queue and install a public SerialModelExecutor that runs every actor job on that same queue. A detached constructor alone and an explicit witness for DefaultSerialModelExecutor both failed real transaction probes; the explicit queue passed, including Core Data concurrency assertions. One cancellable, container-scoped startup object owns construction, configuration, and ordered normalization/dedup/relationship linking. DataController publishes only the completed actor; SyncEngine receives the pending startup object synchronously and waits instead of selecting the legacy path while it is pending. Every waiter rejects obsolete engine/context/account state after the wait.

**Tech Stack:** Swift concurrency, SwiftData ModelActor, XCTest; iOS 17.6 minimum.

**Design System:** N/A; no UI, motion, or copy changes.

**Required Skills:** systematic-debugging, using-git-worktrees, test-driven-development, custom-skills:writing-plans, custom-skills:executing-plans, verification-before-completion.

## 1. Prove executor affinity

- `OPSTests/Sync/DataActorExecutorTests.swift` exercises real DataActor transactions, not just the thread running a factory closure. Old MainActor construction is the positive main-thread control; the production factory is called from MainActor and must still transact off-main. Concurrent calls must serialize real transactions and a disk-backed transaction must survive container reopening. Synthetic one-row persistence and autosave checks establish actual context use.
- PM runs `OPSTests/DataActorExecutorTests` on the pre-repair probe commit. Worker performs only frontend parse.

## 2. Specify readiness and invalidation regressions

- Add tests for the production startup path, coalesced waiters, delayed preparation, cancellation before publication, replacement container, and current-account checks.
- Gate the real startup preparation and enqueue a synthetic operation. Prove the queue remains pending before release and completes through the configured background actor afterward. A decode-valid fake payload must never reach a real repository; use the existing actor test push seam.
- Preserve explicit legacy behavior when the flag is off. Tests must expose the old main-construction and early-publication mutations, not inspect source structure.

## 3. Implement background construction and ordered bootstrap

- New `OPS/Utilities/DataActorStartup.swift` owns its container, detached task, and thread-safe cancellation state. It invalidates a constructed actor synchronously when stopped and checks cancellation/currentness between preparation steps.
- `OPS/Utilities/DataActor.swift`: make configure idempotent; add an ordered preparation method covering the exact old normalize/cleanup/rewire sequence. Keep all context operations actor-isolated.
- `OPS/Utilities/DataController.swift`: install the pending startup and refresh bridge synchronously, await completion before publishing the actor, retain the existing auth initialization paths, and cancel old startup/binding work at context replacement and authentication/data teardown. Remove the FIFO assumption and separate unstructured configure task.

## 4. Bind sync consumers to readiness

- `OPS/Network/Sync/SyncEngine.swift`: retain pending readiness through same-container configure, wait at actor-using entry points and realtime subscription setup, and guard engine generation, context, user, and company after suspension. Logout cancels pending startup. Do not silently use the legacy driver when a registered startup is pending or invalidated.
- Preserve outbound session generation and registered-model guards. Actor publication must not repeatedly invalidate/resume the same actor when multiple waiters complete.
- The authorized CalendarViewModel callsite awaits controller readiness when enabled and the configured background factory in legacy mode, with user/company/context/generation checks after each wait. Realtime processors are permanently retired on rebinding/logout, synchronously closing queued/in-flight merge ingress before asynchronous network teardown.

## 5. Verification and handoff

- Worker: frontend parse, CRLF-aware diff check, inspect scope and clean atomic commits. No compilation, package resolution, tests, or raw phone data/trace access.
- PM: run executor/startup tests plus OutboundLifecycleTests, SyncRecoverySchedulingTests, ProjectNoteMentionEditTests, and relevant bootstrap/auth fixtures. Repeat the original-constructor and early-publication negative mutations only in PM's isolated verification copy.
- Record exact source/test evidence and Bible delta in the worker handoff; PM owns shared Bible integration and a separately authorized equivalent optimized phone measurement.

## 6. Runtime evidence and lifecycle acceptance

- PM probe01/02 showed detached construction did not move real transactions off-main, even with both container and actor created in background. Probe04 showed an explicit witness alone also did not fix DefaultSerialModelExecutor. Probe03 passed the explicit serial queue under Core Data concurrency assertions.
- Production checkpoint `22b7e6f1` plus the parent MainActor annotation/fixture updates passed 44/44 focused tests at integration `ddf14ece` (149.4 seconds, zero skipped). This proves the production factory's actor-body/transaction affinity, concurrent serialization, persisted reopen, startup boundary, and the focused existing sync consumers. It does not prove the later lifecycle additions below.
- Per-invocation lifetime/account scope now flows through every private inbound sync method; each suspension checks the original scope before merge or successful completion. Retired queued transactions fail closed. Retirement drains the serial executor after revocation so a main-context wipe cannot overlap an already-running model transaction.
- SyncEngine scopes completion, progress, cursor, Spotlight, busy-wait continuation, and deferred state cleanup to the original context/account/startup/actor generation. Recovery slots are owned by task identity and clear on every exit. Engine configuration tracks context identity independently of the image-manager sentinel.
- Image manager retirement calls depend on P1-3's synchronous permanent `invalidate()` adjunct; PM integrates those together. No image-manager implementation is owned here.
- New focused tests cover delayed single/batch client responses after wipe/account change, retired queued/realtime ingress, cursor/error publication after retirement, retirement versus an executing transaction, recovery before its first scheduled turn, and an already-authenticated/configured controller's replacement store.
- PM owns final test execution, equivalent optimized phone measurement, and Bible updates. Bible delta: replace the synchronous ModelActor constructor/FIFO guarantee in `06_TECHNICAL_ARCHITECTURE.md` with private serial executor + awaited construction/configuration/bootstrap readiness; describe the startup/current-container account boundary, current-transaction drain before wipe, and no pending-startup legacy fallback. Preserve the actor-owned context and no raw model crossing contracts in `03_DATA_ARCHITECTURE.md`.

## 7. Final nested lifecycle closures

- Sync busy state uses an explicit cycle token for cleanup. Cancellation prevents further work but still releases the cancelled task's own busy/initial flags; replacement revokes the token. The held-pull regression requires the next sync to reach its own pull after background-style cancellation.
- Spotlight dispatch receives the original engine session predicate. Every incremental index entry and submission checks it; a client avatar continuation checks again before reading the retained model. Dispatch claims its current dirty/deleted batch before suspending so later marks survive its completion. The focused Spotlight tests substitute avatar and submission ports, make no network/provider writes, and cover retired-avatar completion plus marks arriving during a live batch.
