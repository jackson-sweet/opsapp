import XCTest
@testable import OPS

final class SupplierBillIntakeModelTests: XCTestCase {
    func testCanproStagesKeepEmployeeInvoicesOutsideAccountsPayable() {
        XCTAssertEqual(SupplierBillStage.allCases.map(\.rawValue), [
            "review", "to_pay", "paid", "held", "payroll"
        ])
        XCTAssertEqual(SupplierDocumentKind.employee.destinationStage, .payroll)
        XCTAssertEqual(SupplierDocumentKind.material.destinationStage, .review)
        XCTAssertEqual(SupplierDocumentKind.subcontractor.destinationStage, .review)
    }

    func testBillFilterCountsOnlyItsLifecycleStage() {
        let bills = [
            SupplierBillIntake.fixture(id: "a", stage: .review),
            SupplierBillIntake.fixture(id: "b", stage: .review),
            SupplierBillIntake.fixture(id: "c", stage: .held),
        ]

        XCTAssertEqual(SupplierBillStage.review.count(in: bills), 2)
        XCTAssertEqual(SupplierBillStage.held.count(in: bills), 1)
        XCTAssertEqual(SupplierBillStage.paid.count(in: bills), 0)
    }
}

private extension SupplierBillIntake {
    static func fixture(id: String, stage: SupplierBillStage) -> SupplierBillIntake {
        SupplierBillIntake(
            id: id,
            companyId: "company",
            documentKind: .material,
            reviewStage: stage,
            supplierName: "Supplier",
            invoiceNumber: id,
            invoiceDate: "2026-09-04",
            dueDate: nil,
            currency: "CAD",
            total: "100.00",
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
