//
//  NotificationDTO.swift
//  OPS
//
//  Data Transfer Object for notifications Supabase table.
//

import Foundation

struct NotificationDTO: Codable, Identifiable {
    let id: String
    let userId: String
    let companyId: String
    let type: String
    let title: String
    let body: String
    let projectId: String?
    let noteId: String?
    let expenseId: String?
    let batchId: String?
    let deepLinkType: String?
    let actionUrl: String?
    let actionLabel: String?
    let persistent: Bool?
    let dedupeKey: String?
    let resolvedAt: String?
    let resolvedBy: String?
    let resolutionReason: String?
    var isRead: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId      = "user_id"
        case companyId   = "company_id"
        case type
        case title
        case body
        case projectId   = "project_id"
        case noteId      = "note_id"
        case expenseId   = "expense_id"
        case batchId     = "batch_id"
        case deepLinkType = "deep_link_type"
        case actionUrl   = "action_url"
        case actionLabel = "action_label"
        case persistent
        case dedupeKey   = "dedupe_key"
        case resolvedAt  = "resolved_at"
        case resolvedBy  = "resolved_by"
        case resolutionReason = "resolution_reason"
        case isRead      = "is_read"
        case createdAt   = "created_at"
    }
}
