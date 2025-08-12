//
//  TaskTypeDTO.swift
//  OPS
//
//  Data Transfer Object for TaskType from Bubble API
//

import Foundation

/// Data Transfer Object for TaskType from Bubble API
struct TaskTypeDTO: Codable {
    // TaskType properties from Bubble
    let id: String
    let color: String
    let display: String
    let icon: String?
    let isDefault: Bool?
    let companyId: String
    let displayOrder: Int?
    
    // Metadata
    let createdDate: String?
    let modifiedDate: String?
    
    // Coding keys to match Bubble field names
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case color = "Color"
        case display = "Display"
        case icon = "Icon"
        case isDefault = "Is Default"
        case companyId = "Company"
        case displayOrder = "Display Order"
        case createdDate = "Created Date"
        case modifiedDate = "Modified Date"
    }
    
    /// Convert DTO to SwiftData model
    func toModel() -> TaskType {
        let taskType = TaskType(
            id: id,
            display: display,
            color: color,
            companyId: companyId,
            isDefault: isDefault ?? false,
            icon: icon
        )
        
        taskType.displayOrder = displayOrder ?? 0
        
        return taskType
    }
    
    /// Create DTO from SwiftData model
    static func from(_ taskType: TaskType) -> TaskTypeDTO {
        return TaskTypeDTO(
            id: taskType.id,
            color: taskType.color,
            display: taskType.display,
            icon: taskType.icon,
            isDefault: taskType.isDefault,
            companyId: taskType.companyId,
            displayOrder: taskType.displayOrder,
            createdDate: nil,
            modifiedDate: nil
        )
    }
}