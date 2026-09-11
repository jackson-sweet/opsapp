# OPS suspension crash diagnosis and bounded repair design

Date: 2026-09-11. Report: `fbc9104a-09f7-476a-a223-542ccb273618`.
Read-only source baseline: iOS main `b08de1042bed5d272d52daa83ef1bc30a501fa86`.
Skills consulted: systematic-debugging and custom writing-plans. No product UI or copy changes.

## Confirmed evidence

The exact raw report was recovered read-only from the paired iPhone 16 Pro, jPhone, through `devicectl` systemCrashLogs. No app installation, launch, restart, app-data copy or app-data write was performed. Local lookup had found no copy in the targeted artifact/diagnostic folders.

- File: `OPS-2026-08-29-150519.ips`, 51,528 bytes.
- SHA256: `a44456f9756e273142ee6f3216b39db10c8f08a5e090edeb60951e8f7db4a871`.
- Incident: `7D7758E9-D888-4C35-BE9B-3C7E4B3E639E`.
- App/build: 3.0.5 / 3.0.5; iPhone OS 26.6.1 (23G83).
- Launched 15:05:03.3281 -0700; captured 15:05:14.5068 -0700 on August 29.
- `EXC_CRASH` / `SIGKILL`, termination namespace `RUNNINGBOARD`, code `3735883980` (`0xDEAD10CC`).
- Main thread is idle in its run loop. Thread 6 is named `SQLQueue 0x127be1680 for default.store`.
- Thread 6 has symbolicated app frames; no further symbolication is needed to identify the function chain:

```text
SyncEngine.drainQueuedSyncRequest() closure
  → SyncEngine.triggerSync()
  → SyncEngine.pullDelta()
  → DataActor.deltaSync(companyId:since:)
  → DataActor.linkAllRelationships() + 296
  → SwiftData
  → NSManagedObjectContext.save
  → NSSQLiteConnection.processSaveRequest
  → _NSPersistentHistoryChange._propertyDataForEntity
```

This resolves the prior missing initiating-caller blocker. The specific observed crash is in the actor delta relationship save, reached through a queued follow-up sync.

Correction to old report wording: `702216e8` is the prefix of `OPS.debug.dylib` UUID `702216e8-90d8-338f-8124-5907088309b6`, not an established git revision. Exact old source line/commit and which relationship subtransaction was executing are not established by this file. The initial trigger that set the queued-follow-up flag and the exact scene transition timing are not preserved. No current-build reproduction or claim about recurrence count is made.

Apple defines this termination as retaining a file/SQLite lock during suspension, and recommends requesting background execution before the file-writing work starts: https://developer.apple.com/documentation/xcode/sigkill?changes=_5 . Background-task identifiers must be ended, including expiration; cancellation is cooperative and is not itself proof a synchronous SQLite save has finished: https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(withname:expirationhandler:) .

## Pre-repair source trace (b08de104 baseline)

Paths below are relative to `/Users/jacksonsweet/Projects/OPS/ops-ios`.

| Boundary | Verified behavior at baseline |
|---|---|
| `OPS/Network/Sync/SyncEngine.swift:1405` | `triggerSync` checks readiness, session, busy state and connectivity; it does not check application execution state or acquire a background allowance. Its defer calls `drainQueuedSyncRequest` even on cancellation, provided it still owns the cycle. |
| `OPS/Network/Sync/SyncEngine.swift:1462` | `drainQueuedSyncRequest` clears the request bit, creates an unretained/unstructured Task and calls `triggerSync`; there is no background gate. This is the exact caller recorded in the crash. |
| `OPS/Network/Sync/SyncEngine.swift:2236` | `pullDelta` dispatches to `actor.deltaSync` at 2265. Session checks protect account/context ownership, not suspension. |
| `OPS/Utilities/DataActor.swift:506` | Delta pulls entity batches, checks cancellation/account lifetime around network awaits, then calls `linkAllRelationships` at 568. |
| `OPS/Utilities/DataActor.swift:6720` | Linker first commits project/client/team and task/project/type/team relationships (6724); then inventory/unit/tag relationships (6814). Fetches and relationship updates are synchronous within each transaction. |
| `OPS/Utilities/DataActor.swift:117` | `currentModelTransaction` checks the active account/task lifetime once, then executes `modelContext.transaction`. This is the only direct production save/transaction call across DataActor Swift source files. No execution allowance or suspension gate. |
| `OPS/OPSApp.swift:385` | Backgrounding schedules future BG tasks and starts a 30-second delayed realtime stop. It does not close sync ingress, cancel/coalesce follow-ups, or extend the active save. `.inactive` does nothing. |
| `OPS/Network/Sync/BackgroundSyncScheduler.swift:79` | BG expiration cancels its parent Task; completion always reports success. A child launched by the queued-follow-up defer is not the awaited parent. Scheduling a future refresh does not extend the foreground-started sync. |

