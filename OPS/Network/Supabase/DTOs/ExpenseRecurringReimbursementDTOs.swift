//
//  ExpenseRecurringReimbursementDTOs.swift
//  OPS
//
//  Recurring reimbursements — `expense_recurring_reimbursements` rows and the
//  one line per month they file into `expenses`. Rows are written only through
//  the SECURITY DEFINER commands (create / update / end / delete, skip /
//  restore a month); every command returns the setup with all of its months.
//

import Foundation

// MARK: - Month line

/// One month a recurring reimbursement filed. A skipped month (and every month
/// of a deleted setup) stays as a tombstone with `deleted = true`, so the
/// database never files that month again.
struct RecurringLineSummary: Codable, Equatable, Identifiable {
    let expenseId: String
    /// First day (`yyyy-MM-01`) of the month the line pays for.
    let period: String
    let batchId: String?
    let status: String
    let amount: Double
    let deleted: Bool

    var id: String { expenseId }

    enum CodingKeys: String, CodingKey {
        case expenseId = "expense_id"
        case period
        case batchId   = "batch_id"
        case status
        case amount
        case deleted
    }
}

/// An `expenses` row read for its recurring month (the table path — the
/// command payload already carries `RecurringLineSummary`).
struct RecurringLineRowDTO: Decodable, Equatable {
    let id: String
    let recurringReimbursementId: String
    let recurringPeriod: String
    let batchId: String?
    let status: String
    let amount: Double
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case recurringReimbursementId = "recurring_reimbursement_id"
        case recurringPeriod          = "recurring_period"
        case batchId                  = "batch_id"
        case status
        case amount
        case deletedAt                = "deleted_at"
    }

    var summary: RecurringLineSummary {
        RecurringLineSummary(
            expenseId: id,
            period: recurringPeriod,
            batchId: batchId,
            status: status,
            amount: amount,
            deleted: deletedAt != nil
        )
    }

    static let selectColumns = "id,recurring_reimbursement_id,recurring_period,batch_id,status,amount,deleted_at"
}

// MARK: - Setup

/// A fixed monthly amount the office pays a crew member with their expenses.
struct ExpenseRecurringReimbursementDTO: Codable, Equatable, Identifiable {
    let id: String
    let companyId: String
    /// The crew member paid.
    let userId: String
    let name: String
    let amount: Double
    let currency: String
    let categoryId: String?
    let firstPeriod: String
    /// Last month paid; nil while it runs until ended.
    let lastPeriod: String?
    /// First month the database has not yet considered.
    let nextPeriod: String
    let createdBy: String
    let updatedBy: String
    let createdAt: String
    /// Optimistic-concurrency token for every command. Passed back verbatim —
    /// a Date round-trip would drop the microseconds the server compares.
    let updatedAt: String
    let deletedAt: String?
    let deletedBy: String?
    /// Every month's line, oldest first. Empty on a bare table read until the
    /// months are joined in.
    var lines: [RecurringLineSummary]

    enum CodingKeys: String, CodingKey {
        case id
        case companyId   = "company_id"
        case userId      = "user_id"
        case name
        case amount
        case currency
        case categoryId  = "category_id"
        case firstPeriod = "first_period"
        case lastPeriod  = "last_period"
        case nextPeriod  = "next_period"
        case createdBy   = "created_by"
        case updatedBy   = "updated_by"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
        case deletedAt   = "deleted_at"
        case deletedBy   = "deleted_by"
        case lines
    }

