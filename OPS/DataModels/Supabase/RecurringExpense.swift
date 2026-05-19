//
//  RecurringExpense.swift
//  OPS
//
//  Owner-managed recurring outflow (rent, insurance, payroll, subscriptions).
//  Powers the recurring layer of the Cashflow Forecast. Does NOT auto-create
//  expense rows on due dates (forecast-only in v1).
//

import Foundation
import SwiftData

enum RecurringCadence: String, Codable, CaseIterable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case annually

    var displayName: String {
        switch self {
        case .weekly:    return "WEEKLY"
        case .biweekly:  return "BIWEEKLY"
        case .monthly:   return "MONTHLY"
        case .quarterly: return "QUARTERLY"
        case .annually:  return "ANNUALLY"
        }
    }
}

@Model
final class RecurringExpense: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var name: String
    var amount: Double
    var currency: String
    var cadenceRaw: String
    var nextDueDate: Date
    var endDate: Date?
    var categoryId: String?
    var notes: String?
    var createdBy: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    // Sync metadata
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    var cadence: RecurringCadence {
        get { RecurringCadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    var isActive: Bool { deletedAt == nil }

    init(
        id: String = UUID().uuidString,
        companyId: String,
        name: String,
        amount: Double,
        currency: String = "USD",
        cadence: RecurringCadence,
        nextDueDate: Date,
        endDate: Date? = nil,
        categoryId: String? = nil,
        notes: String? = nil,
        createdBy: String? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.name = name
        self.amount = amount
        self.currency = currency
        self.cadenceRaw = cadence.rawValue
        self.nextDueDate = nextDueDate
        self.endDate = endDate
        self.categoryId = categoryId
        self.notes = notes
        self.createdBy = createdBy
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
