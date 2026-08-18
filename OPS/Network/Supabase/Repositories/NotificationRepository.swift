//
//  NotificationRepository.swift
//  OPS
//
//  Repository for in-app notification operations via Supabase.
//  Table: notifications
//

import Foundation
import Supabase

/// Persistent rows represent unresolved conditions. Reading or navigating from
/// them must never masquerade as condition recovery.
enum NotificationReadPolicy {
    static let nonPersistentPostgrestFilter = "persistent.is.null,persistent.eq.false"

    static func shouldMarkRead(persistent: Bool?) -> Bool {
        persistent != true
    }
}

class NotificationRepository {
    /// Shared instance for call sites that don't need a per-instance repository.
    /// The repo is stateless beyond the Supabase client handle, so sharing
    /// is safe and avoids re-wiring unrelated callers.
    static let shared = NotificationRepository()

    /// Notification `type` the iOS rail suppresses everywhere (list + badge).
    /// `agent_suggestion` rows are web agent-queue proposals (action_url =
    /// /agent/queue) — reviewed/accepted/dismissed only on the web surface. iOS
    /// has no queue screen and the rows carry no target the app can act on, so
    /// surfacing them is a guaranteed dead-tap. Bug af27ea82.
    static let iosSuppressedType = "agent_suggestion"

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
            // Bug af27ea82 — agent_suggestion rows are web agent-queue items
            // (action_url = /agent/queue) with no iOS review surface and nothing
            // iOS can accept/dismiss. Keep them out of the badge count so the app
            // never advertises a notification it can't act on.
            .neq("type", value: NotificationRepository.iosSuppressedType)
            .execute()
        return response.count ?? 0
    }

    /// Returns true when a notification for the same typed action has already
    /// been created, read or unread. Weekly summary notifications use this to
    /// avoid duplicating a rail row after the operator has already opened it.
    func hasNotification(type: String, userId: String, actionUrl: String) async throws -> Bool {
        let response = try await client
            .from("notifications")
            .select("id", head: true, count: .exact)
            .eq("user_id", value: userId)
            .eq("type", value: type)
            .eq("action_url", value: actionUrl)
            .execute()
        return (response.count ?? 0) > 0
    }

    /// Fetch recent notifications for a user (last 50)
    func fetchRecent(userId: String, limit: Int = 50) async throws -> [NotificationDTO] {
        try await client
            .from("notifications")
            .select()
            .eq("user_id", value: userId)
            // Suppress web-only agent-queue proposals from the iOS rail — see
            // `iosSuppressedType`. Bug af27ea82.
            .neq("type", value: NotificationRepository.iosSuppressedType)
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
            .or(NotificationReadPolicy.nonPersistentPostgrestFilter)
            .execute()
    }

    /// Marks all unread notifications of a given `type` as read for the user.
    /// Used to auto-resolve rail entries after the user addresses the underlying
    /// issue (e.g., `photo_storage_limit` clears when budget is raised or
    /// oldest photos are evicted).
    func markAllAsReadByType(type: String, userId: String) async throws {
        struct MarkRead: Codable {
            let is_read: Bool
        }
        try await client
            .from("notifications")
            .update(MarkRead(is_read: true))
            .eq("type", value: type)
            .eq("user_id", value: userId)
            .eq("is_read", value: false)
            .execute()
    }

    /// Marks any unread `role_needed` notifications whose action_url contains
    /// `assignRole=<memberId>` as read. Called after iOS assigns a role so
    /// the admin's rail notification disappears without a second API call.
    /// The web PATCH /api/users/:id/role endpoint does the same cleanup when
    /// the admin acts from the web — this mirrors that behavior on iOS.
    func markRoleNeededNotificationsAsReadForMember(memberId: String) async throws {
        struct MarkRead: Codable {
            let is_read: Bool
        }
        let pattern = "%assignRole=\(memberId)%"
        try await client
            .from("notifications")
            .update(MarkRead(is_read: true))
            .eq("type", value: "role_needed")
            .like("action_url", pattern: pattern)
            .eq("is_read", value: false)
            .execute()
    }
}

// MARK: - Review-stack reporting

