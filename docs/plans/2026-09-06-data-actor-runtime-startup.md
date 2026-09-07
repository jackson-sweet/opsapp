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
