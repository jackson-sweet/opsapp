//
//  InventoryTag.swift
//  OPS
//
//  InventoryTag model for categorizing inventory items with optional thresholds
//  Synced with Bubble for cross-device/user consistency
//

import Foundation
import SwiftData

/// InventoryTag - tags for inventory items with optional quantity thresholds
@Model
final class InventoryTag: Identifiable {
    // MARK: - Properties
    var id: String
    var name: String
    var warningThreshold: Double?   // Quantity to trigger warning (yellow)
    var criticalThreshold: Double?  // Quantity to trigger critical (red)
    var companyId: String

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify, inverse: \InventoryItem.tags)
    var items: [InventoryItem] = []

    // MARK: - Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    // Soft delete support
    var deletedAt: Date?

    // MARK: - Initialization
    init(
        id: String,
        name: String,
        warningThreshold: Double? = nil,
        criticalThreshold: Double? = nil,
        companyId: String
    ) {
        self.id = id
        self.name = name
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.companyId = companyId
    }

    // MARK: - Computed Properties

    /// Display string for threshold values
    var thresholdDisplayString: String {
        var parts: [String] = []
        if let warning = warningThreshold {
            parts.append("Warning @ \(formatThreshold(warning))")
        }
        if let critical = criticalThreshold {
            parts.append("Critical @ \(formatThreshold(critical))")
        }
        return parts.isEmpty ? "No thresholds" : parts.joined(separator: ", ")
    }

    /// Check if this tag has any threshold values set
    var hasThresholds: Bool {
        warningThreshold != nil || criticalThreshold != nil
    }

    // MARK: - Helper Methods

    /// Check if user can edit this tag
    func canEdit(user: User) -> Bool {
        // Only admin and office crew can manage tags
        return user.role == .admin || user.role == .officeCrew
    }

    private func formatThreshold(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
    }
}
