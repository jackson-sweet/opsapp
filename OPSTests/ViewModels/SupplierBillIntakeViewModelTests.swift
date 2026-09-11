import XCTest
@testable import OPS

@MainActor
final class SupplierBillIntakeViewModelTests: XCTestCase {
    private var root: URL!
    private var source: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        source = root.appendingPathComponent("bill.pdf")
        try Data("%PDF-1.7\nCanpro invoice".utf8).write(to: source)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testOfflineCaptureStaysDurableAndCompanyScoped() async throws {
        let service = SupplierBillIntakeServiceSpy(captureError: URLError(.notConnectedToInternet))
        let queue = SupplierBillCaptureQueue(
            directoryURL: root.appendingPathComponent("queue", isDirectory: true),
            idProvider: { "offline-bill" }
        )
        let viewModel = SupplierBillIntakeViewModel(service: service, queue: queue)
        viewModel.setup(companyId: "canpro")

        let result = try await viewModel.capture(
            sourceURL: source,
            originalFilename: "bill.pdf",
            documentKind: .material
        )

        XCTAssertEqual(result, .queued)
        XCTAssertEqual(viewModel.pendingCaptureCount, 1)
        XCTAssertEqual(try queue.loadQueue(companyId: "canpro").map(\.id), ["offline-bill"])
        XCTAssertTrue(try queue.loadQueue(companyId: "other-company").isEmpty)
    }

    func testConfirmedUploadRemovesPrivateQueueCopyAndAddsBill() async throws {
        let detail = SupplierBillIntakeDetail.fixture(id: "uploaded-bill", companyId: "canpro")
        let service = SupplierBillIntakeServiceSpy(captureResult: detail)
        let queue = SupplierBillCaptureQueue(
            directoryURL: root.appendingPathComponent("queue", isDirectory: true),
            idProvider: { "uploaded-bill" }
        )
        let viewModel = SupplierBillIntakeViewModel(service: service, queue: queue)
        viewModel.setup(companyId: "canpro")

        let result = try await viewModel.capture(
            sourceURL: source,
            originalFilename: "bill.pdf",
            documentKind: .material
        )

        XCTAssertEqual(result, .uploaded(detail))
        XCTAssertEqual(viewModel.pendingCaptureCount, 0)
        XCTAssertEqual(viewModel.bills.map(\.id), ["uploaded-bill"])
        XCTAssertTrue(try queue.loadQueue(companyId: "canpro").isEmpty)
    }

    func testRejectedCaptureStaysSavedButSurfacesRequiredAttention() async throws {
        let service = SupplierBillIntakeServiceSpy(
            captureError: SupplierBillIntakeServiceError.rejected("This PDF is encrypted.")
        )
        let queue = SupplierBillCaptureQueue(
            directoryURL: root.appendingPathComponent("queue", isDirectory: true),
            idProvider: { "rejected-bill" }
        )
        let viewModel = SupplierBillIntakeViewModel(service: service, queue: queue)
        viewModel.setup(companyId: "canpro")

        let result = try await viewModel.capture(
            sourceURL: source,
            originalFilename: "bill.pdf",
            documentKind: .material
        )

        XCTAssertEqual(result, .needsAttention("This PDF is encrypted."))
        XCTAssertEqual(viewModel.pendingCaptureCount, 1)
        XCTAssertEqual(try queue.loadQueue(companyId: "canpro").map(\.id), ["rejected-bill"])
    }

    func testCachedBillsAndDetailRemainReadableWhenRefreshIsOffline() async throws {
        let detail = SupplierBillIntakeDetail.fixture(id: "cached-bill", companyId: "canpro")
        let cache = SupplierBillCache(
            directoryURL: root.appendingPathComponent("cache", isDirectory: true)
        )
        try cache.saveBills([detail.intake], companyId: "canpro")
        try cache.saveDetail(detail, companyId: "canpro")
        let service = SupplierBillIntakeServiceSpy(listError: URLError(.notConnectedToInternet))
        let queue = SupplierBillCaptureQueue(
            directoryURL: root.appendingPathComponent("queue", isDirectory: true)
        )
        let viewModel = SupplierBillIntakeViewModel(
            service: service,
            queue: queue,
            cache: cache
        )

        viewModel.setup(companyId: "canpro")
        await viewModel.load()
        await viewModel.loadDetail(intakeId: detail.intake.id)

        XCTAssertEqual(viewModel.bills, [detail.intake])
        XCTAssertEqual(viewModel.selectedDetail, detail)
        XCTAssertTrue(viewModel.isUsingCachedData)
    }
}

@MainActor
private final class SupplierBillIntakeServiceSpy: SupplierBillIntakeServicing {
    let captureResult: SupplierBillIntakeDetail?
    let captureError: Error?
    let listError: Error?

    init(
        captureResult: SupplierBillIntakeDetail? = nil,
        captureError: Error? = nil,
        listError: Error? = nil
    ) {
        self.captureResult = captureResult
        self.captureError = captureError
        self.listError = listError
    }

    func list(stage: SupplierBillStage?) async throws -> [SupplierBillIntake] {
        if let listError { throw listError }
        return []
    }

    func detail(intakeId: String) async throws -> SupplierBillIntakeDetail {
        if let listError { throw listError }
        return try XCTUnwrap(captureResult)
    }

    func capture(job: QueuedSupplierBillCapture, documentURL: URL) async throws -> SupplierBillIntakeDetail {
        if let captureError { throw captureError }
        return try XCTUnwrap(captureResult)
    }
}

private extension SupplierBillIntakeDetail {
    static func fixture(id: String, companyId: String) -> SupplierBillIntakeDetail {
        SupplierBillIntakeDetail(
            intake: SupplierBillIntake(
                id: id,
                companyId: companyId,
                documentKind: .material,
                reviewStage: .review,
                supplierName: "DEKSMART",
                invoiceNumber: "43066",
                invoiceDate: "2025-12-09",
                dueDate: nil,
                currency: "CAD",
                total: "2378.46",
                paymentOwnerId: nil,
                plannedPaymentDate: nil,
                holdReason: nil,
                nextAction: nil,
                revision: 1,
                createdAt: "2026-09-04T07:00:00.000Z",
                updatedAt: "2026-09-04T07:00:00.000Z",
                promotedBillId: nil,
                subtotal: nil,
                taxTotal: nil,
                purchaseOrder: nil,
                shippingReference: nil,
                categoryId: nil,
                approvedAt: nil,
                paidAt: nil,
                supplierBills: nil
            ),
            lines: [],
            checks: [],
            document: nil,
            events: []
        )
    }
}
