import XCTest
import UIKit
@testable import OPS

final class LeadImageStagerTests: XCTestCase {
    private var root: URL!
    private var photos: [PendingLeadImageUpload] = []
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        for photo in photos {
            _ = ImageFileManager.shared.deleteImage(localID: photo.localURL)
            if let original = photo.originalLocalURL { _ = ImageFileManager.shared.deleteImage(localID: original) }
        }
        photos = []
    }

    func testJournalRecoversExactOwnerAndKeepsRemoteReceiptUntilMerge() async throws {
        let item = pending()
        let stager = LeadImageStager(root: root)
        _ = try await stager.stage(await fixture(), pending: item)
        let recorded = try await stager.recordRemote(item, url: "https://example.test/uploaded.jpg")
        let reopened = LeadImageStager(root: root)
        let recovered = try await reopened.recover(companyID: "company", userID: "user")
        XCTAssertEqual(recovered, [recorded])
        let fromStaleQueue = try await reopened.current(item)
        XCTAssertEqual(fromStaleQueue.uploadedURL, recorded.uploadedURL, "Journal receipt outranks stale UserDefaults")
        XCTAssertTrue(ImageFileManager.shared.imageExists(localID: item.localURL))
        let foreign = try await reopened.recover(companyID: "company", userID: "different")
        XCTAssertTrue(foreign.isEmpty)
        try await reopened.finish(recorded)
        let active = try await reopened.isActive(item)
        XCTAssertFalse(active, "A stale UserDefaults queue must not revive a finished/deleted item")
        let afterFinish = try await LeadImageStager(root: root).recover(companyID: "company", userID: "user")
        XCTAssertTrue(afterFinish.isEmpty)
    }

    func testJPEGFailureKeepsOriginalAndReopenRepairsIt() async throws {
        let item = pending()
        let target = try XCTUnwrap(ImageFileManager.shared.getFileURL(for: item.localURL))
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let stager = LeadImageStager(root: root)
        do { _ = try await stager.stage(await fixture(), pending: item); XCTFail("Expected a failed JPEG write") }
        catch {}
        let originalExists = await stager.hasOriginal(item)
        XCTAssertTrue(originalExists)
        try FileManager.default.removeItem(at: target)
        let recovered = try await LeadImageStager(root: root).recover(companyID: "company", userID: "user")
        XCTAssertEqual(recovered.map(\.id), [item.id])
        let data = try await stager.uploadData(item)
        XCTAssertNotNil(data.flatMap { UIImage(data: $0) })
    }

    func testJournalDiskFailureCannotReportQueuedOrLeaveUntrackedImage() async throws {
        try Data([1]).write(to: root)
        let stager = LeadImageStager(root: root)
        let item = pending()
        do { _ = try await stager.stage(await fixture(), pending: item); XCTFail("Expected journal failure") }
        catch {}
        XCTAssertFalse(ImageFileManager.shared.imageExists(localID: item.localURL))
        XCTAssertFalse(ImageFileManager.shared.imageExists(localID: try XCTUnwrap(item.originalLocalURL)))
    }

    private func pending() -> PendingLeadImageUpload {
        let id = UUID().uuidString.lowercased()
        let item = PendingLeadImageUpload(localURL: "local://project_images/lead_test_\(id).jpg", opportunityId: "lead", companyId: "company", timestamp: Date(), displayID: id, batchIndex: 0, journalID: id, originalLocalURL: "local://project_images/lead_test_\(id).original", userID: "user")
        photos.append(item)
        return item
    }
    @MainActor
    private func fixture() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }
    }
}
