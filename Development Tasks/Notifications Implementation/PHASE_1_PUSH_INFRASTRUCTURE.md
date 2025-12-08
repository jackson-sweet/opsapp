# Phase 1: Push Notification Infrastructure (OneSignal)

**Priority**: P0 (Critical)
**Dependencies**: OneSignal account + APNs key configured in OneSignal dashboard
**Status**: ✅ Complete & Tested
**Last Updated**: December 8, 2025

---

## Objective

Enable the app to send and receive push notifications via OneSignal:
1. Initialize OneSignal SDK in the app
2. Link users to OneSignal via External User ID
3. Handle notification clicks (deep linking)
4. Provide methods to trigger notifications from the app

---

## Prerequisites (OneSignal Dashboard)

### Already Complete
- [x] OneSignal account created
- [x] OneSignal app created
- [x] App ID obtained: `0fc0a8e0-9727-49b6-9e37-5d6d919d741f`

### Required Before Testing
- [x] APNs key (.p8 file) uploaded to OneSignal ✅ Done December 8, 2025

---

## Task 1.1: Add OneSignal SDK to Project

### Status: ✅ Complete

OneSignal package added via Swift Package Manager.

---

## Task 1.2: Initialize OneSignal in AppDelegate

### File to Modify
`/Users/jacksonsweet/Desktop/OPS LTD./OPS/OPS/AppDelegate.swift`

### Implementation

```swift
import OneSignalFramework

class AppDelegate: NSObject, UIApplicationDelegate, OSNotificationLifecycleListener {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // ... existing Firebase, Stripe config ...

        // Configure OneSignal
        configureOneSignal()

        // ... rest of existing code ...
        return true
    }

    // MARK: - OneSignal Configuration

    private func configureOneSignal() {
        // Set log level for debugging (set to .none for production)
        OneSignal.Debug.setLogLevel(.LL_VERBOSE)

        // Initialize OneSignal
        OneSignal.initialize("0fc0a8e0-9727-49b6-9e37-5d6d919d741f", withLaunchOptions: nil)

        // Set up notification click handler
        OneSignal.Notifications.addClickListener { event in
            self.handleOneSignalNotificationClick(event: event)
        }

        // Set up foreground notification handler
        OneSignal.Notifications.addForegroundLifecycleListener(self)

        print("[ONESIGNAL] Initialized successfully")
    }

    // Handle notification clicks
    private func handleOneSignalNotificationClick(event: OSNotificationClickEvent) {
        print("[ONESIGNAL] Notification clicked")

        let additionalData = event.notification.additionalData
        let notificationType = additionalData?["type"] as? String
        let projectId = additionalData?["projectId"] as? String
        let taskId = additionalData?["taskId"] as? String
        let screen = additionalData?["screen"] as? String

        DispatchQueue.main.async {
            if let screen = screen {
                self.routeToScreen(screen, projectId: projectId, taskId: taskId)
            } else if let type = notificationType {
                self.routeByType(type, projectId: projectId, taskId: taskId)
            } else if let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenProjectDetails"),
                    object: nil,
                    userInfo: ["projectId": projectId]
                )
            }
        }
    }

    // MARK: - OSNotificationLifecycleListener

    func onWillDisplay(event: OSNotificationWillDisplayEvent) {
        print("[ONESIGNAL] Notification will display in foreground")

        // Check user settings (DND, mute, etc.)
        if NotificationManager.shared.shouldSendNotification() {
            event.notification.display()
        } else {
            event.preventDefault()
            print("[ONESIGNAL] Notification suppressed by user settings")
        }
    }
}
```

### Status: ✅ Complete
- [x] Import added
- [x] Protocol conformance added (`OSNotificationLifecycleListener`, `OSNotificationClickListener`)
- [x] configureOneSignal() method added
- [x] Click handler added (`onClick(event:)` method)
- [x] Foreground handler added (`onWillDisplay(event:)` method)
- [x] Log verbosity configured (LL_WARN debug, LL_NONE release)
- [x] Tested and working on iPhone 16 and iPhone 13

