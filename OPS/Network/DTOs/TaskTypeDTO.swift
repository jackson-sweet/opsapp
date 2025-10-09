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

    // Coding keys to match Bubble field names exactly
    // Note: Bubble uses "id" for POST responses and "_id" for GET responses
    enum CodingKeys: String, CodingKey {
        case id
        case color = "Color"
        case display = "Display"
        case isDefault = "isDefault"
        case createdDate = "Created Date"
        case modifiedDate = "Modified Date"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try "id" first (POST response), fall back to "_id" (GET response)
        if let idValue = try? container.decode(String.self, forKey: .id) {
            self.id = idValue
        } else {
            // Try "_id" as fallback
            let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
            self.id = try dynamicContainer.decode(String.self, forKey: DynamicCodingKey(stringValue: "_id")!)
        }

        self.color = try container.decode(String.self, forKey: .color)
        self.display = try container.decode(String.self, forKey: .display)
        self.isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault)
        self.createdDate = try container.decodeIfPresent(String.self, forKey: .createdDate)
        self.modifiedDate = try container.decodeIfPresent(String.self, forKey: .modifiedDate)
    }

    init(id: String, color: String, display: String, isDefault: Bool?, createdDate: String?, modifiedDate: String?) {
        self.id = id
        self.color = color
        self.display = display
        self.isDefault = isDefault
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
            modifiedDate: nil
        )
    }
}

/// Bubble's response when creating a new task type (just returns status and ID)
struct TaskTypeCreationResponse: Codable {
    let status: String
    let id: String
}