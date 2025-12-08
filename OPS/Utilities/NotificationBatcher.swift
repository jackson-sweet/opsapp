//
//  NotificationBatcher.swift
//  OPS
//
//  Created by Claude on 2025-12-04.
//
//  Batches notifications during sync to avoid overwhelming users with
//  multiple individual notifications. Groups notifications by type and
//  sends summary notifications at the end of sync.
//

import Foundation
import UserNotifications

/// Collects and batches notifications during sync operations
class NotificationBatcher {

    // MARK: - Singleton

    static let shared = NotificationBatcher()
    private init() {}

    // MARK: - Properties

    private var isCollecting = false
    private var pendingNotifications: [BatchedNotification] = []
    private let queue = DispatchQueue(label: "com.ops.notificationBatcher")

    // MARK: - Notification Types

    struct BatchedNotification {
        let type: NotificationType
        let projectId: String
        let projectName: String
        let taskId: String?
        let details: String?
    }

    enum NotificationType: String, CaseIterable {
        case assignment = "assignment"
        case scheduleChange = "scheduleChange"
        case completion = "completion"
        case taskAssignment = "taskAssignment"
        case taskUpdate = "taskUpdate"

        var displayName: String {
            switch self {
            case .assignment: return "new project assignment"
            case .scheduleChange: return "schedule change"
            case .completion: return "project completed"
            case .taskAssignment: return "new task assignment"
            case .taskUpdate: return "task update"
            }
        }

        var pluralDisplayName: String {
            switch self {
            case .assignment: return "new project assignments"
            case .scheduleChange: return "schedule changes"
            case .completion: return "projects completed"
            case .taskAssignment: return "new task assignments"
            case .taskUpdate: return "task updates"
            }
        }

        var icon: String {
            switch self {
            case .assignment: return "person.badge.plus"
            case .scheduleChange: return "calendar.badge.exclamationmark"
            case .completion: return "checkmark.circle"
            case .taskAssignment: return "checklist"
            case .taskUpdate: return "pencil.circle"
            }
        }
    }

    // MARK: - Public Methods

    /// Start collecting notifications (call at sync start)
    func startBatch() {
        queue.sync {
            isCollecting = true
            pendingNotifications.removeAll()
            print("[NOTIFICATION_BATCHER] Started collecting notifications")
        }
    }

    /// Check if currently in batching mode
    var isBatching: Bool {
        queue.sync { isCollecting }
    }

    /// Add a notification to the current batch
    /// - Parameters:
    ///   - type: The type of notification
    ///   - projectId: The project ID
    ///   - projectName: The project name for display
    ///   - taskId: Optional task ID for task-related notifications
    ///   - details: Optional additional details
    func add(
        type: NotificationType,
        projectId: String,
        projectName: String,
        taskId: String? = nil,
        details: String? = nil
    ) {
        queue.sync {
            guard isCollecting else {
                // Not batching - send immediately via NotificationManager
                sendImmediate(type: type, projectId: projectId, projectName: projectName, taskId: taskId, details: details)
                return
            }

            let notification = BatchedNotification(
                type: type,
                projectId: projectId,
                projectName: projectName,
                taskId: taskId,
                details: details
            )
            pendingNotifications.append(notification)
            print("[NOTIFICATION_BATCHER] Added \(type.rawValue) for \(projectName)")
        }
    }

    /// End collection and send batched notifications (call at sync end)
    func flushBatch() {
        queue.sync {
            guard isCollecting else { return }
            isCollecting = false

            print("[NOTIFICATION_BATCHER] Flushing batch with \(pendingNotifications.count) notifications")

            if pendingNotifications.isEmpty {
                return
            }

            // Group by type
            let grouped = Dictionary(grouping: pendingNotifications) { $0.type }

            // Generate summary notifications for each type
            for (type, notifications) in grouped {
                sendBatchedNotification(type: type, notifications: notifications)
            }

            pendingNotifications.removeAll()
        }
    }

    /// Cancel current batch without sending (call on sync error)
    func cancelBatch() {
        queue.sync {
            isCollecting = false
            pendingNotifications.removeAll()
            print("[NOTIFICATION_BATCHER] Batch cancelled")
        }
    }

    /// Get count of pending notifications in current batch
    var pendingCount: Int {
        queue.sync { pendingNotifications.count }
    }

    // MARK: - Private Methods

