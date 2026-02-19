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

    var displayName: String {
        switch self {
        case .awaitingPayment: return "AWAITING"
        case .partiallyPaid:   return "PARTIAL"
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

// MARK: - Site Visit Status

enum SiteVisitStatus: String, Codable {
    case scheduled = "scheduled"
    case completed = "completed"
    case cancelled = "cancelled"
}
