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

// MARK: - Legacy call-site RPCs (bug e302355c ADDENDUM)
//
// The call sites the first wave left behind — task/project lifecycle, vinyl,
// guided setup, team management, time-off requests, inventory thresholds,
// photo storage, billable week, cashflow forecast — cross the same boundary.
// These are the iOS bindings for migration
// 20260818043043_ios_legacy_notification_surface_rpcs: the server resolves the
// actor from the JWT, derives every recipient from the anchor row (project and
// task crews, permission holders, invitation rows) rather than from these
// arguments, and renders the shipped copy from fixed templates. A caller-
// supplied id list may only SUBSET a row's recorded membership; counts and
// numerics are clamped server-side. Methods that return ids return only the
// recipients that received NEW rows — aim the companion OneSignal push at
// exactly that list.

extension NotificationRepository {

    /// Task marked complete → the project's crew. The server refuses a task
    /// that isn't recorded completed and derives recipients from the project
    /// row's crew list, minus the actor. Returns the ids that received NEW rows.
    @discardableResult
    func notifyTaskCompleted(taskId: String) async throws -> [String] {
        struct Params: Encodable {
            let p_task_id: String
        }
        return try await client
            .rpc("notify_task_completed", params: Params(p_task_id: taskId))
            .execute()
            .value
    }

    /// Project marked complete → the project's crew, minus the actor. The
    /// server refuses a project that isn't recorded completed. Returns the ids
    /// that received NEW rows.
    @discardableResult
    func notifyProjectCompleted(projectId: String) async throws -> [String] {
        struct Params: Encodable {
            let p_project_id: String
        }
        return try await client
            .rpc("notify_project_completed", params: Params(p_project_id: projectId))
            .execute()
            .value
    }

    /// Task dates moved → the task's own crew, minus the actor. The server
    /// refuses completed/cancelled tasks and tasks missing either date — a
    /// schedule nobody can act on is not announceable. Returns the ids that
    /// received NEW rows.
    @discardableResult
    func notifyTaskRescheduled(taskId: String) async throws -> [String] {
        struct Params: Encodable {
            let p_task_id: String
        }
        return try await client
            .rpc("notify_task_rescheduled", params: Params(p_task_id: taskId))
            .execute()
            .value
    }

    /// One task unblocked by `notify_dependency_ready`, with the crew that
    /// received NEW rows for it.
    struct DependencyReadyEntry: Decodable, Equatable {
        let taskId: String
        let userIds: [String]

        enum CodingKeys: String, CodingKey {
            case taskId  = "task_id"
            case userIds = "user_ids"
        }
    }

    /// Completing a task unblocks its dependents: the server resolves each
    /// dependent's effective dependencies, notifies the crew of every task the
    /// completion cleared, and returns one entry per task that produced NEW
    /// rows (tasks with none are omitted). Push per entry.
    @discardableResult
    func notifyDependencyReady(completedTaskId: String) async throws -> [DependencyReadyEntry] {
        struct Params: Encodable {
            let p_completed_task_id: String
        }
        return try await client
            .rpc(
                "notify_dependency_ready",
                params: Params(p_completed_task_id: completedTaskId)
            )
            .execute()
            .value
    }

    /// Crew added to a task. `userIds` nil announces the task's whole recorded
    /// crew; a supplied list may only SUBSET that crew — the server intersects
    /// it with the row's membership and drops the actor. Returns the ids that
    /// received NEW rows.
    @discardableResult
    func notifyTaskAssigned(taskId: String, userIds: [String]? = nil) async throws -> [String] {
        struct Params: Encodable {
            let p_task_id: String
            let p_user_ids: [String]?
        }
        return try await client
            .rpc(
                "notify_task_assigned",
                params: Params(p_task_id: taskId, p_user_ids: userIds)
            )
            .execute()
            .value
    }

    /// Crew added to a project. The list is intersected with the project row's
    /// recorded membership and the actor is dropped. Returns the ids that
    /// received NEW rows.
    @discardableResult
    func notifyProjectAssigned(projectId: String, userIds: [String]) async throws -> [String] {
        struct Params: Encodable {
            let p_project_id: String
            let p_user_ids: [String]
        }
        return try await client
            .rpc(
                "notify_project_assigned",
                params: Params(p_project_id: projectId, p_user_ids: userIds)
            )
            .execute()
            .value
    }

    /// Paired follow-up task spawned by the scheduler → the predecessor's crew,
    /// the actor included (the spawn is system-initiated, not an actor echo).
    /// The spawn row must already exist server-side, so flush pending sync
    /// operations before calling. Rail only — no push lane. Returns the ids
    /// that received NEW rows.
    @discardableResult
    func notifyTaskPairSpawned(taskId: String) async throws -> [String] {
        struct Params: Encodable {
            let p_task_id: String
        }
        return try await client
            .rpc("notify_task_pair_spawned", params: Params(p_task_id: taskId))
            .execute()
            .value
    }

