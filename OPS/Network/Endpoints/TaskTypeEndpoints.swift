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
        print("[API_TASKTYPE_CREATE] 🔵 Starting task type creation")
        print("[API_TASKTYPE_CREATE] Display: \(taskType.display)")
        print("[API_TASKTYPE_CREATE] Color: \(taskType.color)")
        print("[API_TASKTYPE_CREATE] Is Default: \(taskType.isDefault ?? false)")

        let taskTypeData: [String: Any] = [
            BubbleFields.TaskType.display: taskType.display,
            BubbleFields.TaskType.color: taskType.color,
            BubbleFields.TaskType.isDefault: taskType.isDefault ?? false
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: taskTypeData)

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[API_TASKTYPE_CREATE] 📤 Request body: \(jsonString)")
        }

        print("[API_TASKTYPE_CREATE] 📡 Sending POST request to Bubble...")
        let response: TaskTypeCreationResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.taskType)",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )

        print("[API_TASKTYPE_CREATE] ✅ Bubble returned ID: \(response.id)")

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
        print("[UPDATE_TASK_TYPE] 📝 Updating task type: \(id)")

        var updateData: [String: Any] = [:]

        if let display = display {
            updateData[BubbleFields.TaskType.display] = display
            print("[UPDATE_TASK_TYPE] Display: \(display)")
        }

        if let color = color {
            // Ensure color has hash prefix for Bubble
            let colorWithHash = color.hasPrefix("#") ? color : "#\(color)"
            updateData[BubbleFields.TaskType.color] = colorWithHash
            print("[UPDATE_TASK_TYPE] Color: \(colorWithHash)")
        }

        // Note: Icon field doesn't exist in Bubble TaskType - icons are local only

        guard !updateData.isEmpty else {
            print("[UPDATE_TASK_TYPE] ⚠️ No updates to send")
            return
        }

        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[UPDATE_TASK_TYPE] 📤 Request body: \(jsonString)")
        }

        print("[UPDATE_TASK_TYPE] 📡 Sending PATCH request to Bubble...")
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.taskType)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )

        print("[UPDATE_TASK_TYPE] ✅ Task type successfully updated in Bubble")
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