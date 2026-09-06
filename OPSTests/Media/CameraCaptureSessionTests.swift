import XCTest
import UIKit
@testable import OPS

final class CameraCaptureSessionTests: XCTestCase {
    @MainActor
    func testFailedHostSaveRetainsBatchAndRetryUsesSameArtifactIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DurableCaptureStore(root: root.appendingPathComponent("Journal"), images: root.appendingPathComponent("Images"))
        let owner = StagedCaptureOwner(companyID: "company", userID: "user", contextID: "visit")
        let session = CameraCaptureSession(owner: owner, store: store)
        await session.prepare()
        let accepted = await session.capture(fixture())
        XCTAssertTrue(accepted)
        let id = try XCTUnwrap(session.photos.first?.id)
        XCTAssertNil(session.photos.first?.retryData, "Accepted camera state must release original bytes")
        var delivered: [String] = []
        let rejected = await session.commit(onStaged: { batch in delivered += batch.items.map(\.id); return false }, onLegacy: nil)
        XCTAssertFalse(rejected)
        XCTAssertEqual(session.photos.map(\.id), [id])
        let recovered = try await store.recover(owner: owner)
        XCTAssertEqual(recovered.flatMap(\.items).map(\.id), [id])
        let saved = await session.commit(onStaged: { batch in delivered += batch.items.map(\.id); return true }, onLegacy: nil)
        XCTAssertTrue(saved)
        XCTAssertEqual(delivered, [id, id])
        XCTAssertTrue(session.photos.isEmpty)
        let afterSave = try await store.recover(owner: owner)
        XCTAssertTrue(afterSave.isEmpty)
    }

    @MainActor
    func testSuccessfulModelSaveWithFailedAcknowledgmentReplaysStableID() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writes = CameraAckFailure()
        let store = DurableCaptureStore(root: root.appendingPathComponent("Journal"), images: root.appendingPathComponent("Images"), writer: { try writes.write($0, to: $1) })
        let owner = StagedCaptureOwner(companyID: "company", userID: "user", contextID: "visit")
        let session = CameraCaptureSession(owner: owner, store: store)
        await session.prepare()
        let accepted = await session.capture(fixture())
        XCTAssertTrue(accepted)
        var durableArtifactIDs = Set<String>()
        let first = await session.commit(onStaged: { batch in durableArtifactIDs.formUnion(batch.items.map(\.id)); return true }, onLegacy: nil)
        XCTAssertFalse(first)
        XCTAssertEqual(session.photos.count, 1)
        let second = await session.commit(onStaged: { batch in durableArtifactIDs.formUnion(batch.items.map(\.id)); return true }, onLegacy: nil)
        XCTAssertTrue(second)
        XCTAssertEqual(durableArtifactIDs.count, 1)
    }

    @MainActor
    private func fixture() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).pngData { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }
    }
}

private final class CameraAckFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var manifests = 0
    func write(_ data: Data, to url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        if url.pathExtension == "json" { manifests += 1; if manifests == 4 { throw CocoaError(.fileWriteOutOfSpace) } }
        try data.write(to: url, options: .atomic)
    }
}
