//
//  CatalogProductOptionMapping.swift
//  OPS
//
//  Adapter between configurable Products and stock catalog families. Axis
//  mappings connect a product option to a catalog axis; value mappings connect
//  specific product option values to catalog option values.
//

import Foundation
import SwiftData

enum CatalogProductOptionMappingKind: String, CaseIterable, Codable {
    case axis
    case value
}

@Model
final class CatalogProductOptionMapping: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var productId: String
    var catalogItemId: String
    var catalogOptionId: String
    var productOptionId: String
    var catalogOptionValueId: String?
    var productOptionValueId: String?
    var mappingKind: CatalogProductOptionMappingKind
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        companyId: String,
        productId: String,
        catalogItemId: String,
        catalogOptionId: String,
        productOptionId: String,
        catalogOptionValueId: String? = nil,
        productOptionValueId: String? = nil,
        mappingKind: CatalogProductOptionMappingKind = .axis,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.productId = productId
        self.catalogItemId = catalogItemId
        self.catalogOptionId = catalogOptionId
        self.productOptionId = productOptionId
        self.catalogOptionValueId = catalogOptionValueId
        self.productOptionValueId = productOptionValueId
        self.mappingKind = mappingKind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
