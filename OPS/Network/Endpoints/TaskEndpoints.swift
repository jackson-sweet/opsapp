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
        
        let constraints: [[String: Any]] = [
            [
                "key": BubbleFields.Task.projectId,
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
        let historicalMonths = UserDefaults.standard.integer(forKey: "historicalDataMonths")
        let months = historicalMonths == 0 ? 6 : historicalMonths

        var constraints: [[String: Any]] = [
            [
                "key": BubbleFields.Task.companyId,
                "constraint_type": "equals",
                "value": companyId
            ]
        ]

        if months != -1 {
            let calendar = Calendar.current
            let cutoffDate = calendar.date(byAdding: .month, value: -months, to: Date()) ?? Date()
            let formatter = ISO8601DateFormatter()

            constraints.append([
                "key": "Created Date",  // Built-in Bubble field - CANNOT change
                "constraint_type": "greater than",
                "value": formatter.string(from: cutoffDate)
            ])
        }

        let tasks: [TaskDTO] = try await fetchBubbleObjectsWithArrayConstraints(
            objectType: BubbleFields.Types.task,
            constraints: constraints,
            limit: 500,
            sortField: BubbleFields.Task.taskIndex
        )


        // Group by status
        let scheduled = tasks.filter { $0.status == "Scheduled" }
        let inProgress = tasks.filter { $0.status == "In Progress" }
        let completed = tasks.filter { $0.status == "Completed" }
        let cancelled = tasks.filter { $0.status == "Cancelled" }


        // Group by project
        let projectIds = Set(tasks.compactMap { $0.projectId })


        return tasks
    }
    
    /// Fetch tasks assigned to a specific user
    /// - Parameter userId: The user ID
    /// - Returns: Array of task DTOs
    func fetchUserTasks(userId: String) async throws -> [TaskDTO] {
        
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

    /// Update task with arbitrary fields
    /// - Parameters:
    ///   - id: The task ID
    ///   - updates: Dictionary of fields to update
    func updateTask(id: String, updates: [String: Any]) async throws {
        let bodyData = try JSONSerialization.data(withJSONObject: updates)

        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.task)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
    }

    /// Update a task's status
    /// - Parameters:
    ///   - id: The task ID
    ///   - status: The new status string
    func updateTaskStatus(id: String, status: String) async throws {
        
        let statusData = [BubbleFields.Task.status: status]
        let bodyData = try JSONSerialization.data(withJSONObject: statusData)
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.task)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        
    }
    
    /// Update task notes
    /// - Parameters:
    ///   - id: The task ID
    ///   - notes: The new notes text
    func updateTaskNotes(id: String, notes: String) async throws {
        
        let updateData = [BubbleFields.Task.taskNotes: notes]
        let bodyData = try JSONSerialization.data(withJSONObject: updateData)
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.task)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        
    }
    
    /// Update task team members
    /// - Parameters:
    ///   - id: The task ID
    ///   - teamMemberIds: Array of user IDs assigned to the task
    func updateTaskTeamMembers(id: String, teamMemberIds: [String]) async throws {
        print("[UPDATE_TASK_TEAM] 🔄 Updating task team members in Bubble...")
        print("[UPDATE_TASK_TEAM] Task ID: \(id)")
        print("[UPDATE_TASK_TEAM] Team Members: \(teamMemberIds)")

        let updateData = [BubbleFields.Task.teamMembers: teamMemberIds]
        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        print("[UPDATE_TASK_TEAM] 📡 Sending PATCH request to Bubble...")
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.task)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        print("[UPDATE_TASK_TEAM] ✅ Task team members successfully updated in Bubble")

        // Also update the task's calendar event team members
        print("[UPDATE_TASK_TEAM] 🔄 Updating associated calendar event team members...")
        do {
            // Fetch the task to get its calendar event
            let taskDTO = try await fetchTask(id: id)

            if let calendarEventId = taskDTO.calendarEventId {
                print("[UPDATE_TASK_TEAM] Found calendar event: \(calendarEventId)")
                try await updateCalendarEventTeamMembers(
                    id: calendarEventId,
                    teamMemberIds: teamMemberIds
                )
                print("[UPDATE_TASK_TEAM] ✅ Calendar event team members updated")
            } else {
                print("[UPDATE_TASK_TEAM] ℹ️ No calendar event associated with this task")
            }
        } catch {
            print("[UPDATE_TASK_TEAM] ⚠️ Failed to update calendar event team members: \(error)")
            // Don't throw - task update succeeded, calendar event update is secondary
        }
    }

    /// Update task type
    /// - Parameters:
    ///   - id: The task ID
    ///   - taskTypeId: The new task type ID
    ///   - taskColor: The new task color (optional)
    func updateTaskType(id: String, taskTypeId: String, taskColor: String? = nil) async throws {
        print("[API] Updating task \(id) to task type: \(taskTypeId)")

        var updateData: [String: Any] = [BubbleFields.Task.type: taskTypeId]
        if let color = taskColor {
            updateData[BubbleFields.Task.taskColor] = color
        }
        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.task)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )

        print("[API] ✅ Task type updated successfully")
    }

    // MARK: - Task Creation
    
    /// Create a new task
    /// - Parameter task: The task DTO to create
    /// - Returns: The created task DTO with server-assigned ID
    func createTask(_ task: TaskDTO) async throws -> TaskDTO {
        print("[API_TASK_CREATE] 🔵 Starting task creation")
        print("[API_TASK_CREATE] Task ID: \(task.id)")
        print("[API_TASK_CREATE] Project ID: \(task.projectId ?? "nil")")
        print("[API_TASK_CREATE] Company ID: \(task.companyId ?? "nil")")
        print("[API_TASK_CREATE] Type: \(task.type ?? "nil")")
        print("[API_TASK_CREATE] Status: \(task.status ?? "nil")")
        print("[API_TASK_CREATE] 🎨 Task Color: \(task.taskColor ?? "nil")")

        // Prepare task data for creation
        var taskData: [String: Any] = [:]

        // Add required and optional fields
        if let projectId = task.projectId {
            taskData[BubbleFields.Task.projectId] = projectId
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

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[API_TASK_CREATE] 📤 Request body: \(jsonString)")
        }

        struct TaskCreationResponse: Codable {
            let id: String
        }

        print("[API_TASK_CREATE] 📡 Sending POST request to Bubble...")
        let response: TaskCreationResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.task)",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )

        print("[API_TASK_CREATE] ✅ Bubble returned ID: \(response.id)")

        // Link task to project
        if let projectId = task.projectId {
            print("[API_TASK_CREATE] 🔗 Linking task to project...")
            do {
                try await linkTaskToProject(taskId: response.id, projectId: projectId)
                print("[API_TASK_CREATE] ✅ Task linked to project")
            } catch {
                print("[API_TASK_CREATE] ⚠️ Failed to link task to project: \(error)")
            }
        }

        return TaskDTO(
            id: response.id,
            calendarEventId: task.calendarEventId,
            companyId: task.companyId,
            completionDate: nil,
            projectId: task.projectId,
            scheduledDate: nil,
            status: task.status,
            taskColor: task.taskColor,
            taskIndex: task.taskIndex,
            taskNotes: task.taskNotes,
            teamMembers: task.teamMembers,
            type: task.type,
            createdDate: nil,
            modifiedDate: nil
        )
    }

    /// Link a task to its parent project
    private func linkTaskToProject(taskId: String, projectId: String) async throws {
        print("[LINK_TASK_TO_PROJECT] 🔵 Starting to link task to project")
        print("[LINK_TASK_TO_PROJECT] Task ID: \(taskId)")
        print("[LINK_TASK_TO_PROJECT] Project ID: \(projectId)")

        print("[LINK_TASK_TO_PROJECT] 📡 Fetching project from Bubble...")
        let project = try await fetchProject(id: projectId)
        print("[LINK_TASK_TO_PROJECT] ✅ Project fetched: \(project.projectName)")

        var taskIds: [String] = []
        if let tasks = project.tasks {
            taskIds = tasks.compactMap { $0.stringValue }
            print("[LINK_TASK_TO_PROJECT] 📋 Existing tasks in project: \(taskIds)")
        } else {
            print("[LINK_TASK_TO_PROJECT] ⚠️ Project has no tasks field")
        }

        if !taskIds.contains(taskId) {
            taskIds.append(taskId)
            print("[LINK_TASK_TO_PROJECT] ➕ Adding task to project tasks list")
        } else {
            print("[LINK_TASK_TO_PROJECT] ℹ️ Task already in project tasks list")
        }

        let updateData: [String: Any] = [BubbleFields.Project.tasks: taskIds]
        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[LINK_TASK_TO_PROJECT] 📤 Update payload: \(jsonString)")
        }

        print("[LINK_TASK_TO_PROJECT] 📡 Sending PATCH request to Bubble...")
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)/\(projectId)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        print("[LINK_TASK_TO_PROJECT] ✅ Task successfully linked to project")
    }
    
    // MARK: - Task Deletion
    
    /// Delete a task
    /// - Parameter id: The task ID to delete
    func deleteTask(id: String) async throws {
        print("[DELETE_TASK] Deleting task: \(id)")

        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.task)/\(id)",
            method: "DELETE",
            body: nil,
            requiresAuth: false
        )

        print("[DELETE_TASK] ✅ Task deleted successfully")
    }

    // MARK: - Task Status Options

    /// Fetch all task status options for a company
    /// - Parameter companyId: The company ID
    /// - Returns: Array of task status option DTOs
    func fetchTaskStatusOptions(companyId: String) async throws -> [TaskStatusOptionDTO] {

        let constraints: [[String: Any]] = [
            [
                "key": BubbleFields.TaskStatusOption.company,
                "constraint_type": "equals",
                "value": companyId
            ]
        ]

        return try await fetchBubbleObjectsWithArrayConstraints(
            objectType: "task_status",
            constraints: constraints,
            sortField: BubbleFields.TaskStatusOption.index
        )
    }
}