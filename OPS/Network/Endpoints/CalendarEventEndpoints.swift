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
            BubbleFields.CalendarEvent.startDate: event.startDate ?? "",
            BubbleFields.CalendarEvent.endDate: event.endDate ?? "",
            BubbleFields.CalendarEvent.duration: event.duration ?? 1,
            BubbleFields.CalendarEvent.color: event.color ?? "#59779F",
            BubbleFields.CalendarEvent.type: event.type ?? "project"
        ]
        
        // Add optional fields
        if let taskId = event.taskId {
            eventData[BubbleFields.CalendarEvent.taskId] = taskId
        }
        
        if let teamMembers = event.teamMembers {
            eventData[BubbleFields.CalendarEvent.teamMembers] = teamMembers
        }
        
        let bodyData = try JSONSerialization.data(withJSONObject: eventData)
        
        // Create the event and get the response
        let response: BubbleObjectResponse<CalendarEventDTO> = try await executeRequest(
            endpoint: "api/1.1/obj/\(BubbleFields.Types.calendarEvent)",
            method: "POST",
            body: bodyData,
            requiresAuth: false
        )
        
        return response.response
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
}