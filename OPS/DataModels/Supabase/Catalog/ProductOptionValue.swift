//
//  ProductOptionValue.swift
//  OPS
//

import Foundation
import SwiftData

@Model
final class ProductOptionValue: Identifiable {
    @Attribute(.unique) var id: String
    var optionId: String
    var value: String
    var sortOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        optionId: String,
        value: String,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.optionId = optionId
        self.value = value
        self.sortOrder = sortOrder
    }
}
