import Foundation

/// A correction is an explicit review command. It cannot carry receipt/OCR,
/// approval, payment, accounting, or submit fields from an ordinary save.
struct ExpenseCorrectionCommand: Encodable, Equatable {
    let content: ExpenseAtomicSaveCommand
    let actorId: String
    let correctionNote: String

    var requestId: String { content.requestId }

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id", expenseId = "expense_id", companyId = "company_id"
        case actorId = "actor_id", submittedBy = "submitted_by"
        case expectedStatus = "expected_status", expectedUpdatedAt = "expected_updated_at"
        case categoryId = "category_id", merchantName = "merchant_name", description
        case amount, taxAmount = "tax_amount", currency, expenseDate = "expense_date"
        case paymentMethod = "payment_method", projectMissingReason = "project_missing_reason"
        case projectMissingNote = "project_missing_note", allocations, correctionNote = "correction_note"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(content.requestId, forKey: .requestId)
        try c.encode(content.expenseId, forKey: .expenseId)
        try c.encode(content.companyId, forKey: .companyId)
        try c.encode(actorId, forKey: .actorId)
        try c.encode(content.submittedBy, forKey: .submittedBy)
        try c.encode(content.expectedStatus, forKey: .expectedStatus)
        try c.encode(content.expectedUpdatedAt, forKey: .expectedUpdatedAt)
        try c.encode(content.categoryId, forKey: .categoryId)
        try c.encode(content.merchantName, forKey: .merchantName)
        try c.encode(content.description, forKey: .description)
        try c.encode(content.amount, forKey: .amount)
        try c.encode(content.taxAmount, forKey: .taxAmount)
        try c.encode(content.currency, forKey: .currency)
        try c.encode(content.expenseDate, forKey: .expenseDate)
        try c.encode(content.paymentMethod, forKey: .paymentMethod)
        try c.encode(content.projectMissingReason, forKey: .projectMissingReason)
        try c.encode(content.projectMissingNote, forKey: .projectMissingNote)
        try c.encode(content.allocations, forKey: .allocations)
        try c.encode(correctionNote, forKey: .correctionNote)
    }

    func hasSameIntent(as other: Self) -> Bool {
        actorId == other.actorId && correctionNote == other.correctionNote
            && content.hasSameIntent(as: other.content)
    }
}

struct ExpenseCorrectionSnapshot: Decodable, Equatable {
    struct Allocation: Decodable, Equatable {
        let projectId: String
        let projectTitle: String?
        let percentage: Double
        let amount: Double?
        enum CodingKeys: String, CodingKey {
            case projectId = "project_id", projectTitle = "project_title", percentage, amount
        }
    }
    let status: String
    let updatedAt: String
    let categoryId: String?
    let categoryName: String?
    let merchantName: String?
    let description: String?
    let amount: Double
    let taxAmount: Double?
    let currency: String?
    let expenseDate: String?
    let paymentMethod: String?
    let projectMissingReason: String?
    let projectMissingNote: String?
    let allocations: [Allocation]

    enum CodingKeys: String, CodingKey {
        case status, updatedAt = "updated_at", categoryId = "category_id", categoryName = "category_name"
        case merchantName = "merchant_name", description, amount, taxAmount = "tax_amount", currency
        case expenseDate = "expense_date", paymentMethod = "payment_method"
        case projectMissingReason = "project_missing_reason", projectMissingNote = "project_missing_note", allocations
    }
}

struct ExpenseCorrectionDTO: Decodable, Identifiable {
    let id: String
    let requestId: String
    let expenseId: String
    let companyId: String
    let actorId: String
    let submittedBy: String
    let correctedAt: String
    let correctionNote: String
    let before: ExpenseCorrectionSnapshot
    let after: ExpenseCorrectionSnapshot

    enum CodingKeys: String, CodingKey {
        case id, requestId = "request_id", expenseId = "expense_id", companyId = "company_id"
        case actorId = "actor_id", submittedBy = "submitted_by", correctedAt = "corrected_at"
        case correctionNote = "correction_note", before, after
    }
}

