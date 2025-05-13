//
//  ProjectEndpoints.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
import Foundation

/// Extension for project-related API endpoints
extension APIService {
    
    /// Fetch all projects relevant to the field worker
    /// - Returns: Array of project DTOs
    func fetchProjects() async throws -> [ProjectDTO] {
        return try await fetchBubbleObjects(
            objectType: BubbleFields.Types.project,
            sortField: BubbleFields.Project.startDate
        )
    }

    /// Fetch a single project by ID
    /// - Parameter id: The project ID
    /// - Returns: Project DTO
    func fetchProject(id: String) async throws -> ProjectDTO {
        return try await fetchBubbleObject(
            objectType: BubbleFields.Types.project,
            id: id
        )
    }
    
    /// Update a project's status
    /// - Parameters:
    ///   - id: The project ID
    ///   - status: The new status string
    func updateProjectStatus(id: String, status: String) async throws {
        let statusData = [BubbleFields.Project.status: status]
        let bodyData = try JSONSerialization.data(withJSONObject: statusData)
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
    }
    
    /// Complete a project using the workflow endpoint
    /// - Parameters:
    ///   - projectId: The project ID to update
    ///   - status: The new status (typically "Completed")
    /// - Returns: The updated status string from the server
    func completeProject(projectId: String, status: String) async throws -> String {
        // Define response type for this specific endpoint
        struct CompleteProjectResponse: Decodable {
            let response: ResponseData
            
            struct ResponseData: Decodable {
                let new_status: String
            }
        }
        
        // Create the request body
        let requestData: [String: String] = [
            "project_id": projectId,
            "status": status
        ]
        
        // Convert to JSON
        let bodyData = try JSONSerialization.data(withJSONObject: requestData)
        
        // Log the request
        print("🔷 Sending update_job_status request for project: \(projectId) with status: \(status)")
        
        // Execute the request
        let response: CompleteProjectResponse = try await executeRequest(
            endpoint: "api/1.1/wf/update_job_status",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )
        
        // Log the response
        print("✅ Project status updated successfully. New status: \(response.response.new_status)")
        
        // Return the new status from the response
        return response.response.new_status
    }
    
    /// Fetch projects assigned to a specific user
    /// - Parameter userId: The user ID to filter for
    /// - Returns: Array of project DTOs where user is a team member
    func fetchUserProjects(userId: String) async throws -> [ProjectDTO] {
        // Create constraint in array format exactly as shown in the example URL
        let constraints: [[String: Any]] = [
            [
                "key": "Team Members",
                "constraint_type": "contains",
                "value": userId
            ]
        ]
        
        return try await fetchBubbleObjectsWithArrayConstraints(
            objectType: BubbleFields.Types.project,
            constraints: constraints,
            sortField: BubbleFields.Project.startDate
        )
    }

    
    /// Fetch projects by status
    /// - Parameter status: The status to filter by
    /// - Returns: Array of project DTOs
    func fetchProjectsByStatus(status: String) async throws -> [ProjectDTO] {
        let statusConstraint: [String: Any] = [
            "key": BubbleFields.Project.status,
            "constraint_type": "equals",
            "value": status
        ]
        
        return try await fetchBubbleObjects(
            objectType: BubbleFields.Types.project,
            constraints: statusConstraint,
            sortField: BubbleFields.Project.startDate
        )
    }
    
    /// Fetch projects assigned to a user with a specific status
    /// - Parameters:
    ///   - userId: The user ID
    ///   - status: The status to filter by
    /// - Returns: Array of project DTOs
    func fetchUserProjectsByStatus(userId: String, status: String) async throws -> [ProjectDTO] {
        let statusConstraint: [String: Any] = [
            "key": BubbleFields.Project.status,
            "constraint_type": "equals",
            "value": status
        ]
        
        let combined = andConstraints([
            userConstraint(userId: userId),
            statusConstraint
        ])
        
        return try await fetchBubbleObjects(
            objectType: BubbleFields.Types.project,
            constraints: combined,
            sortField: BubbleFields.Project.startDate
        )
    }
    
    /// Fetch projects for a specific date
    /// - Parameter date: The date to filter by
    /// - Returns: Array of project DTOs
    func fetchProjectsForDate(date: Date) async throws -> [ProjectDTO] {
        // Create date range for the entire day
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return try await fetchBubbleObjects(
            objectType: BubbleFields.Types.project,
            constraints: dateRangeConstraint(
                field: BubbleFields.Project.startDate,
                startDate: startOfDay,
                endDate: endOfDay
            ),
            sortField: BubbleFields.Project.startDate
        )
    }
    
    /// Fetch projects for a user on a specific date
    /// - Parameters:
    ///   - userId: The user ID
    ///   - date: The date to filter by
    /// - Returns: Array of project DTOs
    func fetchUserProjectsForDate(userId: String, date: Date) async throws -> [ProjectDTO] {
        // Create date range for the entire day
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let combined = andConstraints([
            userConstraint(userId: userId),
            dateRangeConstraint(
                field: BubbleFields.Project.startDate,
                startDate: startOfDay,
                endDate: endOfDay
            )
        ])
        
        return try await fetchBubbleObjects(
            objectType: BubbleFields.Types.project,
            constraints: combined,
            sortField: BubbleFields.Project.startDate
        )
    }
    
    // MARK: Update Data

    /// Update project notes
    /// - Parameters:
    ///   - id: The project ID
    ///   - notes: The new notes text
    func updateProjectNotes(id: String, notes: String) async throws {
        let updateData = [BubbleFields.Project.teamNotes: notes]
        let bodyData = try JSONSerialization.data(withJSONObject: updateData)
        
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
    }
    
}
