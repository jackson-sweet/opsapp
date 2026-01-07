//
//  InventoryUnitDTO.swift
//  OPS
//
//  Data Transfer Object for InventoryUnit from Bubble API
//

import Foundation

/// Data Transfer Object for InventoryUnit from Bubble API
struct InventoryUnitDTO: Codable {
    // InventoryUnit properties from Bubble
    let id: String
    let display: String
    let company: String?
    let isDefault: Bool?
    let sortOrder: Int?

    // Metadata
    let createdDate: String?
    let modifiedDate: String?

    // Soft delete support
    let deletedAt: String?

    // Coding keys to match Bubble field names exactly
    enum CodingKeys: String, CodingKey {
        case id
        case display = "display"
        case company = "company"
        case isDefault = "isDefault"
        case sortOrder = "sortOrder"
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

        // Try lowercase "display" first, fall back to capitalized "Display"
        if let displayValue = try? container.decode(String.self, forKey: .display) {
            self.display = displayValue
        } else {
            self.display = try dynamicContainer.decode(String.self, forKey: DynamicCodingKey(stringValue: "Display")!)
        }

        self.company = try container.decodeIfPresent(String.self, forKey: .company)
        self.isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault)
        self.sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
        self.createdDate = try container.decodeIfPresent(String.self, forKey: .createdDate)
        self.modifiedDate = try container.decodeIfPresent(String.self, forKey: .modifiedDate)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
    }

    init(id: String, display: String, company: String?, isDefault: Bool?, sortOrder: Int?, createdDate: String?, modifiedDate: String?, deletedAt: String? = nil) {
        self.id = id
        self.display = display
        self.company = company
        self.isDefault = isDefault
        self.sortOrder = sortOrder
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
    func toModel() -> InventoryUnit {
        let unit = InventoryUnit(
            id: id,
            display: display,
            companyId: company ?? "",
            isDefault: isDefault ?? false,
            sortOrder: sortOrder ?? 0
        )

        // Parse deletedAt if present
        if let deletedAtString = deletedAt {
            let formatter = ISO8601DateFormatter()
            unit.deletedAt = formatter.date(from: deletedAtString)
        }

        unit.lastSyncedAt = Date()

        return unit
    }

    /// Create DTO from SwiftData model
    static func from(_ unit: InventoryUnit) -> InventoryUnitDTO {
        return InventoryUnitDTO(
            id: unit.id,
            display: unit.display,
            company: unit.companyId,
            isDefault: unit.isDefault,
            sortOrder: unit.sortOrder,
            createdDate: nil,
            modifiedDate: nil,
            deletedAt: nil
        )
    }

    /// Convert to dictionary for API requests
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "display": display
        ]
        if let company = company { dict["company"] = company }
        if let isDefault = isDefault { dict["isDefault"] = isDefault }
        if let sortOrder = sortOrder { dict["sortOrder"] = sortOrder }
        return dict
    }
}

/// Bubble's response when creating a new inventory unit
struct InventoryUnitCreationResponse: Codable {
    let status: String
    let id: String
}
