//
//  Invoice.swift
//  OPS
//
//  Billing document — Supabase-backed
//

import SwiftData
import Foundation

@Model
class Invoice: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var invoiceNumber: String
    var status: InvoiceStatus
    var clientId: String?
    var projectId: String?
    var opportunityId: String?
    var estimateId: String?
    var title: String?
    var subtotal: Double
    var taxAmount: Double
    var total: Double
    var amountPaid: Double
    var balanceDue: Double
    var taxRate: Double
    var dueDate: Date?
    var sentAt: Date?
    var paidAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var isOverdue: Bool {
        guard let due = dueDate else { return false }
        return balanceDue > 0 && due < Date() && status != .void
    }

    init(
        id: String = UUID().uuidString,
        companyId: String,
        invoiceNumber: String = "",
        status: InvoiceStatus = .draft,
        taxRate: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.invoiceNumber = invoiceNumber
        self.status = status
        self.subtotal = 0
        self.taxAmount = 0
        self.total = 0
        self.amountPaid = 0
        self.balanceDue = 0
        self.taxRate = taxRate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