struct ExpenseCorrectionReceipt: Decodable {
    let requestId: String
    let expenseId: String
    let companyId: String
    let actorId: String
    let submittedBy: String
    let replayed: Bool
    let correction: ExpenseCorrectionDTO

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id", expenseId = "expense_id", companyId = "company_id"
        case actorId = "actor_id", submittedBy = "submitted_by", replayed, correction
    }

    func matches(_ command: ExpenseCorrectionCommand) -> Bool {
        let identity = [requestId, expenseId, companyId, actorId, submittedBy].map { $0.lowercased() }
        let intended = [command.requestId, command.content.expenseId, command.content.companyId,
                        command.actorId, command.content.submittedBy].map { $0.lowercased() }
        let recorded = [correction.requestId, correction.expenseId, correction.companyId,
                        correction.actorId, correction.submittedBy].map { $0.lowercased() }
        guard identity == intended, recorded == intended,
              correction.id.lowercased() == requestId.lowercased(),
              UUID(uuidString: correction.id) != nil,
              let expectedRevision = command.content.expectedUpdatedAt,
              let expectedMicros = ExpenseCorrectionTimestamp.microseconds(expectedRevision),
              ExpenseCorrectionTimestamp.microseconds(correction.before.updatedAt) == expectedMicros,
              let afterMicros = ExpenseCorrectionTimestamp.microseconds(correction.after.updatedAt),
              afterMicros > expectedMicros,
              correction.before.status == command.content.expectedStatus,
              correction.after.status == ExpenseStatus.rejected.rawValue,
              correction.correctionNote == command.correctionNote else { return false }
        let after = correction.after, content = command.content
        let reason = content.allocations.isEmpty ? content.projectMissingReason.flatMap { $0.isEmpty ? nil : $0 } : nil
        let note = reason == nil ? nil : content.projectMissingNote.flatMap { $0.isEmpty ? nil : $0 }
        guard after.categoryId?.lowercased() == content.categoryId?.lowercased(),
              after.merchantName == content.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines),
              after.description == content.description, after.amount == content.amount,
              after.taxAmount == content.taxAmount, after.currency == content.currency,
              after.expenseDate == content.expenseDate, after.paymentMethod == content.paymentMethod,
              after.projectMissingReason == reason, after.projectMissingNote == note else { return false }
        let expectedAllocations = content.allocations.sorted { $0.projectId.lowercased() < $1.projectId.lowercased() }
        let recordedAllocations = after.allocations.sorted { $0.projectId.lowercased() < $1.projectId.lowercased() }
        guard expectedAllocations.count == recordedAllocations.count else { return false }
        return zip(expectedAllocations, recordedAllocations).allSatisfy {
            $0.projectId.lowercased() == $1.projectId.lowercased()
                && $0.percentage == $1.percentage && $0.amount == $1.amount
        }
    }
}

/// Compare database revisions without losing PostgreSQL's microseconds to
/// Date/Double conversion. Only whole seconds use Date; fractions stay integer.
enum ExpenseCorrectionTimestamp {
    static func microseconds(_ raw: String) -> Int64? {
        let pattern = #"^(.+T[0-9]{2}:[0-9]{2}:[0-9]{2})(?:\.([0-9]{1,6}))?(Z|[+-][0-9]{2}:[0-9]{2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let wholeRange = Range(match.range(at: 1), in: raw),
              let zoneRange = Range(match.range(at: 3), in: raw) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let whole = formatter.date(from: String(raw[wholeRange]) + String(raw[zoneRange])) else { return nil }
        let fraction = Range(match.range(at: 2), in: raw).map { String(raw[$0]) } ?? ""
        guard let micros = Int64(fraction + String(repeating: "0", count: 6 - fraction.count)) else { return nil }
        return Int64(whole.timeIntervalSince1970) * 1_000_000 + micros
    }
}
