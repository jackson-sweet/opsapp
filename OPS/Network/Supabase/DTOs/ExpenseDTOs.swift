//
//  ExpenseDTOs.swift
//  OPS
//
//  Data Transfer Objects for Expense Supabase tables.
//

import Foundation

// MARK: - Expense DTOs

struct ExpenseDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let submittedBy: String
    let status: String
    let categoryId: String?
    let merchantName: String?
    let description: String?
    let amount: Double
    let taxAmount: Double?
    let currency: String?
    let expenseDate: String?
    let paymentMethod: String?
    let receiptImageUrl: String?
    let receiptThumbnailUrl: String?
    let receiptMissingReason: String?
    let receiptMissingNote: String?
    let projectMissingReason: String?
    let projectMissingNote: String?
    let ocrRawData: [String: String]?
    let ocrConfidence: Double?
    let batchId: String?
    let approvedBy: String?
    let approvedAt: String?
    let rejectedBy: String?
    let rejectedAt: String?
    let rejectionReason: String?
    let flagComment: String?
    let flaggedBy: String?
    let flaggedAt: String?
    let accountingSyncStatus: String?
    let accountingSyncId: String?
    let accountingSyncedAt: String?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let allocations: [ExpenseAllocationDTO]?
    let category: ExpenseCategoryDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId            = "company_id"
        case submittedBy          = "submitted_by"
        case status
        case categoryId           = "category_id"
        case merchantName         = "merchant_name"
        case description
        case amount
        case taxAmount            = "tax_amount"
        case currency
        case expenseDate          = "expense_date"
        case paymentMethod        = "payment_method"
        case receiptImageUrl      = "receipt_image_url"
        case receiptThumbnailUrl  = "receipt_thumbnail_url"
        case receiptMissingReason = "receipt_missing_reason"
        case receiptMissingNote   = "receipt_missing_note"
        case projectMissingReason = "project_missing_reason"
        case projectMissingNote   = "project_missing_note"
        case ocrRawData           = "ocr_raw_data"
        case ocrConfidence        = "ocr_confidence"
        case batchId              = "batch_id"
        case approvedBy           = "approved_by"
        case approvedAt           = "approved_at"
        case rejectedBy           = "rejected_by"
        case rejectedAt           = "rejected_at"
        case rejectionReason      = "rejection_reason"
        case flagComment          = "flag_comment"
        case flaggedBy            = "flagged_by"
        case flaggedAt            = "flagged_at"
        case accountingSyncStatus = "accounting_sync_status"
        case accountingSyncId     = "accounting_sync_id"
        case accountingSyncedAt   = "accounting_synced_at"
        case createdAt            = "created_at"
        case updatedAt            = "updated_at"
        case deletedAt            = "deleted_at"
        case allocations          = "expense_project_allocations"
        case category             = "expense_categories"
    }
}

/// One allocation inside the all-or-nothing expense save RPC. This is a full
/// replacement snapshot, so `amount` is emitted as JSON null when unset rather
/// than omitted like a patch field.
struct ExpenseAtomicAllocationCommand: Encodable, Equatable {
    let projectId: String
    let percentage: Double
    let amount: Double?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case percentage
        case amount
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(percentage, forKey: .percentage)
        if let amount {
            try container.encode(amount, forKey: .amount)
        } else {
            try container.encodeNil(forKey: .amount)
        }
    }
}

/// Complete desired expense state for `save_expense_atomic`. Every nullable
/// field is encoded explicitly. The server
/// therefore distinguishes an intentional clear from a partial patch and can
/// commit content, allocations, exception metadata, submission, placement,
/// and both affected batch totals in one database transaction.
struct ExpenseAtomicSaveCommand: Encodable, Equatable {
    let requestId: String
    let expenseId: String
    let companyId: String
    let submittedBy: String
    let expectedStatus: String?
    let expectedUpdatedAt: String?
    let categoryId: String?
    let merchantName: String?
    let description: String?
    let amount: Double
    let taxAmount: Double?
    let currency: String
    let expenseDate: String
    let paymentMethod: String
    let receiptImageUrl: String?
    let receiptThumbnailUrl: String?
    let receiptMissingReason: String?
    let receiptMissingNote: String?
    let projectMissingReason: String?
    let projectMissingNote: String?
    let ocrRawData: [String: String]?
    let ocrConfidence: Double?
    let allocations: [ExpenseAtomicAllocationCommand]
    let submit: Bool

