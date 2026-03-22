//
//  InventorySnapshotItemDTO.swift
//  OPS
//
//  Data Transfer Object for InventorySnapshotItem from Bubble API
//

import Foundation

/// Data Transfer Object for InventorySnapshotItem from Bubble API
struct InventorySnapshotItemDTO: Codable {
    let id: String
    let snapshot: String?  // Snapshot ID reference
    let originalItemId: String?
    let name: String?
    let quantity: Double?
    let unitDisplay: String?
    let sku: String?
    let tags: [String]?
    let description: String?

    // Metadata
    let createdDate: String?
    let modifiedDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case snapshot = "snapshot"
        case originalItemId = "originalItemId"
        case name = "name"
        case quantity = "quantity"
        case unitDisplay = "unitDisplay"
        case sku = "sku"
        case tags = "tags"
        case description = "description"
        case createdDate = "Created Date"
        case modifiedDate = "Modified Date"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)

        // Try "id" first, fall back to "_id"
        if let idValue = try? container.decode(String.self, forKey: .id) {
            self.id = idValue
        } else {
            self.id = try dynamicContainer.decode(String.self, forKey: DynamicCodingKey(stringValue: "_id")!)
        }

        self.snapshot = try container.decodeIfPresent(String.self, forKey: .snapshot)
        self.originalItemId = try container.decodeIfPresent(String.self, forKey: .originalItemId)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        self.unitDisplay = try container.decodeIfPresent(String.self, forKey: .unitDisplay)
        self.sku = try container.decodeIfPresent(String.self, forKey: .sku)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.createdDate = try container.decodeIfPresent(String.self, forKey: .createdDate)
        self.modifiedDate = try container.decodeIfPresent(String.self, forKey: .modifiedDate)
    }

    init(
        id: String,
        snapshot: String?,
        originalItemId: String?,
        name: String?,
        quantity: Double?,
        unitDisplay: String?,
        sku: String?,
        tags: [String]?,
        description: String?,
        createdDate: String? = nil,
        modifiedDate: String? = nil
    ) {
        self.id = id
        self.snapshot = snapshot
        self.originalItemId = originalItemId
        self.name = name
        self.quantity = quantity
        self.unitDisplay = unitDisplay
        self.sku = sku
        self.tags = tags
        self.description = description
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? { return nil }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    /// Convert to dictionary for API requests
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let snapshot = snapshot { dict["snapshot"] = snapshot }
        if let originalItemId = originalItemId { dict["originalItemId"] = originalItemId }
        if let name = name { dict["name"] = name }
        if let quantity = quantity { dict["quantity"] = quantity }
        if let unitDisplay = unitDisplay { dict["unitDisplay"] = unitDisplay }
        if let sku = sku { dict["sku"] = sku }
        if let tags = tags { dict["tags"] = tags }
        if let description = description { dict["description"] = description }
        return dict
    }

    /// Create DTO from InventoryItem (for creating snapshot items)
    static func from(item: InventoryItem, snapshotId: String) -> InventorySnapshotItemDTO {
        return InventorySnapshotItemDTO(
            id: "",  // Will be assigned by Bubble
            snapshot: snapshotId,
            originalItemId: item.id,
            name: item.name,
            quantity: item.quantity,
            unitDisplay: item.unit?.display,
            sku: item.sku,
            tags: item.tagNames,
            description: item.itemDescription
        )
    }
}

/// Bubble's response when creating a new snapshot item
struct InventorySnapshotItemCreationResponse: Codable {
    let status: String
    let id: String
}
