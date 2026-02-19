//
//  Payment.swift
//  OPS
//
//  Payment record (insert-only) — Supabase-backed
//

import SwiftData
import Foundation

@Model
class Payment {
    @Attribute(.unique) var id: String
    var invoiceId: String
    var companyId: String
    var amount: Double
    var method: PaymentMethod
    var paidAt: Date
    var notes: String?
    var voidedAt: Date?
    var voidedBy: String?
    var createdAt: Date

    var isVoided: Bool { voidedAt != nil }

    init(
        id: String = UUID().uuidString,
        invoiceId: String,
        companyId: String,
        amount: Double,
        method: PaymentMethod,
        paidAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.invoiceId = invoiceId
        self.companyId = companyId
        self.amount = amount
        self.method = method
        self.paidAt = paidAt
        self.createdAt = createdAt
    }
}
