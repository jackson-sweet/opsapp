# Phase 2: Local Notification Scheduling (Task-Based)

**Priority**: P1
**Estimated Effort**: 2-3 hours
**Dependencies**: None (independent of push infrastructure)
**Status**: ✅ Complete (December 4, 2025)

---

## Objective

Schedule local notifications as advance reminders before tasks start. These are:
- Scheduled on the user's device (not from Bubble)
- Based on task start date
- Only for tasks the user is assigned to
- Lead time configured by user preference (e.g., "notify me 2 days before")

---

## Current State

The existing `NotificationManager.swift` has methods for scheduling advance notices, but they:
- Use **project** dates instead of **task** dates
- Schedule based on project, not individual task assignments

We need to update this to be task-centric.

---

## Task 2.1: Update Advance Notice Scheduling

### File to Modify
`/Users/jacksonsweet/Desktop/OPS LTD./OPS/OPS/Utilities/NotificationManager.swift`

### Current Method (approximate)
```swift
func scheduleProjectAdvanceNotice(project: Project, daysBefore: Int) {
    // Uses project.startDate
}
```

### New Method
```swift
/// Schedule advance notice for a task
/// - Parameters:
///   - task: The task to schedule notification for
///   - projectName: Name of the project (for notification body)
///   - daysBefore: Days before task start to notify
func scheduleTaskAdvanceNotice(task: ProjectTask, projectName: String, daysBefore: Int) {
    guard let taskStartDate = task.startDate else {
        print("[NOTIFICATIONS] Task \(task.id) has no start date - skipping advance notice")
        return
    }

    // Check user preferences
    guard UserDefaults.standard.bool(forKey: "notifyAdvanceNotice") else {
        print("[NOTIFICATIONS] Advance notice disabled by user")
        return
    }

    // Calculate notification date
    let noticeHour = UserDefaults.standard.integer(forKey: "advanceNoticeHour")
    let noticeMinute = UserDefaults.standard.integer(forKey: "advanceNoticeMinute")

    guard let notificationDate = Calendar.current.date(
        byAdding: .day,
        value: -daysBefore,
        to: taskStartDate
    ) else { return }

    // Set specific time
    var components = Calendar.current.dateComponents([.year, .month, .day], from: notificationDate)
    components.hour = noticeHour > 0 ? noticeHour : 8  // Default 8 AM
    components.minute = noticeMinute

    guard let scheduledDate = Calendar.current.date(from: components) else { return }

    // Don't schedule if date is in the past
    guard scheduledDate > Date() else {
        print("[NOTIFICATIONS] Advance notice date already passed for task \(task.id)")
        return
    }

    // Create notification content
    let content = UNMutableNotificationContent()
    content.title = "Upcoming Task"

    if daysBefore == 1 {
        content.body = "\(task.name ?? "Task") on \(projectName) starts tomorrow"
    } else {
        content.body = "\(task.name ?? "Task") on \(projectName) starts in \(daysBefore) days"
    }

    content.sound = .default
    content.categoryIdentifier = NotificationCategory.projectAdvance.rawValue
    content.userInfo = [
        "taskId": task.id,
        "projectId": task.project?.id ?? "",
        "type": "advanceNotice",
        "daysBefore": daysBefore
    ]

    // Create trigger
    let triggerComponents = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute],
        from: scheduledDate
    )
    let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)

    // Create request with unique identifier
    let identifier = "advance-\(task.id)-\(daysBefore)d"
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            print("[NOTIFICATIONS] Failed to schedule advance notice: \(error)")
        } else {
            print("[NOTIFICATIONS] Scheduled \(daysBefore)-day advance notice for task \(task.id) at \(scheduledDate)")
        }
    }
}
```

---

## Task 2.2: Schedule Notifications for All Assigned Tasks

### Add Method to NotificationManager

```swift
/// Schedule advance notices for all tasks assigned to current user
/// Call this after sync completes
func scheduleAdvanceNoticesForUserTasks(tasks: [ProjectTask], currentUserId: String) {
    // Get user's preferred lead times
    let day1 = UserDefaults.standard.integer(forKey: "advanceNoticeDays1")
    let day2 = UserDefaults.standard.integer(forKey: "advanceNoticeDays2")
    let day3 = UserDefaults.standard.integer(forKey: "advanceNoticeDays3")
    let leadTimes = [day1, day2, day3].filter { $0 > 0 }

    guard !leadTimes.isEmpty else {
        print("[NOTIFICATIONS] No advance notice days configured")
        return
    }

    // Filter to only tasks user is assigned to
    let assignedTasks = tasks.filter { task in
        task.assignedTo?.contains(currentUserId) ?? false
    }

    print("[NOTIFICATIONS] Scheduling advance notices for \(assignedTasks.count) assigned tasks")

    for task in assignedTasks {
        guard let projectName = task.project?.projectName else { continue }

        for days in leadTimes {
            scheduleTaskAdvanceNotice(task: task, projectName: projectName, daysBefore: days)
        }
    }
}
```

