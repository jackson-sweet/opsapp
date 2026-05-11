//
//  CompanyDefaultProduct.swift
//  OPS
//
//  Per-company default Product per Deck Builder component_type.
//  Drives the one-click drawing → estimate adapter.
//

import Foundation
import SwiftData

enum DesignComponentType: String, CaseIterable, Codable {
    case railing
    case deckBoard = "deck_board"
    case stairSet = "stair_set"
    case gate
    case postSet = "post_set"
}

@Model
final class CompanyDefaultProduct {
    var companyId: String
    var componentType: DesignComponentType
    var productId: String
    var createdAt: Date
    var updatedAt: Date

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        companyId: String,
        componentType: DesignComponentType,
        productId: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.companyId = companyId
        self.componentType = componentType
        self.productId = productId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
