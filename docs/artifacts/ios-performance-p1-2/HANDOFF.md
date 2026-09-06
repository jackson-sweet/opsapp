# IOS PERFORMANCE - P1-2

**READY FOR BUILD BATON.** Owned code is committed and passes lightweight source checks. No worker build baton received. No xcodebuild, test execution, package resolution, simulator/device action, performance benchmark, real pending replay, deployment or release occurred in this worker.

## Exact integration sequence

Baseline: `94543f955ca8a2ccee4cc148c24c6d33de92cccc`. Apply these local commits in order; the first two alone are superseded by the isolation amendment and are not the final implementation.

1. `774a3778` — scoped changed-entity enqueue, rollback rematerialization, explicit legacy repair, guarded stage outbox/transport and fixtures.
2. `c37d4d91` — capture continuity, staged-camera/async-thumbnail adapters, local suggestions, frozen stage review decisions and fixtures.
3. `ca26d189` — finalized `already_satisfied` receipt, no-transition validation and replay tests.
4. `344c3c7b` — dedicated capture contexts; isolated queue-binding, dimensioned-photo and pending-work deletion adapters; unsaved-other-visit tests; compiler predicate/actor fixes.
5. `835f0a1a` — thumbnail refresh for wildcard cache invalidation and fallback-source changes.
6. `fad0e453` — actual entry/template/deck-host isolation, complete Opportunity snapshots, full queue cache-entry isolation and corresponding fixtures.
7. `9f6c5cdb` — bounded/cancellable search-fixture registration, persisted media readback, and realistic isolated queue-delivery fixture.
8. `93eac1ec` — first delivery is marked for newly captured blank/scan deck rows before a visit references them.

P1-3 media APIs through `c528e1b0` are implemented prerequisites. These visit adapters do not depend on P1-3's remaining non-visit camera adapters. New files use existing synchronized Xcode groups; there are no persistent model/schema or project-file changes. P1-5's finalized SQL contract includes `already_satisfied`; production migration is not applied and remains a separate gate.

## Final ownership and transaction contract

- Each `SiteVisitCaptureViewModel` retains its own ModelContext for its lifetime. `isolatedSession()` creates it from the same container with autosave disabled and preserves injected encoder/validator closures. No caller-context pending values are copied, saved or rolled back.
- The three other reachable shared-context mutation callers are migrated: `ClientLeadAutocreateQueue.bindSiteVisitDrafts`, `SiteVisitDimensionedCaptureStore.persist`, and `PendingWorkView.deleteVisitPacket`. They fetch/insert their records in independently owned contexts. Dimensioned capture resolves its persisted artifact ID back in the caller's context, without inserting a registered foreign model. The console, creation picker and DeckBuilder inherit the VM-owned context through the real root view environment. The typed deck-host save keeps failed drawings for the next DECK tap, reports the failure, and opens the editor only after the row and visit link persist.
- Lead inputs from another context are detached display snapshots using the complete canonical Opportunity.apply method, including nonzero assignmentVersion, summary, images and coordinates. The queue's preceding applyLocalDelivery cache insert also has its own context, so no pre-binding shared save remains. Queue-delivered lead binding reads a fresh context and transfers scalar identity through the owned capture transaction; it does not move registered models or replace active text buffers across contexts.
- The compatible `commit(completing:stageCommand:revisedMediaArtifactIds:mutation:)` wrapper remains. A caller without explicit context ownership must begin with a clean context; pre-existing pending changes cause rejection before its mutation closure runs. All reachable shared production mutation callers now use owned contexts, so unrelated WIP is not a routine-save blocker.
- Ordinary commits inspect only their owned context's changed/inserted visit entities and fetch unresolved operations for those IDs plus exact parent IDs. Completed history is not materialized. A per-transaction entity/type/media index and ID index handle coalescing/dependencies. The empty SyncOperation-table workaround uses a predicate-free count and pending insertion list.
- Missing never-synced parents are queued before children. Unchanged parent/media owners retain parked/declined decisions; changed identity/answer/note/inclusion guards avoid no-op saves. Metadata edits do not revive stopped media; explicit new markup does.
- Completion fetches only the exact visit graph's unresolved tail and inserts a distinct command. Stage commands are excluded from CRUD coalescing and completion's live barrier. Rollback affects only the owned context and rematerializes held row/operation references.
- `recoverOrphanedWrites(siteVisitIds: Set<String>? = nil)` stays source compatible for P1-4. Candidate/company/UUID scope is supported and existing pending/inProgress/failed/parked/declined owners are preserved. Ordinary save never invokes repair. P1-4 owns the background recovery context and scheduling.

