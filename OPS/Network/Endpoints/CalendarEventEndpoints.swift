//
//  CalendarEventEndpoints.swift
//  OPS
//
//  API endpoints for calendar events
//

import Foundation

/// Extension for calendar event-related API endpoints
extension APIService {
    
    // MARK: - Calendar Event Fetching
    
    /// Fetch all calendar events for a company
    /// - Parameter companyId: The company ID
    /// - Returns: Array of calendar event DTOs
    func fetchCompanyCalendarEvents(companyId: String) async throws -> [CalendarEventDTO] {
        
        let constraints: [[String: Any]] = [
            [
                "key": BubbleFields.CalendarEvent.companyId,
                "constraint_type": "equals",
                "value": companyId
            ]
        ]
        
        let events: [CalendarEventDTO] = try await fetchBubbleObjectsWithArrayConstraints(
            objectType: BubbleFields.Types.calendarEvent,
            constraints: constraints,
            sortField: BubbleFields.CalendarEvent.startDate
        )
        
        
        // Summary statistics (case-insensitive comparison)
        let projectEvents = events.filter { $0.type?.lowercased() == "project" && $0.taskId == nil }
        let taskEvents = events.filter { $0.type?.lowercased() == "task" && $0.taskId != nil }
        
        return events
    }
    
    /// Fetch calendar events for a specific project
    /// - Parameter projectId: The project ID
    /// - Returns: Array of calendar event DTOs
    func fetchProjectCalendarEvents(projectId: String) async throws -> [CalendarEventDTO] {
        
        let constraints: [[String: Any]] = [
            [
                "key": BubbleFields.CalendarEvent.projectId,
                "constraint_type": "equals",
                "value": projectId
            ]
        ]
        
        return try await fetchBubbleObjectsWithArrayConstraints(
            objectType: BubbleFields.Types.calendarEvent,
            constraints: constraints,
            sortField: BubbleFields.CalendarEvent.startDate
        )
    }
    
    /// Fetch calendar events for a date range
    /// - Parameters:
    ///   - companyId: The company ID
    ///   - startDate: Start of date range
    ///   - endDate: End of date range
    /// - Returns: Array of calendar event DTOs
    func fetchCalendarEvents(companyId: String, from startDate: Date, to endDate: Date) async throws -> [CalendarEventDTO] {
        
        let dateFormatter = ISO8601DateFormatter()
        
        let constraints: [[String: Any]] = [
            [
                "key": BubbleFields.CalendarEvent.companyId,
                "constraint_type": "equals",
                "value": companyId
            ],
            [
                "key": BubbleFields.CalendarEvent.startDate,
                "constraint_type": "greater than",
                "value": dateFormatter.string(from: startDate)
            ],
            [
                "key": BubbleFields.CalendarEvent.startDate,
                "constraint_type": "less than",
                "value": dateFormatter.string(from: endDate)
            ]
        ]
        
        return try await fetchBubbleObjectsWithArrayConstraints(
            objectType: BubbleFields.Types.calendarEvent,
            constraints: constraints,
            sortField: BubbleFields.CalendarEvent.startDate
        )
    }
    
    /// Fetch a single calendar event by ID
    /// - Parameter id: The calendar event ID
    /// - Returns: Calendar event DTO
    func fetchCalendarEvent(id: String) async throws -> CalendarEventDTO {
        return try await fetchBubbleObject(
            objectType: BubbleFields.Types.calendarEvent,
            id: id
        )
    }
    
    // MARK: - Calendar Event Creation

