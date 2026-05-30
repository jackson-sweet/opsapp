//
//  CatalogStockUnit.swift
//  OPS
//
//  Physical stock ledger row for one catalog variant. Quantity policy is a
//  mirrored aggregate: `catalog_variants.quantity` remains the operational
//  count read by stock/order flows, and stock-unit mutations must mirror their
//  available aggregate back to that variant field.
//

import Foundation
import SwiftData

enum CatalogStockUnitKind: String, CaseIterable, Codable {
    case roll
    case offcut
    case box
    case each
    case lot
    case pallet
    case length
}

enum CatalogStockUnitStatus: String, CaseIterable, Codable {
    case full
    case partial
    case reserved
    case consumed
    case scrapped

    var countsAsAvailable: Bool {
        switch self {
        case .full, .partial:
            return true
        case .reserved, .consumed, .scrapped:
            return false
        }
    }
}

@Model
final class CatalogStockUnit: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var catalogVariantId: String
    var unitKind: CatalogStockUnitKind
    var label: String?
    var lotCode: String?
    var widthValue: Double?
    var widthUnit: String?
    var originalLengthValue: Double?
    var remainingLengthValue: Double?
    var lengthUnit: String?
    var quantityValue: Double
    var location: String?
    var status: CatalogStockUnitStatus
    var sourceOrderItemId: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        companyId: String,
        catalogVariantId: String,
        unitKind: CatalogStockUnitKind = .each,
        label: String? = nil,
        lotCode: String? = nil,
        widthValue: Double? = nil,
        widthUnit: String? = nil,
        originalLengthValue: Double? = nil,
        remainingLengthValue: Double? = nil,
        lengthUnit: String? = nil,
        quantityValue: Double = 1,
        location: String? = nil,
        status: CatalogStockUnitStatus = .full,
        sourceOrderItemId: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.catalogVariantId = catalogVariantId
        self.unitKind = unitKind
        self.label = label
        self.lotCode = lotCode
        self.widthValue = widthValue
        self.widthUnit = widthUnit
        self.originalLengthValue = originalLengthValue
        self.remainingLengthValue = remainingLengthValue
        self.lengthUnit = lengthUnit
        self.quantityValue = quantityValue
        self.location = location
        self.status = status
        self.sourceOrderItemId = sourceOrderItemId
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
