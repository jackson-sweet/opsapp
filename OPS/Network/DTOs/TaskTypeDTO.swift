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
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case color = "Color"
        case display = "Display"
        case isDefault = "isDefault"
        case createdDate = "Created Date"
        case modifiedDate = "Modified Date"
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