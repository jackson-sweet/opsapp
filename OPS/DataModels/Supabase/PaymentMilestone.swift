//
//  PaymentMilestone.swift
//  OPS
//
//  Progress-billing milestone attached to an Estimate. Server table:
//  `payment_milestones`. iOS reads-only for v1 (estimate form writes via
//  `EstimateService` payload). Forecast engine projects amounts onto
//  weeks based on `expectedDate` (added 2026-05-11).
//

import Foundation
import SwiftData

@Model
final class PaymentMilestone: Identifiable {
    @Attribute(.unique) var id: String
    var estimateId: String
    var name: String
    var type: String        // "percentage" | "fixed"
    var value: Double
    var amount: Double
    var sortOrder: Int
    var invoiceId: String?
    var paidAt: Date?
    var expectedDate: Date?

    // Sync metadata
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        estimateId: String,
        name: String,
        type: String,
        value: Double,
        amount: Double,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.estimateId = estimateId
        self.name = name
        self.type = type
        self.value = value
        self.amount = amount
        self.sortOrder = sortOrder
    }

    var isPaid: Bool { paidAt != nil }
}
