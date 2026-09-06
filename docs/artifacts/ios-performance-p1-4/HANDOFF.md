# IOS PERFORMANCE - P1-4

Status: **READY FOR BUILD BATON**. Implementation and synthetic regression cases are locally committed. No build baton was granted to this worker. No compilation/typecheck, XCTest execution, package resolution, simulator work, device work, push, deployment, or release occurred here.

Worktree: `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-p1-4`
Branch: `codex/ios-performance-p1-4`
Audited baseline: `94543f955ca8a2ccee4cc148c24c6d33de92cccc`

## Source commits and integration dependencies

1. `047a719798a4aa6f2e6e08a586fed2cdb549e3b6` — separate capture durability from recovery and upload work.
2. `193f7464b1cd076df9a5d92f96f0541c52543b09` — load compact recovery status off the main actor, including authenticated vault headers and LEAD STAGE recovery classification.

Integrate both with P1-2 before compiling. This slice deliberately uses P1-2's approved APIs without editing or copying its files:

- `SiteVisitPersistenceCoordinator.recoverOrphanedWrites(siteVisitIds: Set<String>? = nil) throws -> CommitResult`.
- `SiteVisitSyncOperation.stageOperationType == "siteVisitStageMove"`.
- `SiteVisitSyncOperation.Payload.stageCommand: SiteVisitStageCommand?`, its `stageCommand:` initializer parameter, `SiteVisitStageSnapshot`, and `SiteVisitStageCommand.canDeliver`/original identity and snapshot fields.
- Both outbound drivers continue using P1-2's shared `SiteVisitOutboundSync.executeIfHandled` transport routing. No second stage dispatcher was added.

P1-1's conservative unknown-dirty-merge-base logic remains untouched. The new reader uses `DeckDesign.hasUnsyncedDrawing`; thumbnail completion never saves the older view model's drawing. ImageSyncManager and P1-3 media acknowledgements remain untouched. No dependency on P1-3's unfinished non-visit camera adapters. No persistent-model or schema changes.

## Resulting behavior

### Ordinary writes and historical repair

- `SyncEngine.pushPending()` only drains queued uploads and refreshes their completion state. The prior broad task/deck/visit recovery pipeline no longer runs at every online edit.
- `requestRecovery()` coalesces historical discovery at configure/launch, company reconfiguration, connectivity restoration, manual `fullSync()`, and the existing 180-second timer. The timer requests recovery even when the pending count is zero. Failed-operation retry-budget resets remain limited to their existing launch/reconnect policy, not every timer tick.
- `SyncRecoveryReader.discover` creates its own read-only ModelContext on a utility task. It returns candidate IDs and custody flags, never registered models. The main context revalidates exact scopes, in batches of eight IDs with yields between batches, serialized with outbound claims. Cancellation, container generation, actor and company identity are checked across the boundary.
- Scoped orphan recovery retains stopped ownership, completion evidence, quarantine, and parent-first dependency behavior. Original legacy identifier spellings are retained through predicates. Completed queue history is retained; discovery reads unresolved statuses, while the orphan evidence path additionally reads completed completion commands.
- Already requested recovery finishes before a subsequent ordinary upload. The coordinator keeps upload and recovery requests in separate coalesced slots; a recovery callback cannot replace a queued upload followup.
- An unchanged site-visit realtime merge no longer publishes a redundant UI invalidation. Inserted/updated records still publish.

### Deck durability and editor exit

- Autosave and inactive/background flushing still persist the drawing and a durable outbox revision. `DeckEditingSessionRegistry` holds only that design's outbound sends while the editor is present; both drivers check before eligibility and immediately before claim. Multiple editor sessions have independent tokens. Process restart naturally releases all in-memory holds.
- `resumeEditingSession()` reacquires the token on appearance. `flushBeforeExit()` releases it on actual disappearance and wakes the upload-only drain with a coalesced 300ms delay. Inactivity retains the hold. Close stays open if the local save failed.
- Exit queue identity reuses `deckDesign.drawingDataJSON` already encoded by `save()` rather than encoding the drawing a second time.
- Optional thumbnail work waits for actual disappearance. `DeckThumbnailWorker` decodes that immutable JSON within its own actor, giving it independent reference-backed drawing caches, then renders and compresses off main. Only image bytes and copied identifiers go through the existing presigned upload service.
- After the asynchronous upload, thumbnail metadata is accepted only when the persisted drawing still matches and no editor has reopened it. It queues a thumbnail-only update; it never calls `save()` on stale drawing state. A thumbnail failure does not undo durable geometry.

