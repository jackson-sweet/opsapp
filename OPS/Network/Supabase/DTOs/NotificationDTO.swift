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
        case isRead      = "is_read"
        case createdAt   = "created_at"
    }
}
