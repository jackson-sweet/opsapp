# IOS PERFORMANCE - P1-3

Status: READY FOR BUILD BATON. No build baton was used by this worker.
Worktree: `/Users/jacksonsweet/Projects/OPS/.worktrees/ios-performance-p1-3`.
Baseline: `94543f955ca8a2ccee4cc148c24c6d33de92cccc`.

## Commit order

Already handed off/integrated by PM:

1. `e2a71a7e` — bounded cache accounting and thumbnail work.
2. `ce8ffb72` — durable camera journal, capture/retry gating and synthetic tests.
3. `3f6e14f2` — background lead staging and durable upload receipts.
4. `c528e1b0` — exact-account pending capture context index.
5. `b4e2418e` — background-safe budget snapshots, Sendable fetch default and approved PhotoProcessor accounting hooks. PM integrated as `163cf001`.

Final source amendments, in order:

6. `7690fb0c` — unreadable journals throw, delivery-retirement receipts, retained draft metadata.
7. `ce1def1b` — all five assigned production camera adapters, project photo draft store, canonical delivery/local-save gating, destination tests.
8. `ce233114` — account revalidation across delivery awaits and inside retirement actor; partial retained-form recovery with failed-item metadata and tests.

## Owned scope

Original: CameraBatchView, ImageFileManager, StorageProfiler, PhotoPrefetchService, LeadImageService, narrow PhotoDownloadManager adapter, new capture/cache/thumbnail/lead helpers and media tests.

PM expansion: LeadDetailView, DaySheetLeadCard, ProjectDetailsView, ProjectActionBar, ProjectFormSheet, necessary destination/draft helpers; ImageSyncManager delivery cleanup hook; three approved PhotoProcessor ledger write/remove hooks. No SiteVisitCaptureView/Model, SyncEngine, DataActor, frozen schema, shared Bible or PM ledger edits.

P1-2 owns the visit camera/gallery integration. This branch retains the old visit caller because it must not overwrite P1-2's file. All five non-visit production hosts owned here use typed camera receipts. The legacy UIImage callback remains source-compatible; it cannot prove a durable destination receipt and retains its journal conservatively. After P1-2 integration no production call should use that initializer.

## Integration contracts

- `StagedCaptureOwner(companyID:userID:contextID:)`: Codable/Hashable/Sendable, lowercase-normalized. Visit context is the exact visit ID. Lead/project contexts are `lead:<id>`, `project:<id>`; creation photos use `project-draft:<reserved-project-id>`.
- `CameraBatchView(owner:onStagedUpload:)`: async Bool callback. Return true only after durable destination custody. Camera acknowledges after true; failed save/ack replays the same item IDs.
- `StagedCaptureBatch`: stable `id`, exact `owner`, `[StagedCaptureItem]`.
- `StagedCaptureItem`: stable `id`, normalized JPEG `localURL`, unchanged source-byte `originalLocalURL`, `capturedAt`, oriented `pixelWidth/pixelHeight`.
- `DurableCaptureStore.recover(owner:)`: prepared unacknowledged siblings for the exact owner. Invalid image siblings remain in `failedItems(owner:)`. Both direct APIs now throw for an unreadable/incompatible manifest; unknown custody never looks empty. Successful files remain untouched when another manifest is corrupt.
- `pendingContextIDs(companyID:userID:)`: one account-scoped manifest scan; includes failed captures with an original; throws unreadable-journal errors.
- `acknowledge(batchID:itemIDs:)`: releases camera ownership only after a durable destination receipt. It retains originals/JPEGs until delivery or explicit authorized discard.
- `retainedRecovery(batchID:owner:)`: returns `RetainedCaptureRecovery(batch: prepared siblings, failedItems: retained metadata)` including receipt-owned draft photos. One invalid original does not hide good siblings. `retainedBatch(...prepareImages:false)` and `retainedBatches(owner:)` expose metadata for exact-owner explicit discard/reconciliation.
- `recordDelivered(localURLs:account:)`: use only after authoritative server delivery and successful local model healing. Writes a retirement intent before manifest/byte cleanup. The actor revalidates current company/user before receipt writes and byte retirement, and processes only that account's manifests. Reopen retries interrupted cleanup. No age/cache-based original deletion.
- `PhotoThumbnailRequest(sourceURL:fallbackURL:maxPixelSize:prefersComposite:)`: exact request cache identity, oriented bounded decode, local composite/source priority and real remote fallback.
- `PhotoThumbnailLoader.image(for:)`: async UIImage?, in-flight dedupe, per-waiter cancellation, generation guard and bounded parallel work.
- `.photoThumbnailSourceChanged`: userInfo `sourceURL`; `*` means cache clear. Observe matching preview/raw sources to rerun a tile's task.
- `PhotoDownloadManager.downloadPhoto(...cacheReservation:)`: optional reservation; existing calls remain compatible.

## Final behavior

