# Retire Unrecoverable Site-Visit Media — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Stop the sync engine from endlessly re-queueing site-visit photo uploads whose local bytes no longer exist, so a permanently-lost photo resolves quietly instead of parking with a raw error — while never discarding a photo that is merely temporarily unreadable.

**Architecture:** A local capture's bytes live only in `Documents/ProjectImages/` until upload. When that file is gone (app reinstall wipes the app container; the SwiftData store lives in the surviving app-group container), the artifact row keeps a `local://…` pointer that can never resolve. `needsMediaUpload` only asks "is this URL still local?", never "does the file exist?", so the op is re-queued every drain, fails, and parks. The fix: treat *file absent* as terminal — clear the dead pointer so the row matches what the server and every other device already hold (`asset_url IS NULL`) — and treat *file present but unreadable* as transient so an iOS Data-Protection lock can never destroy a good photo. No schema change: only existing optional `String?` fields are nilled.

**Tech Stack:** Swift 5, SwiftData, XCTest. iOS deployment target 17.6.

**Design System:** N/A — no UI surface. This change *removes* a raw developer string (`"Unexpected sync error: Site-visit media file is missing: local://…"`) from Pending Work by resolving the operation. It adds no new user-facing copy. Artifacts with no resolvable image already degrade to the existing placeholder; the visit, its notes, checklist answers and deck designs are untouched.

**Required Skills:** `superpowers:test-driven-development` (every task is test-first), `superpowers:verification-before-completion` (before any "done" claim).

**Scope guard:** Site visits are NOT deleted, completed, or modified beyond their artifacts' dead media pointers. Only photo/media bytes are written off.

---

## Background — verified evidence (2026-08-05)

On-device forensics (`xcrun devicectl`, device `F1B83A71-FF52-5645-BA81-F8B8DB07A44C`) plus production Supabase:

- **32 photo artifacts across 5 site visits** hold `local://project_images/…` pointers to files that do not exist. Verified by exact-filename search across the *entire* app container (`Documents`, `Library`, `tmp`): **0 of 34 filenames present**. Server rows exist with `asset_url IS NULL` for all of them.
- Affected visits: `6619ab3e` (Cheryl Cooper, 8), `93980bb5` (unlinked, 4), `99022406` (Faye Keys, 5), `88ab2ec8` (Carol Dancer, 4), `78cd73a0` (Canpro / 630 Agnes St, 11).
- Oldest file anywhere in the app container is dated **2026-07-16** — the container was recreated by a delete+reinstall on 2026-07-17, which erased the bytes. The app-group container (holding `default.store`) survived, so rows outlived their files.
- Current queue state on the phone: **5 parked + 27 pending** media ops that will each park. One *legitimate* pending media op exists (`D1320778`, rendered markup, file present, 30.2 MB) and **must still upload** — the fix must not retire it.
- Post-reinstall visits (2026-07-21 → 07-28, 23 photos) uploaded normally. The pipeline itself is healthy.

**The latent second bug this plan also fixes:** `SiteVisitMediaSyncManager.loadAsset` maps *any* `Data(contentsOf:)` failure to `.localFileMissing`. A file that exists but is unreadable (iOS Data Protection while the device is locked, e.g. a background drain) would therefore be classified `.permanent`. Once the retire behaviour lands, that would silently *delete the pointer to a photo that is actually fine*. Task 1 must land before Task 2 for this reason.

---

## Task 1: Distinguish "file absent" from "file unreadable"

**Skills:** `superpowers:test-driven-development`

**Files:**
- Modify: `OPS/Network/Sync/SiteVisitMediaSyncManager.swift:13-25` (error enum), `:204-225` (`loadAsset`)
- Modify: `OPS/Network/Sync/SyncErrorClassifier.swift:70-72`
- Test: `OPSTests/Sync/SiteVisitMediaSyncManagerTests.swift`

**Step 1: Write the failing tests**

Add to `SiteVisitMediaSyncManagerTests`:

