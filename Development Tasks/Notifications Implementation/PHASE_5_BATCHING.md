# Phase 5: Notification Batching System

**Priority**: P1
**Estimated Effort**: 1-2 hours
**Dependencies**: Phase 2 complete
**Status**: Not Started

---

## Objective

Create a batching system that groups multiple notifications during sync into summary notifications, preventing users from being overwhelmed with individual alerts.

**Instead of:**
- "You've been assigned to Project A"
- "You've been assigned to Project B"
- "Project C schedule changed"
- "Project D schedule changed"
- "Project E schedule changed"

**Show:**
- "2 new project assignments"
- "3 schedule changes"

---

## Design

### NotificationBatcher Class

A stateful class that:
1. Collects notifications during a sync operation
2. Groups them by type
3. Generates summary notifications when sync completes

```
Sync Start → Collect Notifications → Sync End → Flush Batch → Show Summaries
```

---

## Task 5.1: Create NotificationBatcher.swift

### New File
`/Users/jacksonsweet/Desktop/OPS LTD./OPS/OPS/Utilities/NotificationBatcher.swift`

### Implementation

```swift
//
//  NotificationBatcher.swift
//  OPS
//
//  Batches notifications during sync to avoid overwhelming users
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

    /// Add a notification to the current batch
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
                sendImmediate(type: type, projectId: projectId, projectName: projectName, details: details)
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

            // Generate summary notifications
            for (type, notifications) in grouped {
                sendBatchedNotification(type: type, notifications: notifications)
            }

            pendingNotifications.removeAll()
        }
    }

    /// Cancel current batch without sending
    func cancelBatch() {
        queue.sync {
            isCollecting = false
            pendingNotifications.removeAll()
            print("[NOTIFICATION_BATCHER] Batch cancelled")
        }
    }

    // MARK: - Private Methods

    private func sendBatchedNotification(type: NotificationType, notifications: [BatchedNotification]) {
        guard !notifications.isEmpty else { return }

        // Check user preferences
        guard NotificationManager.shared.shouldSendNotification() else {
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

        // Schedule immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "batch-\(type.rawValue)-\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NOTIFICATION_BATCHER] Failed to schedule: \(error)")
            } else {
                print("[NOTIFICATION_BATCHER] Scheduled \(type.rawValue) batch (\(notifications.count) items)")
            }
        }
    }

    private func sendImmediate(type: NotificationType, projectId: String, projectName: String, details: String?) {
        // Delegate to NotificationManager for non-batched notifications
        switch type {
        case .assignment:
            NotificationManager.shared.scheduleProjectAssignmentNotification(projectId: projectId, projectName: projectName)
        case .scheduleChange:
            NotificationManager.shared.scheduleProjectUpdateNotification(projectId: projectId, projectName: projectName, changeDescription: details ?? "Schedule updated")
        case .completion:
            NotificationManager.shared.scheduleProjectCompletionNotification(projectId: projectId, projectName: projectName)
        case .taskAssignment, .taskUpdate:
            // TODO: Add task-specific notification methods
            break
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
        case .assignment: return "PROJECT_ASSIGNMENT_NOTIFICATION"
        case .scheduleChange: return "PROJECT_UPDATE_NOTIFICATION"
        case .completion: return "PROJECT_COMPLETION_NOTIFICATION"
        case .taskAssignment: return "PROJECT_NOTIFICATION"
        case .taskUpdate: return "PROJECT_UPDATE_NOTIFICATION"
        }
    }
}
```

---

## Task 5.2: Integrate with CentralizedSyncManager

### File to Modify
`/Users/jacksonsweet/Desktop/OPS LTD./OPS/OPS/Network/Sync/CentralizedSyncManager.swift`

### Update syncAll() or syncProjects()

```swift
@MainActor
func syncAll() async throws {
    print("[SYNC] Starting complete sync...")

    // Start notification batching
    NotificationBatcher.shared.startBatch()

    do {
        // Existing sync logic...
        try await syncCompany()
        try await syncUsers()
        try await syncClients()
        try await syncTaskTypes()
        try await syncProjects()  // This will add to batch
        try await syncTasks()
        try await syncCalendarEvents()

        // Flush batched notifications
        NotificationBatcher.shared.flushBatch()

        print("[SYNC] Complete sync finished")
    } catch {
        // Cancel batch on error
        NotificationBatcher.shared.cancelBatch()
        throw error
    }
}
```