    init(
        requestId: String,
        expenseId: String,
        companyId: String,
        submittedBy: String,
        expectedStatus: String?,
        expectedUpdatedAt: String?,
        categoryId: String?,
        merchantName: String?,
        description: String?,
        amount: Double,
        taxAmount: Double?,
        currency: String,
        expenseDate: String,
        paymentMethod: String,
        receiptImageUrl: String?,
        receiptThumbnailUrl: String?,
        receiptMissingReason: String?,
        receiptMissingNote: String?,
        projectMissingReason: String?,
        projectMissingNote: String?,
        ocrRawData: [String: String]?,
        ocrConfidence: Double?,
        allocations: [ExpenseAtomicAllocationCommand],
        submit: Bool
    ) {
        self.requestId = requestId
        self.expenseId = expenseId
        self.companyId = companyId
        self.submittedBy = submittedBy
        self.expectedStatus = expectedStatus
        self.expectedUpdatedAt = expectedUpdatedAt
        self.categoryId = categoryId
        self.merchantName = merchantName
        self.description = description
        self.amount = amount
        self.taxAmount = taxAmount
        self.currency = currency
        self.expenseDate = expenseDate
        self.paymentMethod = paymentMethod
        let hasReceipt = !(receiptImageUrl?.isEmpty ?? true)
        self.receiptImageUrl = receiptImageUrl
        self.receiptThumbnailUrl = hasReceipt ? receiptThumbnailUrl : nil

        self.receiptMissingReason = hasReceipt ? nil : receiptMissingReason
        self.receiptMissingNote = hasReceipt ? nil : receiptMissingNote

        self.allocations = allocations
        let hasProject = !allocations.isEmpty
        self.projectMissingReason = hasProject ? nil : projectMissingReason
        self.projectMissingNote = hasProject ? nil : projectMissingNote
        self.ocrRawData = ocrRawData
        self.ocrConfidence = ocrConfidence
        self.submit = submit
    }

    enum CodingKeys: String, CodingKey {
        case requestId             = "request_id"
        case expenseId             = "expense_id"
        case companyId             = "company_id"
        case submittedBy           = "submitted_by"
        case expectedStatus        = "expected_status"
        case expectedUpdatedAt     = "expected_updated_at"
        case categoryId            = "category_id"
        case merchantName          = "merchant_name"
        case description
        case amount
        case taxAmount             = "tax_amount"
        case currency
        case expenseDate           = "expense_date"
        case paymentMethod         = "payment_method"
        case receiptImageUrl       = "receipt_image_url"
        case receiptThumbnailUrl   = "receipt_thumbnail_url"
        case receiptMissingReason  = "receipt_missing_reason"
        case receiptMissingNote    = "receipt_missing_note"
        case projectMissingReason  = "project_missing_reason"
        case projectMissingNote    = "project_missing_note"
        case ocrRawData            = "ocr_raw_data"
        case ocrConfidence         = "ocr_confidence"
        case allocations
        case submit
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(expenseId, forKey: .expenseId)
        try container.encode(companyId, forKey: .companyId)
        try container.encode(submittedBy, forKey: .submittedBy)
        try Self.encodeNullable(expectedStatus, forKey: .expectedStatus, into: &container)
        try Self.encodeNullable(expectedUpdatedAt, forKey: .expectedUpdatedAt, into: &container)
        try Self.encodeNullable(categoryId, forKey: .categoryId, into: &container)
        try Self.encodeNullable(merchantName, forKey: .merchantName, into: &container)
        try Self.encodeNullable(description, forKey: .description, into: &container)
        try container.encode(amount, forKey: .amount)
        try Self.encodeNullable(taxAmount, forKey: .taxAmount, into: &container)
        try container.encode(currency, forKey: .currency)
        try container.encode(expenseDate, forKey: .expenseDate)
        try container.encode(paymentMethod, forKey: .paymentMethod)
        try Self.encodeNullable(receiptImageUrl, forKey: .receiptImageUrl, into: &container)
        try Self.encodeNullable(receiptThumbnailUrl, forKey: .receiptThumbnailUrl, into: &container)
        try Self.encodeNullable(receiptMissingReason, forKey: .receiptMissingReason, into: &container)
        try Self.encodeNullable(receiptMissingNote, forKey: .receiptMissingNote, into: &container)
        try Self.encodeNullable(projectMissingReason, forKey: .projectMissingReason, into: &container)
        try Self.encodeNullable(projectMissingNote, forKey: .projectMissingNote, into: &container)
        try Self.encodeNullable(ocrRawData, forKey: .ocrRawData, into: &container)
        try Self.encodeNullable(ocrConfidence, forKey: .ocrConfidence, into: &container)
        try container.encode(allocations, forKey: .allocations)
        try container.encode(submit, forKey: .submit)
    }

