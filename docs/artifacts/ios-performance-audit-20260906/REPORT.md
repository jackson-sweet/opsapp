# iOS performance and continuity audit — September 6, 2026

The app still has substantial work on the thread responsible for typing, scrolling, and presentation. Site visits concentrate several of those paths: whole-store queue scans during field edits, full-image processing before the camera dismisses, and expensive work when returning from the deck editor. Online sync adds further main-thread recovery and photo-cache work. Airplane mode is a useful diagnostic clue, but it does not identify a single cause.

**Recommended order:** repair the database compatibility regression and capture-loss paths; make site-visit persistence proportional to the actual edit; remove sync recovery, image preparation, and repeated storage scans from interaction paths; then verify the complete visit flow on an optimized device build under several network conditions.

This records the original audit against the source revision below. The later authorized repairs are now verified and integrated locally; see [REPAIR-RESULTS.md](REPAIR-RESULTS.md). The subsequently approved server update and optimized development install were completed; physical upgrade/custody passed. No App Store release occurred. The runtime follow-up below records the additional findings. Source line references below describe the audited baseline; those files now contain repaired code on local main.

## Evidence and limits

- Source examined: local `ops-ios` main at `94543f955ca8a2ccee4cc148c24c6d33de92cccc`.
- Deep review: visit entry and resume, checklist and notes, identity search, camera handoff, artifact thumbnails, deck persistence/exit, sync coordination, visit queue construction, Realtime merge, recovery status, and photo prefetch/storage.
- Broader sampling: calendar/tab performance repairs, lead refresh, Home/Books activation, 3D scene invalidation, and performance instrumentation. This is not an exhaustive audit of every product feature or a visual walkthrough of every screen.
- Paired phone: iPhone 16 Pro, installed OPS `3.0.5 (3.0.5)`. Retrieved reports identify iOS 26.6.1. The version label alone does not establish which source revision was installed.
- **Device CPU evidence:** `OPS.cpu_resource-2026-09-04-140631.ips`, September 4, 14:03:47–14:06:30 Pacific: 90 seconds CPU time over approximately 163 seconds, reported 55% average; memory footprint 361.47 → 444.62 MB. All 31 recorded samples were frontmost, user-active, interactive-priority samples. Stacks include SwiftUI/AttributeGraph and SwiftData/Core Data. This verifies excessive work during use, not the exact action or function responsible for every pause. The report says no action was taken; it is not a crash report.
- **Device crash evidence:** September 4 at 19:22 and September 5 at 16:21 both terminate on the main thread in `OPSApp.sharedModelContainer`, followed by `OPSApp.init()`. These are database-opening failures, separate from the earlier CPU incident. Their `OPS.debug.dylib` UUID matches the local device binary available when inspected. The older CPU report's code UUID does not match available local symbols, so its anonymous app frames were not assigned guessed function names.
- Those crash reports contain the debug entry point. Reproduce performance with a known optimized build as well; do not equate a debug-build CPU sample to an App Store performance measurement.
- The database file was listed as 81.3 MB. Size alone establishes neither corruption nor an oversized data set. Its contents and exact row counts were not inspected. Automatic approval review rejected exporting the full database because it could expose customer data; the audit proceeded without that export.
- A fresh run of the existing schema compatibility check is recorded in `verification.md`. No fresh online/offline interaction trace was collected, so the relative contribution of the performance findings remains to be measured.

## Authorized follow-up database inspection

After this audit, Jackson explicitly authorized a full local database export. The parent copied the database and its zero-byte WAL into private temporary storage, with no phone writes or external upload. SQLite quick_check returned `ok`. The store reports version `25.0.0` and checksum `oDrDy3ePGUW2ZiuwOISzdvuUZ8yf5LtXt42AFLxtTrs=`, matching the original released V25 fixture. The physical deck table lacks the newly added merge-base column. This strengthens finding 1 while still not supplying the historical crash NSError.

