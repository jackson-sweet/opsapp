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
}
