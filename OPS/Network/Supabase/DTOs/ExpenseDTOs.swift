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

struct CreateExpenseDTO: Codable {
    let companyId: String
    let submittedBy: String
    let status: String
    let categoryId: String?
    let merchantName: String?
    let description: String?
    let amount: Double
    let taxAmount: Double?
    /// ISO 4217 code (USD/CAD/etc.). Defaulted from the form's locale-aware
    /// currency picker. Nil falls back to the column default ('USD').
    let currency: String?
    let expenseDate: String?
    let paymentMethod: String?
    let receiptImageUrl: String?
    let receiptThumbnailUrl: String?
    let ocrRawData: [String: String]?
    let ocrConfidence: Double?

    enum CodingKeys: String, CodingKey {
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
        case ocrRawData           = "ocr_raw_data"
        case ocrConfidence        = "ocr_confidence"
    }
}

struct UpdateExpenseDTO: Codable {
    var categoryId: String?
    var merchantName: String?
    var description: String?
    var amount: Double?
    var taxAmount: Double?
    var currency: String?
    var expenseDate: String?
    var paymentMethod: String?
    var receiptImageUrl: String?
    var receiptThumbnailUrl: String?
    var status: String?
    var batchId: String?

    enum CodingKeys: String, CodingKey {
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
        case status
        case batchId              = "batch_id"
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

struct CreateExpenseAllocationDTO: Codable {
    let expenseId: String
    let projectId: String
    let percentage: Double
    let amount: Double?

    enum CodingKeys: String, CodingKey {
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

    enum CodingKeys: String, CodingKey {
        case companyId                = "company_id"
        case reviewFrequency          = "review_frequency"
        case autoApproveThreshold     = "auto_approve_threshold"
        case adminApprovalThreshold   = "admin_approval_threshold"
        case requireReceiptPhoto      = "require_receipt_photo"
        case requireProjectAssignment = "require_project_assignment"
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
