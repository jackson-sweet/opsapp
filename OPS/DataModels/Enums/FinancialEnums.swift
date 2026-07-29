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
    /// Filling envelope — current period, silently accruing on the server.
    /// Peek-only; never reviewable. The server's daily sweep owns when it sends.
    case open              = "open"
    case pendingReview     = "pending_review"
    case submitted         = "submitted"
    case approved          = "approved"
    case partiallyApproved = "partially_approved"
    case rejected          = "rejected"
    case autoApproved      = "auto_approved"

    var displayName: String {
        switch self {
        case .open:              return "FILLING"
        case .pendingReview:     return "PENDING"
        case .submitted:         return "SUBMITTED"
        case .approved:          return "APPROVED"
        case .partiallyApproved: return "PARTIAL"
        case .rejected:          return "REJECTED"
        case .autoApproved:      return "AUTO-APPROVED"
        }
    }

    /// A filling envelope is current-period, silently accruing — not yet
    /// handed to the office, so it is never review-ready or approvable.
    var isFilling: Bool { self == .open }

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
///
/// Case order IS chip order — `LostReasonSheet.options` maps straight off
/// `allCases`. The two self-attributed reasons sit beside NO RESPONSE (the same
/// "nobody talked" family, seen from the other side) and ahead of the OTHER
/// catch-all, which always closes the row.
enum LossReason: String, Codable, CaseIterable, Identifiable {
    case price       = "price"
    case timing      = "timing"
    case competition = "competition"
    case scope       = "scope"
    case noResponse  = "no_response"
    case droppedBall = "dropped_ball"
    case forgot      = "forgot"
    case other       = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .price:       return "PRICE"
        case .timing:      return "TIMING"
        case .competition: return "COMPETITION"
        case .scope:       return "SCOPE"
        case .noResponse:  return "NO RESPONSE"
        case .droppedBall: return "DROPPED THE BALL"
        case .forgot:      return "NEVER FOLLOWED UP"
        case .other:       return "OTHER"
        }
    }

    /// Resolve a value that came off the server rather than off a chip.
    ///
    /// `opportunities.lost_reason` is unconstrained text and holds values this
    /// enum has never defined — `operator_no_response` and `not_a_lead` were
    /// written by server-side flows, and at least one row carries a capitalised
    /// `Other`. Plain `init(rawValue:)` answers nil for all of them, which left
    /// the sheet with no chip lit and no way to tell "never set" from "set to
    /// something I don't recognise". Case- and whitespace-insensitive matching
    /// recovers the ones that ARE ours; the rest stay unresolved on purpose and
    /// are preserved verbatim by `LostReasonSelection`.
    init?(storedValue: String?) {
        guard let normalized = storedValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalized.isEmpty,
              let match = LossReason.allCases.first(where: { $0.rawValue == normalized })
        else { return nil }
        self = match
    }
}

/// Chip selection state for `LostReasonSheet`, kept out of the view so the
/// preserve-unknown-values rule is testable.
///
/// The rule: a stored reason this app does not recognise is NEVER silently
/// dropped. It stays unselected in the UI (no chip lit), and if the operator
/// saves without choosing one, the original value is written back unchanged.
struct LostReasonSelection {
    /// The value already on the lead, exactly as the server sent it.
    let storedReason: String?
    /// The chip the operator picked this session, if any.
    var reason: LossReason?

    init(storedReason: String?, reason: LossReason? = nil) {
        self.storedReason = storedReason
        self.reason = reason ?? LossReason(storedValue: storedReason)
    }

    /// A save is only meaningful once SOME reason is on the record — either one
    /// the operator just picked or one already stored.
    var canSave: Bool { resolvedReasonForSave != nil }

    /// What to persist: the operator's pick when they made one, otherwise the
    /// untouched stored value.
    var resolvedReasonForSave: String? {
        if let reason { return reason.rawValue }
        guard let stored = storedReason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !stored.isEmpty else { return nil }
        return stored
    }
}
