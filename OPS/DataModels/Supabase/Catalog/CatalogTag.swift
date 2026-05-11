//
//  CatalogTag.swift
//  OPS
//
//  Free-form label applied at FAMILY level. The legacy threshold
//  columns are preserved in storage but not surfaced in the UI.
//

import Foundation
import SwiftData

@Model
final class CatalogTag: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var name: String
    var warningThreshold: Double?
    var criticalThreshold: Double?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        name: String,
        warningThreshold: Double? = nil,
        criticalThreshold: Double? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.name = name
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
    }
}