Aggregate counts: 2,636 sync operations (2,625 completed, 9 pending, 1 inProgress, 1 parked); 30 visits; 149 capture artifacts; 283 answers; 25 identity drafts; 153 deck designs; 967 project photos; 484 clients. Drawing JSON totals approximately 614 KB, with a largest drawing of approximately 28 KB. Ordinary accumulated history is enough to exercise the broad-scan paths; database size alone was not the diagnosis. Use synthetic fixtures at these scales, not customer records.

Sanitized schema and aggregate evidence: [store-diagnostics.json](/Users/jacksonsweet/Projects/OPS/ops-ios/docs/artifacts/ios-performance-audit-20260906/store-diagnostics.json). The earlier export rejection was resolved by Jackson's explicit authorization. The audit's initial limitations above describe what was known before this follow-up.

## Ranked findings

### 1. P1 — A recent persistent-model change rewrites released schema definitions

**Evidence:** The September 4 commit `8126e38a` adds stored `syncedDrawingJSON` to live `DeckDesign`. Historical schemas V16 onward still include that live class through `v16DeckDesignModel`. The current schema remains V25 and the migration plan has no new boundary for this property. The device's two inspected crashes occur at the application's database-open failure path.

An optional local property still changes the persistent model's fingerprint. Additive compatibility with a server table does not preserve an already released SwiftData schema. This is especially consequential because the app intentionally preserves an unopenable store instead of deleting potentially unsent work.

**Recommendation:** freeze the previously released deck shape, introduce the widened shape at a new schema version, add the migration, and verify against the committed released fingerprints. Include upgrade fixtures from real released versions. Preserve the installed store; do not use deletion or reinstall as recovery. Replace unconditional startup termination with a recoverable storage-error surface where possible.

**Confidence:** reproduced by the existing compatibility test on current source: one test executed and failed; all V16–V25 fingerprints differ from the released baseline, while V1–V15 match. Device crashes corroborate the failure boundary. The underlying NSError from those historical crashes is not present in the retrieved stack reports, so their precise store error is not asserted.

Sources: [DeckDesign.swift:65](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/DataModels/DeckDesign.swift:65), [OPSSchemaCommon.swift:1440](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/DataModels/Migrations/OPSSchemaCommon.swift:1440), [OPSSchemaCurrent.swift:23](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/DataModels/Migrations/OPSSchemaCurrent.swift:23), [OPSApp.swift:75](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/OPSApp.swift:75).

### 2. P1 — A checklist keystroke can scan and rebuild every dirty visit's queue

Checklist text binds directly to `updateChecklistAnswer`. Every setter commits through `SiteVisitPersistenceCoordinator`, whose `queueDirtyGraphs()` fetches all sync operations, all visits, all artifacts, all answers, and all identity drafts before filtering in memory. It then re-encodes and requeues dirty records across the company. Each enqueue searches the operation list; cycle protection reconstructs an operation dictionary. Historical completed operations are included in the initial fetch too.

This runs synchronously on `@MainActor`. The cost grows with stored history and outstanding work, even when the user changed one character. Notes have a 650 ms debounce and identity has a 450 ms debounce, but they eventually enter the same global operation. Identity saves also lack an unchanged-content guard.

**Recommendation:** persist the changed visit/entities and their dependencies in one bounded local transaction, keeping model and durable queue atomic. Index queue lookups once per transaction. Use a local editing buffer for checklist text with a short coalesced commit and guaranteed flush on focus loss/interruption. Keep global orphan repair separate from ordinary field saves. Preserve all offline and conflict protections.

**Confidence:** exact call chain verified in source; the phone's time per edit has not been measured.

Sources: [checklist binding:1931](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureView.swift:1931), [updateChecklistAnswer:463](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift:463), [queueDirtyGraphs:211](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Services/SiteVisitPersistenceCoordinator.swift:211), [enqueue:367](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Services/SiteVisitPersistenceCoordinator.swift:367).

### 3. P1 — Editing one visit can revive another visit's stopped or parked work

The same global scan has a correctness consequence. Ordinary commits use `onlyOrphans: false`; unresolved statuses include `parked` and `declined`. For every dirty record considered, `enqueue()` resets the existing operation to `pending`, clears its error, and resets its retry count. There is no check that the mutation actually edited that record. Media is reconsidered whenever a local URL remains, even without a dirty flag.