```swift
func test_absentFileClassifiesPermanentAndUnreadableFileClassifiesTransient() {
    XCTAssertEqual(
        SyncErrorClassifier.disposition(for: SiteVisitMediaSyncError.localFileMissing("gone")),
        .permanent
    )
    XCTAssertEqual(
        SyncErrorClassifier.disposition(for: SiteVisitMediaSyncError.localFileUnreadable("locked")),
        .transient
    )
    XCTAssertEqual(
        SyncErrorClassifier.disposition(for: SiteVisitMediaSyncError.invalidRemoteURL("nope")),
        .permanent
    )
}

func test_loadAssetReportsUnreadableWhenFileExistsButCannotBeRead() throws {
    // A directory at the target path exists but is not readable as file data —
    // the stand-in for a Data-Protection-locked file, which must NEVER be
    // mistaken for a permanently missing one.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("unreadable-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    XCTAssertThrowsError(try SiteVisitMediaSyncManager.loadAssetForTesting(directory.path)) { error in
        guard case SiteVisitMediaSyncError.localFileUnreadable = error else {
            return XCTFail("Expected .localFileUnreadable, got \(error)")
        }
    }
}

func test_loadAssetReportsMissingWhenFileIsAbsent() {
    let absent = FileManager.default.temporaryDirectory
        .appendingPathComponent("absent-\(UUID().uuidString).jpg").path

    XCTAssertThrowsError(try SiteVisitMediaSyncManager.loadAssetForTesting(absent)) { error in
        guard case SiteVisitMediaSyncError.localFileMissing = error else {
            return XCTFail("Expected .localFileMissing, got \(error)")
        }
    }
}
```

**Step 2: Run to verify failure**

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/SiteVisitMediaSyncManagerTests 2>&1 | tail -30
```

Expected: compile failure — `localFileUnreadable` and `loadAssetForTesting` do not exist.

**Step 3: Implement**

In `SiteVisitMediaSyncManager.swift`, extend the error enum:

```swift
enum SiteVisitMediaSyncError: Error, Equatable, LocalizedError {
    /// The bytes are gone. The local file is the ONLY copy until upload, so an
    /// absent file can never become present again — this is terminal.
    case localFileMissing(String)
    /// The file exists but could not be read right now (iOS Data Protection
    /// while the device is locked, transient I/O). NEVER terminal: retiring on
    /// this would destroy the pointer to a photo that is actually fine.
    case localFileUnreadable(String)
    case invalidRemoteURL(String)

    var errorDescription: String? {
        switch self {
        case .localFileMissing(let source):
            return "Site-visit media file is missing: \(source)"
        case .localFileUnreadable(let source):
            return "Site-visit media file could not be read: \(source)"
        case .invalidRemoteURL(let value):
            return "Site-visit upload returned an invalid URL: \(value)"
        }
    }
}
```

Rewrite `loadAsset` so the two failure modes cannot be conflated:

```swift
private static func loadAsset(_ source: String) throws -> LoadedAsset {
    let fileURL: URL?
    if source.hasPrefix("file://") {
        fileURL = URL(string: source)
    } else if source.hasPrefix("/") {
        fileURL = URL(fileURLWithPath: source)
    } else {
        fileURL = ImageFileManager.shared.getFileURL(for: source)
    }
    // An unresolvable key and an absent file are the same fact: no bytes.
    guard let fileURL,
          FileManager.default.fileExists(atPath: fileURL.path) else {
        throw SiteVisitMediaSyncError.localFileMissing(source)
    }
    do {
        return (
            try Data(contentsOf: fileURL),
            contentType(forExtension: fileURL.pathExtension)
        )
    } catch {
        // The file IS on disk — this read failed for some other reason. Retry.
        throw SiteVisitMediaSyncError.localFileUnreadable(source)
    }
}

