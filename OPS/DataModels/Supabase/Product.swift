//
//  Product.swift
//  OPS
//
//  Service/product catalog item — Supabase-backed
//

import SwiftData
import Foundation

@Model
class Product: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var name: String
    var productDescription: String?
    var type: LineItemType
    var defaultPrice: Double
    var unitCost: Double?
    var unit: String?
    var taxable: Bool
    var isActive: Bool
    var taskTypeId: String?
    var createdAt: Date

    var marginPercent: Double? {
        guard let cost = unitCost, cost > 0, defaultPrice > 0 else { return nil }
        return ((defaultPrice - cost) / defaultPrice) * 100
    }

    init(
        id: String = UUID().uuidString,
        companyId: String,
        name: String,
        type: LineItemType = .labor,
        defaultPrice: Double = 0,
        taxable: Bool = true,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.name = name
        self.type = type
        self.defaultPrice = defaultPrice
        self.taxable = taxable
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
