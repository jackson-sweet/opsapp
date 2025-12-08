# Phase 3: Handle Remote Push Notifications

**Priority**: P1
**Estimated Effort**: 1-2 hours
**Dependencies**: Phase 1 complete
**Status**: Not Started

---

## Objective

Enable the app to properly receive and handle push notifications sent from Bubble:
1. Implement remote notification delegate methods
2. Parse push payloads
3. Deep link to correct screens when user taps notification

---

## Current State

`AppDelegate.swift` handles device token registration but does NOT handle incoming remote notifications. The app currently cannot:
- Process background notifications
- Handle notification tap when app is not running
- Parse custom payloads from Bubble

---

## Task 3.1: Add Remote Notification Handling to AppDelegate

### File to Modify
`/Users/jacksonsweet/Desktop/OPS LTD./OPS/OPS/AppDelegate.swift`

### Add These Methods

```swift
// MARK: - Remote Notification Handling

/// Called when a remote notification arrives while app is in foreground
func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    print("[PUSH] Received remote notification: \(userInfo)")

    // Parse the notification
    handleRemoteNotification(userInfo: userInfo)

    // Tell system we processed the notification
    completionHandler(.newData)
}

/// Parse and route remote notification
private func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
    // Extract standard APNs fields
    let aps = userInfo["aps"] as? [String: Any]
    let alert = aps?["alert"] as? [String: Any]
    let title = alert?["title"] as? String
    let body = alert?["body"] as? String

    // Extract custom data from Bubble
    let notificationType = userInfo["type"] as? String
    let projectId = userInfo["projectId"] as? String
    let taskId = userInfo["taskId"] as? String
    let screen = userInfo["screen"] as? String

    print("[PUSH] Type: \(notificationType ?? "unknown")")
    print("[PUSH] Project: \(projectId ?? "none"), Task: \(taskId ?? "none")")

    // Route based on type or screen
    if let screen = screen {
        routeToScreen(screen, projectId: projectId, taskId: taskId)
    } else if let type = notificationType {
        routeByType(type, projectId: projectId, taskId: taskId)
    }
}

/// Route to specific screen based on payload
private func routeToScreen(_ screen: String, projectId: String?, taskId: String?) {
    switch screen {
    case "projectDetails":
        if let projectId = projectId {
            NotificationCenter.default.post(
                name: Notification.Name("OpenProjectDetails"),
                object: nil,
                userInfo: ["projectId": projectId]
            )
        }
    case "taskDetails":
        if let taskId = taskId {
            NotificationCenter.default.post(
                name: Notification.Name("OpenTaskDetails"),
                object: nil,
                userInfo: ["taskId": taskId]
            )
        }
    case "schedule", "calendar":
        NotificationCenter.default.post(
            name: Notification.Name("OpenSchedule"),
            object: nil,
            userInfo: [:]
        )
    case "jobBoard":
        NotificationCenter.default.post(
            name: Notification.Name("OpenJobBoard"),
            object: nil,
            userInfo: [:]
        )
    default:
        print("[PUSH] Unknown screen: \(screen)")
    }
}

/// Route based on notification type
private func routeByType(_ type: String, projectId: String?, taskId: String?) {
    switch type {
    case "assignment", "update", "completion":
        if let projectId = projectId {
            NotificationCenter.default.post(
                name: Notification.Name("OpenProjectDetails"),
                object: nil,
                userInfo: ["projectId": projectId]
            )
        }
    case "taskAssignment", "taskUpdate":
        if let taskId = taskId {
            NotificationCenter.default.post(
                name: Notification.Name("OpenTaskDetails"),
                object: nil,
                userInfo: ["taskId": taskId]
            )
        }
    case "message", "announcement":
        // Could open a messages screen or show in-app banner
        print("[PUSH] Message notification - show in-app")
    default:
        print("[PUSH] Unknown type: \(type)")
    }
}
```

---

## Task 3.2: Handle Launch from Notification

When user taps a notification while app is not running, the app launches with the notification payload.

### Add to AppDelegate

```swift
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    // Existing setup code...

    // Check if launched from notification
    if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
        print("[PUSH] App launched from notification")
        // Delay handling to allow app to fully initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.handleRemoteNotification(userInfo: remoteNotification)
        }
    }

    return true
}
```

---

## Task 3.3: Update NotificationManager Response Handler

The existing `userNotificationCenter(_:didReceive:withCompletionHandler:)` already handles local notification taps. Ensure it also works for remote notifications:

### File to Modify
`/Users/jacksonsweet/Desktop/OPS LTD./OPS/OPS/Utilities/NotificationManager.swift`

### Verify/Update Method

Find `userNotificationCenter(_:didReceive:withCompletionHandler:)` and ensure it handles remote payloads:

```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
) {
    let userInfo = response.notification.request.content.userInfo
    let categoryIdentifier = response.notification.request.content.categoryIdentifier

    print("[NOTIFICATIONS] Response received - Category: \(categoryIdentifier)")
    print("[NOTIFICATIONS] UserInfo: \(userInfo)")

    // Check if this is a remote notification (has "aps" key)
    if userInfo["aps"] != nil {
        handleRemoteNotificationResponse(userInfo: userInfo, actionIdentifier: response.actionIdentifier)
    } else {
        // Handle local notification (existing logic)
        switch categoryIdentifier {
        case NotificationCategory.project.rawValue,
             NotificationCategory.projectAssignment.rawValue,
             NotificationCategory.projectUpdate.rawValue,
             NotificationCategory.projectCompletion.rawValue,
             NotificationCategory.projectAdvance.rawValue:
            handleProjectNotificationResponse(userInfo: userInfo, actionIdentifier: response.actionIdentifier)

        case NotificationCategory.schedule.rawValue:
            handleScheduleNotificationResponse(userInfo: userInfo, actionIdentifier: response.actionIdentifier)

        case NotificationCategory.team.rawValue:
            handleTeamNotificationResponse(userInfo: userInfo, actionIdentifier: response.actionIdentifier)

        default:
            print("[NOTIFICATIONS] Unknown category: \(categoryIdentifier)")
        }
    }

    completionHandler()
}

/// Handle tap on remote push notification
private func handleRemoteNotificationResponse(userInfo: [AnyHashable: Any], actionIdentifier: String) {
    let projectId = userInfo["projectId"] as? String
    let taskId = userInfo["taskId"] as? String
    let screen = userInfo["screen"] as? String
    let type = userInfo["type"] as? String

    // Route based on screen or type (same logic as AppDelegate)
    if let screen = screen {
        routeToScreen(screen, projectId: projectId, taskId: taskId)
    } else if let type = type {
        routeByType(type, projectId: projectId, taskId: taskId)
    } else if let projectId = projectId {
        // Default: open project details
        NotificationCenter.default.post(
            name: Notification.Name("OpenProjectDetails"),
            object: nil,
            userInfo: ["projectId": projectId]
        )
    }
}

private func routeToScreen(_ screen: String, projectId: String?, taskId: String?) {
    // Same implementation as AppDelegate
    switch screen {
    case "projectDetails":
        if let projectId = projectId {
            NotificationCenter.default.post(
                name: Notification.Name("OpenProjectDetails"),
                object: nil,
                userInfo: ["projectId": projectId]
            )
        }
    case "taskDetails":
        if let taskId = taskId {
            NotificationCenter.default.post(
                name: Notification.Name("OpenTaskDetails"),
                object: nil,
                userInfo: ["taskId": taskId]
            )
        }
    case "schedule", "calendar":
        NotificationCenter.default.post(name: Notification.Name("OpenSchedule"), object: nil)
    case "jobBoard":
        NotificationCenter.default.post(name: Notification.Name("OpenJobBoard"), object: nil)
    default:
        break
    }
}

private func routeByType(_ type: String, projectId: String?, taskId: String?) {
    switch type {
    case "assignment", "update", "completion":
        if let projectId = projectId {
            NotificationCenter.default.post(
                name: Notification.Name("OpenProjectDetails"),
                object: nil,
                userInfo: ["projectId": projectId]
            )
        }
    case "taskAssignment", "taskUpdate":
        if let taskId = taskId {
            NotificationCenter.default.post(
                name: Notification.Name("OpenTaskDetails"),
                object: nil,
                userInfo: ["taskId": taskId]
            )
        }
    default:
        break
    }
}
```

---

## Task 3.4: Ensure View Navigation Observers Exist

The app needs to observe these NotificationCenter notifications and navigate accordingly.

### Check OPSApp.swift or ContentView.swift

Ensure observers exist for:
- `OpenProjectDetails`
- `OpenTaskDetails`
- `OpenSchedule`
- `OpenJobBoard`

Example observer setup:

```swift
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenProjectDetails"))) { notification in
    if let projectId = notification.userInfo?["projectId"] as? String {
        // Navigate to project details
        // This depends on your navigation architecture
    }
}
```

---

## Push Payload Formats (Bubble → App)

See `BUBBLE_WORKFLOWS.md` for complete Bubble implementation instructions.

### Task Assignment Notification
```json
{
    "aps": {
        "alert": {
            "title": "New Task Assignment",
            "body": "You've been assigned to Framing on 123 Main St"
        },
        "sound": "default",
        "badge": 1
    },
    "type": "taskAssignment",
    "taskId": "1234567890",
    "projectId": "0987654321",
    "screen": "taskDetails"
}
```

### Schedule Change Notification
```json
{
    "aps": {
        "alert": {
            "title": "Schedule Update",
            "body": "Framing on 123 Main St: Schedule has been updated"
        },
        "sound": "default"
    },
    "type": "scheduleChange",
    "taskId": "1234567890",
    "projectId": "0987654321",
    "screen": "taskDetails"
}
```

### Project Completion Notification
```json
{
    "aps": {
        "alert": {
            "title": "Project Completed",
            "body": "123 Main St has been marked as completed"
        },
        "sound": "default"
    },
    "type": "projectCompletion",
    "projectId": "0987654321",
    "screen": "projectDetails"
}
```

### Supported Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | Yes | Notification type: `taskAssignment`, `taskCompletion`, `scheduleChange`, `projectAssignment`, `projectCompletion` |
| `taskId` | string | For task notifications | Bubble task unique ID |
| `projectId` | string | Yes | Bubble project unique ID |
| `screen` | string | Yes | Screen to open: `taskDetails`, `projectDetails`, `jobBoard` |

---

## Verification Checklist

- [ ] `didReceiveRemoteNotification` added to AppDelegate
- [ ] `handleRemoteNotification()` parses payload correctly
- [ ] Launch from notification handled in `didFinishLaunchingWithOptions`
- [ ] NotificationManager `didReceive` handles remote notifications
- [ ] Navigation observers exist for all screen types
- [ ] Test: Receive push while app in foreground
- [ ] Test: Receive push while app in background
- [ ] Test: Tap notification opens correct screen
- [ ] Test: Launch from notification navigates correctly

---

## Next Phase

After Phase 3 is complete:
- `PHASE_4_SETTINGS_RELIABILITY.md` - Settings integration and error handling
- `PHASE_5_BATCHING.md` - Notification batching system
