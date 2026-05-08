//
//  FinancialEnums.swift
//  OPS
//
//  Enums for estimates, invoices, payments, and products
//

import Foundation

// MARK: - Estimate Status

enum EstimateStatus: String, Codable, CaseIterable {
    case draft     = "draft"
    case sent      = "sent"
    case viewed    = "viewed"
    case approved  = "approved"
    case converted = "converted"
    case declined  = "declined"
    case expired   = "expired"

    var displayName: String { rawValue.uppercased() }

    var canSend: Bool     { self == .draft }
    var canApprove: Bool  { self == .sent || self == .viewed }
    var canConvert: Bool  { self == .approved }
}

// MARK: - Invoice Status

enum InvoiceStatus: String, Codable, CaseIterable {
    case draft           = "draft"
    case sent            = "sent"
    case awaitingPayment = "awaiting_payment"
    case partiallyPaid   = "partially_paid"
    case paid            = "paid"
    case pastDue         = "past_due"
    case void            = "void"
    case writtenOff      = "written_off"

    var displayName: String {
        switch self {
        case .awaitingPayment: return "AWAITING"
        case .partiallyPaid:   return "PARTIAL"
        case .writtenOff:      return "WRITTEN OFF"
        default:               return rawValue.uppercased()
        }
    }

    var isPaid: Bool { self == .paid }
    var needsPayment: Bool { self == .awaitingPayment || self == .partiallyPaid || self == .pastDue }
}

// MARK: - Payment Method

enum PaymentMethod: String, Codable, CaseIterable {
    case cash         = "cash"
    case check        = "check"
    case creditCard   = "credit_card"
    case ach          = "ach"
    case bankTransfer = "bank_transfer"
    case stripe       = "stripe"
    case other        = "other"

    var displayName: String {
        switch self {
        case .creditCard:   return "CREDIT CARD"
        case .ach:          return "ACH"
        case .bankTransfer: return "BANK TRANSFER"
        default:            return rawValue.uppercased()
        }
    }
}

// MARK: - Line Item Type

enum LineItemType: String, Codable, CaseIterable {
    case labor    = "LABOR"
    case material = "MATERIAL"
    case other    = "OTHER"
}

// MARK: - Follow-Up Types

enum FollowUpType: String, Codable, CaseIterable {
    case call            = "call"
    case email           = "email"
    case meeting         = "meeting"
    case quoteFollowUp   = "quote_follow_up"
    case invoiceFollowUp = "invoice_follow_up"
    case custom          = "custom"

    var icon: String {
        switch self {
        case .call:            return "phone.fill"
        case .email:           return "envelope.fill"
        case .meeting:         return "person.2.fill"
        case .quoteFollowUp:   return "doc.text.fill"
        case .invoiceFollowUp: return "receipt"
        case .custom:          return "bell.fill"
        }
    }
}

enum FollowUpStatus: String, Codable {
    case pending   = "pending"
    case completed = "completed"
    case skipped   = "skipped"
}

// MARK: - Quote Delivery Method

enum QuoteDeliveryMethod: String, Codable, CaseIterable {
    case inPerson = "in_person"
    case email    = "email"
    case phone    = "phone"
    case mail     = "mail"
    case other    = "other"

    var displayName: String {
        switch self {
        case .inPerson: return "IN PERSON"
        case .email:    return "EMAIL"
        case .phone:    return "PHONE"
        case .mail:     return "MAIL"
        case .other:    return "OTHER"
        }
    }

    var icon: String {
        switch self {
        case .inPerson: return "person.fill"
        case .email:    return "envelope.fill"
        case .phone:    return "phone.fill"
        case .mail:     return "envelope.badge.shield.half.filled.fill"
        case .other:    return "ellipsis.circle.fill"
        }
    }
}

// MARK: - Site Visit Status

enum SiteVisitStatus: String, Codable {
    case scheduled = "scheduled"
    case completed = "completed"
    case cancelled = "cancelled"
}

// MARK: - Expense Status