    init(
        id: String,
        companyId: String,
        userId: String,
        name: String,
        amount: Double,
        currency: String,
        categoryId: String? = nil,
        firstPeriod: String,
        lastPeriod: String? = nil,
        nextPeriod: String,
        createdBy: String,
        updatedBy: String,
        createdAt: String,
        updatedAt: String,
        deletedAt: String? = nil,
        deletedBy: String? = nil,
        lines: [RecurringLineSummary] = []
    ) {
        self.id = id
        self.companyId = companyId
        self.userId = userId
        self.name = name
        self.amount = amount
        self.currency = currency
        self.categoryId = categoryId
        self.firstPeriod = firstPeriod
        self.lastPeriod = lastPeriod
        self.nextPeriod = nextPeriod
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.deletedBy = deletedBy
        self.lines = lines
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        companyId = try container.decode(String.self, forKey: .companyId)
        userId = try container.decode(String.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Double.self, forKey: .amount)
        currency = try container.decode(String.self, forKey: .currency)
        categoryId = try container.decodeIfPresent(String.self, forKey: .categoryId)
        firstPeriod = try container.decode(String.self, forKey: .firstPeriod)
        lastPeriod = try container.decodeIfPresent(String.self, forKey: .lastPeriod)
        nextPeriod = try container.decode(String.self, forKey: .nextPeriod)
        createdBy = try container.decode(String.self, forKey: .createdBy)
        updatedBy = try container.decode(String.self, forKey: .updatedBy)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        deletedBy = try container.decodeIfPresent(String.self, forKey: .deletedBy)
        lines = (try container.decodeIfPresent([RecurringLineSummary].self, forKey: .lines) ?? [])
            .sorted { $0.period < $1.period }
    }

    /// The same setup with its months replaced (table path join).
    func withLines(_ lines: [RecurringLineSummary]) -> ExpenseRecurringReimbursementDTO {
        var copy = self
        copy.lines = lines.sorted { $0.period < $1.period }
        return copy
    }
}

/// Everything the app needs to manage a company's recurring reimbursements.
struct RecurringReimbursementsSnapshot: Equatable {
    var setups: [ExpenseRecurringReimbursementDTO]
    /// Company currency — the database files every new setup in it.
    var currency: String
    /// Company time zone — months follow the company's calendar.
    var timeZone: String?

    func setup(id: String?) -> ExpenseRecurringReimbursementDTO? {
        guard let id = id?.lowercased() else { return nil }
        return setups.first { $0.id.lowercased() == id }
    }
}

// MARK: - Command parameters

/// `create_expense_recurring_reimbursement`. The category is sent as an
/// explicit null so PostgREST always resolves the one signature.
struct CreateRecurringReimbursementParams: Encodable, Equatable {
    let userId: String
    let name: String
    let amount: Double
    let firstPeriod: String
    let categoryId: String?

    enum CodingKeys: String, CodingKey {
        case userId      = "p_user_id"
        case name        = "p_name"
        case amount      = "p_amount"
        case firstPeriod = "p_first_period"
        case categoryId  = "p_category_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(name, forKey: .name)
        try container.encode(amount, forKey: .amount)
        try container.encode(firstPeriod, forKey: .firstPeriod)
        try container.encodeOrNull(categoryId, forKey: .categoryId)
    }
}

/// `update_expense_recurring_reimbursement`. Every parameter is required by
/// the signature, so a cleared category is an explicit null.
struct UpdateRecurringReimbursementParams: Encodable, Equatable {
    let id: String
    let name: String
    let amount: Double
    let categoryId: String?
    let expectedUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case id                = "p_id"
        case name              = "p_name"
        case amount            = "p_amount"
        case categoryId        = "p_category_id"
        case expectedUpdatedAt = "p_expected_updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(amount, forKey: .amount)
        try container.encodeOrNull(categoryId, forKey: .categoryId)
        try container.encode(expectedUpdatedAt, forKey: .expectedUpdatedAt)
    }
}

/// `end_expense_recurring_reimbursement`. A null last month removes the end.
struct EndRecurringReimbursementParams: Encodable, Equatable {
    let id: String
    let lastPeriod: String?
    let expectedUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case id                = "p_id"
        case lastPeriod        = "p_last_period"
        case expectedUpdatedAt = "p_expected_updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeOrNull(lastPeriod, forKey: .lastPeriod)
        try container.encode(expectedUpdatedAt, forKey: .expectedUpdatedAt)
    }
}

/// `delete_expense_recurring_reimbursement`.
struct DeleteRecurringReimbursementParams: Encodable, Equatable {
    let id: String
    let expectedUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case id                = "p_id"
        case expectedUpdatedAt = "p_expected_updated_at"
    }
}

/// `skip_expense_recurring_reimbursement_line` / `restore_…_line`.
struct RecurringLineCommandParams: Encodable, Equatable {
    let expenseId: String

    enum CodingKeys: String, CodingKey {
        case expenseId = "p_expense_id"
    }
}

private extension KeyedEncodingContainer {
    /// Encodes nil as JSON null instead of omitting the key.
    mutating func encodeOrNull<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