---

## Task 1.3: Link User ID to OneSignal

When a user logs in, we need to link their Bubble user ID to OneSignal so we can target them by user ID.

### File to Modify
`/Users/jacksonsweet/Desktop/OPS LTD./OPS/OPS/Utilities/NotificationManager.swift`

### Add Method

```swift
import OneSignalFramework

// MARK: - OneSignal User Linking

/// Link current user to OneSignal for targeted notifications
/// Call this after user logs in
func linkUserToOneSignal() {
    guard let userId = UserDefaults.standard.string(forKey: "currentUserId") else {
        print("[ONESIGNAL] Cannot link user - no user ID found")
        return
    }

    // Set external user ID in OneSignal
    OneSignal.login(userId)
    print("[ONESIGNAL] Linked user ID: \(userId)")

    // Optionally set tags for segmentation
    if let userRole = UserDefaults.standard.string(forKey: "currentUserRole") {
        OneSignal.User.addTag(key: "role", value: userRole)
    }

    if let companyId = UserDefaults.standard.string(forKey: "currentCompanyId") {
        OneSignal.User.addTag(key: "companyId", value: companyId)
    }
}

/// Unlink user from OneSignal when logging out
/// Call this when user logs out
func unlinkUserFromOneSignal() {
    OneSignal.logout()
    print("[ONESIGNAL] User unlinked from OneSignal")
}
```

### Where to Call

**On Login** (after successful authentication):
```swift
NotificationManager.shared.linkUserToOneSignal()
```

**On Logout**:
```swift
NotificationManager.shared.unlinkUserFromOneSignal()
```

### Status: ✅ Complete
- [x] `linkUserToOneSignal()` added to NotificationManager
- [x] `unlinkUserFromOneSignal()` added to NotificationManager
- [x] Called in DataController after login
- [x] Called in DataController.logout()
- [x] Verified working - users appear in OneSignal dashboard with correct external_id

---

## Task 1.4: Create OneSignal Notification Service (Optional)

Create a service to send notifications via OneSignal REST API.

### New File
`/Users/jacksonsweet/Desktop/OPS LTD./OPS/OPS/Services/OneSignalService.swift`

### Implementation

```swift
//
//  OneSignalService.swift
//  OPS
//
//  Service for sending push notifications via OneSignal REST API
//

import Foundation

class OneSignalService {
    static let shared = OneSignalService()
    private init() {}

    private let appId = "0fc0a8e0-9727-49b6-9e37-5d6d919d741f"
    private let apiEndpoint = "https://onesignal.com/api/v1/notifications"

    // IMPORTANT: REST API Key should be stored securely, not hardcoded
    // For production, this should come from a secure backend or keychain
    private var restApiKey: String? {
        // TODO: Retrieve from secure storage
        return nil
    }

    // MARK: - Send Notification Methods

    /// Send notification to specific user by their external user ID (Bubble user ID)
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

    /// Send notification to multiple users
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

    /// Send notification to a segment (defined in OneSignal dashboard)
    func sendToSegment(
        segment: String,
        title: String,
        body: String,
        data: [String: Any]? = nil
    ) async throws {
        try await sendNotification(
            targetType: .segment,
            targetValue: segment,
            title: title,
            body: body,
            data: data
        )
    }

    // MARK: - Private Implementation

    private enum TargetType {
        case externalUserId
        case externalUserIds
        case segment
        case playerId
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
            print("[ONESIGNAL] REST API key not configured")
            throw OneSignalError.apiKeyNotConfigured
        }

        var payload: [String: Any] = [
            "app_id": appId,
            "headings": ["en": title],
            "contents": ["en": body]
        ]

        // Add targeting
        switch targetType {
        case .externalUserId:
            if let value = targetValue {
                payload["include_external_user_ids"] = [value]
            }
        case .externalUserIds:
            if let values = targetValues {
                payload["include_external_user_ids"] = values
            }
        case .segment:
            if let value = targetValue {
                payload["included_segments"] = [value]
            }
        case .playerId:
            if let value = targetValue {
                payload["include_player_ids"] = [value]
            }
        }

        // Add custom data
        if let data = data {
            payload["data"] = data
        }

        // Make request
        var request = URLRequest(url: URL(string: apiEndpoint)!)
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
            print("[ONESIGNAL] API Error: \(errorMessage)")
            throw OneSignalError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        print("[ONESIGNAL] Notification sent successfully")
    }
}

// MARK: - Errors

enum OneSignalError: Error, LocalizedError {
    case apiKeyNotConfigured
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "OneSignal REST API key not configured"
        case .invalidResponse:
            return "Invalid response from OneSignal API"
        case .apiError(let statusCode, let message):
            return "OneSignal API error (\(statusCode)): \(message)"
        }
    }
}
```

