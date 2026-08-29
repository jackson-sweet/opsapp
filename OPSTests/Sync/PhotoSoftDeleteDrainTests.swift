//
//  PhotoSoftDeleteDrainTests.swift
//  OPSTests
//
//  Bug 1154fe67 — a photo the operator deleted must never resurrect.
//
//  `deleteProjectPhoto` and the notes prune loop both stamp `deletedAt` +
//  `needsSync = true` on the local `ProjectPhoto` row and then fire a
//  best-effort remote soft-delete. Before this fix nothing ever drained that
//  flag: a delete that raced a dead spot lost the remote tombstone forever, and
//  the next inbound sync pulled the still-live server row back into the gallery.
//
//  `ImageSyncManager.drainPendingPhotoSoftDeletes` closes that hole by
//  re-pushing every unconfirmed tombstone on each sync pass. Its two halves are
//  plain store operations precisely so they are provable here — the PostgREST
//  call between them has no seam, and the PM's device pass covers that leg:
//
//    * `pendingSoftDeleteTargets(in:)` — the work list. Selects tombstoned rows
//      still flagged, skips confirmed ones, and collapses a (project, url) pair
//      to ONE statement because that is what the UPDATE actually covers.
//    * `clearPendingSoftDelete(url:projectId:in:)` — the confirmation. Clears
//      the flag on exactly the rows the accepted statement covered, and on
//      nothing else.
//
//  Every container is retained for the case's lifetime: a `ModelContext` does
//  not keep its `ModelContainer` alive, and inserting into a context whose
//  container has been released traps inside SwiftData (uncatchable
//  EXC_BREAKPOINT) before the first assertion runs. A `SyncOperation` warm-up
//  row rides along for the same house reason — a `#Predicate` fetch of that
//  entity traps against a table that has never held a row.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class PhotoSoftDeleteDrainTests: XCTestCase {

    // Lowercase throughout — Postgres uuid columns are lowercase and
    // `UUID().uuidString` is uppercase.
    private let projectId = "7e4d418e-6a0c-4ec6-865b-bef70bc57fe6"
    private let otherProjectId = "5c1c7a6a-3f0e-4d1b-9a2c-0b6f4e8d1c33"
    private let companyId = "0a887c18-0000-4832-97f0-f302dcae2e9d"
    private let uploaderId = "283d49df-90a1-4abb-b94c-3e9f17f02c0d"

    private let urlA = "https://ops-media.s3.amazonaws.com/photos/a.jpg"
    private let urlB = "https://ops-media.s3.amazonaws.com/photos/b.jpg"

    // MARK: - Work list

    /// The whole point of the flag: a tombstone the server has not confirmed is
    /// selected for re-push, and a confirmed one is left alone.
    func testDrainSelectsOnlyUnconfirmedTombstones() throws {
        let context = try makeContext()

        let pending = makePhoto(url: urlA)
        pending.deletedAt = Date()
        pending.needsSync = true

        let confirmed = makePhoto(url: urlB)
        confirmed.deletedAt = Date()
        confirmed.needsSync = false

        context.insert(pending)
        context.insert(confirmed)
        try context.save()

        let targets = ImageSyncManager.pendingSoftDeleteTargets(in: context)

        XCTAssertEqual(
            targets,
            [PendingPhotoSoftDelete(projectId: projectId, url: urlA)],
            "Only the unconfirmed tombstone belongs on the work list"
        )
    }

    /// A live row is not a tombstone, however pending it is. Draining one would
    /// soft-delete a photo nobody asked to delete.
    func testDrainIgnoresLiveRowsEvenWhenFlagged() throws {
        let context = try makeContext()

        let live = makePhoto(url: urlA)
        live.needsSync = true          // pending for some other reason
        XCTAssertNil(live.deletedAt)

        context.insert(live)
        try context.save()

        XCTAssertTrue(
            ImageSyncManager.pendingSoftDeleteTargets(in: context).isEmpty,
            "A live row must never be swept into the soft-delete drain"
        )
    }

    /// The remote statement filters on (project_id, url) and covers every row
    /// on that pair — so the work list carries the pair once, not once per row.
    func testDrainCollapsesDuplicateRowsOnTheSamePair() throws {
        let context = try makeContext()

        for _ in 0..<3 {
            let row = makePhoto(url: urlA)
            row.deletedAt = Date()
            row.needsSync = true
            context.insert(row)
        }
        // Same URL on a different project is a different statement.
        let otherProject = makePhoto(url: urlA, projectId: otherProjectId)
        otherProject.deletedAt = Date()
        otherProject.needsSync = true
        context.insert(otherProject)
        try context.save()

        let targets = ImageSyncManager.pendingSoftDeleteTargets(in: context)

        XCTAssertEqual(targets.count, 2, "Three rows on one pair are one statement")
        XCTAssertTrue(targets.contains(PendingPhotoSoftDelete(projectId: projectId, url: urlA)))
        XCTAssertTrue(targets.contains(PendingPhotoSoftDelete(projectId: otherProjectId, url: urlA)))
    }

    /// Nothing tombstoned, nothing to do — the pass is cheap on every launch.
    func testDrainWorkListIsEmptyWhenNothingIsTombstoned() throws {
        let context = try makeContext()
        context.insert(makePhoto(url: urlA))
        try context.save()

        XCTAssertTrue(ImageSyncManager.pendingSoftDeleteTargets(in: context).isEmpty)
    }

    // MARK: - Confirmation

    /// A confirmed statement clears the flag on every row it covered, and the
    /// pair drops off the work list.
    func testConfirmationClearsEveryRowOnThePair() throws {
        let context = try makeContext()

        let first = makePhoto(url: urlA)
        first.deletedAt = Date()
        first.needsSync = true
        let second = makePhoto(url: urlA)
        second.deletedAt = Date()
        second.needsSync = true
        context.insert(first)
        context.insert(second)
        try context.save()

        ImageSyncManager.clearPendingSoftDelete(url: urlA, projectId: projectId, in: context)

        XCTAssertFalse(first.needsSync)
        XCTAssertFalse(second.needsSync)
        XCTAssertTrue(
            ImageSyncManager.pendingSoftDeleteTargets(in: context).isEmpty,
            "A confirmed tombstone must not be re-pushed on the next pass"
        )
    }

    /// Confirmation is scoped: another URL, another project, and a live row on
    /// the same URL all keep their pending state.
    func testConfirmationDoesNotTouchOtherRows() throws {
        let context = try makeContext()

        let target = makePhoto(url: urlA)
        target.deletedAt = Date()
        target.needsSync = true

        let otherURL = makePhoto(url: urlB)
        otherURL.deletedAt = Date()
        otherURL.needsSync = true

        let otherProject = makePhoto(url: urlA, projectId: otherProjectId)
        otherProject.deletedAt = Date()
        otherProject.needsSync = true

        // A live row on the SAME pair: a re-upload of the same URL, pending for
        // its own reasons. The soft-delete statement excludes it server-side
        // (`is deleted_at null`), so clearing its flag would drop a real write.
        let liveSamePair = makePhoto(url: urlA)
        liveSamePair.needsSync = true

        context.insert(target)
        context.insert(otherURL)
        context.insert(otherProject)
        context.insert(liveSamePair)
        try context.save()

        ImageSyncManager.clearPendingSoftDelete(url: urlA, projectId: projectId, in: context)

        XCTAssertFalse(target.needsSync, "The covered row is confirmed")
        XCTAssertTrue(otherURL.needsSync, "A different URL is a different statement")
        XCTAssertTrue(otherProject.needsSync, "A different project is a different statement")
        XCTAssertTrue(liveSamePair.needsSync, "A live row was never covered by the statement")
    }

    /// A confirmation for a pair this device holds no rows for is a no-op, not
    /// a crash — the notes prune loop can delete URLs that never had a local row.
    func testConfirmationForUnknownPairIsHarmless() throws {
        let context = try makeContext()
        let unrelated = makePhoto(url: urlB)
        unrelated.deletedAt = Date()
        unrelated.needsSync = true
        context.insert(unrelated)
        try context.save()

        ImageSyncManager.clearPendingSoftDelete(url: urlA, projectId: projectId, in: context)

        XCTAssertTrue(unrelated.needsSync)
    }

    // MARK: - Fixtures

    private func makePhoto(url: String, projectId: String? = nil) -> ProjectPhoto {
        ProjectPhoto(
            id: UUID().uuidString.lowercased(),
            projectId: projectId ?? self.projectId,
            companyId: companyId,
            url: url,
            source: "site_visit",
            uploadedBy: uploaderId
        )
    }

    private func makeContainer() throws -> ModelContainer {
        // PhotoAnnotation rides along because it binds to photos by URL;
        // SyncOperation because a #Predicate fetch of it traps against a table
        // that has never held a row, and the warm-up row below needs a home.
        let schema = Schema([ProjectPhoto.self, PhotoAnnotation.self, SyncOperation.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Containers outlive the contexts they vend, for the whole test case. A
    /// `ModelContext` does not keep its container alive, and inserting into a
    /// context whose container has been released traps inside SwiftData
    /// (uncatchable EXC_BREAKPOINT) — the test dies before its first assertion.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try makeContainer()
        retainedContainers.append(container)
        let context = container.mainContext
        // Inert warm-up row: house rule for any container whose exercised paths
        // can reach a SyncOperation predicate fetch.
        context.insert(
            SyncOperation(
                entityType: SyncEntityType.projectPhoto.rawValue,
                entityId: "00000000-0000-0000-0000-000000000000",
                operationType: "create",
                payload: Data("{}".utf8),
                changedFields: []
            )
        )
        try context.save()
        return context
    }
}
