//
//  InventorySnapshot.swift
//  OPS
//
//  Inventory snapshot model for point-in-time inventory records
//

import Foundation
import SwiftData

/// InventorySnapshot model - captures inventory state at a point in time
@Model
final class InventorySnapshot: Identifiable {
    // MARK: - Properties
    var id: String
    var companyId: String
    var createdAt: Date
    var createdById: String?  // User ID who created (nil if automatic)
    var isAutomatic: Bool
    var itemCount: Int
    var notes: String?

    // MARK: - Relationships
    @Relationship(deleteRule: .cascade, inverse: \InventorySnapshotItem.snapshot)
    var items: [InventorySnapshotItem]?

    // MARK: - Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    // MARK: - Initialization
    init(
        id: String,
        companyId: String,
        createdAt: Date = Date(),
        createdById: String? = nil,
        isAutomatic: Bool = false,
        itemCount: Int = 0,
        notes: String? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.createdAt = createdAt
        self.createdById = createdById
        self.isAutomatic = isAutomatic
        self.itemCount = itemCount
        self.notes = notes
    }

    // MARK: - Computed Properties

    /// Formatted date string for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    /// Short date string (just date, no time)
    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: createdAt)
    }

    /// Type label for display
    var typeLabel: String {
        isAutomatic ? "Automatic" : "Manual"
    }
}
