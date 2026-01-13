//
//  InventoryTagDTO.swift
//  OPS
//
//  Data Transfer Object for Tag from Bubble API
//

import Foundation

/// Data Transfer Object for Tag from Bubble API
struct InventoryTagDTO: Codable {
    // Tag properties from Bubble
    let id: String
    let name: String?
    let warningThreshold: Double?
    let criticalThreshold: Double?
    let company: String?  // Company ID reference

    // Metadata
    let createdDate: String?
    let modifiedDate: String?

    // Soft delete support
    let deletedAt: String?

    // Coding keys to match Bubble field names exactly
    enum CodingKeys: String, CodingKey {
        case id
        case name = "name"
        case warningThreshold = "warningThreshold"
        case criticalThreshold = "criticalThreshold"
        case company = "company"
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
        self.warningThreshold = try container.decodeIfPresent(Double.self, forKey: .warningThreshold)
        self.criticalThreshold = try container.decodeIfPresent(Double.self, forKey: .criticalThreshold)
        self.company = try container.decodeIfPresent(String.self, forKey: .company)
        self.createdDate = try container.decodeIfPresent(String.self, forKey: .createdDate)
        self.modifiedDate = try container.decodeIfPresent(String.self, forKey: .modifiedDate)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
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

    /// Memberwise initializer for creating DTOs programmatically
    init(
        id: String,
        name: String?,
        warningThreshold: Double?,
        criticalThreshold: Double?,
        company: String?,
        createdDate: String? = nil,
        modifiedDate: String? = nil,
        deletedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.company = company
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.deletedAt = deletedAt
    }

    /// Convert DTO to SwiftData model
    func toModel() -> InventoryTag {
        return InventoryTag(
            id: id,
            name: name ?? "",
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold,
            companyId: company ?? ""
        )
    }

    /// Update existing model from DTO
    func updateModel(_ model: InventoryTag) {
        model.name = name ?? ""
        model.warningThreshold = warningThreshold
        model.criticalThreshold = criticalThreshold
        model.companyId = company ?? ""
        model.lastSyncedAt = Date()
        model.needsSync = false
    }

    /// Create DTO from model
    static func from(_ model: InventoryTag) -> InventoryTagDTO {
        return InventoryTagDTO(
            id: model.id,
            name: model.name,
            warningThreshold: model.warningThreshold,
            criticalThreshold: model.criticalThreshold,
            company: model.companyId
        )
    }

    /// Create dictionary for Bubble API updates
    static func dictionaryFrom(_ model: InventoryTag) -> [String: Any] {
        var dict: [String: Any] = [
            BubbleFields.Tag.name: model.name,
            BubbleFields.Tag.company: model.companyId
        ]

        if let warning = model.warningThreshold {
            dict[BubbleFields.Tag.warningThreshold] = warning
        }

        if let critical = model.criticalThreshold {
            dict[BubbleFields.Tag.criticalThreshold] = critical
        }

        return dict
    }
}

/// Response from Bubble when creating a new Tag
struct InventoryTagCreationResponse: Codable {
    let id: String
}