    /// Whether two commands describe the same intended database state. The
    /// request id is deliberately ignored so a failed attempt can reuse its
    /// ledger entry, while any operator edit receives a fresh request id.
    func hasSameIntent(as other: ExpenseAtomicSaveCommand) -> Bool {
        replacingRequestId(with: other.requestId) == other
    }

    func replacingRequestId(with requestId: String) -> ExpenseAtomicSaveCommand {
        ExpenseAtomicSaveCommand(
            requestId: requestId,
            expenseId: expenseId,
            companyId: companyId,
            submittedBy: submittedBy,
            expectedStatus: expectedStatus,
            expectedUpdatedAt: expectedUpdatedAt,
            categoryId: categoryId,
            merchantName: merchantName,
            description: description,
            amount: amount,
            taxAmount: taxAmount,
            currency: currency,
            expenseDate: expenseDate,
            paymentMethod: paymentMethod,
            receiptImageUrl: receiptImageUrl,
            receiptThumbnailUrl: receiptThumbnailUrl,
            receiptMissingReason: receiptMissingReason,
            receiptMissingNote: receiptMissingNote,
            projectMissingReason: projectMissingReason,
            projectMissingNote: projectMissingNote,
            ocrRawData: ocrRawData,
            ocrConfidence: ocrConfidence,
            allocations: allocations,
            submit: submit
        )
    }

    private static func encodeNullable<T: Encodable>(
        _ value: T?,
        forKey key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }
}

struct ExpenseAtomicSaveParams: Encodable {
    let command: ExpenseAtomicSaveCommand

    enum CodingKeys: String, CodingKey {
        case command = "p_command"
    }
}

// MARK: - Allocation DTOs

struct ExpenseAllocationDTO: Codable, Identifiable {
    let id: String
    let expenseId: String
    let projectId: String
    let percentage: Double
    let amount: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case expenseId  = "expense_id"
        case projectId  = "project_id"
        case percentage
        case amount
    }
}

// MARK: - Category DTOs

struct ExpenseCategoryDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let name: String
    let icon: String?
    let isActive: Bool?
    let isDefault: Bool?
    let sortOrder: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId  = "company_id"
        case name
        case icon
        case isActive   = "is_active"
        case isDefault  = "is_default"
        case sortOrder  = "sort_order"
        case createdAt  = "created_at"
    }
}

struct CreateExpenseCategoryDTO: Codable {
    let companyId: String
    let name: String
    let icon: String?
    let sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case companyId  = "company_id"
        case name
        case icon
        case sortOrder  = "sort_order"
    }
}

// MARK: - Batch DTOs

struct ExpenseBatchDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let batchNumber: String
    let periodStart: String?
    let periodEnd: String?
    let status: String
    let submittedBy: String?
    let reviewedBy: String?
    let reviewedAt: String?
    let totalAmount: Double?
    let approvedAmount: Double?
    let parentBatchId: String?
    let amendmentNumber: Int?
    let reviewNotes: String?
    let createdAt: String
    /// Project this batch is scoped to. Non-nil only for companies with
    /// review_frequency = 'per_job'; nil for period-mode batches.
    let scopeProjectId: String?
    /// Payout stage (2026-07-10). Non-nil once the office records the batch as
    /// paid out — an approved batch with `paidAt == nil` is money still owed.
    let paidAt: String?
    let paidBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId       = "company_id"
        case batchNumber     = "batch_number"
        case periodStart     = "period_start"
        case periodEnd       = "period_end"
        case status
        case submittedBy     = "submitted_by"
        case reviewedBy      = "reviewed_by"
        case reviewedAt      = "reviewed_at"
        case totalAmount     = "total_amount"
        case approvedAmount  = "approved_amount"
        case parentBatchId   = "parent_batch_id"
        case amendmentNumber = "amendment_number"
        case reviewNotes     = "review_notes"
        case createdAt       = "created_at"
        case scopeProjectId  = "scope_project_id"
        case paidAt          = "paid_at"
        case paidBy          = "paid_by"
    }
}