/// Test seam for the absent/unreadable split. Production code reaches
/// `loadAsset` through the injected `loader`.
static func loadAssetForTesting(_ source: String) throws -> LoadedAsset {
    try loadAsset(source)
}
```

In `SyncErrorClassifier.swift`, replace the blanket `if error is SiteVisitMediaSyncError { return .permanent }` (line 70-72) with a case-aware switch:

```swift
if let mediaError = error as? SiteVisitMediaSyncError {
    switch mediaError {
    case .localFileMissing, .invalidRemoteURL:
        return .permanent
    case .localFileUnreadable:
        // The bytes are still on disk; a later drain (device unlocked) succeeds.
        return .transient
    }
}
```

**Step 4: Run to verify pass**

Same command as Step 2. Expected: the three new tests pass.

**Step 5: Commit**

```bash
git add OPS/Network/Sync/SiteVisitMediaSyncManager.swift OPS/Network/Sync/SyncErrorClassifier.swift OPSTests/Sync/SiteVisitMediaSyncManagerTests.swift
git commit -m "fix(sync): separate absent site-visit media from temporarily unreadable media"
```

---

## Task 2: Retire absent media instead of parking the operation

**Skills:** `superpowers:test-driven-development`

**Files:**
- Modify: `OPS/Network/Sync/SiteVisitMediaSyncManager.swift:82-117` (`uploadPendingMedia`), add `clearSourceURL`
- Test: `OPSTests/Sync/SiteVisitMediaSyncManagerTests.swift`

**Step 1: Write the failing tests**

Replace the existing `test_missingLocalFileIsPermanentInsteadOfInfiniteRetry` (lines 129-149) — its premise (throw so the op parks) is precisely the behaviour being removed. Add:

```swift
func test_absentVariantIsRetiredAndOperationCompletesWithoutThrowing() async throws {
    let context = try makeContainer().mainContext
    let artifact = makeArtifact()
    context.insert(artifact)
    let media = try insertMediaOperation(for: artifact, in: context)

    var uploadCount = 0
    let manager = SiteVisitMediaSyncManager(
        uploader: { _, _, _, _, _ in uploadCount += 1; return "" },
        loader: { source in throw SiteVisitMediaSyncError.localFileMissing(source) }
    )

    // Must NOT throw — there is nothing left to do, so the work is finished.
    try await manager.uploadPendingMedia(
        artifactId: artifactId,
        mediaOperation: media,
        context: context
    )

    XCTAssertEqual(uploadCount, 0, "Nothing to upload when every file is gone")
    XCTAssertNil(artifact.localAssetURL, "Dead pointer must be cleared")
    XCTAssertNil(artifact.renderedAssetURL)
    XCTAssertNil(artifact.thumbnailURL)
    XCTAssertTrue(artifact.needsSync, "Cleared state must reach the server")
}

func test_unreadableVariantThrowsAndPreservesItsLocalPointer() async throws {
    let context = try makeContainer().mainContext
    let artifact = makeArtifact()
    context.insert(artifact)
    let media = try insertMediaOperation(for: artifact, in: context)

    let manager = SiteVisitMediaSyncManager(
        uploader: { _, _, _, _, _ in "" },
        loader: { source in throw SiteVisitMediaSyncError.localFileUnreadable(source) }
    )

    do {
        try await manager.uploadPendingMedia(
            artifactId: artifactId, mediaOperation: media, context: context
        )
        XCTFail("A temporarily unreadable file must not resolve the operation")
    } catch let error as SiteVisitMediaSyncError {
        guard case .localFileUnreadable = error else {
            return XCTFail("Expected .localFileUnreadable, got \(error)")
        }
    }

    XCTAssertEqual(artifact.localAssetURL, "local://project_images/original.jpg",
                   "A readable-later photo must keep its pointer")
}

