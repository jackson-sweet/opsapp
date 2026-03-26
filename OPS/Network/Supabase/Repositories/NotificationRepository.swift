//
//  NotificationRepository.swift
//  OPS
//
//  Repository for in-app notification operations via Supabase.
//  Table: notifications
//

import Foundation
import Supabase

class NotificationRepository {
    private let client: SupabaseClient

    init() {
        self.client = SupabaseService.shared.client
    }

    // MARK: - Create

    struct CreateNotificationDTO: Codable {
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

        enum CodingKeys: String, CodingKey {
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
        }
    }

    /// Insert a new notification row (used for expense/invoice events)
    func createNotification(_ dto: CreateNotificationDTO) async throws {
        try await client
            .from("notifications")
            .insert(dto)
            .execute()
    }

    // MARK: - Fetch

    /// Fetch unread notification count for a user (server-side count, no row transfer)
    func fetchUnreadCount(userId: String) async throws -> Int {
        let response = try await client
            .from("notifications")
            .select("id", head: true, count: .exact)
            .eq("user_id", value: userId)
            .eq("is_read", value: false)
            .execute()
        return response.count ?? 0
    }

    /// Fetch recent notifications for a user (last 50)
    func fetchRecent(userId: String, limit: Int = 50) async throws -> [NotificationDTO] {
        try await client
            .from("notifications")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    // MARK: - Mark Read

    /// Mark a single notification as read
    func markAsRead(_ notificationId: String) async throws {
        struct MarkRead: Codable {
            let is_read: Bool
        }
        try await client
            .from("notifications")
            .update(MarkRead(is_read: true))
            .eq("id", value: notificationId)
            .execute()
    }

    /// Mark all notifications as read for a user
    func markAllAsRead(userId: String) async throws {
        struct MarkRead: Codable {
            let is_read: Bool
        }
        try await client
            .from("notifications")
            .update(MarkRead(is_read: true))
            .eq("user_id", value: userId)
            .eq("is_read", value: false)
            .execute()
    }
}