extension NotificationRepository: ReviewStackSyncing {
    /// Reports one review stack's count to `sync_review_stack_notification`,
    /// the narrow actor-derived RPC that owns the rail semantics (threshold,
    /// fixed copy, at-most-one-unread dedupe, below-threshold auto-clear).
    /// Direct `notifications` inserts are revoked for app roles by the
    /// 2026-07-15 creation hardening — creation must cross this boundary.
    @discardableResult
    func syncReviewStack(stack: String, count: Int) async throws -> String {
        struct Params: Encodable {
            let p_stack: String
            let p_count: Int
        }
        let action: String = try await client
            .rpc(
                "sync_review_stack_notification",
                params: Params(p_stack: stack, p_count: count)
            )
            .execute()
            .value
        return action
    }
}

// MARK: - Narrow creation RPCs (2026-07-15 hardening)
//
// The 2026-07-15 notification-creation hardening revoked app-role INSERT on
// `notifications` — every rail row is created by a narrow SECURITY DEFINER
// RPC that derives the actor from the JWT, derives recipients from server
// rows (never from these inputs), and renders fixed copy server-side. The
// methods below are the iOS bindings for migration
// 20260818023254_ios_notification_surface_rpcs (bug e302355c); the only data
// they carry is clamped counts / validated dimension integers that the server
// interpolates into its fixed templates. `createNotification` above remains
// only as the legacy shape — direct inserts fail 42501 for app roles.

extension NotificationRepository {

    /// AppState periodic review reminders (self). `kind` is one of
    /// `projects_needing_tasks` / `stale_estimate_review`; the server holds at
    /// most one unread reminder per kind ('kept'), so a second device inside
    /// the client throttle window cannot stack a duplicate rail row.
    @discardableResult
    func syncReviewReminder(kind: String, count: Int, thresholdDays: Int? = nil) async throws -> String {
        struct Params: Encodable {
            let p_kind: String
            let p_count: Int
            let p_threshold_days: Int?
        }
        return try await client
            .rpc(
                "sync_review_reminder_notification",
                params: Params(p_kind: kind, p_count: count, p_threshold_days: thresholdDays)
            )
            .execute()
            .value
    }

    /// Overdue-invoice rail for `invoices.record_payment` holders. The server
    /// computes the overdue set and the recipient list itself and returns the
    /// user ids that received NEW rows — aim the companion OneSignal push at
    /// exactly that list so push matches the rail's 24h dedupe.
    @discardableResult
    func syncOverdueInvoiceNotifications() async throws -> [String] {
        struct Params: Encodable {}
        return try await client
            .rpc("sync_overdue_invoice_notifications", params: Params())
            .execute()
            .value
    }

    /// Share-extension completion confirmation (self). Project title is
    /// server-derived; the count is clamped server-side.
    @discardableResult
    func notifySharePhotosFinalized(projectId: String, photoCount: Int) async throws -> String {
        struct Params: Encodable {
            let p_project_id: String
            let p_photo_count: Int
        }
        return try await client
            .rpc(
                "notify_share_photos_finalized",
                params: Params(p_project_id: projectId, p_photo_count: photoCount)
            )
            .execute()
            .value
    }

    /// Recipients that received NEW rows from `notify_note_created`, per
    /// notification type — the push lanes target exactly these ids.
    struct NoteCreatedFanout: Decodable, Equatable {
        /// `photo_comment` (photo note) or `project_note` (plain note).
        let kind: String
        let mentionUserIds: [String]
        let photoOwnerId: String?
        let teamUserIds: [String]

        enum CodingKeys: String, CodingKey {
            case kind
            case mentionUserIds = "mention_user_ids"
            case photoOwnerId   = "photo_owner_id"
            case teamUserIds    = "team_user_ids"
        }
    }

    /// Fans out one created note's rail rows server-side: mention rows from
    /// the note's `mentioned_user_ids`, then either the photo owner
    /// (photo comment) or the project-crew broadcast (plain note). The actor
    /// must be the note's author; re-calls are idempotent per note.
    @discardableResult
    func notifyNoteCreated(noteId: String) async throws -> NoteCreatedFanout {
        struct Params: Encodable {
            let p_note_id: String
        }
        return try await client
            .rpc("notify_note_created", params: Params(p_note_id: noteId))
            .execute()
            .value
    }

