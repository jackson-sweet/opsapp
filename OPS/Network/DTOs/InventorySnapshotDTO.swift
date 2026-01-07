//
//  InventorySnapshotDTO.swift
//  OPS
//
//  Data Transfer Object for InventorySnapshot from Bubble API
//

import Foundation

/// Data Transfer Object for InventorySnapshot from Bubble API
struct InventorySnapshotDTO: Codable {
    let id: String
    let company: String?
    let createdAt: String?
    let createdBy: String?  // User ID
    let isAutomatic: Bool?
    let itemCount: Int?
    let notes: String?

    // Metadata
    let createdDate: String?
    let modifiedDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case company = "company"
        case createdAt = "createdAt"
        case createdBy = "createdBy"
        case isAutomatic = "isAutomatic"
        case itemCount = "itemCount"
        case notes = "notes"
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

        self.company = try container.decodeIfPresent(String.self, forKey: .company)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        self.createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        self.isAutomatic = try container.decodeIfPresent(Bool.self, forKey: .isAutomatic)
        self.itemCount = try container.decodeIfPresent(Int.self, forKey: .itemCount)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.createdDate = try container.decodeIfPresent(String.self, forKey: .createdDate)
        self.modifiedDate = try container.decodeIfPresent(String.self, forKey: .modifiedDate)
    }

    init(
        id: String,
        company: String?,
        createdAt: String?,
        createdBy: String?,
        isAutomatic: Bool?,
        itemCount: Int?,
        notes: String?,
        createdDate: String? = nil,
        modifiedDate: String? = nil
    ) {
        self.id = id
        self.company = company
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.isAutomatic = isAutomatic
        self.itemCount = itemCount
        self.notes = notes
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
        if let company = company { dict["company"] = company }
        if let createdAt = createdAt { dict["createdAt"] = createdAt }
        if let createdBy = createdBy { dict["createdBy"] = createdBy }
        if let isAutomatic = isAutomatic { dict["isAutomatic"] = isAutomatic }
        if let itemCount = itemCount { dict["itemCount"] = itemCount }
        if let notes = notes { dict["notes"] = notes }
        return dict
    }
}

/// Bubble's response when creating a new snapshot
struct InventorySnapshotCreationResponse: Codable {
    let status: String
    let id: String
}