enum ExpenseStatus: String, Codable, CaseIterable {
    case draft      = "draft"
    case submitted  = "submitted"
    case approved   = "approved"
    case rejected   = "rejected"
    case reimbursed = "reimbursed"

    var displayName: String { rawValue.uppercased() }
    var isEditable: Bool { self == .draft || self == .rejected || self == .submitted }
    var canSubmit: Bool { self == .draft }
    var canApprove: Bool { self == .submitted }
    var isTerminal: Bool { self == .approved || self == .reimbursed }
}

// MARK: - Expense Batch Status

enum ExpenseBatchStatus: String, Codable, CaseIterable {
    case pendingReview     = "pending_review"
    case submitted         = "submitted"
    case approved          = "approved"
    case partiallyApproved = "partially_approved"
    case rejected          = "rejected"
    case autoApproved      = "auto_approved"

    var displayName: String {
        switch self {
        case .pendingReview:     return "PENDING"
        case .submitted:         return "SUBMITTED"
        case .approved:          return "APPROVED"
        case .partiallyApproved: return "PARTIAL"
        case .rejected:          return "REJECTED"
        case .autoApproved:      return "AUTO-APPROVED"
        }
    }

    var needsReview: Bool { self == .pendingReview || self == .submitted }
    var isApproved: Bool { self == .approved || self == .autoApproved || self == .partiallyApproved }
}

// MARK: - Auto-Approve Rule Type

enum AutoApproveRuleType: String, Codable, CaseIterable {
    case invoice  = "invoice"
    case lineItem = "line_item"

    var displayName: String {
        switch self {
        case .invoice:  return "INVOICE"
        case .lineItem: return "LINE ITEM"
        }
    }
}

// MARK: - Expense Payment Method

enum ExpensePaymentMethod: String, Codable, CaseIterable {
    case cash        = "cash"
    case personalCard = "personal_card"
    case companyCard  = "company_card"

    var displayName: String {
        switch self {
        case .cash:         return "CASH"
        case .personalCard: return "PERSONAL CARD"
        case .companyCard:  return "COMPANY CARD"
        }
    }
}

// MARK: - Review Frequency

enum ReviewFrequency: String, Codable, CaseIterable {
    case weekly    = "weekly"
    case biweekly  = "biweekly"
    case monthly   = "monthly"
    case quarterly = "quarterly"

    var displayName: String {
        switch self {
        case .weekly:    return "WEEKLY"
        case .biweekly:  return "BI-WEEKLY"
        case .monthly:   return "MONTHLY"
        case .quarterly: return "QUARTERLY"
        }
    }
}

// MARK: - Accounting Sync Status

enum AccountingSyncStatus: String, Codable {
    case pending = "pending"
    case synced  = "synced"
    case error   = "error"
}

// MARK: - Opportunity Source

/// Where a pipeline opportunity came from. Mirrors bible §9.85 source enum.
enum OpportunitySource: String, Codable, CaseIterable, Identifiable {
    case referral     = "referral"
    case website      = "website"
    case email        = "email"
    case phone        = "phone"
    case walkIn       = "walk_in"
    case socialMedia  = "social_media"
    case repeatClient = "repeat_client"
    case other        = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .referral:     return "REFERRAL"
        case .website:      return "WEBSITE"
        case .email:        return "EMAIL"
        case .phone:        return "PHONE"
        case .walkIn:       return "WALK-IN"
        case .socialMedia:  return "SOCIAL MEDIA"
        case .repeatClient: return "REPEAT CLIENT"
        case .other:        return "OTHER"
        }
    }
}

// MARK: - Loss Reason

/// Why a pipeline opportunity was marked Lost. Used by LostReasonSheet.
enum LossReason: String, Codable, CaseIterable, Identifiable {
    case price       = "price"
    case timing      = "timing"
    case competition = "competition"
    case scope       = "scope"
    case noResponse  = "no_response"
    case other       = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .price:       return "PRICE"
        case .timing:      return "TIMING"
        case .competition: return "COMPETITION"
        case .scope:       return "SCOPE"
        case .noResponse:  return "NO RESPONSE"
        case .other:       return "OTHER"
        }
    }
}
