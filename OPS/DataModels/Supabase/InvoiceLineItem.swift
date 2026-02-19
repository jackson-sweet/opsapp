//
//  InvoiceLineItem.swift
//  OPS
//
//  Line item on an invoice — Supabase-backed
//

import SwiftData
import Foundation

@Model
class InvoiceLineItem {
    @Attribute(.unique) var id: String
    var invoiceId: String
    var name: String
    var itemDescription: String?
    var type: LineItemType
    var quantity: Double
    var unit: String?
    var unitPrice: Double
    var lineTotal: Double
    var displayOrder: Int
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        invoiceId: String,
        name: String,
        type: LineItemType = .labor,
        quantity: Double = 1,
        unitPrice: Double = 0,
        displayOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.invoiceId = invoiceId
        self.name = name
        self.type = type
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.lineTotal = quantity * unitPrice
        self.displayOrder = displayOrder
        self.createdAt = createdAt
    }
}
