//
//  BooksSection.swift
//  OPS
//
//  Books Phase 2 — Pipeline split out to its own top-level tab (see
//  `PIPELINE TAB - P1-1`). Books now lists three document types only.
//

import Foundation

enum BooksSection: String, CaseIterable, Identifiable, Codable {
    case invoices  = "INVOICES"
    case estimates = "ESTIMATES"
    case expenses  = "EXPENSES"

    var id: String { rawValue }

    /// Permission required for this segment to be visible.
    var requiredPermission: String {
        switch self {
        case .invoices:  return "finances.view"
        case .estimates: return "estimates.view"
        case .expenses:  return "expenses.view"
        }
    }

    /// FAB primary action label for this segment.
    var fabActionLabel: String {
        switch self {
        case .invoices:  return "New Invoice"
        case .estimates: return "New Estimate"
        case .expenses:  return "New Expense"
        }
    }
}
