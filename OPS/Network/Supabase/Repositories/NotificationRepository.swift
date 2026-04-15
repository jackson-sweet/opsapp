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
        /// Persistent notifications stay in the rail until explicitly
        /// resolved — used for long-running background tasks where the
        /// user is actively waiting for completion.
        let persistent: Bool?
        /// Destination when the user taps the notification's action button.
        /// Either a deep-link URL the app can resolve internally or a web URL.
        let actionUrl: String?
        /// Label for the action button on the notification card.
        let actionLabel: String?

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
            case persistent
            case actionUrl   = "action_url"
            case actionLabel = "action_label"
        }

        init(
            userId: String,
            companyId: String,
            type: String,
            title: String,
            body: String,
            projectId: String? = nil,
            noteId: String? = nil,
            expenseId: String? = nil,
            batchId: String? = nil,
            deepLinkType: String? = nil,
            persistent: Bool? = nil,
            actionUrl: String? = nil,
            actionLabel: String? = nil
        ) {
            self.userId = userId
            self.companyId = companyId
            self.type = type
            self.title = title
            self.body = body
            self.projectId = projectId
            self.noteId = noteId
            self.expenseId = expenseId
            self.batchId = batchId
            self.deepLinkType = deepLinkType
            self.persistent = persistent
            self.actionUrl = actionUrl
            self.actionLabel = actionLabel
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
