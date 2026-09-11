import SwiftData
import XCTest
@testable import OPS

@MainActor
final class PhotoProcessorSuspensionTests: XCTestCase {
    func testExpiredUploadResponseStaysRetryableAndResumesOnce() async throws {
        let schema = Schema([LocalPhoto.self])
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let relativePath = "suspension-fixture-\(UUID().uuidString).jpg"
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(relativePath)
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let photo = LocalPhoto(companyId: "suspension-company", entityType: "project", entityId: "suspension-project", localPath: relativePath, fileSize: 3)
        photo.uploadRetryCount = 19
        container.mainContext.insert(photo)
        try container.mainContext.save()
        let entered = expectation(description: "upload response held")
        let uploader = SuspensionPhotoUploader(entered: entered)
        let processor = PhotoProcessor(uploadService: uploader)
        let allowance = ControlledSyncAllowance()
        let execution = SyncExecutionCoordinator(allowance: allowance)
        let first = Task {
            try await execution.run(name: "photos") {
                await processor.processUploadQueue(context: container.mainContext, connectivity: SuspensionPhotoConnectivity())
            }
        }
        await fulfillment(of: [entered], timeout: 3)
        allowance.expire()
        await uploader.gate.release()
        do { try await first.value; XCTFail("Expired upload reported completion") }
        catch { XCTAssertTrue(error is CancellationError) }
        let interruptedContext = ModelContext(container)
        let interrupted = try XCTUnwrap(interruptedContext.fetch(FetchDescriptor<LocalPhoto>()).first)
        XCTAssertEqual(interrupted.status, "uploading")
        XCTAssertNil(interrupted.uploadedURL)
        XCTAssertTrue(interrupted.needsSync)

        try await execution.run(name: "photos-resumed") {
            await processor.processUploadQueue(context: container.mainContext, connectivity: SuspensionPhotoConnectivity())
        }
        let reloadedContext = ModelContext(container)
        let reloaded = try XCTUnwrap(reloadedContext.fetch(FetchDescriptor<LocalPhoto>()).first)
        XCTAssertEqual(reloaded.status, "uploaded")
        XCTAssertEqual(reloaded.uploadedURL, "https://example.invalid/photo.jpg")
        XCTAssertEqual(uploader.calls, 2)
        XCTAssertEqual(reloaded.uploadRetryCount, 20, "Suspension must not consume another attempt")
    }

    func testRetiredProcessorDoesNotTouchDeletedPhotoAfterUploadReturns() async throws {
        let schema = Schema([LocalPhoto.self])
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let relativePath = "suspension-retired-\(UUID().uuidString).jpg"
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(relativePath)
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let photo = LocalPhoto(companyId: "old-company", entityType: "project", entityId: "old-project", localPath: relativePath, fileSize: 3)
        container.mainContext.insert(photo)
        try container.mainContext.save()
        let entered = expectation(description: "old account upload held")
        let uploader = SuspensionPhotoUploader(entered: entered)
        let processor = PhotoProcessor(uploadService: uploader)
        let upload = Task {
            await processor.processUploadQueue(context: container.mainContext, connectivity: SuspensionPhotoConnectivity())
        }
        await fulfillment(of: [entered], timeout: 3)
        processor.invalidate()
        container.mainContext.delete(photo)
        try container.mainContext.save()
        await uploader.gate.release()
        await upload.value
        let readback = ModelContext(container)
        XCTAssertTrue(try readback.fetch(FetchDescriptor<LocalPhoto>()).isEmpty)
        XCTAssertEqual(uploader.calls, 1)
    }
}

@MainActor
private final class SuspensionPhotoUploader: PhotoDataUploading {
    let gate = SyncExecutionTestGate()
    private let entered: XCTestExpectation
    private(set) var calls = 0
    init(entered: XCTestExpectation) { self.entered = entered }
    func uploadImageData(_ data: Data, filename: String, folder: String) async throws -> String {
        calls += 1
        if calls == 1 { entered.fulfill(); await gate.wait() }
        return "https://example.invalid/photo.jpg"
    }
}

@MainActor
private final class SuspensionPhotoConnectivity: ConnectivityManager {
    override var shouldUploadPhotos: Bool { true }
}