struct CreateExpenseBatchDTO: Codable {
    let companyId: String
    let batchNumber: String
    let periodStart: String?
    let periodEnd: String?
    let status: String
    let submittedBy: String?
    let totalAmount: Double?
    let parentBatchId: String?
    let amendmentNumber: Int?

    enum CodingKeys: String, CodingKey {
        case companyId       = "company_id"
        case batchNumber     = "batch_number"
        case periodStart     = "period_start"
        case periodEnd       = "period_end"
        case status
        case submittedBy     = "submitted_by"
        case totalAmount     = "total_amount"
        case parentBatchId   = "parent_batch_id"
        case amendmentNumber = "amendment_number"
    }
}

// MARK: - Settings DTO

struct ExpenseSettingsDTO: Codable {
    var companyId: String?
    var reviewFrequency: String?
    var autoApproveThreshold: Double?
    var adminApprovalThreshold: Double?
    var requireReceiptPhoto: Bool?
    var requireProjectAssignment: Bool?
    /// Days after a period ends before the server sweep auto-sends its
    /// envelope for review (default 7). Powers the console's
    /// "AUTO-SENDS <date>" foresight on filling envelopes.
    var autoSubmitGraceDays: Int?

    enum CodingKeys: String, CodingKey {
        case companyId                = "company_id"
        case reviewFrequency          = "review_frequency"
        case autoApproveThreshold     = "auto_approve_threshold"
        case adminApprovalThreshold   = "admin_approval_threshold"
        case requireReceiptPhoto      = "require_receipt_photo"
        case requireProjectAssignment = "require_project_assignment"
        case autoSubmitGraceDays      = "auto_submit_grace_days"
    }
}

// MARK: - Accounting Category Mapping DTOs

struct AccountingCategoryMappingDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let expenseCategoryId: String
    let provider: String
    let externalAccountId: String
    let externalAccountName: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId            = "company_id"
        case expenseCategoryId    = "expense_category_id"
        case provider
        case externalAccountId    = "external_account_id"
        case externalAccountName  = "external_account_name"
        case createdAt            = "created_at"
    }
}

struct CreateAccountingCategoryMappingDTO: Codable {
    let companyId: String
    let expenseCategoryId: String
    let provider: String
    let externalAccountId: String
    let externalAccountName: String?

    enum CodingKeys: String, CodingKey {
        case companyId            = "company_id"
        case expenseCategoryId    = "expense_category_id"
        case provider
        case externalAccountId    = "external_account_id"
        case externalAccountName  = "external_account_name"
    }
}

// MARK: - Auto-Approve Rule DTOs

struct AutoApproveRuleDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let createdBy: String
    let ruleType: String
    let thresholdAmount: Double
    let appliesToAll: Bool
    let isActive: Bool
    let createdAt: String
    let updatedAt: String
    let members: [AutoApproveRuleMemberDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId       = "company_id"
        case createdBy       = "created_by"
        case ruleType        = "rule_type"
        case thresholdAmount = "threshold_amount"
        case appliesToAll    = "applies_to_all"
        case isActive        = "is_active"
        case createdAt       = "created_at"
        case updatedAt       = "updated_at"
        case members         = "expense_auto_approve_rule_members"
    }
}

struct AutoApproveRuleMemberDTO: Codable, Identifiable {
    let id: String
    let ruleId: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case id
        case ruleId  = "rule_id"
        case userId  = "user_id"
    }
}

struct CreateAutoApproveRuleDTO: Codable {
    let companyId: String
    let createdBy: String
    let ruleType: String
    let thresholdAmount: Double
    let appliesToAll: Bool

    enum CodingKeys: String, CodingKey {
        case companyId       = "company_id"
        case createdBy       = "created_by"
        case ruleType        = "rule_type"
        case thresholdAmount = "threshold_amount"
        case appliesToAll    = "applies_to_all"
    }
}

struct CreateAutoApproveRuleMemberDTO: Codable {
    let ruleId: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case ruleId  = "rule_id"
        case userId  = "user_id"
    }
}
