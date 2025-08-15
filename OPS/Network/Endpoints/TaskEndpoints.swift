//
//  TaskEndpoints.swift
//  OPS
//
//  API endpoints for task-based scheduling
//

import Foundation

/// Extension for task-related API endpoints
extension APIService {
    
    // MARK: - Task Fetching
    
    /// Fetch all tasks for a project
    /// - Parameter projectId: The project ID
    /// - Returns: Array of task DTOs
    func fetchProjectTasks(projectId: String) async throws -> [TaskDTO] {
        print("🔵 APIService: Fetching tasks for project \(projectId)")
        
        let constraints: [[String: Any]] = [
            [
                "key": BubbleFields.Task.projectID,
                "constraint_type": "equals",
                "value": projectId
            ]
        ]
        
        return try await fetchBubbleObjectsWithArrayConstraints(
            objectType: BubbleFields.Types.task,
            constraints: constraints,
            sortField: BubbleFields.Task.taskIndex
        )
    }
    
    /// Fetch all tasks for a company
    /// - Parameter companyId: The company ID
    /// - Returns: Array of task DTOs
    func fetchCompanyTasks(companyId: String) async throws -> [TaskDTO] {
        print("\n📋 ==== FETCHING TASKS ====")
        print("🔵 APIService: Fetching all tasks for company \(companyId)")
        
        let constraints: [[String: Any]] = [
            [
                "key": BubbleFields.Task.companyId,
                "constraint_type": "equals",
                "value": companyId
            ]
        ]
        
        let tasks: [TaskDTO] = try await fetchBubbleObjectsWithArrayConstraints(
            objectType: BubbleFields.Types.task,
            constraints: constraints,
            sortField: BubbleFields.Task.taskIndex
        )
        
        print("📋 Found \(tasks.count) tasks")
        
        // Group by status
        let scheduled = tasks.filter { $0.status == "Scheduled" }
        let inProgress = tasks.filter { $0.status == "In Progress" }
        let completed = tasks.filter { $0.status == "Completed" }
        let cancelled = tasks.filter { $0.status == "Cancelled" }
        
        print("   - Scheduled: \(scheduled.count)")
        print("   - In Progress: \(inProgress.count)")
        print("   - Completed: \(completed.count)")
        print("   - Cancelled: \(cancelled.count)")
        
        // Group by project
        let projectIds = Set(tasks.compactMap { $0.projectId })
        print("   - Across \(projectIds.count) unique projects")
        
        print("📋 ==== END TASKS ====\n")
        
        return tasks
    }
    
    /// Fetch tasks assigned to a specific user
    /// - Parameter userId: The user ID
    /// - Returns: Array of task DTOs
    func fetchUserTasks(userId: String) async throws -> [TaskDTO] {
        print("🔵 APIService: Fetching tasks for user \(userId)")
        
        let constraints: [[String: Any]] = [
            [
                "key": BubbleFields.Task.teamMembers,
                "constraint_type": "contains",
                "value": userId
            ]
        ]
        
        return try await fetchBubbleObjectsWithArrayConstraints(
            objectType: BubbleFields.Types.task,
            constraints: constraints,
            sortField: BubbleFields.Task.taskIndex
        )
    }
    
    /// Fetch a single task by ID
    /// - Parameter id: The task ID
    /// - Returns: Task DTO
    func fetchTask(id: String) async throws -> TaskDTO {
        return try await fetchBubbleObject(
            objectType: BubbleFields.Types.task,
            id: id
        )
    }
    
    // MARK: - Task Updates
    
    /// Update a task's status
    /// - Parameters:
    ///   - id: The task ID
    ///   - status: The new status string
    func updateTaskStatus(id: String, status: String) async throws {
        print("🔵 APIService: Updating task \(id) status to \(status)")
        
        let statusData = [BubbleFields.Task.status: status]
        let bodyData = try JSONSerialization.data(withJSONObject: statusData)
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.task)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        
        print("✅ Task status updated successfully")
    }
    
    /// Update task notes
    /// - Parameters:
    ///   - id: The task ID
    ///   - notes: The new notes text
    func updateTaskNotes(id: String, notes: String) async throws {
        print("🔵 APIService: Updating task \(id) notes")
        
        let updateData = [BubbleFields.Task.taskNotes: notes]
        let bodyData = try JSONSerialization.data(withJSONObject: updateData)
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.task)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        
        print("✅ Task notes updated successfully")
    }
    
    /// Update task team members
    /// - Parameters:
    ///   - id: The task ID
    ///   - teamMemberIds: Array of user IDs assigned to the task
    func updateTaskTeamMembers(id: String, teamMemberIds: [String]) async throws {
        print("🔵 APIService: Updating task \(id) team members")
        
        let updateData = [BubbleFields.Task.teamMembers: teamMemberIds]
        let bodyData = try JSONSerialization.data(withJSONObject: updateData)
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.task)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        
        print("✅ Task team members updated successfully")
    }
    
    // MARK: - Task Creation
    
    /// Create a new task
    /// - Parameter task: The task DTO to create
    /// - Returns: The created task DTO with server-assigned ID
    func createTask(_ task: TaskDTO) async throws -> TaskDTO {
        print("🔵 APIService: Creating new task")
        
        // Prepare task data for creation
        var taskData: [String: Any] = [:]
        
        // Add required and optional fields
        if let projectId = task.projectId {
            taskData[BubbleFields.Task.projectID] = projectId
        }
        if let companyId = task.companyId {
            taskData[BubbleFields.Task.companyId] = companyId
        }
        if let type = task.type {
            taskData[BubbleFields.Task.type] = type
        }
        if let status = task.status {
            taskData[BubbleFields.Task.status] = status
        }
        if let taskColor = task.taskColor {
            taskData[BubbleFields.Task.taskColor] = taskColor
        }
        
        // Add optional fields
        if let notes = task.taskNotes {
            taskData[BubbleFields.Task.taskNotes] = notes
        }
        
        if let teamMembers = task.teamMembers {
            taskData[BubbleFields.Task.teamMembers] = teamMembers
        }
        
        if let taskIndex = task.taskIndex {
            taskData[BubbleFields.Task.taskIndex] = taskIndex
        }
        
        if let calendarEventId = task.calendarEventId {
            taskData[BubbleFields.Task.calendarEventId] = calendarEventId
        }
        
        let bodyData = try JSONSerialization.data(withJSONObject: taskData)
        
        // Create the task and get the response
        let response: BubbleObjectResponse<TaskDTO> = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.task)",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )
        
        print("✅ Task created successfully with ID: \(response.response.id)")
        return response.response
    }
    
    // MARK: - Task Deletion
    
    /// Delete a task
    /// - Parameter id: The task ID to delete
    func deleteTask(id: String) async throws {
        print("🔵 APIService: Deleting task \(id)")
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.task)/\(id)",
            method: "DELETE",
            body: nil,
            requiresAuth: false
        )
        
        print("✅ Task deleted successfully")
    }
}