Cache: one background reconciliation per prefetch pass; background-owned ModelContext produces immutable URL plans. Ledger reserves intake and settles actual writes, overwrites and deletes without per-photo directory scans. Pending originals/local composites are protected. Remote cache writes honor budget; prefetch does not evict. Existing local composite keys remain readable. `StorageProfiler.budgetSnapshot()` reads a thread-safe persisted scalar without touching the MainActor singleton; immutable Sendable constants are nonisolated.

Camera: every accepted capture/import is journaled and atomically written before confirmation. View state retains only bounded thumbnails for accepted shots. A failed write keeps source bytes for retry, a failed host save keeps stable IDs, and cancellation cannot silently lose accepted photos.

Lead: typed camera handoff adopts existing durable files without rebuilding an image array. Lead staging journals each item before publishing the old queue; original pixels survive until S3, authoritative lead row and successful local healing. Uploaded URLs survive lost-response/retry cases. Reopen is exact company/user/destination; background delivery rechecks the original account across awaits. Tombstones prevent stale queue resurrection.

Existing project: an owned ModelContext saves stable ProjectPhoto IDs plus local URL projection before camera acknowledgment. Existing pending-row reconciliation supplies durable upload recovery. Canonical row readback matches photo ID, project, company, uploader and live remote URL before healing; healing commits in another owned context before retiring bytes or removing the upload queue. A failed save leaves original rows/queue/bytes and unrelated UI edits intact. Project reopen reconciles interrupted retirement after persisted remote-row healing.

Project creation: a file-backed photo draft is created before opening the camera. It reserves one project UUID and retains identifying/basic form fields (name, client, address, notes, description, status and dates), plus batch IDs. It is a photo draft, not a replacement for every existing form field. The next creation form offers exact-account resume/discard. New draft project and create SyncOperation save in the same transaction before photo transfer. Replays use the reserved ID; closed markers prevent delayed field saves from recreating completed drafts. A failed original remains visible and removable while successful siblings preview and transfer independently. Partial failure keeps the form draft for retry; explicitly discarding a leftover draft preserves photos already owned by ProjectPhoto rows.

Account changes: capture intake checks original uploader before upload; delivery rechecks the captured company/user after deletion probe, upload, row insert and canonical fetch, before local healing and queue retirement. Deferred manifest reads revalidate on return; the actor checks again before deleting. A replacement session cannot finish the original account's retirement.

## Verification

Executed locally: `python3 docs/artifacts/ios-performance-p1-3/verify-static.py`.

- PASS: Swift syntax parse for 21 owned source files and 8 media test files.
- PASS: diff whitespace with existing CRLF accepted; original LF/CRLF conventions preserved. ProjectDetailsView's unchanged mixed-ending segments were preserved.
- PASS: all five owned production camera hosts use typed receipts; no main-actor per-photo cache scans or full-image camera batch array.
- No xcodebuild, swift build/test, package resolution, simulator launch, real pending replay, phone-data mutation, external writes, push or release performed.

Authored XCTest classes (synthetic fixtures only; compilation/execution delegated to PM):

- `OPSTests/PhotoCacheLedgerTests` — reservations, overwrite/deletion accounting, original/pinned protection, PhotoProcessor-style concurrent writes.
- `OPSTests/PhotoThumbnailLoaderTests` — pixel bound, composite precedence/cache arrival, remote fallback, EXIF orientation, dedupe/cancellation.
- `OPSTests/DurableCaptureStoreTests` — exact-owner reopen, interrupted writes, valid/invalid siblings, unreadable direct reopen/index, explicit draft discard, durable retirement intent.
- `OPSTests/CameraCaptureSessionTests` — failed destination save and failed acknowledgment replay stable IDs.
- `OPSTests/LeadImageStagerTests` — original retention, partial write repair and durable remote receipts.
- `OPSTests/StorageProfilerBudgetTests` — off-main budget snapshot without MainActor singleton access.
- `OPSTests/ProjectPhotoFormDraftStoreTests` — reserved identity, exact account, stale edits, completed tombstones, unreadable drafts.
- `OPSTests/StagedPhotoDestinationsTests` — stable metadata-only receipts, parent-create custody, failed local healing, canonical identity match, delivered-original retirement, actual retained-form mixed-sibling recovery and suspended-read account switch.

Compilation, XCTest results, performance benchmarks and physical-device/force-quit UX proof remain UNVERIFIED here. PM owns the build baton and combined proof. The parent reported schema guards passed (68 tests, zero failures, one optional skip); that is parent evidence, not this worker's execution.

## Bible handoff (PM-owned update)

Update photo/cache architecture and offline custody sections with the contracts and final behavior above. No SwiftData schema changes or new backend columns/endpoints. Document the file-journal ownership sequence: durable raw bytes -> typed local receipt -> canonical remote delivery -> durable local healing -> original retirement. Include creation-draft tombstones, partial-image recovery, and account revalidation across suspension. Journal format remains v1 for this unreleased implementation; a future change to custody semantics/required fields must bump the version. Higher/unknown versions fail closed; arbitrary unknown same-version JSON fields are not treated as a supported producer contract.