    /// One crew member's share of an auto-schedule run — the moved-task count
    /// their NEW summary row reports.
    struct ScheduleRunSummaryEntry: Decodable, Equatable {
        let userId: String
        let movedCount: Int

        enum CodingKeys: String, CodingKey {
            case userId     = "user_id"
            case movedCount = "moved_count"
        }
    }

    /// Bulk auto-schedule run → one summary row per affected crew member. Pass
    /// every moved task id (already pushed); the server counts each member's
    /// share itself and returns one entry per member that received a NEW row.
    @discardableResult
    func notifyScheduleRunSummary(taskIds: [String]) async throws -> [ScheduleRunSummaryEntry] {
        struct Params: Encodable {
            let p_task_ids: [String]
        }
        return try await client
            .rpc("notify_schedule_run_summary", params: Params(p_task_ids: taskIds))
            .execute()
            .value
    }

    /// Vinyl order drafted off a deck note (self). The note must be the actor's
    /// own on that project; square footage is clamped server-side. Returns
    /// `created` or `noop` — a throw is the call site's rail failure.
    @discardableResult
    func notifyVinylOrderDrafted(projectId: String, noteId: String, orderedSqFt: Int) async throws -> String {
        struct Params: Encodable {
            let p_project_id: String
            let p_note_id: String
            let p_ordered_sq_ft: Int
        }
        return try await client
            .rpc(
                "notify_vinyl_order_drafted",
                params: Params(
                    p_project_id: projectId,
                    p_note_id: noteId,
                    p_ordered_sq_ft: orderedSqFt
                )
            )
            .execute()
            .value
    }

    /// Vinyl bulk order marked (self). The date blurb is rendered from the
    /// server clock and the count is clamped. Returns `created` or `noop`.
    @discardableResult
    func notifyVinylBulkOrdered(markedCount: Int) async throws -> String {
        struct Params: Encodable {
            let p_marked_count: Int
        }
        return try await client
            .rpc("notify_vinyl_bulk_ordered", params: Params(p_marked_count: markedCount))
            .execute()
            .value
    }

    /// Offcut banked to stock (self). The dimensions in the copy are rendered
    /// from the stock-unit row's own measurements — it must be a live offcut in
    /// the actor's company. Returns `created` or `noop`.
    @discardableResult
    func notifyVinylOffcutBanked(stockUnitId: String, projectId: String? = nil) async throws -> String {
        struct Params: Encodable {
            let p_stock_unit_id: String
            let p_project_id: String?
        }
        return try await client
            .rpc(
                "notify_vinyl_offcut_banked",
                params: Params(p_stock_unit_id: stockUnitId, p_project_id: projectId)
            )
            .execute()
            .value
    }

    /// Guided setup finished (self). `kind` is `product_setup`,
    /// `catalog_setup`, or `stock_setup`; pass only the counts that kind
    /// reports and the server assembles the matching body from them, dropping
    /// the zeroes. Returns `created` or `noop`.
    @discardableResult
    func notifyGuidedSetupCompleted(
        kind: String,
        productCount: Int? = nil,
        recipeCount: Int? = nil,
        serviceCount: Int? = nil,
        goodCount: Int? = nil,
        assemblyCount: Int? = nil,
        familyCount: Int? = nil,
        variantCount: Int? = nil,
        rollCount: Int? = nil,
        offcutCount: Int? = nil,
        bundleCount: Int? = nil
    ) async throws -> String {
        struct Params: Encodable {
            let p_kind: String
            let p_product_count: Int?
            let p_recipe_count: Int?
            let p_service_count: Int?
            let p_good_count: Int?
            let p_assembly_count: Int?
            let p_family_count: Int?
            let p_variant_count: Int?
            let p_roll_count: Int?
            let p_offcut_count: Int?
            let p_bundle_count: Int?
        }
        return try await client
            .rpc(
                "notify_guided_setup_completed",
                params: Params(
                    p_kind: kind,
                    p_product_count: productCount,
                    p_recipe_count: recipeCount,
                    p_service_count: serviceCount,
                    p_good_count: goodCount,
                    p_assembly_count: assemblyCount,
                    p_family_count: familyCount,
                    p_variant_count: variantCount,
                    p_roll_count: rollCount,
                    p_offcut_count: offcutCount,
                    p_bundle_count: bundleCount
                )
            )
            .execute()
            .value
    }

    /// Role assigned to a teammate. The actor must hold `team.assign_roles`,
    /// and the role named in the copy is the member's recorded role — never the
    /// caller's claim about it. Returns `created` or `noop`; push only on
    /// `created`.
    @discardableResult
    func notifyRoleAssigned(memberId: String) async throws -> String {
        struct Params: Encodable {
            let p_member_id: String
        }
        return try await client
            .rpc("notify_role_assigned", params: Params(p_member_id: memberId))
            .execute()
            .value
    }