    /// Expense envelope decision → submitter. `decision` is one of
    /// `approved` / `sent_back` / `paid`; the server validates the decision is
    /// actually recorded on the batch row and derives the recipient from it.
    /// `count` is the sent-back line count (ignored otherwise).
    @discardableResult
    func notifyExpenseBatchDecision(batchId: String, decision: String, count: Int? = nil) async throws -> String {
        struct Params: Encodable {
            let p_batch_id: String
            let p_decision: String
            let p_count: Int?
        }
        return try await client
            .rpc(
                "notify_expense_batch_decision",
                params: Params(p_batch_id: batchId, p_decision: decision, p_count: count)
            )
            .execute()
            .value
    }

    /// Time-off decision → requester. The event row must carry the recorded
    /// decision and the actor must be its recorded reviewer.
    @discardableResult
    func notifyTimeOffDecision(eventId: String) async throws -> String {
        struct Params: Encodable {
            let p_event_id: String
        }
        return try await client
            .rpc("notify_time_off_decision", params: Params(p_event_id: eventId))
            .execute()
            .value
    }

    /// In-app photo upload → assigned-crew broadcast. Recipients come from
    /// the project row's crew list server-side; returns the ids that received
    /// NEW rows for push targeting.
    @discardableResult
    func notifyProjectPhotosAdded(projectId: String, photoCount: Int) async throws -> [String] {
        struct Params: Encodable {
            let p_project_id: String
            let p_photo_count: Int
        }
        return try await client
            .rpc(
                "notify_project_photos_added",
                params: Params(p_project_id: projectId, p_photo_count: photoCount)
            )
            .execute()
            .value
    }

    /// Inventory threshold rail (self, persistent, review-stack shape): the
    /// server keeps at most one unread alert, and a zero count clears it —
    /// report honest counts after every sync, including zero.
    @discardableResult
    func syncThresholdAlert(count: Int) async throws -> String {
        struct Params: Encodable {
            let p_count: Int
        }
        return try await client
            .rpc("sync_threshold_alert_notification", params: Params(p_count: count))
            .execute()
            .value
    }

    /// LiDAR measurement captured (self). The dimension integers interpolate
    /// into the server's fixed spec-§6 template; kind is `opening` or
    /// `wall_section` with the matching argument set.
    @discardableResult
    func notifyMeasurementCaptured(
        projectId: String,
        kind: String,
        widthInches: Int? = nil,
        heightInches: Int? = nil,
        openingType: String? = nil,
        sillInches: Int? = nil,
        wallWidthFeet: Int? = nil,
        wallWidthInches: Int? = nil,
        wallHeightFeet: Int? = nil
    ) async throws -> String {
        struct Params: Encodable {
            let p_project_id: String
            let p_kind: String
            let p_width_inches: Int?
            let p_height_inches: Int?
            let p_opening_type: String?
            let p_sill_inches: Int?
            let p_wall_width_feet: Int?
            let p_wall_width_inches: Int?
            let p_wall_height_feet: Int?
        }
        return try await client
            .rpc(
                "notify_measurement_captured",
                params: Params(
                    p_project_id: projectId,
                    p_kind: kind,
                    p_width_inches: widthInches,
                    p_height_inches: heightInches,
                    p_opening_type: openingType,
                    p_sill_inches: sillInches,
                    p_wall_width_feet: wallWidthFeet,
                    p_wall_width_inches: wallWidthInches,
                    p_wall_height_feet: wallHeightFeet
                )
            )
            .execute()
            .value
    }

    /// LiDAR offline queue banner (self, persistent, review-stack shape):
    /// depth zero clears the banner when the queue drains.
    @discardableResult
    func syncMeasurementPending(queueDepth: Int) async throws -> String {
        struct Params: Encodable {
            let p_queue_depth: Int
        }
        return try await client
            .rpc("sync_measurement_pending_notification", params: Params(p_queue_depth: queueDepth))
            .execute()
            .value
    }

    /// LiDAR retries exhausted (self). Project-anchored — the annotation row
    /// may not exist server-side when the insert is what failed.
    @discardableResult
    func notifyMeasurementSyncFailed(projectId: String) async throws -> String {
        struct Params: Encodable {
            let p_project_id: String
        }
        return try await client
            .rpc("notify_measurement_sync_failed", params: Params(p_project_id: projectId))
            .execute()
            .value
    }
}