    /// Create a new calendar event and link it to the company
    /// This is the universal method that should be used for all calendar event creation
    /// - Parameter event: The calendar event DTO to create
    /// - Returns: The created calendar event DTO with server-assigned ID
    /// - Note: Automatically links the event based on its type:
    ///   - If type is "Project", links to project.calendarEvent field
    ///   - If type is "Task", links to task.calendarEventId field
    ///   - Always links to company.calendarEventsList
    func createAndLinkCalendarEvent(_ event: CalendarEventDTO) async throws -> CalendarEventDTO {
        print("[CREATE_AND_LINK_EVENT] 🆕 Creating and linking calendar event")
        print("[CREATE_AND_LINK_EVENT] Title: \(event.title ?? "Untitled")")
        print("[CREATE_AND_LINK_EVENT] Type: \(event.type ?? "Unknown")")
        print("[CREATE_AND_LINK_EVENT] Company ID: \(event.companyId ?? "Unknown")")
        print("[CREATE_AND_LINK_EVENT] Project ID: \(event.projectId ?? "Unknown")")
        print("[CREATE_AND_LINK_EVENT] Task ID: \(event.taskId ?? "Unknown")")

        let createdEvent = try await createCalendarEvent(event)
        print("[CREATE_AND_LINK_EVENT] ✅ Event created with ID: \(createdEvent.id)")

        // Auto-detect type and link appropriately
        let eventType = event.type?.lowercased() ?? ""

        if eventType == "project" {
            // Link to project's calendarEvent field
            if let projectId = event.projectId, !projectId.isEmpty {
                print("[CREATE_AND_LINK_EVENT] 🔗 Type is 'Project' - linking to project...")
                try await self.linkCalendarEventToProject(
                    projectId: projectId,
                    calendarEventId: createdEvent.id
                )
                print("[CREATE_AND_LINK_EVENT] ✅ Event linked to project")
            } else {
                print("[CREATE_AND_LINK_EVENT] ⚠️ Type is 'Project' but no project ID provided")
            }
        } else if eventType == "task" {
            // Link to task's calendarEventId field
            if let taskId = event.taskId, !taskId.isEmpty {
                print("[CREATE_AND_LINK_EVENT] 🔗 Type is 'Task' - linking to task...")
                try await self.linkCalendarEventToTask(
                    taskId: taskId,
                    calendarEventId: createdEvent.id
                )
                print("[CREATE_AND_LINK_EVENT] ✅ Event linked to task")
            } else {
                print("[CREATE_AND_LINK_EVENT] ⚠️ Type is 'Task' but no task ID provided")
            }
        } else {
            print("[CREATE_AND_LINK_EVENT] ⚠️ Unknown event type '\(eventType)' - skipping project/task linking")
        }

        // Always link to company (done last to ensure event exists)
        guard let companyId = event.companyId else {
            print("[CREATE_AND_LINK_EVENT] ⚠️ No company ID provided - skipping company link")
            return createdEvent
        }

        try await linkCalendarEventToCompany(
            companyId: companyId,
            calendarEventId: createdEvent.id
        )
        print("[CREATE_AND_LINK_EVENT] ✅ Event linked to company")

        return createdEvent
    }

    /// Create a new calendar event (low-level method)
    /// - Parameter event: The calendar event DTO to create
    /// - Returns: The created calendar event DTO with server-assigned ID
    /// - Warning: This method does NOT link the event to the company. Use createAndLinkCalendarEvent instead.
    func createCalendarEvent(_ event: CalendarEventDTO) async throws -> CalendarEventDTO {

        let dateFormatter = ISO8601DateFormatter()

        // Prepare event data for creation
        var eventData: [String: Any] = [
            BubbleFields.CalendarEvent.title: event.title ?? "Untitled",
            BubbleFields.CalendarEvent.projectId: event.projectId ?? "",
            BubbleFields.CalendarEvent.companyId: event.companyId ?? "",
            BubbleFields.CalendarEvent.duration: event.duration ?? 1,
            BubbleFields.CalendarEvent.color: event.color ?? "#59779F",
            BubbleFields.CalendarEvent.eventType: event.type ?? "Project"
        ]

        // Add dates if provided
        if let startDate = event.startDate {
            eventData[BubbleFields.CalendarEvent.startDate] = startDate
        }

        if let endDate = event.endDate {
            eventData[BubbleFields.CalendarEvent.endDate] = endDate
        }

        // Add optional fields
        if let taskId = event.taskId {
            eventData[BubbleFields.CalendarEvent.taskId] = taskId
        }

        if let teamMembers = event.teamMembers {
            eventData[BubbleFields.CalendarEvent.teamMembers] = teamMembers
        }

        if let active = event.active {
            eventData[BubbleFields.CalendarEvent.active] = active
        }

        let bodyData = try JSONSerialization.data(withJSONObject: eventData)

        struct CalendarEventCreationResponse: Codable {
            let id: String
        }

        // Create the event and get the response
        let response: CalendarEventCreationResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.calendarEvent)",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )

        // Return a DTO with the new ID
        return CalendarEventDTO(
            id: response.id,
            color: event.color,
            companyId: event.companyId,
            projectId: event.projectId,
            taskId: event.taskId,
            duration: event.duration,
            endDate: event.endDate,
            startDate: event.startDate,
            teamMembers: event.teamMembers,
            title: event.title,
            type: event.type,
            active: event.active,
            createdDate: nil,
            modifiedDate: nil
        )
    }
    
    // MARK: - Calendar Event Updates
    
    /// Update a calendar event
    /// - Parameters:
    ///   - id: The calendar event ID
    ///   - updates: Dictionary of fields to update
    func updateCalendarEvent(id: String, updates: [String: Any]) async throws {
        print("[UPDATE_CALENDAR_EVENT] 📅 Updating calendar event in Bubble...")
        print("[UPDATE_CALENDAR_EVENT] Event ID: \(id)")
        print("[UPDATE_CALENDAR_EVENT] Updates: \(updates)")

        let bodyData = try JSONSerialization.data(withJSONObject: updates)

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[UPDATE_CALENDAR_EVENT] 📤 Request Body JSON: \(jsonString)")
        }

        let endpoint = "api/1.1/obj/\(BubbleFields.Types.calendarEvent)/\(id)"
        print("[UPDATE_CALENDAR_EVENT] 📡 PATCH to: \(endpoint)")

        let _: EmptyResponse = try await executeRequest(
            endpoint: endpoint,
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )

        print("[UPDATE_CALENDAR_EVENT] ✅ Calendar event successfully updated in Bubble")
    }

    /// Update calendar event team members
    /// - Parameters:
    ///   - id: The calendar event ID
    ///   - teamMemberIds: Array of team member IDs
    func updateCalendarEventTeamMembers(id: String, teamMemberIds: [String]) async throws {
        print("[UPDATE_EVENT_TEAM] 🔄 Updating calendar event team members in Bubble...")
        print("[UPDATE_EVENT_TEAM] Event ID: \(id)")
        print("[UPDATE_EVENT_TEAM] Team Members: \(teamMemberIds)")

        let updateData: [String: Any] = [
            BubbleFields.CalendarEvent.teamMembers: teamMemberIds
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        print("[UPDATE_EVENT_TEAM] 📡 Sending PATCH request to Bubble...")
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.calendarEvent)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        print("[UPDATE_EVENT_TEAM] ✅ Calendar event team members successfully updated in Bubble")
    }
    
    /// Delete a calendar event
    /// - Parameter id: The calendar event ID to delete
    func deleteCalendarEvent(id: String) async throws {

        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.calendarEvent)/\(id)",
            method: "DELETE",
            body: nil,
            requiresAuth: false
        )

    }

    /// Link a calendar event to company's EventsList
    /// - Parameters:
    ///   - companyId: The company ID
    ///   - calendarEventId: The calendar event ID to link
    func linkCalendarEventToCompany(companyId: String, calendarEventId: String) async throws {
        print("[LINK_EVENT_TO_COMPANY] 🔵 Linking calendar event to company via workflow endpoint")
        print("[LINK_EVENT_TO_COMPANY] Event ID: \(calendarEventId)")
        print("[LINK_EVENT_TO_COMPANY] Company ID: \(companyId)")

        // Use workflow endpoint to add event to company list server-side
        let parameters: [String: Any] = [
            "calendarEvent": calendarEventId,
            "company": companyId
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: parameters)

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[LINK_EVENT_TO_COMPANY] 📤 Workflow parameters: \(jsonString)")
        }

        print("[LINK_EVENT_TO_COMPANY] 📡 Calling workflow endpoint...")
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/wf/add-calendar-event-to-company",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )
        print("[LINK_EVENT_TO_COMPANY] ✅ Calendar event successfully added to company list")
    }

    /// Link a calendar event to a task
    /// - Parameters:
    ///   - taskId: The task ID
    ///   - calendarEventId: The calendar event ID to link
    func linkCalendarEventToTask(taskId: String, calendarEventId: String) async throws {
        print("[LINK_EVENT_TO_TASK] 🔗 Linking calendar event to task")
        print("[LINK_EVENT_TO_TASK] Task ID: \(taskId)")
        print("[LINK_EVENT_TO_TASK] Event ID: \(calendarEventId)")
        print("[LINK_EVENT_TO_TASK] Field name in Bubble: '\(BubbleFields.Task.calendarEventId)'")

        let updateData: [String: Any] = [BubbleFields.Task.calendarEventId: calendarEventId]
        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[LINK_EVENT_TO_TASK] 📤 Request Body JSON: \(jsonString)")
        }

        let endpoint = "api/1.1/obj/\(BubbleFields.Types.task)/\(taskId)"
        print("[LINK_EVENT_TO_TASK] 📡 PATCH to: \(endpoint)")

        let _: EmptyResponse = try await executeRequest(
            endpoint: endpoint,
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )

        print("[LINK_EVENT_TO_TASK] ✅ Calendar event successfully linked to task")

        // Verify the update by fetching the task back
        print("[LINK_EVENT_TO_TASK] 🔍 Verifying task was updated...")
        let verifyEndpoint = "api/1.1/obj/\(BubbleFields.Types.task)/\(taskId)"

        struct TaskVerification: Codable {
            let calendarEventId: String?

            enum CodingKeys: String, CodingKey {
                case calendarEventId = "calendarEventId"
            }
        }

        let verifiedTask: TaskVerification = try await executeRequest(
            endpoint: verifyEndpoint,
            method: "GET",
            body: nil,
            requiresAuth: false
        )

        if let linkedEventId = verifiedTask.calendarEventId {
            print("[LINK_EVENT_TO_TASK] ✅ VERIFIED: Task.calendarEventId = \(linkedEventId)")
        } else {
            print("[LINK_EVENT_TO_TASK] ⚠️ WARNING: Task.calendarEventId is still empty!")
        }
    }
}