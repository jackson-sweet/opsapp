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

    func updateProject(id: String, updates: [String: Any]) async throws {
        let bodyData = try JSONSerialization.data(withJSONObject: updates)

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
                // Define all possible response fields
                let result: String?
                let message: String?
                let status: String?
                
                // Use coding keys to handle snake_case conversion
                enum CodingKeys: String, CodingKey {
                    case result
                    case message
                    case status = "status" // Using fallback as the API might return just "status" instead of "new_status"
                }
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
        
        // Execute the request
        let response: CompleteProjectResponse = try await executeRequest(
            endpoint: "api/1.1/wf/update_job_status",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )
        
        // Log detailed response for debugging
        if let result = response.response.result {
        }
        if let message = response.response.message {
        }
        if let responseStatus = response.response.status {
        }
        
        // Return the status or fallback to the requested status if not available
        return response.response.status ?? status
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
    
    /// Start a project by updating its status to 'In Progress'
    /// - Parameter id: The project ID to start
    /// - Returns: The updated status string from the server
    func startProject(id: String) async throws -> String {
        // Set the status to 'In Progress'
        return try await completeProject(projectId: id, status: BubbleFields.JobStatus.inProgress)
    }
    
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

    /// Create a new project on Bubble
    /// - Parameter project: The local project to create
    /// - Returns: The Bubble-assigned project ID
    func createProject(_ project: Project) async throws -> String {
        print("[CREATE_PROJECT] Building project data for: \(project.title)")

        var projectData: [String: Any] = [
            BubbleFields.Project.projectName: project.title,
            BubbleFields.Project.status: project.status.rawValue,
            BubbleFields.Project.company: project.companyId,
            BubbleFields.Project.allDay: project.allDay
        ]

        print("[CREATE_PROJECT] Required fields - name: \(project.title), status: \(project.status.rawValue), company: \(project.companyId), allDay: \(project.allDay)")

        if let clientId = project.clientId {
            projectData[BubbleFields.Project.client] = clientId
            print("[CREATE_PROJECT] Client ID: \(clientId)")
        } else {
            print("[CREATE_PROJECT] ⚠️ No client ID - project will be created without client reference")
        }

        if let address = project.address, !address.isEmpty {
            // Bubble expects Address as a structured object, not a string
            var addressObject: [String: Any] = ["address": address]

            if let lat = project.latitude {
                addressObject["lat"] = lat
            }

            if let lng = project.longitude {
                addressObject["lng"] = lng
            }

            projectData[BubbleFields.Project.address] = addressObject
            print("[CREATE_PROJECT] Address object: \(addressObject)")
        }

        if let description = project.projectDescription, !description.isEmpty {
            projectData[BubbleFields.Project.description] = description
            print("[CREATE_PROJECT] Description: \(description)")
        }

        if let notes = project.notes, !notes.isEmpty {
            projectData[BubbleFields.Project.teamNotes] = notes
            print("[CREATE_PROJECT] Notes: \(notes)")
        }

        // Only send dates if explicitly set
        if let startDate = project.startDate {
            let startDateString = DateFormatter.bubbleFormatter.string(from: startDate)
            projectData[BubbleFields.Project.startDate] = startDateString
            print("[CREATE_PROJECT] Start date: \(startDateString)")
        } else {
            print("[CREATE_PROJECT] No start date - project is unscheduled")
        }

        if let endDate = project.endDate {
            let dateString = DateFormatter.bubbleFormatter.string(from: endDate)
            projectData[BubbleFields.Project.completion] = dateString
            print("[CREATE_PROJECT] End date: \(dateString)")
        } else {
            print("[CREATE_PROJECT] No end date")
        }

        if !project.teamMembers.isEmpty {
            let memberIds = project.teamMembers.map { $0.id }
            projectData[BubbleFields.Project.teamMembers] = memberIds
            print("[CREATE_PROJECT] Team members: \(memberIds)")
        } else {
            print("[CREATE_PROJECT] No team members")
        }

        if let eventType = project.eventType {
            // Bubble expects capitalized values: "Task" or "Project"
            let bubbleEventType = eventType.rawValue.capitalized
            projectData["eventType"] = bubbleEventType
            print("[CREATE_PROJECT] Event type: \(bubbleEventType)")
        }

        let bodyData = try JSONSerialization.data(withJSONObject: projectData)

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[CREATE_PROJECT] Request body JSON: \(jsonString)")
        }

        print("[CREATE_PROJECT] Sending POST to: api/1.1/obj/\(BubbleFields.Types.project)")

        struct CreateResponse: Codable {
            let id: String
        }

        do {
            let response: CreateResponse = try await executeRequest(
                endpoint: "api/1.1/obj/\(BubbleFields.Types.project)",
                method: "POST",
                body: bodyData,
                requiresAuth: false
            )

            print("[CREATE_PROJECT] ✅ Success! Bubble ID: \(response.id)")
            return response.id
        } catch {
            print("[CREATE_PROJECT] ❌ Error creating project: \(error)")
            throw error
        }
    }

    /// Delete a project from Bubble
    /// - Parameter id: The project ID to delete
    func deleteProject(id: String) async throws {
        print("[DELETE_PROJECT] Deleting project: \(id)")

        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)/\(id)",
            method: "DELETE",
            body: nil,
            requiresAuth: false
        )

        print("[DELETE_PROJECT] ✅ Project deleted successfully")
    }

    /// Link a project to a client's Projects List
    /// - Parameters:
    ///   - clientId: The client ID
    ///   - projectId: The project ID to link
    func linkProjectToClient(clientId: String, projectId: String) async throws {
        print("[LINK_PROJECT_TO_CLIENT] 🔵 Linking project to client")
        print("[LINK_PROJECT_TO_CLIENT] Project ID: \(projectId)")
        print("[LINK_PROJECT_TO_CLIENT] Client ID: \(clientId)")

        let client = try await fetchClient(id: clientId)
        print("[LINK_PROJECT_TO_CLIENT] ✅ Client fetched")

        var projectIds: [String] = []
        if let projects = client.projectsList {
            projectIds = projects
            print("[LINK_PROJECT_TO_CLIENT] 📋 Existing projects in client: \(projectIds.count)")
        } else {
            print("[LINK_PROJECT_TO_CLIENT] ⚠️ Client has no projects")
        }

        if !projectIds.contains(projectId) {
            projectIds.append(projectId)
            print("[LINK_PROJECT_TO_CLIENT] ➕ Adding project to client projects list")
        } else {
            print("[LINK_PROJECT_TO_CLIENT] ℹ️ Project already in client projects list")
            return
        }

        let updateData: [String: Any] = [BubbleFields.Client.projectsList: projectIds]
        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[LINK_PROJECT_TO_CLIENT] 📤 Update payload: \(jsonString)")
        }

        print("[LINK_PROJECT_TO_CLIENT] 📡 Sending PATCH request to Bubble...")
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.client)/\(clientId)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        print("[LINK_PROJECT_TO_CLIENT] ✅ Project successfully linked to client")
    }

    /// Link a project to a company's Projects list
    /// - Parameters:
    ///   - companyId: The company ID
    ///   - projectId: The project ID to link
    func linkProjectToCompany(companyId: String, projectId: String) async throws {
        print("[LINK_PROJECT_TO_COMPANY] 🔵 Linking project to company")
        print("[LINK_PROJECT_TO_COMPANY] Project ID: \(projectId)")
        print("[LINK_PROJECT_TO_COMPANY] Company ID: \(companyId)")

        let company = try await fetchCompany(id: companyId)
        print("[LINK_PROJECT_TO_COMPANY] ✅ Company fetched")

        var projectIds: [String] = []
        if let projects = company.projects {
            projectIds = projects.compactMap { $0.stringValue }
            print("[LINK_PROJECT_TO_COMPANY] 📋 Existing projects in company: \(projectIds.count)")
        } else {
            print("[LINK_PROJECT_TO_COMPANY] ⚠️ Company has no projects")
        }

        if !projectIds.contains(projectId) {
            projectIds.append(projectId)
            print("[LINK_PROJECT_TO_COMPANY] ➕ Adding project to company projects list")
        } else {
            print("[LINK_PROJECT_TO_COMPANY] ℹ️ Project already in company projects list")
            return
        }

        let updateData: [String: Any] = [BubbleFields.Company.projects: projectIds]
        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[LINK_PROJECT_TO_COMPANY] 📤 Update payload: \(jsonString)")
        }

        print("[LINK_PROJECT_TO_COMPANY] 📡 Sending PATCH request to Bubble...")
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.company)/\(companyId)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        print("[LINK_PROJECT_TO_COMPANY] ✅ Project successfully linked to company")
    }

    func updateProjectTeamMembers(projectId: String, teamMemberIds: [String]) async throws {
        print("[UPDATE_PROJECT_TEAM] 🔄 Updating project team members in Bubble...")
        print("[UPDATE_PROJECT_TEAM] Project ID: \(projectId)")
        print("[UPDATE_PROJECT_TEAM] Team Members: \(teamMemberIds)")

        let updateData: [String: Any] = [
            BubbleFields.Project.teamMembers: teamMemberIds
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        print("[UPDATE_PROJECT_TEAM] 📡 Sending PATCH request to Bubble...")
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)/\(projectId)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        print("[UPDATE_PROJECT_TEAM] ✅ Team members successfully updated in Bubble")
    }

    func updateProjectDates(projectId: String, startDate: Date?, endDate: Date?) async throws {
        print("[UPDATE_PROJECT_DATES] 🔄 Updating project dates in Bubble...")
        print("[UPDATE_PROJECT_DATES] Project ID: \(projectId)")
        print("[UPDATE_PROJECT_DATES] Start: \(startDate?.description ?? "nil"), End: \(endDate?.description ?? "nil")")

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        var updateData: [String: Any] = [:]

        if let start = startDate {
            updateData[BubbleFields.Project.startDate] = dateFormatter.string(from: start)
        }

        if let end = endDate {
            updateData[BubbleFields.Project.completion] = dateFormatter.string(from: end)
        }

        guard !updateData.isEmpty else {
            print("[UPDATE_PROJECT_DATES] ⚠️ No dates to update")
            return
        }

        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        print("[UPDATE_PROJECT_DATES] 📡 Sending PATCH request to Bubble...")
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.project)/\(projectId)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        print("[UPDATE_PROJECT_DATES] ✅ Dates successfully updated in Bubble")
    }

}