The same actor linker is reachable from `fullSync` (489), delta including realtime catch-up (568; SyncEngine 2326), schedule refresh (627; SyncEngine 1718), and startup/cleanup through `rewireRelationships` (6716; `prepareForFirstSync` at 188). A change only at `triggerSync` would not cover all these entry paths. Account retirement in `DataActorModelExecutor.drain` is an existing useful drain mechanism, but background suspension is temporary: do not reuse permanent logout retirement as the lifecycle state.

Other independently scheduled sync work includes direct `pushPending`, targeted company/client pulls, recovery tasks, realtime merges, retry timer, reconnect handlers, and `notifyDurableOperationQueued` (1309). They must not bypass any new sync admission rule. Actor writes converge on `currentModelTransaction`; legacy inbound uses direct `context.save` including linker line 1886, and needs equivalent coverage. BG processing also calls PhotoProcessor, which saves before/after upload awaits (161/173) and currently has no cancellation checks. A BG expiration design that awaits only `triggerSync` is therefore incomplete.

The application store is explicitly configured into `group.co.opsapp.ops` (`OPS/Utilities/OPSModelStore.swift:18`; `Shared/AppGroupConfig.swift:26`). Current share-extension source uses shared photo files/JSON and a background URLSession; it contains no SwiftData context/container access. The crash proves an app-side SQLite writer, not extension contention. Do not relocate/reset the installed store as this repair.

## Implemented bounded repair (source ready for serial verification, 2026-09-11)

The repair is committed as `6a6283c370bd88a6cec185405f5834be1ebc3635` and root cherry-picked it as `d78887ac` for serial verification. The private source is on accepted P19 base `187a36d631a7413ced22d631c3cc153c62eb195f`, in `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-bugs-p3-suspension`. The exact recovered caller is the actor delta/linker chain above. No persisted model, schema, App Group location, OPSApp, Lead Details, legacy InboundProcessor or RealtimeProcessor was changed.

1. `SyncExecutionCoordinator` installs ordinary foreground/background admission observers before its first lease. An ordinary pass obtains a UIKit assertion before model access; nested async phases inherit one task-local scope across actor hops. On background entry it closes new admission and reserves two seconds from reported remaining execution time before admitting another transaction. An admitted synchronous transaction is counted until it actually exits. The linker now commits at most 32 parent records per transaction, with checks between chunks.
2. Expiration closes permission and cancels the owned async root immediately, then ends the UIKit identifier promptly, as Apple requires. Assertion ending and actual transaction drainage are separate facts. Normal/proactive completion ends after drainage; on OS expiration the assertion ends promptly even if SQLite is still returning. No MainActor path synchronously waits for the actor. Callers cannot report completion before transaction drainage. This cannot guarantee an arbitrarily hung SQLite operation returns before a deadline.
3. `SyncFollowUpRequest` retains/coalesces pending work, owns its task, drops inherited execution scope before a new pass, and checks foreground and busy ownership again immediately before admission. Denied admission or an interrupted/no-op cycle restores one pending request and stops retrying until another valid boundary. A foreground trigger consumes the pending request. Logout/configuration replacement cancels and clears obsolete ownership.
4. DataActor's single `currentModelTransaction` boundary checks the inherited execution scope around the actual synchronous transaction. Relationship failures/cancellation propagate through full/delta/schedule/startup instead of being swallowed, so partial commits do not advance pull cursors or produce a false successful pass. Already-committed links remain durable and the next pass completes them idempotently.
5. Background scheduler callbacks install a thread-safe expiration scope synchronously before their MainActor task can start. Their callbacks return real success/admission outcomes and capture account/context/actor session only after startup readiness. Each post-await phase validates that captured session. Cold background startup can borrow a current OS grant; interrupted preparation waits for a newer foreground or system admission. Each grant retains its actual admission generation. Selection chooses the newest eligible live permission, so expiration of the borrowed older grant can resume preparation under a newer grant that is already active without requiring a third event. Cancelling a readiness waiter returns promptly without cancelling shared preparation.
6. Photo processing retains its originating container and owns an invalidatable lifetime. It checks lifetime and execution permission before every post-upload model access. In-flight uploads stay `uploading` on interruption and are picked up by the next pass without spending a second retry count. Success persists immediately under the scope. Configure/logout invalidates the old processor before replacing its context.

