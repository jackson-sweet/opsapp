//
//  OneSignalService.swift
//  OPS
//
//  Service for sending push notifications via ops-web API route
//  (server-side OneSignal REST API calls handled by ops-web)
//

import Foundation
// FirebaseAuthService used for token retrieval (Firebase Auth migration)

/// Service for sending targeted push notifications via ops-web backend
class OneSignalService {
    static let shared = OneSignalService()
    private init() {}

    private let appId = "0fc0a8e0-9727-49b6-9e37-5d6d919d741f"

    // MARK: - Configuration

    /// No configuration needed - ops-web handles the OneSignal API key server-side
    func configure() async {
        print("[ONESIGNAL SERVICE] Ready (server-side via ops-web)")
    }

    /// Clear on logout (no-op, kept for API compatibility)
    func clearConfiguration() {
        print("[ONESIGNAL SERVICE] Configuration cleared")
    }

    // MARK: - Send Notification Methods

    /// Ask ops-web to push the companion for rail rows this device just caused
    /// a narrow SECURITY DEFINER RPC to write. `rowType` is the `type` those
    /// rows carry — the server reads their own copy, so nothing about the
    /// message originates here.
    func sendToUser(
        userId: String,
        rowType: String,
        dedupeKey: String? = nil
    ) async throws {
        try await sendViaOpsWeb(
            recipientUserIds: [userId],
            rowType: rowType,
            dedupeKey: dedupeKey
        )
    }

    /// Multi-recipient form of `sendToUser`.
    func sendToUsers(
        userIds: [String],
        rowType: String,
        dedupeKey: String? = nil
    ) async throws {
        guard !userIds.isEmpty else { return }
        try await sendViaOpsWeb(
            recipientUserIds: userIds,
            rowType: rowType,
            dedupeKey: dedupeKey
        )
    }

    // MARK: - Server-owned notification kinds (no client push)

    // Task and project lifecycle notifications were re-homed onto
    // `/api/notifications/dispatch` (P1-17): the server writes the rail rows AND
    // sends the push in one authorized call, and the repository methods that
    // feed these wrappers now return empty recipient lists, so every call site
    // short-circuits before reaching them. They remain only so those legacy
    // call sites compile. Sending from here would double-push what the server
    // already delivered — hence deliberate no-ops, not companion sends.

    func notifyTaskAssignment(
        userId: String,
        taskName: String,
        projectName: String,
        taskId: String,
        projectId: String
    ) async throws {}

    func notifyScheduleChange(
        userIds: [String],
        taskName: String,
        projectName: String,
        taskId: String,
        projectId: String
    ) async throws {}

    func notifyScheduleBatchUpdate(userMoveCounts: [String: Int]) async {}

    func notifyTaskCompletion(
        userIds: [String],
        taskName: String,
        projectName: String,
        taskId: String,
        projectId: String,
        completedByName: String?
    ) async throws {}

    func notifyProjectCompletion(
        userIds: [String],
        projectName: String,
        projectId: String
    ) async throws {}

    func notifyProjectAssignment(
        userId: String,
        projectName: String,
        projectId: String
    ) async throws {}

    func notifyDependencyCompleted(
        completedTaskTitle: String,
        dependentTaskTitle: String,
        projectTitle: String,
        recipientUserIds: [String],
        projectId: String,
        dependentTaskId: String
    ) async throws {}

    // MARK: - Companion pushes for iOS-written rail rows

    /// Mention rows written by `notify_note_created`.
    func notifyProjectNoteMention(userIds: [String]) async throws {
        let currentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        let filtered = userIds.filter { $0 != currentUserId }
        guard !filtered.isEmpty else { return }

        try await sendToUsers(userIds: filtered, rowType: "mention")
        print("[ONESIGNAL SERVICE] Mention companion sent to \(filtered.count) user(s)")
    }

    /// Plain-note broadcast rows written by `notify_note_created`.
    func notifyProjectNoteAdded(userIds: [String]) async throws {
        let currentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        let filtered = userIds.filter { $0 != currentUserId }
        guard !filtered.isEmpty else { return }

        try await sendToUsers(userIds: filtered, rowType: "project_note")
        print("[ONESIGNAL SERVICE] Note-added companion sent to \(filtered.count) user(s)")
    }