### Compact status and stage custody

- `RecoveryAttentionReader` computes an equatable `{ attentionCount, anyParked }` summary using a fresh background ModelContext. It reads active operations, pending/failed local photos, relevant drafts, and only deck artifacts needed for grouping. Healthy status returns before reading capture/drawing tables.
- The pill no longer builds the detailed RecoveryInventory: no checklist-answer scan, manifests, entity name lookup, orphan drawing scan, delivery-history scan, member construction, or row sorting. Full detail remains on demand.
- `SyncStatusIndicatorModel` coalesces requests, rejects obsolete identity/container snapshots, publishes only changed summaries, and retains the prior same-account summary on read failures. Existing 500ms debounce and 60-second default-mode fallback remain unchanged.
- `SiteVisitRecoveryVault.quarantinedVisitIds(userId:companyId:) async throws -> Set<String>` authenticates/decrypts archive headers off main, scopes to exact user/company, and does not load media or full archive models. Proven missing directory means empty; permission, key, corrupt-data, or decryption failures throw.
- Detailed packets classify stage commands separately as LEAD STAGE. Automatic recovery requires their original supported snapshot and exact actor/company/visit binding. Parked/declined/quarantined commands and missing-snapshot envelopes cannot be automatically resumed. Deleted-parent restoration keeps old stage commands parked for deliberate review, preserving payload, retry evidence, and receipt fields. Generic legacy cleanup cannot delete stage-command custody. No historical stage receipt is merged into an opportunity here.

## Verification performed

`STATIC-CHECKS.txt` records a successful `xcrun swiftc -frontend -parse` of all 29 changed Swift files, and a successful diff whitespace check with `core.whitespace=cr-at-eol` to preserve the repository's existing mixed CRLF source. Parse is syntax validation only; it cannot establish SwiftData predicate macro validity, actor/type compatibility, linking, or test outcomes.

All new fixture content is synthetic. The queue fixture mirrors the sanitized phone shape (2,636 operations; 2,625 completed and 11 unresolved) without copying any customer records.

## Parent build/test commands — NOT EXECUTED HERE

Run only under the parent's serial build baton, after integrating P1-1/P1-2 and these source commits. The destination and build cache below come from the parent PM ledger; use the same integration stream and never start a competing writer. The selector set exercises this slice plus directly adjacent custody and coalescing contracts.

```bash
cd /Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-integration
xcodebuild -project OPS.xcodeproj -scheme OPS \
  -destination 'platform=iOS Simulator,id=1C6A8F09-A337-41F0-AFDD-81C4F3EDFB8A' \
  -derivedDataPath /private/tmp/ops-ios-performance-integration-deriveddata \
  -clonedSourcePackagesDirPath .spm-local \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  -parallel-testing-enabled NO \
  -only-testing:OPSTests/DeckEditingSessionTests \
  -only-testing:OPSTests/DeckExitResponsivenessTests \
  -only-testing:OPSTests/DeckBuilderRegressionTests \
  -only-testing:OPSTests/RecoveryAttentionSummaryTests \
  -only-testing:OPSTests/RecoveryStoreQueriesTests \
  -only-testing:OPSTests/RecoveryVaultHeaderTests \
  -only-testing:OPSTests/SyncRecoverySchedulingTests \
  -only-testing:OPSTests/SiteVisitCommandRecoveryTests \
  -only-testing:OPSTests/SiteVisitStageDeliveryTests \
  -only-testing:OPSTests/SiteVisitOrphanRecoveryTests \
  -only-testing:OPSTests/SiteVisitInboundSyncTests \
  -only-testing:OPSTests/SiteVisitRecoveryVaultTests \
  -only-testing:OPSTests/RecoveryInventoryTests \
  -only-testing:OPSTests/RecoveryInventoryCaptureScanTests \
  -only-testing:OPSTests/SiteVisitDeliveredCaptureRecoveryTests \
  -only-testing:OPSTests/OutboundRetryPolicyTests \
  -only-testing:OPSTests/ClientDeletionSyncRegressionTests \
  test
```