Thus a save in visit A can reactivate a matching stopped/parked operation belonging to visit B in the same company. This can cause repeated failed sends and recurring recovery indicators. The existing orphan-recovery preservation check covers a different path with `onlyOrphans: true`.

**Recommendation:** only an explicit retry or a genuine revision of that exact entity may reactivate stopped work. Preserve unrelated statuses and retry history. Verify with two visits, including a declined media upload in the visit not being edited.

**Confidence:** source-established state transition; not reproduced against customer records.

Source: [SiteVisitPersistenceCoordinator.swift:24](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Services/SiteVisitPersistenceCoordinator.swift:24), [reset at:404](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Services/SiteVisitPersistenceCoordinator.swift:404).

### 4. P1 — Every outbound drain performs extensive recovery work on the UI thread

`pushPending()` runs multiple recovery/reconciliation passes before checking the ready queue: task repair, missing visit parents, dirty visit graphs, deleted-parent settlement, parked-media inspection, stranded decks, and note-chain reconciliation. `SiteVisitOrphanRecovery` independently fetches visits, operations, artifacts, answers, and drafts, then invokes the coordinator for another graph scan. The stranded-deck pass scans every non-deleted drawing and compares content with its merge base.

The network send generally uses `DataActor`, but the preparation before it does not. The ordinary `recordOperation()` starts a push for online mutations; periodic retries and resume also enter this work. A serialized/coalesced drain prevents simultaneous pushes but does not make each pass cheap. The connectivity check inside the actor branch occurs after those main-thread scans.

**Recommendation:** maintain incremental recovery candidates and move repair scanning to an owned background context. Bound each pass and run broad historical repair at controlled recovery boundaries. UI edits should enqueue quickly, then wake a single background drain. Preserve exact dependency and custody rules.

**Confidence:** verified source; a strong explanation for online-sensitive lag, not yet an A/B device result.

Sources: [SyncEngine.swift:1466](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Network/Sync/SyncEngine.swift:1466), [SiteVisitOrphanRecovery.swift:68](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Network/Sync/SiteVisitOrphanRecovery.swift:68), [stranded decks:1677](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Network/Sync/SyncEngine.swift:1677).

### 5. P1 — Photo batches block dismissal and are not durable until Done

`CameraBatchView` retains captured `UIImage`s in an array. Done clears that array and calls the host synchronously before dismissing. The visit host compresses every image to JPEG and writes every file synchronously on `@MainActor`, then runs the global queue transaction and checklist hydration. The host provides no per-image retry result; partial compression/write failures are skipped, and the camera still closes. Success haptics key off the input batch being nonempty rather than confirmed persistence.

Before Done, the camera has no file-backed draft. An app termination loses the batch; Cancel discards it without a confirmation. Many full-resolution images also increase memory pressure. The lead-photo path similarly resizes, encodes, and writes its batch on its main-actor service, so the performance concern extends beyond site visits.

**Recommendation:** stage original capture bytes durably as each shot arrives, generate bounded thumbnails away from the UI thread, and let Done attach already staged files in one transaction. Retain failed items for retry; report success only for saved items. Confirm discarding a nonempty batch. Do not reduce archival image quality merely to make thumbnails cheap.

**Confidence:** source-established blocking and loss paths; no measured per-photo latency.

Sources: [camera state:29](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/Components/Images/CameraBatchView.swift:29), [commitBatch:219](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/Components/Images/CameraBatchView.swift:219), [addPhotos:510](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift:510), [LeadImageService.swift:157](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Services/LeadImageService.swift:157).

### 6. P1 — Checklist-only visits can be deleted as empty on re-entry

`hasCapturedAnything` and `canComplete` correctly count answered checklist fields. However, the separate `visitHasContent()` used during re-entry checks only artifacts and selected identity fields. An unlinked visit containing checklist answers alone is classified as empty, and the automatic cleanup calls `hardDeleteVisit()`, which deletes its answers and associated unresolved queue work. Identity-only notes/search text also do not contribute to `filledFieldCount`.