func test_absentVariantIsRetiredWhileHealthyVariantStillUploads() async throws {
    let context = try makeContainer().mainContext
    let artifact = makeArtifact()
    artifact.renderedAssetURL = nil
    artifact.thumbnailURL = nil
    context.insert(artifact)
    // Only `.original` is local; prove a sibling artifact's good file is
    // unaffected by another's retirement.
    let healthy = SiteVisitCaptureArtifact(
        id: "55555555-5555-4555-8555-555555555555",
        siteVisitId: visitId, companyId: companyId, kind: .photo, source: .camera,
        localAssetURL: "local://project_images/present.jpg",
        createdBy: userId, createdAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
    context.insert(healthy)
    let media = try insertMediaOperation(for: artifact, in: context)

    let manager = SiteVisitMediaSyncManager(
        uploader: { _, _, _, _, _ in "https://cdn.ops.test/ok.jpg" },
        loader: { source in throw SiteVisitMediaSyncError.localFileMissing(source) }
    )
    try await manager.uploadPendingMedia(
        artifactId: artifactId, mediaOperation: media, context: context
    )

    XCTAssertNil(artifact.localAssetURL)
    XCTAssertEqual(healthy.localAssetURL, "local://project_images/present.jpg",
                   "Retiring one artifact must never touch another")
}
```

**Step 2: Run to verify failure**

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/SiteVisitMediaSyncManagerTests 2>&1 | tail -30
```

Expected: `test_absentVariantIsRetired…` fails — the manager currently throws.

**Step 3: Implement**

In `uploadPendingMedia`, wrap the loader call so an absent file retires that variant and the loop continues:

```swift
for variant in SiteVisitArtifactVariant.allCases {
    guard let source = sourceURL(for: variant, artifact: artifact),
          !Self.isRemoteURL(source) else {
        continue
    }

    let asset: LoadedAsset
    do {
        asset = try loader(source)
    } catch let error as SiteVisitMediaSyncError {
        guard case .localFileMissing = error else { throw error }
        // The bytes are gone and a local file is the only copy until upload,
        // so no future drain can succeed. Clearing the pointer makes this row
        // match what the server and every other device already hold (a null
        // asset URL) and stops `needsMediaUpload` re-queueing this forever.
        // The artifact, its visit, notes and checklist answers all survive.
        try context.transaction {
            guard sourceURL(for: variant, artifact: artifact) == source else { return }
            setSourceURL(nil, for: variant, artifact: artifact)
            artifact.updatedAt = Date()
            artifact.needsSync = true
            try queueArtifactURLUpsert(
                artifact,
                dependsOn: mediaOperation,
                context: context
            )
        }
        continue
    }

    let remoteURL = try await uploader(
        artifact.siteVisitId.lowercased(),
        artifact.id.lowercased(),
        variant,
        asset.data,
        asset.contentType
    )
    // …unchanged remainder…
}
```

Change `setSourceURL` to accept an optional so the same writer handles both set and clear:

```swift
private func setSourceURL(
    _ value: String?,
    for variant: SiteVisitArtifactVariant,
    artifact: SiteVisitCaptureArtifact
) {
    switch variant {
    case .original:  artifact.localAssetURL = value
    case .rendered:  artifact.renderedAssetURL = value
    case .thumbnail: artifact.thumbnailURL = value
    }
}
```

The existing success-path call `setSourceURL(remoteURL, …)` still compiles (`String` → `String?`).

**Step 4: Run to verify pass**

Same command. Expected: all `SiteVisitMediaSyncManagerTests` pass, including the pre-existing partial-failure and restart tests (which must be unaffected — they use `URLError`, not `SiteVisitMediaSyncError`).

**Step 5: Commit**

```bash
git add OPS/Network/Sync/SiteVisitMediaSyncManager.swift OPSTests/Sync/SiteVisitMediaSyncManagerTests.swift
git commit -m "fix(sync): retire site-visit media whose local bytes are permanently gone"
```

---

## Task 3: Clear the parked backlog already on the device

**Skills:** `superpowers:test-driven-development`

**Why:** Tasks 1–2 fix future drains. Parked operations never auto-retry (`SyncOperationFailurePolicy` parks permanently by design, and `hasUnresolvedOperation` counts `parked` as unresolved so the orphan sweep will not replace them). Without this task the 5 already-parked ops on the phone sit in Pending Work forever. The 27 still-`pending` ops self-heal through Task 2.

**Files:**
- Modify: `OPS/Network/Sync/SyncEngine.swift` — add `reconcileParkedUnrecoverableSiteVisitMedia()`, call it in `pushPending()` beside the existing sweeps (~line 1315)
- Test: `OPSTests/Sync/SiteVisitMediaSyncManagerTests.swift` (or a new `SiteVisitParkedMediaReconcileTests.swift`)

**Design:** Mirror the existing `reconcileSupersededParkedProjectNoteMentionUpdates()` precedent. For each parked media op: re-check every local variant on disk. Variants whose file is **absent** are cleared; if any local variant's file is **present**, the op returns to `pending` so it uploads. An op with nothing local left is marked `completed`. This never guesses — it re-reads the filesystem.

**Step 1: Write the failing test**

```swift
func test_parkedMediaOperationWithAbsentFilesIsClearedAndCompleted() throws {
    let context = try makeContainer().mainContext
    let artifact = makeArtifact()
    artifact.renderedAssetURL = nil
    artifact.thumbnailURL = nil
    context.insert(artifact)
    let media = try insertMediaOperation(for: artifact, in: context)
    media.status = "parked"
    media.lastError = "Unexpected sync error: Site-visit media file is missing: local://project_images/original.jpg"

    let healed = SiteVisitParkedMediaReconciler.reconcile(
        in: context,
        fileExists: { _ in false }        // injected — no real filesystem in tests
    )

    XCTAssertEqual(healed, 1)
    XCTAssertEqual(media.status, "completed")
    XCTAssertNil(media.lastError)
    XCTAssertNil(artifact.localAssetURL)
    XCTAssertTrue(artifact.needsSync)
}

func test_parkedMediaOperationWithPresentFileIsRequeuedNotCleared() throws {
    let context = try makeContainer().mainContext
    let artifact = makeArtifact()
    artifact.renderedAssetURL = nil
    artifact.thumbnailURL = nil
    context.insert(artifact)
    let media = try insertMediaOperation(for: artifact, in: context)
    media.status = "parked"

    let healed = SiteVisitParkedMediaReconciler.reconcile(
        in: context,
        fileExists: { _ in true }
    )

    XCTAssertEqual(healed, 1)
    XCTAssertEqual(media.status, "pending", "A present file deserves another attempt")
    XCTAssertEqual(artifact.localAssetURL, "local://project_images/original.jpg")
}
```

**Step 2: Run to verify failure**

Expected: `SiteVisitParkedMediaReconciler` undefined.

**Step 3: Implement**

Create the reconciler as a pure, injectable type (new file `OPS/Network/Sync/SiteVisitParkedMediaReconciler.swift`) so it is testable without touching the real filesystem, then call it from `SyncEngine.pushPending()`:

```swift
enum SiteVisitParkedMediaReconciler {
    typealias FileProbe = (String) -> Bool

    static func defaultProbe(_ source: String) -> Bool {
        let url: URL?
        if source.hasPrefix("file://") { url = URL(string: source) }
        else if source.hasPrefix("/") { url = URL(fileURLWithPath: source) }
        else { url = ImageFileManager.shared.getFileURL(for: source) }
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Returns the number of parked media operations resolved.
    @discardableResult
    static func reconcile(
        in context: ModelContext,
        fileExists: FileProbe = defaultProbe
    ) -> Int { /* fetch parked media ops; per artifact clear absent variants;
                  complete or re-pend; save. Full body written during execution. */ }
}
```

Call site in `pushPending()`, immediately after `enqueueOrphanedSiteVisitWrites()`:

```swift
// A media op parked because its local bytes were gone can never be retried
// by the normal path. Re-read the filesystem: clear pointers that are truly
// dead, and give any op whose file is present another attempt.
SiteVisitParkedMediaReconciler.reconcile(in: modelContext)
```

**Step 4: Run to verify pass**

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/Sync 2>&1 | tail -30
```

**Step 5: Commit**

```bash
git add OPS/Network/Sync/SiteVisitParkedMediaReconciler.swift OPS/Network/Sync/SyncEngine.swift OPSTests/Sync/
git commit -m "fix(sync): resolve parked site-visit media ops whose files are permanently gone"
```

---

## Task 4: Full-suite verification and device proof

**Skills:** `superpowers:verification-before-completion`

**Step 1: Device-target build**

```bash
xcodebuild -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`. (Check `ps aux | grep xcodebuild` first — parallel sessions share DerivedData.)

**Step 2: Full sync suite**

```bash
xcodebuild test -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/Sync 2>&1 | tail -30
```

Expected: all pass, zero regressions in `SiteVisitOutboundSyncTests`, `SiteVisitDrainStressTests`, `SiteVisitOrphanRecoveryTests`.

**Step 3: Prove on the real device**

After installing the build on `F1B83A71-FF52-5645-BA81-F8B8DB07A44C` and letting one sync pass run, re-pull the store and confirm:

```bash
sqlite3 default.store "SELECT ZSTATUS, COUNT(*) FROM ZSYNCOPERATION WHERE ZOPERATIONTYPE='siteVisitMediaUpload' GROUP BY 1;"
```

Expected: **0 parked**, 0 pending for the 5 dead visits; the legitimate `D1320778` markup op completed (its 30.2 MB file is present and must upload, not retire).

```bash
sqlite3 default.store "SELECT COUNT(*) FROM ZSITEVISITCAPTUREARTIFACT WHERE ZLOCALASSETURL LIKE 'local://%';"
```

Expected: only artifacts whose files genuinely exist remain.

Confirm in-app: Pending Work shows no site-visit media errors; the 5 visits and their notes/checklists/deck designs are still present.

**Step 4: Commit any fixes, then report with evidence**

Report to Jackson in plain language with the before/after counts. No "done" claim without the Step 3 output.

---

## Out of scope (deliberate)

- **Recovering the 32 photos** — proven unrecoverable 2026-08-05 (no bytes on device, server, vault, camera roll, or any Mac backup; app has no iCloud container).
- **Deleting or completing the 5 site visits** — Jackson's instruction is "just the images, not the site visits."
- **Warning the operator that unsent captures exist only on the phone** — the standing hazard that caused this loss. Offered and not taken this round; worth revisiting.
