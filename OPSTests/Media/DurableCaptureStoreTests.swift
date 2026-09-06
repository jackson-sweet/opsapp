import XCTest
import UIKit
import ImageIO
@testable import OPS

final class DurableCaptureStoreTests: XCTestCase {
    private var scratch: URL!
    private let owner = StagedCaptureOwner(companyID: "COMPANY-A", userID: "USER-A", contextID: "VISIT-A")
    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: scratch) }
    private func store(writer: @escaping DurableCaptureStore.Writer = { try $0.write(to: $1, options: .atomic) }) -> DurableCaptureStore {
        DurableCaptureStore(root: scratch.appendingPathComponent("Journal"), images: scratch.appendingPathComponent("Images"), writer: writer)
    }
    private func file(_ id: String) -> URL { scratch.appendingPathComponent("Images").appendingPathComponent((id as NSString).lastPathComponent) }

    func testReopenRetainsOriginalAndRecoversOnlyExactOwnerUntilAcknowledged() async throws {
        let data = await fixture()
        let first = store()
        let batch = try await first.create(owner: owner)
        let item = try await first.stage(data: data, batchID: batch.id)
        let reopened = store()
        let recovered = try await reopened.recover(owner: owner)
        XCTAssertEqual(recovered.first?.items, [item])
        XCTAssertEqual(try Data(contentsOf: file(item.originalLocalURL)), data)
        for other in [
            StagedCaptureOwner(companyID: "different", userID: "user-a", contextID: "visit-a"),
            StagedCaptureOwner(companyID: "company-a", userID: "different", contextID: "visit-a"),
            StagedCaptureOwner(companyID: "company-a", userID: "user-a", contextID: "different")
        ] {
            let foreign = try await reopened.recover(owner: other)
            XCTAssertTrue(foreign.isEmpty)
        }
        try await reopened.acknowledge(batchID: batch.id, itemIDs: [item.id])
        try await reopened.acknowledge(batchID: batch.id, itemIDs: [item.id])
        let afterAck = try await store().recover(owner: owner)
        XCTAssertTrue(afterAck.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file(item.localURL).path))
        XCTAssertEqual(try Data(contentsOf: file(item.originalLocalURL)), data)
        do {
            try await reopened.discard(batchID: batch.id, itemIDs: [item.id])
            XCTFail("Acknowledged model-owned bytes must not be discarded by the camera")
        } catch {}
    }

    func testInterruptedJPEGWriteRepairsFromOriginalWithoutChangingIdentity() async throws {
        let data = await fixture()
        let failing = store { data, url in
            if url.pathExtension == "jpg" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
        let batch = try await failing.create(owner: owner)
        let id = UUID().uuidString.lowercased()
        do { _ = try await failing.stage(data: data, batchID: batch.id, itemID: id); XCTFail("Expected disk failure") }
        catch {}
        let recovered = try await store().recover(owner: owner)
        let item = try XCTUnwrap(recovered.first?.items.first)
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(try Data(contentsOf: file(item.originalLocalURL)), data)
        XCTAssertNotNil(UIImage(contentsOfFile: file(item.localURL).path))
    }

    func testInvalidSiblingDoesNotHideValidCaptureAndDiscardCannotResurrect() async throws {
        let journal = store()
        let batch = try await journal.create(owner: owner)
        let good = try await journal.stage(data: await fixture(), batchID: batch.id)
        let badID = UUID().uuidString.lowercased()
        do { _ = try await journal.stage(data: Data("invalid-image".utf8), batchID: batch.id, itemID: badID); XCTFail("Expected invalid image") }
        catch {}
        let recovered = try await store().recover(owner: owner)
        XCTAssertEqual(recovered.flatMap(\.items).map(\.id), [good.id])
        let failures = try await store().failedItems(owner: owner)
        XCTAssertEqual(failures.flatMap(\.items).map(\.id), [badID])
        try await journal.discard(batchID: batch.id, itemIDs: [badID])
        let remainingFailures = try await store().failedItems(owner: owner)
        XCTAssertTrue(remainingFailures.isEmpty)
        do { _ = try await journal.stage(data: await fixture(), batchID: batch.id, itemID: badID); XCTFail("Discard is durable") }
        catch {}
    }

    func testFinalManifestFailureStillRecoversBankedPhoto() async throws {
        let gate = ManifestWriteFailure()
        let journal = store { data, url in try gate.write(data, to: url) }
        let batch = try await journal.create(owner: owner)
        do { _ = try await journal.stage(data: await fixture(), batchID: batch.id); XCTFail("Expected manifest failure") }
        catch {}
        let recovered = try await store().recover(owner: owner)
        XCTAssertEqual(recovered.flatMap(\.items).count, 1)
    }

    @MainActor
    private func fixture() -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40), format: format).pngData { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        }
    }
}

private final class ManifestWriteFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func write(_ data: Data, to url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        if url.pathExtension == "json" { count += 1; if count == 3 { throw CocoaError(.fileWriteOutOfSpace) } }
        try data.write(to: url, options: .atomic)
    }
}
