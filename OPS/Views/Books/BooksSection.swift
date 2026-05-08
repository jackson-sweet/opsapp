//
//  BooksSection.swift
//  OPS
//

import Foundation

enum BooksSection: String, CaseIterable, Identifiable, Codable {
    case pipeline  = "PIPELINE"
    case estimates = "ESTIMATES"
    case invoices  = "INVOICES"
    case expenses  = "EXPENSES"

    var id: String { rawValue }

    /// Permission required for this segment to be visible.
    var requiredPermission: String {
        switch self {
        case .pipeline:  return "pipeline.view"
        case .estimates: return "estimates.view"
        case .invoices:  return "finances.view"
        case .expenses:  return "expenses.view"
        }
    }

    /// FAB primary action label for this segment.
    var fabActionLabel: String {
        switch self {
        case .pipeline:  return "Add Lead"
        case .estimates: return "New Estimate"
        case .invoices:  return "New Invoice"
        case .expenses:  return "New Expense"
        }
    }
}
