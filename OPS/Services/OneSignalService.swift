//
//  OneSignalService.swift
//  OPS
//
//  Service for sending push notifications via OneSignal REST API
//  Created December 8, 2025
//

import Foundation

/// Service for sending targeted push notifications via OneSignal
class OneSignalService {
    static let shared = OneSignalService()
    private init() {}

    private let appId = "0fc0a8e0-9727-49b6-9e37-5d6d919d741f"
    private let apiEndpoint = "https://onesignal.com/api/v1/notifications"

    /// The REST API key fetched from Bubble (stored in memory only, not persisted)
    private var restApiKey: String?

    /// Whether the service is ready to send notifications
    var isConfigured: Bool {
        return restApiKey != nil
    }

    // MARK: - Configuration

    /// Fetch the OneSignal REST API key from Bubble
    /// Call this after user logs in
    func configure() async {
        do {
            let key = try await fetchApiKeyFromBubble()
            self.restApiKey = key
            print("[ONESIGNAL SERVICE] Configured successfully")
        } catch {
            print("[ONESIGNAL SERVICE] Failed to fetch API key: \(error.localizedDescription)")
        }
    }

    /// Clear the API key on logout
    func clearConfiguration() {
        restApiKey = nil
        print("[ONESIGNAL SERVICE] Configuration cleared")
    }

    /// Fetch API key from Bubble backend
    private func fetchApiKeyFromBubble() async throws -> String {
        let urlString = "\(AppConfiguration.bubbleBaseURL)\(AppConfiguration.bubbleWorkflowAPIPath)/fetch-os-key"
        print("[ONESIGNAL SERVICE] Fetching API key from: \(urlString)")

        guard let url = URL(string: urlString) else {
            print("[ONESIGNAL SERVICE] Invalid URL")
            throw OneSignalError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"  // Bubble workflow endpoints typically use POST
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AppConfiguration.bubbleAPIToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        // Log response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("[ONESIGNAL SERVICE] Response: \(responseString)")
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[ONESIGNAL SERVICE] Failed to fetch API key, status: \(statusCode)")
            throw OneSignalError.apiError(statusCode: statusCode, message: "Failed to fetch API key")
        }

        // Response format: { "status": "success", "response": { "key": "os_v2_app_..." } }
        struct KeyResponse: Decodable {
            let status: String
            let response: ResponseData

            struct ResponseData: Decodable {
                let key: String
            }
        }

        do {
            let keyResponse = try JSONDecoder().decode(KeyResponse.self, from: data)
            print("[ONESIGNAL SERVICE] Successfully decoded API key")
            return keyResponse.response.key
        } catch {
            print("[ONESIGNAL SERVICE] Failed to decode response: \(error)")
            throw error
        }
    }

    // MARK: - Send Notification Methods

    /// Send notification to a specific user by their Bubble user ID
    func sendToUser(
        userId: String,
        title: String,
        body: String,
        data: [String: Any]? = nil
    ) async throws {
        try await sendNotification(
            targetType: .externalUserId,
            targetValue: userId,
            title: title,
            body: body,
            data: data
        )
    }

    /// Send notification to multiple users by their Bubble user IDs
    func sendToUsers(
        userIds: [String],
        title: String,
        body: String,
        data: [String: Any]? = nil
    ) async throws {
        try await sendNotification(
            targetType: .externalUserIds,
            targetValues: userIds,
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
        // Don't notify yourself
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
        // Filter out current user
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
        // Filter out current user
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
        // Filter out current user
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
        // Don't notify yourself
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

    private enum TargetType {
        case externalUserId
        case externalUserIds
        case segment
    }

    private func sendNotification(
        targetType: TargetType,
        targetValue: String? = nil,
        targetValues: [String]? = nil,
        title: String,
        body: String,
        data: [String: Any]? = nil
    ) async throws {
        guard let apiKey = restApiKey else {
            print("[ONESIGNAL SERVICE] Not configured - cannot send notification")
            throw OneSignalError.apiKeyNotConfigured
        }

        var payload: [String: Any] = [
            "app_id": appId,
            "headings": ["en": title],
            "contents": ["en": body]
        ]

        // Add targeting based on type
        switch targetType {
        case .externalUserId:
            if let value = targetValue {
                payload["include_aliases"] = ["external_id": [value]]
                payload["target_channel"] = "push"
            }
        case .externalUserIds:
            if let values = targetValues, !values.isEmpty {
                payload["include_aliases"] = ["external_id": values]
                payload["target_channel"] = "push"
            }
        case .segment:
            if let value = targetValue {
                payload["included_segments"] = [value]
            }
        }

        // Add custom data for deep linking
        if let data = data {
            payload["data"] = data
        }

        // Make the API request
        guard let url = URL(string: apiEndpoint) else {
            throw OneSignalError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(apiKey)", forHTTPHeaderField: "Authorization")
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

        print("[ONESIGNAL SERVICE] Notification sent successfully")
    }
}

// MARK: - Errors

enum OneSignalError: Error, LocalizedError {
    case apiKeyNotConfigured
    case invalidEndpoint
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "OneSignal REST API key not configured"
        case .invalidEndpoint:
            return "Invalid OneSignal API endpoint"
        case .invalidResponse:
            return "Invalid response from OneSignal API"
        case .apiError(let statusCode, let message):
            return "OneSignal API error (\(statusCode)): \(message)"
        }
    }
}
