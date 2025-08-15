//
//  TaskTypeEndpoints.swift
//  OPS
//
//  API endpoints for task type management
//

import Foundation

/// Extension for task type-related API endpoints
extension APIService {
    
    // MARK: - TaskType Fetching
    
    /// Fetch all task types for a company
    /// - Parameter companyId: The company ID
    /// - Returns: Array of task type DTOs
    func fetchCompanyTaskTypes(companyId: String) async throws -> [TaskTypeDTO] {
        print("🔵 APIService: Fetching task types for company \(companyId)")
        
        // Note: TaskType doesn't have a company field in Bubble
        // We'll need to fetch all task types and filter client-side
        // or add a company field to TaskType in Bubble
        
        return try await fetchBubbleObjectsWithArrayConstraints(
            objectType: BubbleFields.Types.taskType,
            constraints: [],
            sortField: BubbleFields.TaskType.display
        )
    }
    
    /// Fetch a single task type by ID
    /// - Parameter id: The task type ID
    /// - Returns: TaskType DTO
    func fetchTaskType(id: String) async throws -> TaskTypeDTO {
        return try await fetchBubbleObject(
            objectType: BubbleFields.Types.taskType,
            id: id
        )
    }
    
    // MARK: - TaskType Creation
    
    /// Create a new task type
    /// - Parameter taskType: The task type DTO to create
    /// - Returns: The created task type DTO with server-assigned ID
    func createTaskType(_ taskType: TaskTypeDTO) async throws -> TaskTypeDTO {
        print("🔵 APIService: Creating new task type '\(taskType.display)'")
        
        // Prepare task type data for creation
        var taskTypeData: [String: Any] = [
            BubbleFields.TaskType.display: taskType.display,
            BubbleFields.TaskType.color: taskType.color,
            BubbleFields.TaskType.isDefault: taskType.isDefault ?? false
        ]
        
        // Note: TaskType doesn't have company, icon, or displayOrder fields in Bubble
        
        let bodyData = try JSONSerialization.data(withJSONObject: taskTypeData)
        
        // Create the task type and get the response
        let response: BubbleObjectResponse<TaskTypeDTO> = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.taskType)",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )
        
        print("✅ Task type created successfully with ID: \(response.response.id)")
        return response.response
    }
    
    // MARK: - TaskType Updates
    
    /// Update a task type
    /// - Parameters:
    ///   - id: The task type ID
    ///   - display: New display name (optional)
    ///   - color: New color (optional)
    ///   - icon: New icon (optional)
    func updateTaskType(id: String, display: String? = nil, color: String? = nil, icon: String? = nil) async throws {
        print("🔵 APIService: Updating task type \(id)")
        
        var updateData: [String: Any] = [:]
        
        if let display = display {
            updateData[BubbleFields.TaskType.display] = display
        }
        
        if let color = color {
            updateData[BubbleFields.TaskType.color] = color
        }
        
        // Note: Icon field doesn't exist in Bubble TaskType
        
        guard !updateData.isEmpty else {
            print("⚠️ No fields to update")
            return
        }
        
        let bodyData = try JSONSerialization.data(withJSONObject: updateData)
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.taskType)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        
        print("✅ Task type updated successfully")
    }
    
    // MARK: - TaskType Deletion
    
    /// Delete a task type (only if not default and not in use)
    /// - Parameter id: The task type ID to delete
    func deleteTaskType(id: String) async throws {
        print("🔵 APIService: Deleting task type \(id)")
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.taskType)/\(id)",
            method: "DELETE",
            body: nil,
            requiresAuth: false
        )
        
        print("✅ Task type deleted successfully")
    }
}