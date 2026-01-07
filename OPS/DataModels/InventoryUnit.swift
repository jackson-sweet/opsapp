//
//  InventoryUnit.swift
//  OPS
//
//  InventoryUnit model for defining measurement units (ea, box, ft, etc.)
//

import Foundation
import SwiftData

/// InventoryUnit model - measurement units for inventory items
@Model
final class InventoryUnit: Identifiable {
    // MARK: - Properties
    var id: String
    var display: String  // Display name (e.g., "ea", "box", "ft")
    var companyId: String
    var isDefault: Bool
    var sortOrder: Int = 0

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify, inverse: \InventoryItem.unit)
    var items: [InventoryItem] = []

    // MARK: - Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    // Soft delete support
    var deletedAt: Date?

    // MARK: - Initialization
    init(
        id: String,
        display: String,
        companyId: String,
        isDefault: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.display = display
        self.companyId = companyId
        self.isDefault = isDefault
        self.sortOrder = sortOrder
    }

    // MARK: - Helper Methods

    /// Check if user can edit this unit
    func canEdit(user: User) -> Bool {
        // Only admin and office crew can manage inventory units
        return user.role == .admin || user.role == .officeCrew
    }

    /// Check if this unit can be deleted
    var canDelete: Bool {
        // Default units cannot be deleted
        // Also check if any items are using this unit
        return !isDefault && items.isEmpty
    }

    /// Check if this unit is in use by any inventory items
    var isInUse: Bool {
        return !items.isEmpty
    }
}
