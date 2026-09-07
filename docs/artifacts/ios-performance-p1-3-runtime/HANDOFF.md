# ImageSyncManager lifetime handoff

## Scope and caller contract

Base: `6f485f7289695ced487cead1aebb7e0aab290d7f`. Only ImageSyncManager and focused lifecycle tests changed. No service routes, schema, custody formats, or UI changed.

`@MainActor func invalidate()` is synchronous, terminal and idempotent. Call it before releasing/replacing the manager on context or account teardown. It cancels startup/retry/connectivity triggers and owned tasks without clearing pending image uploads, portal mirrors, tombstones, or image/capture files. The manager retains its originating ModelContainer until the manager and outstanding callers release it.

P1-4 commit `ae91c86035c707455b1f9c68ba03fc902e411478` provides the DataController invalidation/recreation callsites. Integrate together. Existing initializer callsites remain compatible. Account identity is captured per invocation, allowing the initial company assignment to settle after manager creation; a changed identity stops an earlier invocation after suspension.

## Guard inventory

- Startup, timer and connectivity callbacks enter through a revocable scheduler. Already-dispatched callbacks check invalidation before creating any drain task.
- Owned tasks clean up their slot on every exit, including account change before their first actor turn. Invalidation cancels and releases task handles.
- Full drains acquire the reentry gate before their first sweep/await, and release only their own gate on exit.
- Upload, portal insertion/rejection probes, visibility refresh, handoff insertion, project deletion probes and soft-delete responses check the invocation before model changes, persistence or follow-up requests.
- New portal mirror obligations are persisted before their insert request; a response after invalidation cannot overwrite a replacement manager's queue.
- Crew rail completion checks the invocation before sending its companion push.
- Capture retirement retains the existing canonical receipt/local persistence order. The manager checks its invocation before requesting retirement and before later queue changes.
- Synchronous instance model/queue entry points refuse invalidated owners. Static context helpers retain their existing contract for other callers.

Requests already issued before invalidation can finish in the service layer. The boundary suppresses the old manager's subsequent effects; it does not retract an accepted server request or redesign transport cancellation.

## Verification

Worker checks passed: Swift frontend syntax parse for both edited Swift files; `git diff --check`. No build, typecheck, XCTest, simulator, device or live service operation was run by this worker. Parent holds the serial build/test baton.

Run `OPSTests/ImageSyncManagerLifecycleTests` (11 test methods). Synthetic ports and isolated UserDefaults cover delayed success and rejection; replacement queue preservation; fresh mirror durability before suspension; delayed project deletion and soft-delete responses; upload and notification account switches; trigger cancellation including callbacks already dispatched; overlap before the first await; first account assignment; and ModelContainer lifetime. No test calls real photo/notification write services.

Existing adjacent regression classes: `ProjectPortalMirrorDeliveryTests`, `PhotoSoftDeleteDrainTests`, `SharePhotoCreateBarrierTests`.

## Proposed Bible update for parent

In the ImageSyncManager lifetime/runtime description: the context owner synchronously invalidates the old image manager before context/account teardown and recreates it for the current context. Each manager retains its originating ModelContainer, owns revocable startup/retry/connectivity triggers and tasks, and gates asynchronous continuations by terminal validity and per-invocation user/company identity. Invalidation preserves all durable delivery obligations for the replacement owner. Full drain ownership starts before the first awaited recovery sweep; pending portal inserts are journaled before their request.
