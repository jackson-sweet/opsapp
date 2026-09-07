# Image sync manager lifetime implementation plan

> Execute with custom-skills:executing-plans; PM owns serial build/test verification.

**Goal:** Retired ImageSyncManager instances cannot use old model contexts, change durable photo obligations or start follow-up sends after invalidation/account replacement.

**Architecture:** Add one terminal MainActor lifecycle boundary to the existing manager. Retain its originating ModelContainer for all in-flight references. Route startup, retry and connectivity triggers through revocable handles; gate instance entry points and every post-await model/queue/follow-up boundary. Preserve current backend operations and photo custody formats.

**Tech Stack:** Swift, SwiftData, Foundation scheduling and existing injected photo service ports.

**Design System:** N/A; no UI, styling or product copy changes.

**Required Skills:** systematic-debugging, custom-skills:writing-plans, custom-skills:executing-plans, test-driven-development, verification-before-completion.

## Scope

Only OPS/Network/ImageSyncManager.swift, focused OPSTests/Network/ImageSyncManagerLifecycleTests.swift, and this task's docs. Fresh checkout .worktrees/ios-performance-p1-3-runtime from 6f485f7289695ced487cead1aebb7e0aab290d7f. P1-4 owns DataController/SyncEngine invalidation/recreation callsites. Preserve previous worker checkout. No build/test/simulator baton, physical-phone operations, live service writes or push.

## Contract

`@MainActor func invalidate()` is synchronous, idempotent and terminal. It stops scheduled/observed triggers and cancels manager-owned tasks. It never calls clearAllPendingUploads, clears persistent queues, drops tombstones, or deletes image/capture bytes. Already-sent service requests may return; their continuations must stop before touching retired models/queues or issuing subsequent requests. A replacement manager reloads the existing durable queues.

## Steps

1. Read all async/public manager entry paths, initialization, queue helpers and callbacks. Confirm account bootstrap/rebind contract directly with P1-4.
2. Author failing-case fixtures for suspended mirror insert/probe/soft-delete, invalidation before scheduled work, account switch, overlapping drain triggers, retained container and unchanged durable queues. Use temporary UserDefaults suites, synthetic SwiftData and injected service/scheduler ports only. PM executes red/green checks; no local test execution under no-baton boundary.
3. Add lifecycle state and synchronous invalidation, retained container, trigger/task handles, account comparison and guarded durable save helpers. Preserve existing initializer compatibility.
4. Guard every instance model/queue entry, post-await model access, incident/notification follow-up, and image-retirement request. Set drain ownership before the first await so timer/connectivity calls cannot duplicate sweeps.
5. Add narrow injected ports only where needed to exercise actual existing logic without service writes. Prepare caller contract/guard inventory and proposed Bible text for PM.
6. Run lightweight Swift syntax parse and diff/line-ending checks only. Commit exact owned paths. Return READY FOR BUILD BATON with test selectors and explicit unverified-runtime limits.
