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
        
        print("Running Fetch Projects in Project Endpoints")
        
        // Create smart constraints for the API call
        var constraints: [String: Any] = [:]
        
        // 1. Company constraint - essential for focusing on relevant data
        if let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") {
            let companyConstraint: [String: Any] = [
                "key": BubbleFields.Project.company,
                "constraint_type": "equals",
                "value": companyId
            ]
            constraints["company"] = companyConstraint
        }
        
        // 2. Date constraint - only get projects in a reasonable time window
        // We'll get projects from X days ago through Y days in future
        let dateConstraints = constructSmartDateConstraint()
        constraints["date"] = dateConstraints
        
        // Convert constraints to JSON
        let constraintsJson = try JSONSerialization.data(withJSONObject: constraints)
        let constraintsString = String(data: constraintsJson, encoding: .utf8) ?? ""
        
        // Execute the targeted query
        struct ProjectsResponse: Decodable {
            let response: ResultsWrapper
            
            struct ResultsWrapper: Decodable {
                let cursor: Int
                let results: [ProjectDTO]
            }
        }
        
        let wrapper: ProjectsResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "cursor", value: "0"),
                URLQueryItem(name: "sort_field", value: BubbleFields.Project.startDate),
                URLQueryItem(name: "sort_order", value: "asc"),
                URLQueryItem(name: "constraints", value: constraintsString)
            ],
            requiresAuth: false
        )
        
        return wrapper.response.results
    }

    // Create a smarter date constraint
    private func constructSmartDateConstraint() -> [String: Any] {
        let calendar = Calendar.current
        let now = Date()
        
        // Get past date based on configuration
        let pastDate = calendar.date(
            byAdding: .day,
            value: -AppConfiguration.Sync.jobHistoryDays,
            to: now
        )!
        
        // Get future date based on configuration
        let futureDate = calendar.date(
            byAdding: .day,
            value: AppConfiguration.Sync.jobFutureDays,
            to: now
        )!
        
        let dateFormatter = ISO8601DateFormatter()
        
        // Build date range constraint
        return [
            "or": [
                [
                    "key": BubbleFields.Project.startDate,
                    "constraint_type": "greater than",
                    "value": dateFormatter.string(from: pastDate)
                ],
                [
                    "key": BubbleFields.Project.startDate,
                    "constraint_type": "less than",
                    "value": dateFormatter.string(from: futureDate)
                ],
                // Always include active projects regardless of date
                [
                    "key": BubbleFields.Project.status,
                    "constraint_type": "equals",
                    "value": BubbleFields.JobStatus.inProgress
                ]
            ]
        ]
    }
    
    /// Fetch a single project by ID
    /// - Parameter id: The project ID
    /// - Returns: Project DTO
    func fetchProject(id: String) async throws -> ProjectDTO {
        // Create wrapper for single project response
        struct ProjectResponse: Decodable {
            let response: ProjectDTO
        }
        
        let wrapper: ProjectResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)/\(id)",
            requiresAuth: false
        )
        
        return wrapper.response
    }
    
    /// Update a project's status
    /// - Parameters:
    ///   - id: The project ID
    ///   - status: The new status string
    func updateProjectStatus(id: String, status: String) async throws {
        let statusData = [BubbleFields.Project.status: status]
        let bodyData = try JSONSerialization.data(withJSONObject: statusData)
        
        // Create wrapper for empty response
        struct EmptyDataResponse: Decodable {
            let response: EmptyResponse
        }
        
        let _: EmptyDataResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
    }
    
    /// Fetch projects assigned to a specific user
    /// - Parameter userId: The user ID
    /// - Returns: Array of project DTOs
    /*
    func fetchUserProjects(userId: String) async throws -> [ProjectDTO] {
        
        print("running FetchUserProjects")
        
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
        
        // Create a wrapper structure to match Bubble's response format
        struct ProjectsResponse: Decodable {
            let response: ResultsWrapper
            
            struct ResultsWrapper: Decodable {
                let cursor: Int
                let results: [ProjectDTO]
            }
        }
        
        // Fetch with proper response handling
        let wrapper: ProjectsResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "cursor", value: "0"),
                URLQueryItem(name: "sort_field", value: BubbleFields.Project.startDate),
                URLQueryItem(name: "sort_order", value: "asc"),
                URLQueryItem(name: "constraints", value: jsonString)
            ],
            requiresAuth: false
        )
        
        // Return just the projects array
        return wrapper.response.results
    }
     */
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
        
        print("🔍 Fetching projects for user ID: \(userId)")
        print("🔍 With constraint: \(jsonString)")
        
        // Create a wrapper structure to match Bubble's response format
        struct ProjectsResponse: Decodable {
            let response: ResultsWrapper
            
            struct ResultsWrapper: Decodable {
                let cursor: Int
                let results: [ProjectDTO]
                let remaining: Int?
                let count: Int?
            }
        }
        
        // Add queryItems for debugging - higher limit to ensure we get everything
        let queryItems = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "cursor", value: "0"),
            URLQueryItem(name: "sort_field", value: BubbleFields.Project.startDate),
            URLQueryItem(name: "sort_order", value: "asc"),
            URLQueryItem(name: "constraints", value: jsonString)
        ]
        
        do {
            // Log the raw endpoint we're hitting
            let endpoint = "api/1.1/obj/\(BubbleFields.Types.project)"
            print("🔍 API Endpoint: \(endpoint)")
            
            // Fetch with proper response handling
            let wrapper: ProjectsResponse = try await executeRequest(
                endpoint: endpoint,
                queryItems: queryItems,
                requiresAuth: false
            )
            
            // Log the response details
            print("🔍 API Response - cursor: \(wrapper.response.cursor)")
            print("🔍 API Response - count: \(wrapper.response.count ?? 0)")
            print("🔍 API Response - remaining: \(wrapper.response.remaining ?? 0)")
            print("🔍 API Response - results count: \(wrapper.response.results.count)")
            
            // Log the actual projects received
            if wrapper.response.results.isEmpty {
                print("❌ No projects returned from API")
            } else {
                print("✅ Projects returned: \(wrapper.response.results.count)")
                
                // Print brief summary of each project
                for (index, project) in wrapper.response.results.enumerated() {
                    print("  Project \(index+1): \(project.projectName), ID: \(project.id)")
                    // If there are team members, print them
                    if let teamMembers = project.teamMembers, !teamMembers.isEmpty {
                        print("    Team Members: \(teamMembers)")
                    } else {
                        print("    ⚠️ No team members assigned!")
                    }
                }
            }
            
            // Return just the projects array
            //1745476201929x236655048429806000
            return wrapper.response.results
        } catch {
            print("❌ Error fetching user projects: \(error)")
            throw error
        }
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
        
        // Create a wrapper structure to match Bubble's response format
        struct ProjectsResponse: Decodable {
            let response: ResultsWrapper
            
            struct ResultsWrapper: Decodable {
                let cursor: Int
                let results: [ProjectDTO]
            }
        }
        
        // Fetch with proper response handling
        let wrapper: ProjectsResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "cursor", value: "0"),
                URLQueryItem(name: "sort_field", value: BubbleFields.Project.startDate),
                URLQueryItem(name: "sort_order", value: "asc"),
                URLQueryItem(name: "constraints", value: jsonString)
            ],
            requiresAuth: false
        )
        
        // Return just the projects array
        return wrapper.response.results
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