Key authored cases:

- `DeckExitResponsivenessTests/testExitEncodesOnceAndInterruptionKeepsDurableRevisionHeld`
- `DeckExitResponsivenessTests/testThumbnailRendersOffMainAndCannotOverwriteReopenedDrawing`
- `DeckEditingSessionTests/testBothOutboundDriversLeaveHeldRevisionUnclaimed`
- `RecoveryStoreQueriesTests/testBackgroundReadReturnsLiveWorkWithoutMaterializingCompletedHistory`
- `RecoveryAttentionSummaryTests/testHealthyCompactStatusDoesNotRequireCaptureOrDrawingTables`
- `RecoveryAttentionSummaryTests/testCompactSummaryMatchesDetailedInventoryForMixedAndBundledWork` (36 status combinations)
- `RecoveryAttentionSummaryTests/testStageReviewRemainsOnePacketAndHasItsOwnDetailedMember`
- `SiteVisitCommandRecoveryTests` (original snapshot/actor/company, missing snapshot/legacy envelope, and stopped custody)
- `SiteVisitRecoveryVaultTests/test_activeServerSyncedParentReleasesDeletedParentCustodyWithoutDeletingWork` now also asserts stage parking and unchanged original payload/attempt evidence.

## Instrumentation and limits

Parent combined compile follow-up: the first compilation stopped before tests because the worker referenced `DeckRendererError` without its enclosing `DeckRenderer` namespace. The bounded follow-up qualifies the existing type as `DeckRenderer.DeckRendererError.compressionFailed`; no new error contract or upload behavior is introduced. The renderer error declaration, drawing JSON decoder, and presigned `uploadImageData(_:filename:folder:) async throws -> String` signature were inspected directly. This worker still has no build baton; the parent must rerun combined verification. Source parse cannot prove symbol resolution.

`CapturePerformanceTrace.signposter` uses subsystem `com.ops.capture`, category `Persistence`, with `DeckLocalSave`, `SyncRecoveryDiscovery`, and `RecoveryAttentionRead` intervals. They record no content or identity. Instruments can show main-thread saves separately from the two utility reads and `DeckThumbnailWorker` execution.

Remaining proof requirements for the parent: combined compilation/typecheck and focused tests, then separately authorized phone behavior/timing on real capture/edit/exit/navigation. No latency or customer-live improvement is claimed by this handoff.

The explicit recovery path still performs rare protected-vault/parked-media/parked-note settlement and one-time authorship/link repairs on the owning main context. Candidate flags keep these out of ordinary edit upload wakes; this is not a claim that every legacy repair helper is background-only. Existing outbound dependency evaluation may still consult completed queue rows. Already in-flight uploads are not cancelled when an editor opens; existing merge/ack guards continue protecting newer drawings. Optional thumbnails remain best effort, and no independent durable thumbnail retry mechanism was added.

## Bible delta for parent integration

Update the existing deck persistence and recovery sections when merging the initiative:

> Embedded deck autosave and interruption boundaries persist both local drawing data and its durable outbox revision. A process-local, per-editor hold defers that design's uploads until actual editor disappearance; crash/restart leaves durable work eligible for ordinary recovery. Exit reuses the saved JSON. Thumbnail rendering decodes its own drawing/cache state on a serial worker and can update metadata only while the captured revision remains current and the editor stays closed. Historical task/deck/site-visit discovery runs at controlled launch/reconnect/manual/timer boundaries with background reads and scoped mutation batches. Ordinary online edits drain their outbox directly. The global sync pill reads a compact asynchronous attention summary; detailed RecoveryInventory stays on demand. Stage commands keep their original snapshot and identity through retry/recovery and remain parked after deleted-parent custody restoration until deliberately reviewed.