    /// Gallery upload rows written by `notify_project_photos_added`.
    func notifyPhotosAdded(userIds: [String]) async throws {
        let currentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        let filtered = userIds.filter { $0 != currentUserId }
        guard !filtered.isEmpty else { return }

        try await sendToUsers(userIds: filtered, rowType: "photo_uploaded")
        print("[ONESIGNAL SERVICE] Photos-added companion sent to \(filtered.count) user(s)")
    }

    /// Photo-comment rows written by `notify_note_created`.
    func notifyPhotoComment(userIds: [String]) async throws {
        let currentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        let filtered = userIds.filter { $0 != currentUserId }
        guard !filtered.isEmpty else { return }

        try await sendToUsers(userIds: filtered, rowType: "photo_comment")
        print("[ONESIGNAL SERVICE] Photo-comment companion sent to \(filtered.count) user(s)")
    }

    /// Admin rows written by `join_user_to_company` when a member joins by crew
    /// code. That RPC writes ONE `role_needed` row per admin (deduped) — there
    /// is no `notify_team_join` RPC and no `team_join` row to match; the web
    /// join-company route writes the same `role_needed` type.
    func notifyTeamJoin(adminUserIds: [String]) async throws {
        let currentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        let filtered = adminUserIds.filter { $0 != currentUserId }
        guard !filtered.isEmpty else { return }

        try await sendToUsers(userIds: filtered, rowType: "role_needed")
        print("[ONESIGNAL SERVICE] Team-join companion sent to \(filtered.count) admin(s)")
    }

    /// Expense envelope decision rows written by `notify_expense_batch_decision`.
    func notifyBatchApproved(userId: String) async throws {
        guard userId != UserDefaults.standard.string(forKey: "currentUserId") else { return }
        try await sendToUser(userId: userId, rowType: "expense_approved")
    }

    func notifyBatchSentBack(userId: String) async throws {
        guard userId != UserDefaults.standard.string(forKey: "currentUserId") else { return }
        try await sendToUser(userId: userId, rowType: "expense_rejected")
    }

    func notifyBatchPaid(userId: String) async throws {
        guard userId != UserDefaults.standard.string(forKey: "currentUserId") else { return }
        try await sendToUser(userId: userId, rowType: "expense_paid")
    }

    // MARK: - Private Implementation

    /// Ask ops-web to push the companion for rail rows of `rowType` that this
    /// company wrote in the last few minutes for `recipientUserIds`.
    ///
    /// Replaces `/api/notifications/send`, retired as a 404 on 2026-07-16 — every
    /// call from this service silently failed between then and 2026-08-28. The
    /// replacement takes no copy and no arbitrary targeting: the server matches
    /// the durable rail rows and pushes their own server-rendered copy, gated on
    /// the recipient's push preference, channel preference and quiet hours.
    private func sendViaOpsWeb(
        recipientUserIds: [String],
        rowType: String,
        dedupeKey: String? = nil
    ) async throws {
        let idToken: String
        do {
            idToken = try await FirebaseAuthService.shared.getIDToken()
        } catch {
            print("[ONESIGNAL SERVICE] No authenticated user - cannot send notification")
            throw OneSignalError.notAuthenticated
        }

        let url = AppConfiguration.apiBaseURL
            .appendingPathComponent("/api/notifications/push-companion")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        var payload: [String: Any] = [
            "notificationType": rowType,
            "recipientUserIds": recipientUserIds
        ]
        if let dedupeKey = dedupeKey {
            payload["dedupeKey"] = dedupeKey
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OneSignalError.invalidResponse
        }

        let responseBody = String(data: responseData, encoding: .utf8) ?? "Unknown"

        if httpResponse.statusCode != 200 {
            print("[ONESIGNAL SERVICE] API Error (\(httpResponse.statusCode)): \(responseBody)")
            throw OneSignalError.apiError(statusCode: httpResponse.statusCode, message: responseBody)
        }

        print("[ONESIGNAL SERVICE] ✅ Companion \(rowType) (\(httpResponse.statusCode)): \(responseBody)")
    }
}

// MARK: - Errors

enum OneSignalError: Error, LocalizedError {
    case notAuthenticated
    case invalidEndpoint
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated - cannot send notification"
        case .invalidEndpoint:
            return "Invalid API endpoint"
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        }
    }
}
