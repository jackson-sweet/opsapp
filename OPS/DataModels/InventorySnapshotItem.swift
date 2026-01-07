//
//  InventorySnapshotItem.swift
//  OPS
//
//  Individual item record within an inventory snapshot
//

import Foundation
import SwiftData

/// InventorySnapshotItem model - captures individual item state at snapshot time
@Model
final class InventorySnapshotItem: Identifiable {
    // MARK: - Properties
    var id: String
    var snapshotId: String
    var originalItemId: String  // Reference to original InventoryItem
    var name: String
    var quantity: Double
    var unitDisplay: String?  // Unit name at time of snapshot
    var sku: String?
    var tagsString: String = ""
    var itemDescription: String?

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify)
    var snapshot: InventorySnapshot?

    // MARK: - Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    // MARK: - Initialization
    init(
        id: String,
        snapshotId: String,
        originalItemId: String,
        name: String,
        quantity: Double,
        unitDisplay: String? = nil,
        sku: String? = nil,
        tagsString: String = "",
        itemDescription: String? = nil
    ) {
        self.id = id
        self.snapshotId = snapshotId
        self.originalItemId = originalItemId
        self.name = name
        self.quantity = quantity
        self.unitDisplay = unitDisplay
        self.sku = sku
        self.tagsString = tagsString
        self.itemDescription = itemDescription
    }

    // MARK: - Computed Properties

    /// Tags as an array
    var tags: [String] {
        guard !tagsString.isEmpty else { return [] }
        return tagsString.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Formatted quantity display
    var quantityDisplay: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let quantityStr = formatter.string(from: NSNumber(value: quantity)) ?? "0"

        if let unit = unitDisplay, !unit.isEmpty {
            return "\(quantityStr) \(unit)"
        } else {
            return quantityStr
        }
    }

    // MARK: - Factory Method

    /// Create a snapshot item from an existing inventory item
    static func from(
        inventoryItem: InventoryItem,
        snapshotId: String,
        itemId: String
    ) -> InventorySnapshotItem {
        return InventorySnapshotItem(
            id: itemId,
            snapshotId: snapshotId,
            originalItemId: inventoryItem.id,
            name: inventoryItem.name,
            quantity: inventoryItem.quantity,
            unitDisplay: inventoryItem.unit?.display,
            sku: inventoryItem.sku,
            tagsString: inventoryItem.tagsString,
            itemDescription: inventoryItem.itemDescription
        )
    }
}