No shared Bible or PM ledger was edited by this worker. Existing visual tokens, notification layout, and refresh timing are preserved. No new paid service, subscription, or upload route was introduced.

## Combined core03 lifecycle crash follow-up

PM reported 287 passing and five failing tests in the combined core03 run. Two failures crashed in `SyncOperation.operationType.getter` from the legacy driver's post-request catch block (`OutboundProcessor.executeOperation`, pre-fix line 518), after a preceding lead-capture fixture had queued a real asynchronous client drain and then released its container. Evidence was read from the integration tree's `docs/artifacts/ios-performance-combined/core03-relevant-diagnostics/test-stdout.txt`, `OPS-2026-09-06-135158.ips`, and `OPS-2026-09-06-135214.ips`. Both crash reports identify a model destroyed by `ModelContext.reset`. Fixture teardown releases its containers without waiting for the background drain. This supports the container-lifetime diagnosis; it is not a claim that the new regression has passed.

The bounded repair retains both the container and context throughout each legacy drain, execution, and reconciliation. Both drivers capture immutable operation identifiers before suspension, check task cancellation, account identity, and owning-context registration before post-request model reads/writes, and release the shared claim using the captured UUID. `SyncEngine` invalidates the old processor and actor session synchronously before logout/reconfiguration. The actor's locked scalar generation prevents an invalidate/resume cycle from authorizing an old callback. Interrupted callbacks leave the persisted claim in progress for the existing recovery path without charging retry budget or acknowledging delivery.

The validity predicate is also passed into P1-2's typed site-visit executor. **Integrate P1-2 `bad6ad3a` before compiling this follow-up** (P1-2's preceding fixture commit is `26e9936d`). Its verified source signature is `executeIfHandled(operation:context:activeCompanyId:isCurrent:isolation:)`, with `isCurrent: () -> Bool = { true }` and `isolation: isolated (any Actor)? = #isolation`. That companion change preserves the calling actor and checks the same validity at internal CRUD/media suspension points; those files were not copied or edited here. Repository routing, merge-base advancement, retry classification, and newer-revision acknowledgement rules remain in place.

Seven synthetic, gated tests were authored in `OutboundLifecycleTests`: container-owner release during a failing request; invalidation during either success or failure; user/company replacement; task cancellation; invalidation before a synthetic in-memory reset; actor invalidation/resume during either success or failure; and successful completion of a current actor session. The latter also covers the normal claim rollback/refetch registration path. Injected repository closures prevent these tests from making real network writes. The synthetic reset exists only in test source and has not been executed by this worker.

Source-only verification for this follow-up: frontend parse of the five changed/new Swift files and CRLF-aware whitespace validation both exited 0. No compilation, typecheck, XCTest, package resolution, simulator, or device commands were run. PM should use the existing serial integration command and include:

```text
-only-testing:OPSTests/OutboundLifecycleTests
-only-testing:OPSTests/SiteVisitLeadCaptureTests
-only-testing:OPSTests/OutboundProcessorTests
-only-testing:OPSTests/OutboundRetryPolicyTests
-only-testing:OPSTests/DeckEditingSessionTests
-only-testing:OPSTests/ProjectNoteMentionEditTests
-only-testing:OPSTests/SyncCrossEntityDependencyTests
```

The two originally crashing selectors are `SiteVisitLeadCaptureTests/test_createLead_queuesImmediatelyWhenOfflineInsteadOfBurningTheWait` and `SiteVisitLeadCaptureTests/test_queueDeliveredLeadBindsTheOpenVisit`; run the full class because the observed callback began in an earlier fixture. The other three core03 failures remain with P1-2. Parent Bible addition: outbound callbacks retain their storage owner and reject cancelled, replaced-account, unregistered-model, or obsolete-session continuations before stored-state acknowledgement; interrupted claims remain recoverable.
