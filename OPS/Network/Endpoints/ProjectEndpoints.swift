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
        return try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "cursor", value: "0"),
                URLQueryItem(name: "sort_field", value: BubbleFields.Project.startDate),
                URLQueryItem(name: "sort_order", value: "asc"),
                URLQueryItem(name: "constraints", value: constructDateConstraint())
            ]
        )
    }
    
    /// Fetch a single project by ID
    /// - Parameter id: The project ID
    /// - Returns: Project DTO
    func fetchProject(id: String) async throws -> ProjectDTO {
        return try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)/\(id)"
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
            body: bodyData
        )
    }
    
    /// Fetch projects assigned to a specific user
    /// - Parameter userId: The user ID
    /// - Returns: Array of project DTOs
    func fetchUserProjects(userId: String) async throws -> [ProjectDTO] {
        // Create constraint for team members containing this user
        let memberConstraint: [String: Any] = [
            "key": BubbleFields.Project.teamMembers,
            "constraint_type": "contains",
            "value": userId
        ]
        
        // Convert to JSON string
        guard let jsonData = try? JSONSerialization.data(withJSONObject: memberConstraint),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw APIError.invalidURL
        }
        
        return try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "cursor", value: "0"),
                URLQueryItem(name: "sort_field", value: BubbleFields.Project.startDate),
                URLQueryItem(name: "sort_order", value: "asc"),
                URLQueryItem(name: "constraints", value: jsonString)
            ]
        )
    }
    
    /// Fetch projects by status
    /// - Parameter status: The status to filter by
    /// - Returns: Array of project DTOs
    func fetchProjectsByStatus(status: String) async throws -> [ProjectDTO] {
        // Create constraint for status
        let statusConstraint: [String: Any] = [
            "key": BubbleFields.Project.status,
            "constraint_type": "equals",
            "value": status
        ]
        
        // Convert to JSON string
        guard let jsonData = try? JSONSerialization.data(withJSONObject: statusConstraint),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw APIError.invalidURL
        }
        
        return try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "cursor", value: "0"),
                URLQueryItem(name: "sort_field", value: BubbleFields.Project.startDate),
                URLQueryItem(name: "sort_order", value: "asc"),
                URLQueryItem(name: "constraints", value: jsonString)
            ]
        )
    }
    
    /// Construct a date constraint for project queries
    /// Focuses on recent projects and upcoming projects
    private func constructDateConstraint() -> String {
        // Get past date based on configuration
        let calendar = Calendar.current
        let now = Date()
        let pastDate = calendar.date(
            byAdding: .day,
            value: -AppConfiguration.Sync.jobHistoryDays,
            to: now
        )!
        
        let dateFormatter = ISO8601DateFormatter()
        
        // JSON structure for Bubble's API
        let constraints: [String: Any] = [
            "or": [
                // All projects with start date >= configured past date
                [
                    "key": BubbleFields.Project.startDate,
                    "constraint_type": "greater than",
                    "value": dateFormatter.string(from: pastDate)
                ],
                // Plus any in-progress projects
                [
                    "key": BubbleFields.Project.status,
                    "constraint_type": "equals",
                    "value": BubbleFields.JobStatus.inProgress
                ]
            ]
        ]
        
        // Convert to JSON string
        if let jsonData = try? JSONSerialization.data(withJSONObject: constraints),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        // Fallback - if JSON conversion fails
        return ""
    }
}
