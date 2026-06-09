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

    /// Send notification to a specific user by their user ID
    func sendToUser(
        userId: String,
        title: String,
        body: String,
        data: [String: Any]? = nil,
        imageUrl: String? = nil
    ) async throws {
        try await sendViaOpsWeb(
            recipientUserIds: [userId],
            title: title,
            body: body,
            data: data,
            imageUrl: imageUrl
        )
    }

    /// Send notification to multiple users by their user IDs
    func sendToUsers(
        userIds: [String],
        title: String,
        body: String,
        data: [String: Any]? = nil,
        imageUrl: String? = nil
    ) async throws {
        guard !userIds.isEmpty else { return }
        try await sendViaOpsWeb(
            recipientUserIds: userIds,
            title: title,
            body: body,
            data: data,
            imageUrl: imageUrl
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

    /// One summary push per crew member after a bulk auto-schedule run — replaces
    /// the per-task push (one per task per member) that flooded the connection.
    /// Each member gets a single push carrying their own moved-task count.
    func notifyScheduleBatchUpdate(userMoveCounts: [String: Int]) async {
        let currentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        for (userId, count) in userMoveCounts where userId != currentUserId && count > 0 {
            let body = count == 1
                ? "1 of your tasks was rescheduled"
                : "\(count) of your tasks were rescheduled"
            try? await sendToUsers(
                userIds: [userId],
                title: "Schedule updated",
                body: body,
                data: [
                    "type": "scheduleChange",
                    "screen": "jobBoard"
                ]
            )
        }
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

    /// Notify a user they've been mentioned in a project note
    func notifyProjectNoteMention(
        userId: String,
        authorName: String,
        notePreview: String,
        projectName: String,
        projectId: String,
        noteId: String,
        imageUrl: String? = nil
    ) async throws {
        if userId == UserDefaults.standard.string(forKey: "currentUserId") {
            print("[ONESIGNAL SERVICE] Skipping self-notification for note mention")
            return
        }

        let preview = notePreview.count > 80 ? String(notePreview.prefix(80)) + "..." : notePreview
        try await sendToUser(
            userId: userId,
            title: "\(authorName) mentioned you",
            body: "\"\(preview)\" on \(projectName)",
            data: [
                "type": "projectNoteMention",
                "projectId": projectId,
                "noteId": noteId,
                "screen": "projectNotes"
            ],
            imageUrl: imageUrl
        )
        print("[ONESIGNAL SERVICE] Note mention notification sent to user: \(userId)")
    }

    /// Notify project team members when a note is added (excludes author and @mentioned users)
    func notifyProjectNoteAdded(
        userIds: [String],
        authorName: String,
        notePreview: String,
        projectName: String,
        projectId: String,
        noteId: String,
        imageUrl: String? = nil
    ) async throws {
        guard !userIds.isEmpty else { return }

        let preview = notePreview.count > 80 ? String(notePreview.prefix(80)) + "..." : notePreview
        try await sendToUsers(
            userIds: userIds,
            title: "\(authorName) added a note",
            body: "\"\(preview)\" on \(projectName)",
            data: [
                "type": "projectNoteAdded",
                "projectId": projectId,
                "noteId": noteId,
                "screen": "projectNotes"
            ],
            imageUrl: imageUrl
        )
        print("[ONESIGNAL SERVICE] Note-added notification sent to \(userIds.count) team member(s)")
    }

    /// Notify project team members when photos are added to the project
    /// (excludes the uploader). Mirrors `notifyProjectNoteAdded` but for the
    /// gallery "add photos" action. The note-attachment path opts out via
    /// `ImageSyncManager.saveImages(notifyCrew:)`, so a photo-bearing note
    /// never double-notifies.
    func notifyPhotosAdded(
        userIds: [String],
        uploaderName: String,
        photoCount: Int,
        projectName: String,
        projectId: String,
        imageUrl: String? = nil
    ) async throws {
        let currentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        let filtered = userIds.filter { $0 != currentUserId }
        guard !filtered.isEmpty else { return }

        let title = photoCount == 1 ? "\(uploaderName) added a photo" : "\(uploaderName) added photos"
        let body = photoCount == 1 ? "1 photo on \(projectName)" : "\(photoCount) photos on \(projectName)"
        try await sendToUsers(
            userIds: filtered,
            title: title,
            body: body,
            data: [
                "type": "photo_uploaded",
                "projectId": projectId,
                "screen": "projectNotes"
            ],
            imageUrl: imageUrl
        )
        print("[ONESIGNAL SERVICE] Photos-added notification sent to \(filtered.count) team member(s)")
    }

    /// Notify the uploader of a photo when someone else comments on it.
    func notifyPhotoComment(
        userId: String,
        authorName: String,
        notePreview: String,
        projectName: String,
        projectId: String,
        noteId: String,
        imageUrl: String? = nil
    ) async throws {
        if userId == UserDefaults.standard.string(forKey: "currentUserId") {
            print("[ONESIGNAL SERVICE] Skipping self-notification for photo comment")
            return
        }

        let preview = notePreview.count > 80 ? String(notePreview.prefix(80)) + "..." : notePreview
        try await sendToUser(
            userId: userId,
            title: "\(authorName) commented on your photo",
            body: "\"\(preview)\" on \(projectName)",
            data: [
                "type": "photo_comment",
                "projectId": projectId,
                "noteId": noteId,
                "screen": "projectNotes"
            ],
            imageUrl: imageUrl
        )
        print("[ONESIGNAL SERVICE] Photo-comment notification sent to user: \(userId)")
    }

    /// Notify admins when a new team member joins via crew code
    func notifyTeamJoin(
        adminUserIds: [String],
        newMemberName: String,
        newMemberUserId: String,
        companyId: String
    ) async throws {
        let currentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        let filtered = adminUserIds.filter { $0 != currentUserId }

        guard !filtered.isEmpty else {
            print("[ONESIGNAL SERVICE] No admins to notify for team join (all filtered)")
            return
        }

        try await sendToUsers(
            userIds: filtered,
            title: "New Team Member",
            body: "\(newMemberName) joined as Crew. Tap to set their role.",
            data: [
                "type": "teamJoin",
                "userId": newMemberUserId,
                "companyId": companyId,
                "screen": "manageTeam"
            ]
        )
        print("[ONESIGNAL SERVICE] Team join notification sent to \(filtered.count) admins")
    }

    /// Notify team members that a dependency has been completed and their task is ready to start
    func notifyDependencyCompleted(
        completedTaskTitle: String,
        dependentTaskTitle: String,
        projectTitle: String,
        recipientUserIds: [String],
        projectId: String,
        dependentTaskId: String
    ) async throws {
        let currentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        let filteredUserIds = recipientUserIds.filter { $0 != currentUserId }

        guard !filteredUserIds.isEmpty else {
            print("[ONESIGNAL SERVICE] No users to notify for dependency completion (all filtered)")
            return
        }

        try await sendToUsers(
            userIds: filteredUserIds,
            title: "Ready to start",
            body: "\(dependentTaskTitle) on \(projectTitle) — \(completedTaskTitle) is complete",
            data: [
                "type": "dependencyCompleted",
                "screen": "taskDetails",
                "projectId": projectId,
                "taskId": dependentTaskId
            ]
        )
        print("[ONESIGNAL SERVICE] Dependency completion notification sent to \(filteredUserIds.count) users")
    }

    /// Notify admins that an expense invoice has been submitted for review
    func notifyExpenseSubmitted(
        adminUserIds: [String],
        submitterName: String,
        batchNumber: String,
        batchId: String
    ) async throws {
        let currentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        let filtered = adminUserIds.filter { $0 != currentUserId }
        guard !filtered.isEmpty else { return }

        try await sendToUsers(
            userIds: filtered,
            title: "Invoice Submitted",
            body: "\(submitterName) submitted invoice \(batchNumber) for review",
            data: [
                "type": "expense_submitted",
                "batchId": batchId,
                "screen": "expenses"
            ]
        )
        print("[ONESIGNAL SERVICE] Expense submitted notification sent to \(filtered.count) admins")
    }

    /// Notify a crew member that their invoice has been approved
    func notifyInvoiceApproved(
        userId: String,
        batchNumber: String,
        batchId: String
    ) async throws {
        if userId == UserDefaults.standard.string(forKey: "currentUserId") {
            return
        }

        try await sendToUser(
            userId: userId,
            title: "Invoice Approved",
            body: "Your invoice \(batchNumber) has been approved",
            data: [
                "type": "invoice_approved",
                "batchId": batchId,
                "screen": "expenses"
            ]
        )
        print("[ONESIGNAL SERVICE] Invoice approved notification sent to user: \(userId)")
    }

    /// Notify a crew member that their invoice needs revisions
    func notifyInvoiceRevisions(
        userId: String,
        batchNumber: String,
        batchId: String,
        flaggedCount: Int
    ) async throws {
        if userId == UserDefaults.standard.string(forKey: "currentUserId") {
            return
        }

        try await sendToUser(
            userId: userId,
            title: "Invoice Revisions Needed",
            body: "\(flaggedCount) expense\(flaggedCount == 1 ? "" : "s") on \(batchNumber) need\(flaggedCount == 1 ? "s" : "") revision",
            data: [
                "type": "invoice_revisions",
                "batchId": batchId,
                "screen": "expenses"
            ]
        )
        print("[ONESIGNAL SERVICE] Invoice revisions notification sent to user: \(userId)")
    }

    // MARK: - Private Implementation

    /// Send notification via ops-web backend route
    private func sendViaOpsWeb(
        recipientUserIds: [String],
        title: String,
        body: String,
        data: [String: Any]? = nil,
        imageUrl: String? = nil
    ) async throws {
        let idToken: String
        do {
            idToken = try await FirebaseAuthService.shared.getIDToken()
        } catch {
            print("[ONESIGNAL SERVICE] No authenticated user - cannot send notification")
            throw OneSignalError.notAuthenticated
        }

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

        if let imageUrl = imageUrl {
            payload["imageUrl"] = imageUrl
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

        print("[ONESIGNAL SERVICE] ✅ Response (\(httpResponse.statusCode)): \(responseBody)")
        print("[ONESIGNAL SERVICE] Sent to user IDs: \(recipientUserIds)")
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