- Capture entry's ensureSiteVisitTypesSeeded uses an isolated SiteVisitTypeSeedStore. Templates and queue entries save together, permissions/stopped owners are preserved, and a no-op seed does not save any context. The actual opening path never saves the controller's unrelated pending edits.

## Product behavior

- One content policy includes artifacts, answered checklists, partial identity fields/links, and visit notes/measurements/address/photos. Automatic deletion of apparently empty visits is removed because a camera journal can own unattached originals. Explicit pending-work packet deletion remains available.
- New-visit intent starts fresh; exact resume selects the requested eligible visit, with no age heuristic. Prior content is offered for deliberate resume. Exact account camera-manifest discovery includes photo-only interrupted visits without switching the active new visit.
- Entry fetches company/creator-or-assignee/open candidates. Child content and recency are grouped once across candidate IDs. Deck selection fetches explicit design IDs or the active lead's eligible designs.
- Checklist text debounces for 350 ms and flushes at focus/navigation/review/close/background boundaries. Failed persistence retains buffers. Identity values are flushed before navigation and unchanged content is guarded.
- Incomplete work saves as a draft. Completing a visit requires captured evidence and all applicable required answers. Local save acknowledges the durable transaction immediately; stage delivery has its own pending/review feedback.
- Local clients appear before network work. The existing company/operator DaySheet cache supplies lead suggestions. Remote search requests at most 50 active nonterminal company leads, with escaped/quoted search values and stale-request/account guards. Network completion never overwrites the active identity form. Live opportunity columns/policies were inspected read-only before the repository addition.

## Media and stage contracts

Camera uses `CameraBatchView(owner:onStagedUpload:)`. Stable staged item IDs are artifact IDs. The exact company/user/visit is checked before artifact/outbox save. Callback success is returned only after commit; the camera then acknowledges. Reopen recovery acknowledges only after that same idempotent save succeeds. Failure retains journal/original custody. Packet rows are lazy; thumbnails use display-size async decoding with local/markup precedence, remote fallback and cache-arrival refresh. Markup renders get separate local URLs, preserving the previous file on transaction failure; an explicit repeated-URL save is still a media revision.

Stage review freezes a `SiteVisitStageDecision` containing the same validated server snapshot, displayed current/default stage and chosen target. Fresh server `quoted` plus stale local `new_lead` displays/defaults to `quoted`. An explicit target equal to a stale local stage still queues against the snapshot. Late snapshot arrival cannot authorize or rebase a decision already made without that token.

The existing Codable outbox payload holds the stable command UUID, original actor/company/visit/lead, selected target and original snapshot. Completion and its stage dependency commit atomically. Missing/unsupported/unmovable snapshots store parked review custody while preserving the visit. Delivery uses only `apply_site_visit_stage_command` and all eight final arguments; no legacy mover or token refresh fallback. Current siteVisit routing in DataActor/OutboundProcessor reaches this lane without a new entity switch.

`applied` and `already_applied` require a matching transition receipt. `already_satisfied` requires matching lead/target, null reason and null transition, and settles without claiming a move. All success/replay outcomes settle only and never merge historical stage into a newer local lead. Conflict is permanent review; not-ready and SQL 55P03/40P01/40001 retry the unchanged command. Missing capability/permission/invalid request fails closed. Prior immutable conflicts remain conflicts.

## Verification performed and authored

`static-verification.json` records all 27 changed Swift files passing frontend syntax parsing, preserved CRLF boundaries, and zero new literal color/font/spacing/radius violations in changed visit UI. `git diff --check` passes. These are source checks only. The PM's earlier combined compile found a complex predicate and actor-conversion warning; `344c3c7b` splits the predicate and uses the nonisolated classifier. Those fixes have not yet been typechecked by this worker.

