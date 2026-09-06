import XCTest
@testable import OPS

final class PhotoCacheLedgerTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("ProjectImages")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

    func testReservationsPreventConcurrentOvercommitAndReleaseAfterFailure() async throws {
        let ledger = PhotoCacheLedger(directories: [root])
        _ = await ledger.backgroundSnapshot()
        let reservations = await withTaskGroup(of: UUID?.self, returning: [UUID].self) { group in
            for _ in 0..<8 { group.addTask { ledger.reserve(bytes: 4096, budget: 8192) } }
            var ids: [UUID] = []
            for await id in group { if let id { ids.append(id) } }
            return ids
        }
        XCTAssertEqual(reservations.count, 2)
        for id in reservations { ledger.release(id) }
        XCTAssertNotNil(ledger.reserve(bytes: 8192, budget: 8192))
        XCTAssertEqual(ledger.snapshotCount, 1)
    }

    func testWritesSettleActualBytesWithoutRescansAndOverwritesDoNotDoubleCount() throws {
        let ledger = PhotoCacheLedger(directories: [root])
        ledger.reconcile()
        let target = root.appendingPathComponent("remote_test")
        let id = try XCTUnwrap(ledger.reserve(bytes: 4096, budget: 1_000_000))
        XCTAssertTrue(ledger.write(data: Data(repeating: 7, count: 1000), to: target, budget: 1_000_000, reservation: id, allowEviction: false))
        let initial = ledger.snapshot()
        XCTAssertGreaterThan(initial, 0)
        for _ in 0..<10 { XCTAssertTrue(ledger.write(data: Data(repeating: 8, count: 1000), to: target, budget: 1_000_000)) }
        XCTAssertEqual(ledger.snapshot(), initial)
        XCTAssertEqual(ledger.snapshotCount, 1)
        ledger.remove(target)
        XCTAssertEqual(ledger.snapshot(), 0)
    }

    func testBudgetNeverEvictsPendingOriginalOverlayOrPinnedPhoto() throws {
        let ledger = PhotoCacheLedger(directories: [root])
        let protected = ["capture_pending.original", "capture_pending.jpg", "overlay_unsent", "composited_local_pending", "remote_pinned", "composited_remote_pinned"]
        for name in protected + ["remote_reclaimable"] {
            XCTAssertTrue(ledger.write(data: Data(repeating: 1, count: 4096), to: root.appendingPathComponent(name), budget: nil))
        }
        _ = ledger.evict(bytesNeeded: 4096, budget: 1, pinned: ["remote_pinned", "composited_remote_pinned"])
        for name in protected { XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path), name) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("remote_reclaimable").path))
        XCTAssertFalse(ledger.write(data: Data(repeating: 1, count: 4096), to: root.appendingPathComponent("remote_new"), budget: 1, allowEviction: false))
    }

    func testFailedWriteKeepsReservationUntilCallerReleasesIt() throws {
        let ledger = PhotoCacheLedger(directories: [root])
        let id = try XCTUnwrap(ledger.reserve(bytes: 4096, budget: 4096))
        // Writing over a directory fails atomically; existing bytes stay intact.
        XCTAssertFalse(ledger.write(data: Data(repeating: 1, count: 100), to: root, budget: 4096, reservation: id, allowEviction: false))
        XCTAssertNil(ledger.reserve(bytes: 1, budget: 4096))
        ledger.release(id)
        XCTAssertNotNil(ledger.reserve(bytes: 4096, budget: 4096))
    }

    func testOriginalAndThumbnailWritersSettleUsageDuringRemoteReservations() throws {
        let photos = root.deletingLastPathComponent().appendingPathComponent("photos")
        let thumbnails = root.deletingLastPathComponent().appendingPathComponent("thumbnails")
        let ledger = PhotoCacheLedger(directories: [root, photos, thumbnails])
        ledger.reconcile()
        let reservation = try XCTUnwrap(ledger.reserve(bytes: 4096, budget: 8192))
        let original = photos.appendingPathComponent("original.jpg")
        let thumbnail = thumbnails.appendingPathComponent("original_thumb.jpg")
        XCTAssertTrue(ledger.write(data: Data(repeating: 3, count: 8192), to: original, budget: nil))
        XCTAssertTrue(ledger.write(data: Data(repeating: 4, count: 4096), to: thumbnail, budget: nil))
        XCTAssertGreaterThanOrEqual(ledger.snapshot(), 12288)
        XCTAssertFalse(ledger.write(data: Data(repeating: 8, count: 4096), to: root.appendingPathComponent("remote_reserved"), budget: 8192, reservation: reservation, allowEviction: false))
        XCTAssertTrue(ledger.remove(original))
        XCTAssertTrue(ledger.remove(thumbnail))
        XCTAssertEqual(ledger.snapshot(), 0)
        XCTAssertTrue(ledger.write(data: Data(repeating: 8, count: 4096), to: root.appendingPathComponent("remote_reserved"), budget: 8192, reservation: reservation, allowEviction: false))
        XCTAssertEqual(ledger.snapshotCount, 1)
    }
}
