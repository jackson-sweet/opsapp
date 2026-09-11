import XCTest
@testable import OPS

@MainActor
final class SupplierBillCacheTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testBillsAndDetailSurviveRelaunchWithoutCrossingCompanies() throws {
        let canproBill = SupplierBillIntake.cacheFixture(id: "canpro-bill", companyId: "canpro")
        let detail = SupplierBillIntakeDetail(
            intake: canproBill,
            lines: [],
            checks: [],
            document: nil,
            events: []
        )
        let first = SupplierBillCache(directoryURL: root)
        try first.saveBills([canproBill], companyId: "canpro")
        try first.saveDetail(detail, companyId: "canpro")

        let relaunched = SupplierBillCache(directoryURL: root)

        XCTAssertEqual(try relaunched.loadBills(companyId: "canpro"), [canproBill])
        XCTAssertEqual(try relaunched.loadDetail(intakeId: canproBill.id, companyId: "canpro"), detail)
        XCTAssertTrue(try relaunched.loadBills(companyId: "other-company").isEmpty)
        XCTAssertNil(try relaunched.loadDetail(intakeId: canproBill.id, companyId: "other-company"))
    }
}

private extension SupplierBillIntake {
    static func cacheFixture(id: String, companyId: String) -> SupplierBillIntake {
        SupplierBillIntake(
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
        )
    }
}
