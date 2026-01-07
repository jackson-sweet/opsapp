//
//  InventoryItem.swift
//  OPS
//
//  InventoryItem model for tracking inventory items (materials, supplies, etc.)
//

import Foundation
import SwiftData

/// InventoryItem model - items tracked in inventory
@Model
final class InventoryItem: Identifiable {
    // MARK: - Properties
    var id: String
    var name: String
    var itemDescription: String?
    var quantity: Double
    var unitId: String?
    var tagsString: String = ""  // Comma-separated tags for flexible categorization
    var companyId: String
    var sku: String?
    var notes: String?
    var imageUrl: String?

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify)
    var unit: InventoryUnit?

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
        tagsString: String = "",
        sku: String? = nil,
        notes: String? = nil,
        imageUrl: String? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.companyId = companyId
        self.unitId = unitId
        self.itemDescription = itemDescription
        self.tagsString = tagsString
        self.sku = sku
        self.notes = notes
        self.imageUrl = imageUrl
    }

    // MARK: - Computed Properties

    /// Tags as an array (parsed from comma-separated string)
    var tags: [String] {
        get {
            guard !tagsString.isEmpty else { return [] }
            return tagsString.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsString = newValue.joined(separator: ",")
        }
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

    /// Check if item is low on stock (below a threshold)
    /// Note: minQuantity is Phase 2, for now just returns false
    var isLowStock: Bool {
        // Future: compare against minQuantity threshold
        return false
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

    /// Add a tag if not already present
    func addTag(_ tag: String) {
        let trimmedTag = tag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmedTag.isEmpty else { return }

        var currentTags = tags
        if !currentTags.contains(trimmedTag) {
            currentTags.append(trimmedTag)
            tags = currentTags
        }
    }

    /// Remove a tag
    func removeTag(_ tag: String) {
        let trimmedTag = tag.trimmingCharacters(in: .whitespaces).lowercased()
        var currentTags = tags
        currentTags.removeAll { $0.lowercased() == trimmedTag }
        tags = currentTags
    }

    /// Check if item has a specific tag
    func hasTag(_ tag: String) -> Bool {
        let trimmedTag = tag.trimmingCharacters(in: .whitespaces).lowercased()
        return tags.contains { $0.lowercased() == trimmedTag }
    }

    /// Adjust quantity by a delta (positive or negative)
    func adjustQuantity(by delta: Double) {
        quantity = max(0, quantity + delta)
        needsSync = true
    }
}
