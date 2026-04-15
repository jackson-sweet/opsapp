//
//  CalendarUserEvent.swift
//  OPS
//
//  User-owned calendar events (personal events + time off requests) — Supabase-backed
//

import SwiftData
import Foundation

enum CalendarUserEventType: String, Codable {
    case personal = "personal"
    case timeOff = "time_off"
}

enum CalendarUserEventStatus: String, Codable {
    case none = "none"
    case pending = "pending"
    case approved = "approved"
    case denied = "denied"
}

@Model
class CalendarUserEvent: Identifiable {
    @Attribute(.unique) var id: String
    var userId: String
    var companyId: String
    var type: String            // CalendarUserEventType.rawValue
    var title: String
    var startDate: Date
    var endDate: Date
    var allDay: Bool
    var notes: String?
    var status: String          // CalendarUserEventStatus.rawValue
    var address: String?
    var teamMemberIds: [String]?
    var reviewedBy: String?
    var reviewedAt: Date?
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?

    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String = UUID().uuidString,
        userId: String,
        companyId: String,
        type: CalendarUserEventType,
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool = true,
        notes: String? = nil,
        address: String? = nil,
        teamMemberIds: [String]? = nil
    ) {
        self.id = id
        self.userId = userId
        self.companyId = companyId
        self.type = type.rawValue
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.allDay = allDay
        self.notes = notes
        self.address = address
        self.teamMemberIds = teamMemberIds
        self.status = CalendarUserEventStatus.none.rawValue
        self.createdAt = Date()
    }

    // MARK: - Computed Accessors

    var eventType: CalendarUserEventType {
        CalendarUserEventType(rawValue: type) ?? .personal
    }

    var eventStatus: CalendarUserEventStatus {
        CalendarUserEventStatus(rawValue: status) ?? .none
    }

    var isTimeOff: Bool { eventType == .timeOff }
    var isPersonal: Bool { eventType == .personal }
    var isPending: Bool { eventStatus == .pending }

    /// Returns true if this event overlaps the given date
    func overlaps(date: Date) -> Bool {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return startDate < dayEnd && endDate > dayStart
    }
}
