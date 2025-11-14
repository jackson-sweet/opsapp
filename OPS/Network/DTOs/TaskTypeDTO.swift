//
//  TaskTypeDTO.swift
//  OPS
//
//  Data Transfer Object for TaskType from Bubble API
//

import Foundation

/// Data Transfer Object for TaskType from Bubble API
struct TaskTypeDTO: Codable {
    // TaskType properties from Bubble (based on screenshots)
    let id: String
    let color: String
    let display: String
    let isDefault: Bool?

    // Metadata
    let createdDate: String?
    let modifiedDate: String?

    // Soft delete support
    let deletedAt: String?

    // Coding keys to match Bubble field names exactly
    // Note: Bubble uses "id" for POST responses and "_id" for GET responses
    enum CodingKeys: String, CodingKey {
        case id
        case color = "color"
        case display = "display"
        case isDefault = "isDefault"
        case createdDate = "Created Date"  // Bubble default field
        case modifiedDate = "Modified Date"  // Bubble default field
        case deletedAt = "deletedAt"  // Soft delete timestamp
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

        self.color = try container.decode(String.self, forKey: .color)

        // Try lowercase "display" first, fall back to capitalized "Display" (for older Bubble data)
        if let displayValue = try? container.decode(String.self, forKey: .display) {
            self.display = displayValue
        } else {
            self.display = try dynamicContainer.decode(String.self, forKey: DynamicCodingKey(stringValue: "Display")!)
        }

        self.isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault)
        self.createdDate = try container.decodeIfPresent(String.self, forKey: .createdDate)
        self.modifiedDate = try container.decodeIfPresent(String.self, forKey: .modifiedDate)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
    }

    init(id: String, color: String, display: String, isDefault: Bool?, createdDate: String?, modifiedDate: String?, deletedAt: String? = nil) {
        self.id = id
        self.color = color
        self.display = display
        self.isDefault = isDefault
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
    func toModel() -> TaskType {
        // Note: companyId needs to be passed separately since it's not in the DTO
        let taskType = TaskType(
            id: id,
            display: display,
            color: color,
            companyId: "",  // Will need to be set by caller
            isDefault: isDefault ?? false,
            icon: nil  // Icon field doesn't exist in Bubble
        )

        taskType.displayOrder = 0  // Display order field doesn't exist in Bubble

        // Parse deletedAt if present
        if let deletedAtString = deletedAt {
            let formatter = ISO8601DateFormatter()
            taskType.deletedAt = formatter.date(from: deletedAtString)
        }

        return taskType
    }
    
    /// Create DTO from SwiftData model
    static func from(_ taskType: TaskType) -> TaskTypeDTO {
        return TaskTypeDTO(
            id: taskType.id,
            color: taskType.color,
            display: taskType.display,
            isDefault: taskType.isDefault,
            createdDate: nil,
            modifiedDate: nil,
            deletedAt: nil
        )
    }
}

/// Bubble's response when creating a new task type (just returns status and ID)
struct TaskTypeCreationResponse: Codable {
    let status: String
    let id: String
}