//
//  CatalogOrder.swift
//  OPS
//
//  Threshold-driven restock order (suggested / draft / sent / fulfilled).
//

import Foundation
import SwiftData

enum CatalogOrderStatus: String, CaseIterable, Codable {
    case suggested
    case draft
    case sent
    case fulfilled
    case cancelled
}

@Model
final class CatalogOrder: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var status: CatalogOrderStatus
    var title: String?
    var supplierName: String?
    var supplierContact: String?
    var expectedDeliveryDate: Date?
    var notes: String?
    var createdById: String?
    var createdAt: Date
    var updatedAt: Date
    var sentAt: Date?
    var fulfilledAt: Date?
    var cancelledAt: Date?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        status: CatalogOrderStatus = .draft,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
