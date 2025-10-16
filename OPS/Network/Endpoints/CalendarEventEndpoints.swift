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
    
    /// Create a new calendar event
    /// - Parameter event: The calendar event DTO to create
    /// - Returns: The created calendar event DTO with server-assigned ID
    func createCalendarEvent(_ event: CalendarEventDTO) async throws -> CalendarEventDTO {

        let dateFormatter = ISO8601DateFormatter()

        // Prepare event data for creation
        var eventData: [String: Any] = [
            BubbleFields.CalendarEvent.title: event.title ?? "Untitled",
            BubbleFields.CalendarEvent.projectId: event.projectId ?? "",
            BubbleFields.CalendarEvent.companyId: event.companyId ?? "",
            BubbleFields.CalendarEvent.duration: event.duration ?? 1,
            BubbleFields.CalendarEvent.color: event.color ?? "#59779F",
            BubbleFields.CalendarEvent.type: event.type ?? "Project"
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

        let bodyData = try JSONSerialization.data(withJSONObject: updates)

        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.calendarEvent)/\(id)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )

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
        print("[LINK_EVENT_TO_COMPANY] 🔵 Linking calendar event to company")
        print("[LINK_EVENT_TO_COMPANY] Event ID: \(calendarEventId)")
        print("[LINK_EVENT_TO_COMPANY] Company ID: \(companyId)")

        // Fetch company to get existing calendar events
        let company = try await fetchCompany(id: companyId)
        print("[LINK_EVENT_TO_COMPANY] ✅ Company fetched")

        // Get existing event IDs
        var eventIds: [String] = []
        if let events = company.calendarEventsList {
            eventIds = events.compactMap { $0.stringValue }
            print("[LINK_EVENT_TO_COMPANY] 📋 Existing events in company: \(eventIds.count)")
        } else {
            print("[LINK_EVENT_TO_COMPANY] ⚠️ Company has no calendar events")
        }

        // Add new event if not already present
        if !eventIds.contains(calendarEventId) {
            eventIds.append(calendarEventId)
            print("[LINK_EVENT_TO_COMPANY] ➕ Adding event to company events list")
        } else {
            print("[LINK_EVENT_TO_COMPANY] ℹ️ Event already in company events list")
            return
        }

        // Update company with new events list
        let updateData: [String: Any] = ["Calendar.EventsList": eventIds]
        let bodyData = try JSONSerialization.data(withJSONObject: updateData)

        if let jsonString = String(data: bodyData, encoding: .utf8) {
            print("[LINK_EVENT_TO_COMPANY] 📤 Update payload: \(jsonString)")
        }

        print("[LINK_EVENT_TO_COMPANY] 📡 Sending PATCH request to Bubble...")
        let _: EmptyResponse = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.company)/\(companyId)",
            method: "PATCH",
            body: bodyData,
            requiresAuth: false
        )
        print("[LINK_EVENT_TO_COMPANY] ✅ Calendar event successfully linked to company")
    }
}