import XCTest
@testable import OPS

@MainActor
final class SupplierBillCaptureQueueTests: XCTestCase {
    private var root: URL!
    private var source: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        source = root.appendingPathComponent("DeksMart-43066.pdf")
        try Data("%PDF-1.7\nCanpro supplier invoice".utf8).write(to: source)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testEnqueueCopiesOriginalIntoDurableQueueAndSurvivesRelaunch() throws {
        let queueDirectory = root.appendingPathComponent("queue", isDirectory: true)
        let queue = SupplierBillCaptureQueue(
            directoryURL: queueDirectory,
            idProvider: { "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA" },
            dateProvider: { Date(timeIntervalSince1970: 1_788_500_000.123_456) }
        )

        let item = try queue.enqueue(
            sourceURL: source,
            originalFilename: "DeksMart-43066.pdf",
            documentKind: .material,
            companyId: "canpro"
        )

        XCTAssertEqual(item.id, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        XCTAssertEqual(item.originalFilename, "DeksMart-43066.pdf")
        XCTAssertEqual(item.documentKind, .material)
        XCTAssertEqual(item.companyId, "canpro")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(queue.documentURL(for: item)).path))

        let reloaded = SupplierBillCaptureQueue(directoryURL: queueDirectory)
        XCTAssertEqual(try reloaded.loadQueue(), [item])
    }

    func testRemoveDeletesManifestEntryAndItsPrivatePDFOnlyAfterConfirmation() throws {
        let queue = SupplierBillCaptureQueue(
            directoryURL: root.appendingPathComponent("queue", isDirectory: true),
            idProvider: { "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB" }
        )
        let item = try queue.enqueue(
            sourceURL: source,
            originalFilename: "invoice.pdf",
            documentKind: .subcontractor,
            companyId: "canpro"
        )
        let persistedURL = try XCTUnwrap(queue.documentURL(for: item))

        XCTAssertTrue(FileManager.default.fileExists(atPath: persistedURL.path))
        try queue.remove(item)

        XCTAssertTrue(try queue.loadQueue().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: persistedURL.path))
    }

    func testEnqueueRejectsAFileThatOnlyPretendsToBeAPDF() throws {
        let fake = root.appendingPathComponent("fake.pdf")
        try Data("not a pdf".utf8).write(to: fake)
        let queue = SupplierBillCaptureQueue(
            directoryURL: root.appendingPathComponent("queue", isDirectory: true)
        )

        XCTAssertThrowsError(
            try queue.enqueue(
                sourceURL: fake,
                originalFilename: "fake.pdf",
                documentKind: .material,
                companyId: "canpro"
            )
        ) { error in
            XCTAssertEqual(error as? SupplierBillCaptureQueueError, .invalidPDF)
        }
        XCTAssertTrue(try queue.loadQueue().isEmpty)
    }

    func testCompanyScopedLoadNeverHandsAnotherCompanyItsCapture() throws {
        var ids = ["canpro-bill", "other-bill"].makeIterator()
        let queue = SupplierBillCaptureQueue(
            directoryURL: root.appendingPathComponent("queue", isDirectory: true),
            idProvider: { ids.next()! }
        )

        let canpro = try queue.enqueue(
            sourceURL: source,
            originalFilename: "canpro.pdf",
            documentKind: .material,
            companyId: "canpro"
        )
        _ = try queue.enqueue(
            sourceURL: source,
            originalFilename: "other.pdf",
            documentKind: .material,
            companyId: "other-company"
        )

        XCTAssertEqual(try queue.loadQueue(companyId: "canpro"), [canpro])
    }
}