**Recommendation:** share one explicit content policy across close, resume, completion, and cleanup. Any user-entered answer or draft content must prevent automatic deletion. Restrict automatic cleanup to provably pristine, never-synced drafts. Verify checklist-only, identity-note-only, interruption, and next-site cases.

Also review the unconditional 15-minute auto-resume rule: proximity in time does not establish that the operator is still at the same property. Preserve the current interrupted session by identity; make a deliberate new visit distinct from resuming a prior visit.

**Confidence:** source-established mismatch; not exercised against the phone's stored visits.

Sources: [resume decision:271](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift:271), [content test:1373](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift:1373), [hard delete:1409](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift:1409).

### 7. P2 — Online photo prefetch repeatedly walks the entire photo cache on main

`PhotoPrefetchService.runPrefetch` is main-actor isolated. It calls `StorageProfiler.currentUsageBytes()` at start and `wouldExceedBudget()` before each missing image. That helper walks three photo directories recursively. `nonisolated` on this synchronous helper permits off-main calls but does not move this caller's work off main. Consequently, downloading N photos can rescan the growing cache N times. Wi-Fi is the default eligibility; cellular requires opt-in.

**Recommendation:** calculate a background storage snapshot once, reserve/update bytes incrementally during the pass, and reconcile periodically. Move project prioritization and filesystem work off the UI thread; allow interaction/capture to take precedence. Keep the existing cache budget and protection for unsent files.

**Confidence:** verified source; applicable online when prefetch is enabled and eligible. It cannot explain all cellular/offline lag.

Sources: [PhotoPrefetchService.swift:204](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Utilities/PhotoPrefetchService.swift:204), [per-image budget:271](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Utilities/PhotoPrefetchService.swift:271), [StorageProfiler.swift:99](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Utilities/StorageProfiler.swift:99).

### 8. P2 — Returning from the deck editor still schedules expensive UI-thread work

The close button calls `saveForExit()` before dismissal: full drawing reconciliation/encoding, a context save, another full encoding for the queue identity, JSON payload preparation, and a second context save through the outbox. Thumbnail rendering runs in an inherited main-actor `Task` after `Task.yield()`. Yielding does not guarantee that dismissal has finished and does not change the executor. The deferred sync calls `triggerSync()`, which includes push and pull; after thumbnail upload, another save/enqueue/sync occurs.

The two-minute autosave now also creates a durable queue revision. That is valuable protection against loss, but `deferPush` only stops the immediate push call; another global drain may send that revision while the editor is still open. There is no editor-session exclusion in the scanned drain path.

**Recommendation:** retain immediate local durability while eliminating duplicate encoding, move thumbnail preparation to a safe background pipeline, and coalesce the post-exit push. Treat the new mid-session durability protection as a requirement; do not remove it to gain speed. Profile first-frame return to the visit, not just the close handler.

Sources: [close:610](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/DeckBuilder/Views/DeckBuilderView.swift:610), [save:3927](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/DeckBuilder/DeckBuilderViewModel.swift:3927), [exit:4193](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/DeckBuilder/DeckBuilderViewModel.swift:4193), [deferred sync:935](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/DeckBuilder/DeckBuilderViewModel.swift:935).

### 9. P2 — The sync-status display still rebuilds a large recovery inventory

The old two-second poll has been replaced correctly with a 500 ms debounced signal and a 60-second default-runloop fallback. However, every refresh still builds the full recovery inventory on main. Whenever a draft or visit operation exists, it fetches all active artifacts/answers and filters them in memory; names for pending entities can require additional whole-table loads. An active visit is precisely when the empty-state optimization stops helping. The app-level monitor remains mounted during capture.

**Recommendation:** compute one shared background snapshot scoped to relevant IDs, diff the displayed summary, and avoid rebuilding detailed recovery rows just to show a badge. Preserve the default-runloop scheduling and debounce already introduced.

