import Foundation
import SwiftUI

enum SupplierDocumentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case material
    case subcontractor
    case employee

    var id: String { rawValue }

    var label: String {
        switch self {
        case .material: return "MATERIAL"
        case .subcontractor: return "SUBCONTRACTOR"
        case .employee: return "EMPLOYEE"
        }
    }

    var detail: String {
        switch self {
        case .material: return "Supplier materials and deliveries"
        case .subcontractor: return "Subcontractor labour and scope"
        case .employee: return "Route to payroll, outside payables"
        }
    }

    var destinationStage: SupplierBillStage {
        self == .employee ? .payroll : .review
    }
}

enum SupplierBillStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case review
    case toPay = "to_pay"
    case paid
    case held
    case payroll

    var id: String { rawValue }

    var label: String {
        switch self {
        case .review: return "REVIEW"
        case .toPay: return "TO PAY"
        case .paid: return "PAID"
        case .held: return "HELD"
        case .payroll: return "PAYROLL"
        }
    }

    var color: Color {
        switch self {
        case .review, .held: return OPSStyle.Colors.tan
        case .toPay: return OPSStyle.Colors.opsAccent
        case .paid: return OPSStyle.Colors.olive
        case .payroll: return OPSStyle.Colors.text2
        }
    }

    func count(in bills: [SupplierBillIntake]) -> Int {
        bills.lazy.filter { $0.reviewStage == self }.count
    }

    func matches(_ bill: SupplierBillIntake) -> Bool {
        bill.reviewStage == self
    }
}

enum SupplierBillCheckKey: String, Codable, CaseIterable, Sendable {
    case rateCompliance = "rate_compliance"
    case duplicateBilling = "duplicate_billing"
    case quantityScope = "quantity_scope"
    case orderSpecification = "order_specification"
    case receipt

    var label: String {
        switch self {
        case .rateCompliance: return "RATE COMPLIANCE"
        case .duplicateBilling: return "DUPLICATE BILLING"
        case .quantityScope: return "PLAN VS SITE"
        case .orderSpecification: return "ORDER + SPEC"
        case .receipt: return "RECEIPT"
        }
    }
}

enum SupplierBillCheckOutcome: String, Codable, Sendable {
    case pending
    case clear
    case exception
}

enum SupplierBillCheckDisposition: String, Codable, Sendable {
    case unresolved
    case accepted
    case held
}

struct SupplierBillBalance: Codable, Equatable, Sendable {
    let balance: String
    let status: String
}

struct SupplierBillIntake: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let companyId: String
    let documentKind: SupplierDocumentKind
    let reviewStage: SupplierBillStage
    let supplierName: String
    let invoiceNumber: String
    let invoiceDate: String
    let dueDate: String?
    let currency: String
    let total: String
    let paymentOwnerId: String?
    let plannedPaymentDate: String?
    let holdReason: String?
    let nextAction: String?
    let revision: Int
    let createdAt: String
    let updatedAt: String
    let promotedBillId: String?

    let subtotal: String?
    let taxTotal: String?
    let purchaseOrder: String?
    let shippingReference: String?
    let categoryId: String?
    let approvedAt: String?
    let paidAt: String?
    let supplierBills: SupplierBillBalance?

    var displaySupplier: String {
        supplierName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "SUPPLIER PENDING"
            : supplierName.uppercased()
    }

    var displayInvoiceNumber: String {
        invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "INVOICE PENDING"
            : "#\(invoiceNumber)"
    }
}

struct SupplierBillIntakeAllocation: Codable, Equatable, Sendable {
    let projectId: String
    let amount: String
    let allocationBasis: String
    let confirmedBy: String?
}

struct SupplierBillIntakeLine: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let position: Int
    let sku: String?
    let description: String
    let orderedQuantity: String?
    let invoicedQuantity: String
    let unitOfMeasure: String?
    let unitPrice: String
    let subtotal: String
    let taxAmount: String
    let total: String
    let categoryId: String?
    let jobHint: String?
    let matchBasis: String?
    let matchStatus: String
    let matchedProjectId: String?
    let supplierBillIntakeAllocations: [SupplierBillIntakeAllocation]
}

struct SupplierBillIntakeCheck: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let checkKey: SupplierBillCheckKey
    let outcome: SupplierBillCheckOutcome
    let disposition: SupplierBillCheckDisposition
    let observedValue: String?
    let policyLimit: String?
    let evidence: [String: SupplierBillJSONValue]
    let note: String?

    var color: Color {
        switch (outcome, disposition) {
        case (_, .held), (.exception, _): return OPSStyle.Colors.rose
        case (.clear, _), (_, .accepted): return OPSStyle.Colors.olive
        case (.pending, _): return OPSStyle.Colors.tan
        }
    }

    var statusLabel: String {
        switch disposition {
        case .accepted: return "ACCEPTED"
        case .held: return "HELD"
        case .unresolved: return outcome.rawValue.uppercased()
        }
    }
}

enum SupplierBillJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: SupplierBillJSONValue])
    case array([SupplierBillJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: SupplierBillJSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([SupplierBillJSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct SupplierBillIntakeDocument: Codable, Equatable, Sendable {
    let publicUrl: String
    let originalFilename: String
    let sizeBytes: Int64
}

struct SupplierBillIntakeEvent: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let action: String
    let actorUserId: String
    let createdAt: String
}

struct SupplierBillIntakeDetail: Codable, Equatable, Sendable {
    let intake: SupplierBillIntake
    let lines: [SupplierBillIntakeLine]
    let checks: [SupplierBillIntakeCheck]
    let document: SupplierBillIntakeDocument?
    let events: [SupplierBillIntakeEvent]
}