    private func sendBatchedNotification(type: NotificationType, notifications: [BatchedNotification]) {
        guard !notifications.isEmpty else { return }

        // Check user preferences using shouldSendNotification
        let priority: NotificationPriorityLevel = (type == .assignment || type == .taskAssignment) ? .important : .normal
        guard NotificationManager.shared.shouldSendNotification(priority: priority) else {
            print("[NOTIFICATION_BATCHER] Skipped - notifications filtered by settings")
            return
        }

        let content = UNMutableNotificationContent()

        if notifications.count == 1 {
            // Single notification - show specific details
            let notification = notifications[0]
            content.title = singleTitle(for: type)
            content.body = singleBody(for: type, projectName: notification.projectName, details: notification.details)
            content.userInfo = [
                "type": type.rawValue,
                "projectId": notification.projectId,
                "taskId": notification.taskId as Any,
                "batchCount": 1
            ]
        } else {
            // Multiple notifications - show summary
            content.title = "OPS Updates"
            content.body = "\(notifications.count) \(type.pluralDisplayName)"
            content.userInfo = [
                "type": "batch",
                "batchType": type.rawValue,
                "projectIds": notifications.map { $0.projectId },
                "batchCount": notifications.count
            ]
        }

        content.sound = .default
        content.categoryIdentifier = categoryIdentifier(for: type)

        // Schedule immediately (1 second delay)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "batch-\(type.rawValue)-\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NOTIFICATION_BATCHER] Failed to schedule: \(error.localizedDescription)")
            } else {
                print("[NOTIFICATION_BATCHER] Scheduled \(type.rawValue) batch (\(notifications.count) items)")
            }
        }
    }

    private func sendImmediate(type: NotificationType, projectId: String, projectName: String, taskId: String?, details: String?) {
        // Delegate to NotificationManager for non-batched notifications
        switch type {
        case .assignment:
            _ = NotificationManager.shared.scheduleProjectAssignmentNotification(
                projectId: projectId,
                projectTitle: projectName
            )
        case .scheduleChange:
            _ = NotificationManager.shared.scheduleProjectUpdateNotification(
                projectId: projectId,
                projectTitle: projectName,
                updateType: "schedule",
                previousDate: nil,
                newDate: nil
            )
        case .completion:
            _ = NotificationManager.shared.scheduleProjectCompletionNotification(
                projectId: projectId,
                projectTitle: projectName
            )
        case .taskAssignment, .taskUpdate:
            // For task notifications, create a simple notification directly
            let content = UNMutableNotificationContent()
            content.title = type == .taskAssignment ? "New Task Assignment" : "Task Updated"
            content.body = type == .taskAssignment
                ? "You've been assigned a task on \(projectName)"
                : "A task on \(projectName) has been updated"
            content.sound = .default
            content.categoryIdentifier = NotificationCategory.projectAssignment.rawValue
            content.userInfo = [
                "type": type.rawValue,
                "projectId": projectId,
                "taskId": taskId as Any
            ]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let identifier = "\(type.rawValue)-\(projectId)-\(taskId ?? UUID().uuidString)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("[NOTIFICATION_BATCHER] Failed to send immediate: \(error.localizedDescription)")
                }
            }
        }
    }

    private func singleTitle(for type: NotificationType) -> String {
        switch type {
        case .assignment: return "New Project Assignment"
        case .scheduleChange: return "Schedule Update"
        case .completion: return "Project Completed"
        case .taskAssignment: return "New Task Assignment"
        case .taskUpdate: return "Task Updated"
        }
    }

    private func singleBody(for type: NotificationType, projectName: String, details: String?) -> String {
        switch type {
        case .assignment:
            return "You've been assigned to \(projectName)"
        case .scheduleChange:
            return "\(projectName): \(details ?? "Schedule has been updated")"
        case .completion:
            return "\(projectName) has been marked as completed"
        case .taskAssignment:
            return "You've been assigned a task on \(projectName)"
        case .taskUpdate:
            return "A task on \(projectName) has been updated"
        }
    }

    private func categoryIdentifier(for type: NotificationType) -> String {
        switch type {
        case .assignment: return NotificationCategory.projectAssignment.rawValue
        case .scheduleChange: return NotificationCategory.projectUpdate.rawValue
        case .completion: return NotificationCategory.projectCompletion.rawValue
        case .taskAssignment: return NotificationCategory.projectAssignment.rawValue
        case .taskUpdate: return NotificationCategory.projectUpdate.rawValue
        }
    }
}
