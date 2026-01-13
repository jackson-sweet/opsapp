//
//  InventoryItemDTO.swift
//  OPS
//
//  Data Transfer Object for InventoryItem from Bubble API
//

import Foundation

/// Data Transfer Object for InventoryItem from Bubble API
struct InventoryItemDTO: Codable {
    // InventoryItem properties from Bubble
    let id: String
    let name: String?
    let description: String?
    let quantity: Double?
    let unit: String?  // Unit ID reference
    let tags: [String]?  // List of tags
    let company: String?  // Company ID reference
    let sku: String?
    let notes: String?
    let imageUrl: String?

    // Threshold properties
    let warningThreshold: Double?
    let criticalThreshold: Double?

    // Metadata
    let createdDate: String?
    let modifiedDate: String?

    // Soft delete support
    let deletedAt: String?

    // Coding keys to match Bubble field names exactly
    enum CodingKeys: String, CodingKey {
        case id
        case name = "name"
        case description = "description"
        case quantity = "quantity"
        case unit = "unit"
        case tags = "tags"
        case company = "company"
        case sku = "sku"
        case notes = "notes"
        case imageUrl = "imageUrl"
        case warningThreshold = "warningThreshold"
        case criticalThreshold = "criticalThreshold"
        case createdDate = "Created Date"
        case modifiedDate = "Modified Date"
        case deletedAt = "deletedAt"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)

        // Try "id" first (POST response), fall back to "_id" (GET response)
        if let idValue = try? container.decode(String.self, forKey: .id) {
            self.id = idValue
        } else {
            self.id = try dynamicContainer.decode(String.self, forKey: DynamicCodingKey(stringValue: "_id")!)
        }

        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        self.unit = try container.decodeIfPresent(String.self, forKey: .unit)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags)
        self.company = try container.decodeIfPresent(String.self, forKey: .company)
        self.sku = try container.decodeIfPresent(String.self, forKey: .sku)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        self.warningThreshold = try container.decodeIfPresent(Double.self, forKey: .warningThreshold)
        self.criticalThreshold = try container.decodeIfPresent(Double.self, forKey: .criticalThreshold)
        self.createdDate = try container.decodeIfPresent(String.self, forKey: .createdDate)
        self.modifiedDate = try container.decodeIfPresent(String.self, forKey: .modifiedDate)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
    }

    init(
        id: String,
        name: String?,
        description: String?,
        quantity: Double?,
        unit: String?,
        tags: [String]?,
        company: String?,
        sku: String?,
        notes: String?,
        imageUrl: String?,
        warningThreshold: Double? = nil,
        criticalThreshold: Double? = nil,
        createdDate: String?,
        modifiedDate: String?,
        deletedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.quantity = quantity
        self.unit = unit
        self.tags = tags
        self.company = company
        self.sku = sku
        self.notes = notes
        self.imageUrl = imageUrl
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.deletedAt = deletedAt
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

    /// Convert DTO to SwiftData model
    func toModel() -> InventoryItem {
        let item = InventoryItem(
            id: id,
            name: name ?? "Unnamed Item",
            quantity: quantity ?? 0,
            companyId: company ?? "",
            unitId: unit,
            itemDescription: description,
            tagIds: tags ?? [],
            sku: sku,
            notes: notes,
            imageUrl: imageUrl,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold
        )

        // Parse deletedAt if present
        if let deletedAtString = deletedAt {
            let formatter = ISO8601DateFormatter()
            item.deletedAt = formatter.date(from: deletedAtString)
        }

        item.lastSyncedAt = Date()

        return item
    }

    /// Create DTO from SwiftData model
    static func from(_ item: InventoryItem) -> InventoryItemDTO {
        return InventoryItemDTO(
            id: item.id,
            name: item.name,
            description: item.itemDescription,
            quantity: item.quantity,
            unit: item.unitId,
            tags: item.tagIds,
            company: item.companyId,
            sku: item.sku,
            notes: item.notes,
            imageUrl: item.imageUrl,
            warningThreshold: item.warningThreshold,
            criticalThreshold: item.criticalThreshold,
            createdDate: nil,
            modifiedDate: nil,
            deletedAt: nil
        )
    }

    /// Convert to dictionary for API requests
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let name = name { dict["name"] = name }
        if let description = description { dict["description"] = description }
        if let quantity = quantity { dict["quantity"] = quantity }
        if let unit = unit { dict["unit"] = unit }
        if let tags = tags { dict["tags"] = tags }
        if let company = company { dict["company"] = company }
        if let sku = sku { dict["sku"] = sku }
        if let notes = notes { dict["notes"] = notes }
        if let imageUrl = imageUrl { dict["imageUrl"] = imageUrl }
        if let warningThreshold = warningThreshold { dict["warningThreshold"] = warningThreshold }
        if let criticalThreshold = criticalThreshold { dict["criticalThreshold"] = criticalThreshold }
        return dict
    }

    /// Create dictionary from SwiftData model for API requests
    static func dictionaryFrom(_ item: InventoryItem) -> [String: Any] {
        var dict: [String: Any] = [
            "name": item.name,
            "quantity": item.quantity,
            "company": item.companyId
        ]
        if let description = item.itemDescription { dict["description"] = description }
        if let unit = item.unitId { dict["unit"] = unit }
        if !item.tagIds.isEmpty { dict["tags"] = item.tagIds }
        if let sku = item.sku { dict["sku"] = sku }
        if let notes = item.notes { dict["notes"] = notes }
        if let imageUrl = item.imageUrl { dict["imageUrl"] = imageUrl }
        if let warningThreshold = item.warningThreshold { dict["warningThreshold"] = warningThreshold }
        if let criticalThreshold = item.criticalThreshold { dict["criticalThreshold"] = criticalThreshold }
        return dict
    }
}

/// Bubble's response when creating a new inventory item
struct InventoryItemCreationResponse: Codable {
    let status: String
    let id: String
}
