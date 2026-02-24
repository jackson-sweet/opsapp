//
//  OneSignalService.swift
//  OPS
//
//  Service for sending push notifications via ops-web API route
//  (server-side OneSignal REST API calls handled by ops-web)
//

import Foundation
import Supabase

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

    /// Send notification to a specific user by their user ID
    func sendToUser(
        userId: String,
        title: String,
        body: String,
        data: [String: Any]? = nil
    ) async throws {
        try await sendViaOpsWeb(
            recipientUserIds: [userId],
            title: title,
            body: body,
            data: data
        )
    }

    /// Send notification to multiple users by their user IDs
    func sendToUsers(
        userIds: [String],
        title: String,
        body: String,
        data: [String: Any]? = nil
    ) async throws {
        guard !userIds.isEmpty else { return }
        try await sendViaOpsWeb(
            recipientUserIds: userIds,
            title: title,
            body: body,
            data: data
        )
    }

    // MARK: - App Event Notifications

    /// Notify a user they've been assigned to a task
    func notifyTaskAssignment(
        userId: String,
        taskName: String,
        projectName: String,
        taskId: String,
        projectId: String
    ) async throws {
        if userId == UserDefaults.standard.string(forKey: "currentUserId") {
            print("[ONESIGNAL SERVICE] Skipping self-notification for task assignment")
            return
        }

        try await sendToUser(
            userId: userId,
            title: "New Task Assignment",
            body: "You've been assigned to \"\(taskName)\" on \(projectName)",
            data: [
                "type": "taskAssignment",
                "taskId": taskId,
                "projectId": projectId,
                "screen": "taskDetails"
            ]
        )
        print("[ONESIGNAL SERVICE] Task assignment notification sent to user: \(userId)")
    }

    /// Notify users of a schedule change
    func notifyScheduleChange(
        userIds: [String],
        taskName: String,
        projectName: String,
        taskId: String,
        projectId: String
    ) async throws {
        let currentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        let filteredUserIds = userIds.filter { $0 != currentUserId }

        guard !filteredUserIds.isEmpty else {
            print("[ONESIGNAL SERVICE] No users to notify for schedule change (all filtered)")
            return
        }

        try await sendToUsers(
            userIds: filteredUserIds,
            title: "Schedule Update",
            body: "\"\(taskName)\" on \(projectName) has been rescheduled",
            data: [
                "type": "scheduleChange",
                "taskId": taskId,
                "projectId": projectId,
                "screen": "taskDetails"
            ]
        )
        print("[ONESIGNAL SERVICE] Schedule change notification sent to \(filteredUserIds.count) users")
    }

    /// Notify project team when a task is completed (workflow handoff)
    func notifyTaskCompletion(
        userIds: [String],
        taskName: String,
        projectName: String,
        taskId: String,
        projectId: String,
        completedByName: String?
    ) async throws {
        let currentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        let filteredUserIds = userIds.filter { $0 != currentUserId }

        guard !filteredUserIds.isEmpty else {
            print("[ONESIGNAL SERVICE] No users to notify for task completion (all filtered)")
            return
        }

        let completedBy = completedByName ?? "A team member"
        try await sendToUsers(
            userIds: filteredUserIds,
            title: "Task Completed",
            body: "\(completedBy) completed \"\(taskName)\" on \(projectName)",
            data: [
                "type": "taskCompletion",
                "taskId": taskId,
                "projectId": projectId,
                "screen": "projectDetails"
            ]
        )
        print("[ONESIGNAL SERVICE] Task completion notification sent to \(filteredUserIds.count) project team members")
    }

    /// Notify users of project completion
    func notifyProjectCompletion(
        userIds: [String],
        projectName: String,
        projectId: String
    ) async throws {
        let currentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        let filteredUserIds = userIds.filter { $0 != currentUserId }

        guard !filteredUserIds.isEmpty else {
            print("[ONESIGNAL SERVICE] No users to notify for project completion (all filtered)")
            return
        }

        try await sendToUsers(
            userIds: filteredUserIds,
            title: "Project Completed",
            body: "\"\(projectName)\" has been marked as completed",
            data: [
                "type": "projectCompletion",
                "projectId": projectId,
                "screen": "projectDetails"
            ]
        )
        print("[ONESIGNAL SERVICE] Project completion notification sent to \(filteredUserIds.count) users")
    }

    /// Notify a user they've been added to a project team
    func notifyProjectAssignment(
        userId: String,
        projectName: String,
        projectId: String
    ) async throws {
        if userId == UserDefaults.standard.string(forKey: "currentUserId") {
            print("[ONESIGNAL SERVICE] Skipping self-notification for project assignment")
            return
        }

        try await sendToUser(
            userId: userId,
            title: "Added to Project",
            body: "You've been added to \"\(projectName)\"",
            data: [
                "type": "projectAssignment",
                "projectId": projectId,
                "screen": "projectDetails"
            ]
        )
        print("[ONESIGNAL SERVICE] Project assignment notification sent to user: \(userId)")
    }

    // MARK: - Private Implementation

    /// Send notification via ops-web backend route
    private func sendViaOpsWeb(
        recipientUserIds: [String],
        title: String,
        body: String,
        data: [String: Any]? = nil
    ) async throws {
        let session: Session
        do {
            session = try await SupabaseService.shared.client.auth.session
        } catch {
            print("[ONESIGNAL SERVICE] No authenticated user - cannot send notification")
            throw OneSignalError.notAuthenticated
        }

        let idToken = session.accessToken

        let url = AppConfiguration.apiBaseURL.appendingPathComponent("/api/notifications/send")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        var payload: [String: Any] = [
            "recipientUserIds": recipientUserIds,
            "title": title,
            "body": body
        ]

        if let data = data {
            payload["data"] = data
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OneSignalError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            print("[ONESIGNAL SERVICE] API Error (\(httpResponse.statusCode)): \(errorMessage)")
            throw OneSignalError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        print("[ONESIGNAL SERVICE] Notification sent successfully via ops-web")
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