Sources: [RecoveryInventory.swift:1260](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Network/Sync/RecoveryInventory.swift:1260), [indicator refresh:234](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/Components/Sync/SyncStatusIndicator.swift:234), [app monitor:1239](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/MainTabView.swift:1239).

### 10. P2 — Known local clients wait behind a network request in visit search

The identity panel hydrates the saved draft before networking, which is good. But `loadSearchSources()` awaits a full company opportunity fetch before it loads locally cached clients. Slow connectivity therefore delays even local suggestions. The request is neither a bounded search nor a shared cached snapshot, and the fallback depends on Opportunity rows that this flow describes as normally network-only.

**Recommendation:** populate local clients and an operator/company-scoped lead cache immediately, then refresh remotely without replacing what the operator is editing. Share the existing lead data source; use bounded search/pagination for large companies.

Sources: [identity search:1785](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureView.swift:1785), [OpportunityRepository.swift:73](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Network/Supabase/Repositories/OpportunityRepository.swift:73).

### 11. P2 — Opening a visit or deck performs avoidable broad fetches

Visit entry fetches all visits, evaluates the content test twice per unlinked visit, and performs child fetches inside recency sorting. Opening a deck from a visit fetches every `DeckDesign` before choosing the relevant one. These operations precede presenting the useful screen.

**Recommendation:** fetch by company/owner/open status and exact design ID; build candidate content/recency metadata once. Reuse the owner-scoped deck feed pattern already used elsewhere. Keep resume identity and deduplication correct.

Sources: [entry:271](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift:271), [recency:1395](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift:1395), [deck lookup:976](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureView.swift:976).

### 12. P2 — Packet thumbnails load full images and lack an uncached remote fallback

The expanded packet is an eager `VStack`. Each 54-point thumbnail synchronously reads a composited/full image from disk inside its view task. It does not request a downsampled display image. For remote URLs, `ImageFileManager.loadImage()` only consults local caches; this thumbnail has no network loader or cache-arrival observer. A valid remote artifact can therefore show a placeholder when its image is not cached, even though opening the full photo uses a different loader.

**Recommendation:** use one bounded async thumbnail loader with size-specific decode, a lazy packet list, local-original/markup precedence, and a real remote fallback. Cache arrivals should update the tile without requiring reopening the visit.

Sources: [packet list:657](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureView.swift:657), [thumbnail:2233](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureView.swift:2233), [ImageFileManager.swift:240](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Utilities/ImageFileManager.swift:240).

### 13. P2 — Save completion and required-field meaning need clearer behavior

After a visit is durably committed, `saveVisit(movingLeadTo:)` still awaits a remote stage change before dismissing the saving UI. Poor connectivity can make a successful local save feel stuck. Failure is correctly distinguished with a saved-but-stage-not-updated result, but there is no durable stage-move queue in this method.

Separately, fields labeled required are listed in review, yet Save remains enabled whenever any capture or answered checklist evidence exists. This is a product inconsistency to resolve: saving an incomplete draft is sensible; declaring a required checklist complete needs an explicit rule.

**Recommendation:** acknowledge local save immediately and track stage delivery separately with a safe retry mechanism. Distinguish preserving incomplete work from finishing a visit; do not silently discard answers or imply required checks were satisfied.

Sources: [stage change:820](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift:820), [saving presentation:2682](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureView.swift:2682), [completion gate:181](/Users/jacksonsweet/Projects/OPS/ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift:181).

## Existing improvements to preserve

- Supabase Swift is pinned at 2.54.1, including the previous Realtime cancellation fix. The old lock deadlock is not assumed to be recurring.
- Calendar snapshots and immediate retained-tab selection are present. Hidden-tab activation gates exist in the sampled roots.
- Deck geometry caching, gesture coalescing, and a 3D revision gate are present. The 3D renderer does not rebuild for every unrelated SwiftUI update. It still builds a complete scene for a changed revision and resets the camera; measure that separately for complex drawings.
- Visit Realtime merges have scoped row lookup and no-op diff guards. Do not blame every echo for a database write. One remaining inefficiency is that `DataActor` discards the unchanged report and still publishes a site-visit change signal.
- Downloaded-photo decode/store already has a nonisolated async path. The remaining cache-budget scans and capture writes are distinct paths.
- Durable local visit commits and deck-save failure reporting are valuable. Performance repairs must retain them.