Authored synthetic tests cover:

- 30 visits, 149 artifacts, 283 answers, 25 identity drafts and 2,625 completed operations plus stopped media owners: one target edit asserts one changed/encoded entity and one loaded operation. No elapsed-time claim.
- Isolated coordinator and actual VM paths: another visit's pending note, answer and newly inserted draft keep their memory values while its prior stored values remain unchanged on both success and failure. A later deliberate save of B must not overwrite A.
- 1,000 unsaved unrelated drafts: one owned edit produces one boundary snapshot and no persisted unrelated drafts.
- Actual entry seed success/failure/no-op with B pending, real deck-host save failure/retry with B pending, full queue arrival cache+binding isolation, and complete initial/reassigned lead snapshots.
- Rollback rematerialization, exact orphan candidates, metadata versus new markup retry, draft versus completion, explicit new/resume, staged-photo deduplication/foreign-owner rejection/failure replay, local suggestions under held networking, frozen late-stage snapshots, durable stage dependency, offline parked custody and settle-only historical receipts.

All fixtures/photo URLs are synthetic. No XCTest has run in this worker, and there is no visual, device-frame-time or customer-live proof. P1-3 owns filesystem/original/thumbnail failure tests; P1-4 owns recovery scheduling and deck/sync tests. PM owns the Bible and final combined proof.

## Parent combined run and current rerun status

Parent core03 ran an earlier combined snapshot: 292 tests, 287 passed, 5 failed, zero skipped. Two lead tests trapped in SyncOperation backing data through OutboundProcessor; P1-4 owns the sync-driver/lifetime repair, and this worker did not alter the driver or hide the crashes with fixture teardown. Exact retained diagnostics are in the integration checkout under docs/artifacts/ios-performance-combined/core03-relevant-diagnostics/.

The three assertion failures were both search fixtures and the repeated-URL markup test. Commit 9f6c5cdb replaces the 100-yield polling gate with a MainActor request-registration expectation, a five-second bound and cancellation cleanup; the markup assertion reads the same operation ID from a fresh context and still requires pending status/retryCount zero. The queue-delivery fixture now writes its binding through a separate context, matching production. These amendments, plus the latest entry/deck/snapshot tests, await the focused combined rerun. Syntax parsing passes for the final 27 Swift files; runtime completion is not yet claimed.

## Exact focused commands — PM only with baton

Run from the combined integration checkout with its existing ignored Secrets.xcconfig and approved locked `.spm-local` packages. Reuse the single PM-owned DerivedData path after the current process ends. Do not set private phone-fixture environment variables or replay real pending work. Use a fresh result suffix if the bundle already exists.

```sh
xcodebuild test -project OPS.xcodeproj -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath /private/tmp/ops-ios-performance-integration-deriveddata \
  -clonedSourcePackagesDirPath .spm-local \
  -resultBundlePath docs/artifacts/ios-performance-p1-2/visit-tests-01.xcresult \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:OPSTests/SiteVisitPersistenceCoordinatorTests \
  -only-testing:OPSTests/SiteVisitContinuityTests \
  -only-testing:OPSTests/SiteVisitSearchSourceTests \
  -only-testing:OPSTests/SiteVisitTypeSeedStoreTests \
  -only-testing:OPSTests/SiteVisitStageDeliveryTests \
  -only-testing:OPSTests/SiteVisitLeadCaptureTests \
  -only-testing:OPSTests/SiteVisitCapturePacketTests \
  -only-testing:OPSTests/SiteVisitActivityPostTests \
  -only-testing:OPSTests/SiteVisitStageDefaultTests \
  -only-testing:OPSTests/ClientLeadAutocreateParentGateTests
```

The device-target compile is shared with other workers, not an extra concurrent build:

```sh
xcodebuild build -project OPS.xcodeproj -scheme OPS \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/ops-ios-performance-integration-deriveddata \
  -clonedSourcePackagesDirPath .spm-local \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO
```

Required UI proof in the combined app: new/resume, required-checklist partial save, delayed-network local suggestions, camera interruption/reopen, markup transaction failure, remote thumbnail arrival and completion/stage feedback. Phone installation, production migration/canary and iOS release still require their separate approval gates.
