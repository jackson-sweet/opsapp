//
//  EstimateLineItem.swift
//  OPS
//
//  Line item on an estimate — Supabase-backed
//

import SwiftData
import Foundation

@Model
class EstimateLineItem {
    @Attribute(.unique) var id: String
    var estimateId: String
    var productId: String?
    var name: String
    var itemDescription: String?
    var type: LineItemType
    var quantity: Double
    var unit: String?
    var unitPrice: Double
    var discountPercent: Double
    var taxable: Bool
    var optional: Bool
    var lineTotal: Double
    var displayOrder: Int
    var taskTypeId: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        estimateId: String,
        name: String,
        type: LineItemType = .labor,
        quantity: Double = 1,
        unitPrice: Double = 0,
        displayOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.estimateId = estimateId
        self.name = name
        self.type = type
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.discountPercent = 0
        self.taxable = true
        self.optional = false
        self.lineTotal = quantity * unitPrice
        self.displayOrder = displayOrder
        self.createdAt = createdAt
    }
}