## Verification needed to close the performance issue

Use a known source revision and optimized build on the iPhone 16 Pro and a supported older phone. Run the same scripted sequence: new visit → checklist typing → ten photos → note/dictation → create/edit a representative deck → return to visit → save → reopen. Repeat with Wi-Fi, cellular, high latency/loss, offline, and reconnect with queued work. Include a long-lived store and a stopped/parked queue, not just a fresh empty install.

Record Instruments Time Profiler, SwiftUI updates, hangs/hitches, allocations, and signposted timings around each persistence boundary. Add lightweight production hang/MetricKit collection and capture-specific spans; the current tree has a schedule-commit signposter and failure telemetry, but the search found no general MetricKit subscriber or end-to-end site-visit latency metrics. Existing deck performance tests mostly verify work counts/caching rather than frame time.

Suggested engineering acceptance targets, not measured results: visible tap acknowledgement within 100 ms; no storage/image work monopolizing main during typing or gestures; no visible hitch when a network response arrives; stable memory after repeated capture/editor cycles; every accepted photo/answer survives interruption; no unrelated stopped work is revived; an existing installed store opens after upgrade.

Apple's guidance specifically distinguishes asynchronous work from work executed off the main actor, and recommends profiling SwiftUI update cost and its causes. References: [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness), [Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/).

## Verified local repair closeout

The thirteen ranked findings are dispositioned in REPAIR-RESULTS.md and REPAIR-ACCEPTANCE.md. All final focused checks passed; the actual copied V25 store upgraded toV26 and independently reopened while preserving checked content/custody across16groups. Those initial checks used a disposable copy. Subsequent installation and the reviewed server update were explicitly approved and completed. The real phone upgrade retained the original data, and an optimized startup trace exposed additional work on the UI thread. Final equivalent-build workflow speed remains unmeasured; current private custody copies are retained only while that diagnostic work remains active.


## Physical runtime follow-up — September 6–7, 2026

**P1 — The database worker still ran on the UI thread.** The known optimized phone binary recorded five main-thread stalls of 253–384 ms during startup under nominal thermal conditions. Symbolicated samples include queue processing, claims and media bookkeeping in `DataActor`. Synthetic probes reproduced the mechanism: detached construction alone still ran actor transactions on main. The accepted local repair uses an explicit serial executor and awaited configured startup; the production factory, concurrent real transactions and persistence/reopen checkpoint passed. The repair also closes stale session callbacks before logout/store replacement. See [executor mechanism evidence](executor-mechanism-summary.json) and [physical startup evidence](physical-startup-profile-summary.json).

**P2 — Passive review counts repeatedly enumerated task/project models.** The physical trace also includes review threshold evaluation and task/project reads from the main UI path. The repair shares a current-company scalar snapshot across the FAB, Job Board header and review notifications. Its background actor reads tasks and projects once per refresh; loading, failed or retired reads do not become false zero counts. Company/account/permissions/time changes invalidate the cache. A persisted warm-context read/edit/read check and 41 focused tests passed before the final combined lifetime check. Review sheets still resolve their actual rows on entry.

**Continuity — Interrupted work must belong to the original session.** Review of the real background transition found account/context replacement hazards in inbound sync, image callbacks and incremental Spotlight avatar loading. The repair revokes old work, preserves durable photo obligations and checks validity after suspension before accessing old models. A cancelled current sync releases its busy flag without clearing a replacement cycle. These are concrete lifecycle corrections associated with moving the measured work off main; no server or product flow redesign is included.

The later warm recording ran a different Debug binary and is excluded from comparisons. Neither these samples nor simulator tests establish the percentage improvement during the user's visit/photo/note/deck sequence. See [current repair results](REPAIR-RESULTS.md) for final verification status.
