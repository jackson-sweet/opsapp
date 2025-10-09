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

        // Fetch company to get task type IDs from the relationship
        let company = try await fetchCompany(id: companyId)

        // Extract task type IDs from the company's taskTypes relationship
        guard let taskTypeRefs = company.taskTypes, !taskTypeRefs.isEmpty else {
            return []
        }

        let taskTypeIds = taskTypeRefs.compactMap { $0.stringValue }

        // Fetch the specific task types by their IDs
        return try await fetchTaskTypesByIds(ids: taskTypeIds)
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
    
    /// Fetch specific task types by their IDs
    /// - Parameter ids: Array of task type IDs to fetch
    /// - Returns: Array of task type DTOs
    func fetchTaskTypesByIds(ids: [String]) async throws -> [TaskTypeDTO] {
        guard !ids.isEmpty else { return [] }
        
        
        // Create constraint for fetching specific IDs
        let constraints = [
            [
                "key": "_id",
                "constraint_type": "in",
                "value": ids
            ]
        ]
        
        return try await fetchBubbleObjectsWithArrayConstraints(
            objectType: BubbleFields.Types.taskType,
            constraints: constraints,
            sortField: BubbleFields.TaskType.display
        )
    }
    
    // MARK: - TaskType Creation
    
    /// Create a new task type
    /// - Parameter taskType: The task type DTO to create
    /// - Returns: The created task type DTO with server-assigned ID
    func createTaskType(_ taskType: TaskTypeDTO) async throws -> TaskTypeDTO {
        var taskTypeData: [String: Any] = [
            BubbleFields.TaskType.display: taskType.display,
            BubbleFields.TaskType.color: taskType.color,
            BubbleFields.TaskType.isDefault: taskType.isDefault ?? false
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: taskTypeData)

        let response: TaskTypeCreationResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.taskType)",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )

        return TaskTypeDTO(
            id: response.id,
            color: taskType.color,
            display: taskType.display,
            isDefault: taskType.isDefault,
            createdDate: nil,
            modifiedDate: nil
        )
    }
    
    // MARK: - TaskType Updates
    
    /// Update a task type
    /// - Parameters:
    ///   - id: The task type ID
    ///   - display: New display name (optional)
    ///   - color: New color (optional)
    ///   - icon: New icon (optional)
    func updateTaskType(id: String, display: String? = nil, color: String? = nil, icon: String? = nil) async throws {
        
        var updateData: [String: Any] = [:]
        
        if let display = display {
            updateData[BubbleFields.TaskType.display] = display
        }
        
        if let color = color {
            updateData[BubbleFields.TaskType.color] = color
        }
        
        // Note: Icon field doesn't exist in Bubble TaskType
        
        guard !updateData.isEmpty else {
            return
        }
        
        let bodyData = try JSONSerialization.data(withJSONObject: updateData)
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.taskType)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        
    }
    
    // MARK: - TaskType Deletion
    
    /// Delete a task type (only if not default and not in use)
    /// - Parameter id: The task type ID to delete
    func deleteTaskType(id: String) async throws {
        print("[API] Deleting task type: \(id)")

        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.taskType)/\(id)",
            method: "DELETE",
            body: nil,
            requiresAuth: false
        )

        print("[API] ✅ Task type deleted successfully")
    }
}