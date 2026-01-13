//
//  InventoryItem.swift
//  OPS
//
//  InventoryItem model for tracking inventory items (materials, supplies, etc.)
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - ThresholdStatus Enum

/// Status based on quantity compared to thresholds
enum ThresholdStatus: Int, Comparable, CaseIterable {
    case normal = 0
    case warning = 1
    case critical = 2

    static func < (lhs: ThresholdStatus, rhs: ThresholdStatus) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    var color: Color {
        switch self {
        case .normal:
            return OPSStyle.Colors.primaryText
        case .warning:
            return OPSStyle.Colors.warningStatus
        case .critical:
            return OPSStyle.Colors.errorStatus
        }
    }

    /// Label for badge display (nil for normal status)
    var label: String? {
        switch self {
        case .normal:
            return nil
        case .warning:
            return "LOW"
        case .critical:
            return "CRITICAL"
        }
    }
}

/// InventoryItem model - items tracked in inventory
@Model
final class InventoryItem: Identifiable {
    // MARK: - Properties
    var id: String
    var name: String
    var itemDescription: String?
    var quantity: Double
    var unitId: String?
    var companyId: String
    var sku: String?
    var notes: String?
    var imageUrl: String?

    // Tag IDs for sync (stores Bubble IDs)
    var tagIds: [String] = []

    // MARK: - Threshold Properties
    /// Quantity at which to show warning (yellow). nil = no item-level warning threshold
    var warningThreshold: Double?
    /// Quantity at which to show critical (red). nil = no item-level critical threshold
    var criticalThreshold: Double?

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify)
    var unit: InventoryUnit?

    @Relationship(deleteRule: .nullify)
    var tags: [InventoryTag] = []

    // MARK: - Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    // Soft delete support
    var deletedAt: Date?

    // MARK: - Initialization
    init(
        id: String,
        name: String,
        quantity: Double,
        companyId: String,
        unitId: String? = nil,
        itemDescription: String? = nil,
        tagIds: [String] = [],
        sku: String? = nil,
        notes: String? = nil,
        imageUrl: String? = nil,
        warningThreshold: Double? = nil,
        criticalThreshold: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.companyId = companyId
        self.unitId = unitId
        self.itemDescription = itemDescription
        self.tagIds = tagIds
        self.sku = sku
        self.notes = notes
        self.imageUrl = imageUrl
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
    }

    // MARK: - Computed Properties

    /// Tag names as an array (for display and backward compatibility)
    var tagNames: [String] {
        tags.filter { $0.deletedAt == nil }.map { $0.name }
    }

    /// Display string for quantity with unit (e.g., "10 ea", "5.5 ft")
    var quantityDisplay: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let quantityStr = formatter.string(from: NSNumber(value: quantity)) ?? "0"

        if let unitDisplay = unit?.display {
            return "\(quantityStr) \(unitDisplay)"
        } else {
            return quantityStr
        }
    }

    /// Get threshold status for this item (item-level thresholds only)
    /// For effective threshold considering tag relationships, use `effectiveThresholdStatus()` method
    var thresholdStatus: ThresholdStatus {
        return Self.calculateThresholdStatus(
            quantity: quantity,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold
        )
    }

    /// Get threshold status considering both item-level and tag-level thresholds
    /// Uses the stricter (higher) threshold when both exist
    func effectiveThresholdStatus() -> ThresholdStatus {
        let effective = effectiveThresholds()
        return Self.calculateThresholdStatus(
            quantity: quantity,
            warningThreshold: effective.warning,
            criticalThreshold: effective.critical
        )
    }

    /// Calculate effective thresholds considering tag thresholds from relationships
    /// Uses the stricter (higher) threshold when both item and tag thresholds exist
    func effectiveThresholds() -> (warning: Double?, critical: Double?) {
        var warning = warningThreshold
        var critical = criticalThreshold

        // Check each tag for stricter thresholds
        for tag in tags where tag.deletedAt == nil {
            if let tw = tag.warningThreshold {
                // Higher threshold is stricter (warns earlier)
                warning = warning.map { max($0, tw) } ?? tw
            }
            if let tc = tag.criticalThreshold {
                critical = critical.map { max($0, tc) } ?? tc
            }
        }

        return (warning, critical)
    }

    /// Calculate threshold status from quantity and thresholds
    private static func calculateThresholdStatus(
        quantity: Double,
        warningThreshold: Double?,
        criticalThreshold: Double?
    ) -> ThresholdStatus {
        // Check critical first (takes precedence)
        if let critical = criticalThreshold, quantity <= critical {
            return .critical
        }
        // Then check warning
        if let warning = warningThreshold, quantity <= warning {
            return .warning
        }
        return .normal
    }

    /// Check if item is low on stock (has any threshold warning)
    var isLowStock: Bool {
        return thresholdStatus != .normal
    }

    // MARK: - Helper Methods

    /// Check if user can edit this item
    func canEdit(user: User) -> Bool {
        // Admin and office crew can always edit
        // Field crew can edit if they have inventory access
        return user.role == .admin || user.role == .officeCrew || user.inventoryAccess
    }

    /// Check if user can delete this item
    func canDelete(user: User) -> Bool {
        // Only admin and office crew can delete
        return user.role == .admin || user.role == .officeCrew
    }

    /// Add a tag to this item
    func addTag(_ tag: InventoryTag) {
        if !tags.contains(where: { $0.id == tag.id }) {
            tags.append(tag)
            if !tagIds.contains(tag.id) {
                tagIds.append(tag.id)
            }
            needsSync = true
        }
    }

    /// Remove a tag from this item
    func removeTag(_ tag: InventoryTag) {
        tags.removeAll { $0.id == tag.id }
        tagIds.removeAll { $0 == tag.id }
        needsSync = true
    }

    /// Check if item has a specific tag
    func hasTag(_ tag: InventoryTag) -> Bool {
        return tags.contains { $0.id == tag.id }
    }

    /// Check if item has a tag by name
    func hasTagNamed(_ name: String) -> Bool {
        let lowercasedName = name.lowercased().trimmingCharacters(in: .whitespaces)
        return tags.contains { $0.name.lowercased() == lowercasedName && $0.deletedAt == nil }
    }

    /// Adjust quantity by a delta (positive or negative)
    func adjustQuantity(by delta: Double) {
        quantity = max(0, quantity + delta)
        needsSync = true
    }
}