    /// Team invitations sent (self). The server confirms each contact against
    /// the actor's own recent invitation rows and names the first confirmed one
    /// in the body; nothing confirmed means no row. Returns `created` or `noop`.
    @discardableResult
    func notifyTeamInvitesSent(emails: [String], phones: [String]) async throws -> String {
        struct Params: Encodable {
            let p_emails: [String]
            let p_phones: [String]
        }
        return try await client
            .rpc(
                "notify_team_invites_sent",
                params: Params(p_emails: emails, p_phones: phones)
            )
            .execute()
            .value
    }

    /// Time off booked → the person it was booked for. The event must be
    /// recorded approved and the actor must hold `time_off.approve`; the server
    /// renders the date range and picks the self- or on-behalf wording. Returns
    /// `created` or `noop` — push only when the target isn't the actor and the
    /// row was created.
    @discardableResult
    func notifyTimeOffBooked(eventId: String) async throws -> String {
        struct Params: Encodable {
            let p_event_id: String
        }
        return try await client
            .rpc("notify_time_off_booked", params: Params(p_event_id: eventId))
            .execute()
            .value
    }

    /// Recipients that received NEW rows from `notify_time_off_requested` — the
    /// approver push lane targets exactly these ids.
    struct TimeOffRequestFanout: Decodable, Equatable {
        let approverUserIds: [String]
        let targetNotified: Bool

        enum CodingKeys: String, CodingKey {
            case approverUserIds = "approver_user_ids"
            case targetNotified  = "target_notified"
        }
    }

    /// Time-off request submitted → the requester's own confirmation, the
    /// person it was requested for when that isn't the actor, and every
    /// approver. The event must be recorded pending; re-calls are idempotent
    /// per event, so a retried transport can't double-post.
    @discardableResult
    func notifyTimeOffRequested(eventId: String) async throws -> TimeOffRequestFanout {
        struct Params: Encodable {
            let p_event_id: String
        }
        return try await client
            .rpc("notify_time_off_requested", params: Params(p_event_id: eventId))
            .execute()
            .value
    }

    /// Inventory quantity crossed a threshold → `inventory.manage` holders. The
    /// server recomputes the item's status from the stored row, so call after
    /// every successful adjustment and let it decide: an in-range item returns
    /// an empty list rather than throwing. Returns the ids that received NEW
    /// rows.
    @discardableResult
    func notifyInventoryThresholdCrossed(itemId: String) async throws -> [String] {
        struct Params: Encodable {
            let p_item_id: String
        }
        return try await client
            .rpc("notify_inventory_threshold_crossed", params: Params(p_item_id: itemId))
            .execute()
            .value
    }

    /// Photo storage limit reached on this device (self, persistent). The
    /// server holds at most one unread row per device, so a second report from
    /// the same device can't stack. Returns `created` or `kept`.
    @discardableResult
    func syncPhotoStorageLimit(photosRemaining: Int, deviceName: String) async throws -> String {
        struct Params: Encodable {
            let p_photos_remaining: Int
            let p_device_name: String
        }
        return try await client
            .rpc(
                "sync_photo_storage_limit_notification",
                params: Params(p_photos_remaining: photosRemaining, p_device_name: deviceName)
            )
            .execute()
            .value
    }

    /// Weekly billable summary (self). The actor must hold `finances.view`;
    /// `weekStart` is the week's first day as a `yyyy-MM-dd` date string, and
    /// the count and amount are clamped server-side. Returns `created` or
    /// `kept` — a week already reported stays reported, read or unread.
    @discardableResult
    func syncBillableWeek(projectCount: Int, amount: Double, weekStart: String) async throws -> String {
        struct Params: Encodable {
            let p_project_count: Int
            let p_amount: Double
            let p_week_start: String
        }
        return try await client
            .rpc(
                "sync_billable_week_notification",
                params: Params(
                    p_project_count: projectCount,
                    p_amount: amount,
                    p_week_start: weekStart
                )
            )
            .execute()
            .value
    }

    /// Cashflow dip forecast → every `finances.view` holder, the actor included
    /// (a dip is a company condition, not an actor echo). Persistent: the
    /// server keeps an identical unread row and replaces one whose balance has
    /// moved. `weekStart` is a `yyyy-MM-dd` date string. Returns the ids that
    /// received NEW rows.
    @discardableResult
    func syncForecastDip(lowestBalance: Double, weekStart: String) async throws -> [String] {
        struct Params: Encodable {
            let p_lowest_balance: Double
            let p_week_start: String
        }
        return try await client
            .rpc(
                "sync_forecast_dip_notification",
                params: Params(p_lowest_balance: lowestBalance, p_week_start: weekStart)
            )
            .execute()
            .value
    }

    /// Forecast recovered: resolves the company's outstanding dip rows — a
    /// persistent row must never outlive its condition — and posts the
    /// all-clear to the same `finances.view` holders. Returns the ids that
    /// received NEW rows.
    @discardableResult
    func syncForecastCleared() async throws -> [String] {
        struct Params: Encodable {}
        return try await client
            .rpc("sync_forecast_cleared_notification", params: Params())
            .execute()
            .value
    }
}