These controls cover the proven actor sync/linker mechanism and associated explicit startup/BG/photo phase ownership. They do not inventory or promise all app writers: legacy flag-off merge paths, realtime ingress, main-context autosave, capture/deck saves, ImageSyncManager and share finalization retain their separate policies.

## Prepared verification

There are 33 new focused tests across `SyncExecutionCoordinatorTests`, `SyncFollowUpRequestTests`, `SyncSuspensionRegressionTests`, `DataActorSuspensionTransactionTests`, `DataActorStartupSuspensionTests`, and `PhotoProcessorSuspensionTests`.

Coverage includes allowance denial; begin/end order; nested leases; prompt expiration versus actual transaction drainage; positive headroom with controlled monotonic clock; cancellation; OS grant expiration before MainActor admission; queued-cycle background/foreground bounce; losing admission to a concurrent cycle; denial at the acquisition seam; closed-parent recovery; unchanged cursor/paused status; a real 70-project linker interrupted after the first <=32-record commit and resumed; cold background readiness; an expired readiness waiter returning before held network completion; BG actor binding and overlapping system-grant ownership; expired upload resumption near retry cap; and logout before a late upload response. Test gates and synchronous test semaphores are time-bounded. Test sync defaults restore all affected sync.* keys.

Static verification: `git -c core.whitespace=cr-at-eol diff --check` passes. No compiler, build, tests, simulator or device runtime was executed by this agent. P3-3 completed final independent source review with no remaining actionable findings. Root owns serial build/test execution and reports the 13-class suite is compiling, with no result claimed yet. The run includes all six new classes and the seven affected existing classes: `DataActorExecutorTests`, `DataActorStartupTests`, `DataActorInboundLifetimeTests`, `OutboundLifecycleTests`, `InboundChangeSignalDataActorTests`, `SyncCursorInvariantTests`, and `SyncRecoverySchedulingTests`.

Physical-device proof remains outstanding: use an optimized current build without debugger for queued delta, background network return, large relationship graphs, expiration and foreground recovery; inspect crashes and durable store/queue states independently. This source repair is not a release and does not establish global 0xDEAD10CC prevention.

## Ownership and evidence status

The raw crash was recovered read-only. No device install/launch/restart/app-store write, production/Supabase mutation, build/compiler execution, push or release occurred in this agent's work. The previous caller-evidence blocker is resolved. P19's accepted V28 schema and site-visit duplicate-PK guard remain unchanged. External email-photo-origin WIP remains untouched. Root separately owns bug-report notes and integration.

Adjacent observation, outside this exact caller: `SpotlightBackfillCoordinator` has an existing UIKit expiration callback that logs without ending its assertion. It was not used as a reference for this repair and has not been changed.

## First serial runtime findings and bounded correction

Root's first compiled 13-class run reported 70 passed, 2 failed, 0 skipped (72 total). All 11 execution-coordinator, 9 follow-up, 5 startup-suspension, 2 actual-linker, and 2 photo-processor tests passed. The remaining failures were the expiration orchestration test (signal trap with no available stack/current IPS) and the closed-parent recovery assertion.

The trap followed the preceding fixture's successful sync and a singleton PhotoPrefetch log. Source independently establishes a concrete defect: `prefetchIfAppropriate` queued a task retaining only `ModelContext`, and `runPrefetch` awaited the storage profiler before accessing `modelContext.container`. Container ownership could end with the calling fixture/session. This is a source-proven lifetime defect; the unsymbolicated trap is not claimed to establish its exact cause.

The bounded correction captures and retains `ModelContainer` synchronously before queuing prefetch, passes it directly into the snapshot reader, checks cancellation after the profiler await, and claims the task slot synchronously with UUID-owned completion so an old cancelled task cannot clear a replacement. Independent prefetch is not checked against an inherited sync scope that closes during normal sync completion. Two real queued-worker/SwiftData regressions cover caller release before queued startup and during a held snapshot, plus cancelled old completion while a newer task owns the slot. The new total is 35 tests across seven classes.

The recovery fixture used an online-decision override but still received real NWPathMonitor broadcasts. Its configured engine could therefore admit a legitimate independent recovery while the assertion observed the closed parent's slot. The correction gives that recovery-only fixture an offline decision helper, preventing notification-triggered admission while preserving both explicit recovery requests and all original pending/owner assertions. Root will rerun 14 classes (74 total expected); no corrected runtime result is yet claimed.