### Update Phase 2 Trigger Methods to Use Batcher

Replace direct NotificationManager calls with batcher calls:

```swift
private func triggerAssignmentNotifications(for newAssignments: [ProjectDTO]) {
    guard UserDefaults.standard.bool(forKey: "notifyProjectAssignment") else { return }

    for dto in newAssignments {
        NotificationBatcher.shared.add(
            type: .assignment,
            projectId: dto.id,
            projectName: dto.projectName ?? "New Project"
        )
    }
}

private func triggerScheduleChangeNotifications(for changes: [(dto: ProjectDTO, project: Project)]) {
    guard UserDefaults.standard.bool(forKey: "notifyProjectScheduleChanges") else { return }

    for change in changes {
        NotificationBatcher.shared.add(
            type: .scheduleChange,
            projectId: change.dto.id,
            projectName: change.dto.projectName ?? "Project",
            details: "Schedule has been updated"
        )
    }
}

private func triggerCompletionNotifications(for completions: [ProjectDTO]) {
    guard UserDefaults.standard.bool(forKey: "notifyProjectCompletion") else { return }

    for dto in completions {
        NotificationBatcher.shared.add(
            type: .completion,
            projectId: dto.id,
            projectName: dto.projectName ?? "Project"
        )
    }
}
```

---

## Task 5.3: Handle Batch Notification Taps

### File to Modify
`/Users/jacksonsweet/Desktop/OPS LTD./OPS/OPS/Utilities/NotificationManager.swift`

### Update Response Handler

```swift
private func handleBatchNotificationResponse(userInfo: [AnyHashable: Any]) {
    let batchType = userInfo["batchType"] as? String
    let projectIds = userInfo["projectIds"] as? [String]
    let batchCount = userInfo["batchCount"] as? Int ?? 0

    print("[NOTIFICATIONS] Batch notification tapped - Type: \(batchType ?? "unknown"), Count: \(batchCount)")

    if batchCount == 1, let projectId = projectIds?.first {
        // Single item - go to project details
        NotificationCenter.default.post(
            name: Notification.Name("OpenProjectDetails"),
            object: nil,
            userInfo: ["projectId": projectId]
        )
    } else {
        // Multiple items - go to Job Board or relevant list
        NotificationCenter.default.post(
            name: Notification.Name("OpenJobBoard"),
            object: nil,
            userInfo: ["filter": batchType ?? "all"]
        )
    }
}
```

In `userNotificationCenter(_:didReceive:)`, add batch handling:

```swift
// Check for batch notification
if let batchType = userInfo["batchType"] as? String {
    handleBatchNotificationResponse(userInfo: userInfo)
    completionHandler()
    return
}
```

---

## Summary Notification Format Examples

### Single Assignment
```
Title: "New Project Assignment"
Body: "You've been assigned to 123 Main St"
```

### Multiple Assignments
```
Title: "OPS Updates"
Body: "3 new project assignments"
```

### Single Schedule Change
```
Title: "Schedule Update"
Body: "456 Oak Ave: Schedule has been updated"
```

### Multiple Schedule Changes
```
Title: "OPS Updates"
Body: "5 schedule changes"
```

### Mixed Batch (optional future enhancement)
```
Title: "OPS Updates"
Body: "2 new assignments, 3 schedule changes, 1 project completed"
```

---

## Verification Checklist

- [ ] `NotificationBatcher.swift` created in Utilities folder
- [ ] `startBatch()` called at start of `syncAll()`
- [ ] `flushBatch()` called at end of `syncAll()`
- [ ] `cancelBatch()` called on sync error
- [ ] Trigger methods use `NotificationBatcher.shared.add()` instead of direct scheduling
- [ ] Batch notification tap handler implemented
- [ ] Test: Single notification shows specific details
- [ ] Test: Multiple same-type notifications batched into summary
- [ ] Test: Tapping batch notification navigates to Job Board
- [ ] Test: Batch cancelled if sync fails

---

## Future Enhancements

1. **Mixed type summaries**: "2 assignments, 3 schedule changes"
2. **Notification grouping**: Use iOS notification threading
3. **Time-based batching**: Batch notifications within 5-minute windows even outside sync
4. **Priority-based batching**: Always show critical notifications immediately, batch normal ones