---

## Task 2.3: Cancel Notifications When Task Changes

### Add Cancellation Methods

```swift
/// Remove all advance notices for a specific task
func removeAdvanceNoticesForTask(taskId: String) {
    // Remove all possible advance notice identifiers for this task
    let possibleDays = [1, 2, 3, 4, 5, 6, 7, 14, 30]  // Cover all reasonable lead times
    let identifiers = possibleDays.map { "advance-\(taskId)-\($0)d" }

    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    print("[NOTIFICATIONS] Removed advance notices for task \(taskId)")
}

/// Remove all advance notices for a project's tasks
func removeAdvanceNoticesForProject(projectId: String, tasks: [ProjectTask]) {
    for task in tasks where task.project?.id == projectId {
        removeAdvanceNoticesForTask(taskId: task.id)
    }
}
```

---

## Task 2.4: Integrate with Sync Manager

### File to Modify
`/Users/jacksonsweet/Desktop/OPS LTD./OPS/OPS/Network/Sync/CentralizedSyncManager.swift`

### After Task Sync Completes

```swift
// In syncTasks() or syncAll(), after tasks are saved:
private func scheduleLocalNotifications() {
    guard let currentUserId = UserDefaults.standard.string(forKey: "currentUserId") else {
        return
    }

    // Fetch all tasks from local database
    let descriptor = FetchDescriptor<ProjectTask>()
    guard let tasks = try? modelContext.fetch(descriptor) else { return }

    // Schedule advance notices
    NotificationManager.shared.scheduleAdvanceNoticesForUserTasks(
        tasks: tasks,
        currentUserId: currentUserId
    )
}
```

---

## Task 2.5: Reschedule on Preference Change

### File to Modify
`/Users/jacksonsweet/Desktop/OPS LTD./OPS/OPS/Views/Settings/NotificationSettingsView.swift`

When user changes advance notice preferences, reschedule all notifications:

```swift
// Add onChange handler to the advance notice settings
.onChange(of: advanceNoticeDays1) { oldValue, newValue in
    rescheduleAllAdvanceNotices()
}
.onChange(of: advanceNoticeDays2) { oldValue, newValue in
    rescheduleAllAdvanceNotices()
}
.onChange(of: advanceNoticeDays3) { oldValue, newValue in
    rescheduleAllAdvanceNotices()
}
.onChange(of: advanceNoticeHour) { oldValue, newValue in
    rescheduleAllAdvanceNotices()
}

private func rescheduleAllAdvanceNotices() {
    // Clear all existing advance notices
    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
        let advanceIds = requests
            .filter { $0.identifier.hasPrefix("advance-") }
            .map { $0.identifier }

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: advanceIds)

        // Trigger reschedule via notification or direct call
        NotificationCenter.default.post(
            name: Notification.Name("RescheduleAdvanceNotices"),
            object: nil
        )
    }
}
```

---

## User Preference Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `notifyAdvanceNotice` | Bool | true | Enable/disable advance notices |
| `advanceNoticeDays1` | Int | 1 | First lead time (days before) |
| `advanceNoticeDays2` | Int | 0 | Second lead time (0 = disabled) |
| `advanceNoticeDays3` | Int | 0 | Third lead time (0 = disabled) |
| `advanceNoticeHour` | Int | 8 | Hour to send notification (24h) |
| `advanceNoticeMinute` | Int | 0 | Minute to send notification |

---

## Notification Format

### Single Day Before
```
Title: "Upcoming Task"
Body: "Framing on 123 Main St starts tomorrow"
```

### Multiple Days Before
```
Title: "Upcoming Task"
Body: "Framing on 123 Main St starts in 3 days"
```

---

## Verification Checklist

- [x] `scheduleTaskAdvanceNotice()` method added to NotificationManager
- [x] `scheduleAdvanceNoticesForUserTasks()` method added
- [x] `removeAdvanceNoticesForTask()` method added
- [x] Sync manager calls scheduling after task sync
- [x] Settings view triggers reschedule on preference change
- [ ] Test: Notification scheduled for correct date/time
- [ ] Test: Only assigned tasks get notifications
- [ ] Test: Changing lead time reschedules notifications
- [ ] Test: Deleting task cancels its notifications
- [ ] Test: Past tasks don't get notifications scheduled

---

## Next Phase

After Phase 2 is complete, proceed to:
- `PHASE_3_REMOTE_HANDLING.md` - Handle incoming push notifications