### Status: 🔵 Not Started

---

## Task 1.5: Convenience Methods for App Events

Add helper methods for common notification scenarios.

### Add to NotificationManager.swift or OneSignalService.swift

```swift
// MARK: - App Event Notifications

extension OneSignalService {

    /// Notify user they've been assigned to a task
    func notifyTaskAssignment(
        userId: String,
        taskName: String,
        projectName: String,
        taskId: String,
        projectId: String
    ) async throws {
        try await sendToUser(
            userId: userId,
            title: "New Task Assignment",
            body: "You've been assigned to \(taskName) on \(projectName)",
            data: [
                "type": "taskAssignment",
                "taskId": taskId,
                "projectId": projectId,
                "screen": "taskDetails"
            ]
        )
    }

    /// Notify users of schedule change
    func notifyScheduleChange(
        userIds: [String],
        taskName: String,
        projectName: String,
        taskId: String,
        projectId: String
    ) async throws {
        try await sendToUsers(
            userIds: userIds,
            title: "Schedule Update",
            body: "\(taskName) on \(projectName): Schedule has been updated",
            data: [
                "type": "scheduleChange",
                "taskId": taskId,
                "projectId": projectId,
                "screen": "taskDetails"
            ]
        )
    }

    /// Notify users of project completion
    func notifyProjectCompletion(
        userIds: [String],
        projectName: String,
        projectId: String
    ) async throws {
        try await sendToUsers(
            userIds: userIds,
            title: "Project Completed",
            body: "\(projectName) has been marked as completed",
            data: [
                "type": "projectCompletion",
                "projectId": projectId,
                "screen": "projectDetails"
            ]
        )
    }
}
```

### Status: 🔵 Not Started

---

## Verification Checklist

### OneSignal Dashboard
- [x] APNs key uploaded
- [x] Test notification sent from dashboard works

### iOS App
- [x] OneSignal SDK imported
- [x] OneSignal initialized in AppDelegate
- [x] Click handler routes to correct screens
- [x] Foreground handler respects user settings
- [x] External User ID linked on login
- [x] External User ID cleared on logout
- [ ] OneSignalService created (if using app-triggered notifications) - Optional

### Testing (Completed December 8, 2025)
- [x] Receive notification while app in foreground
- [x] Receive notification while app in background
- [x] Tap notification opens correct screen
- [ ] DND/Mute settings suppress foreground notifications - Not yet tested

---

## Keep for Future Use

The existing device token sync to Bubble should be kept:
- Device token is still captured and stored locally
- Token synced to Bubble User record
- Can be used if direct APNs is needed later

---

## Security Note

The OneSignal REST API Key should NOT be hardcoded in the app. Options:
1. **Manual notifications only** - Use OneSignal dashboard, no API key needed in app
2. **Backend triggers** - Have Bubble call OneSignal API (API key stays on server)
3. **Secure storage** - Store API key in Keychain (less secure, key is on device)

For now, the dashboard + Bubble approach is recommended.
