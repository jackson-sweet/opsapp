//
//  CalendarUserEventDTOs.swift
//  OPS
//
//  Codable DTOs for calendar_user_events Supabase table
//

import Foundation

// MARK: - Read DTO

struct CalendarUserEventDTO: Codable, Identifiable {
    let id: String
    let userId: String
    let companyId: String
    let type: String
    let title: String
    let startDate: Date
    let endDate: Date
    let allDay: Bool
    let notes: String?
    let status: String
    let address: String?
    let teamMemberIds: [String]?
    let reviewedBy: String?
    let reviewedAt: Date?
    let createdAt: Date
    let updatedAt: Date?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case companyId = "company_id"
        case type
        case title
        case startDate = "start_date"
        case endDate = "end_date"
        case allDay = "all_day"
        case notes
        case status
        case address
        case teamMemberIds = "team_member_ids"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    func toModel() -> CalendarUserEvent {
        let event = CalendarUserEvent(
            id: id,
            userId: userId,
            companyId: companyId,
            type: CalendarUserEventType(rawValue: type) ?? .personal,
            title: title,
            startDate: startDate,
            endDate: endDate,
            allDay: allDay,
            notes: notes,
            address: address,
            teamMemberIds: teamMemberIds
        )
        event.status = status
        event.reviewedBy = reviewedBy
        event.reviewedAt = reviewedAt
        event.createdAt = createdAt
        event.updatedAt = updatedAt
        event.deletedAt = deletedAt
        event.lastSyncedAt = Date()
        return event
    }
}

// MARK: - Create DTO

struct CreateCalendarUserEventDTO: Codable {
    let userId: String
    let companyId: String
    let type: String
    let title: String
    let startDate: String   // ISO8601 string
    let endDate: String     // ISO8601 string
    let allDay: Bool
    let notes: String?
    let status: String
    var address: String? = nil
    var teamMemberIds: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case companyId = "company_id"
        case type
        case title
        case startDate = "start_date"
        case endDate = "end_date"
        case allDay = "all_day"
        case notes
        case status
        case address
        case teamMemberIds = "team_member_ids"
    }
}

// MARK: - Status Update DTO

struct CalendarUserEventStatusUpdateDTO: Codable {
    let status: String
    let reviewedBy: String
    let reviewedAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case updatedAt = "updated_at"
    }
}
