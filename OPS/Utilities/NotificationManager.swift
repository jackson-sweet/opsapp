//
//  NotificationManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-09.
//

import Foundation
import UserNotifications
import UIKit
import Combine
import CoreLocation
import SwiftData
import OneSignalFramework

/// Notification categories for different types of notifications
enum NotificationCategory: String {
    case project = "PROJECT_NOTIFICATION"
    case schedule = "SCHEDULE_NOTIFICATION"
    case team = "TEAM_NOTIFICATION"
    case general = "GENERAL_NOTIFICATION"
    case projectAssignment = "PROJECT_ASSIGNMENT_NOTIFICATION"
    case projectUpdate = "PROJECT_UPDATE_NOTIFICATION"
    case projectCompletion = "PROJECT_COMPLETION_NOTIFICATION"
    case projectAdvance = "PROJECT_ADVANCE_NOTIFICATION"
}

/// Notification actions that can be taken on notifications
enum NotificationAction: String {
    case view = "VIEW_ACTION"
    case accept = "ACCEPT_ACTION"
    case decline = "DECLINE_ACTION"
    case dismiss = "DISMISS_ACTION"
}

/// Notification priority levels for filtering
enum NotificationPriorityLevel: String {
    case normal = "normal"
    case important = "important"
    case critical = "critical"
}

/// Errors that can occur during notification operations
enum NotificationError: Error, LocalizedError {
    case permissionDenied
    case schedulingFailed(String)
    case tokenSyncFailed(Error)
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permissions not granted"
        case .schedulingFailed(let reason):
            return "Failed to schedule notification: \(reason)"
        case .tokenSyncFailed(let error):
            return "Failed to sync device token: \(error.localizedDescription)"
        case .invalidDate:
            return "Invalid date for notification"
        }
    }
}

/// Manages all notification-related functionality including requesting permissions,
/// sending local notifications, and handling remote notifications
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    // Status of notification permissions
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var isNotificationsEnabled: Bool = false
    
    // List of pending notifications
    @Published var pendingNotifications: [UNNotificationRequest] = []
    
    // Subject for publishing notification events
    private let notificationSubject = PassthroughSubject<UNNotification, Never>()
    var notificationPublisher: AnyPublisher<UNNotification, Never> {
        notificationSubject.eraseToAnyPublisher()
    }
    
    let notificationCenter = UNUserNotificationCenter.current()
    
    override init() {
        super.init()
        
        // Set delegate to handle notification responses
        notificationCenter.delegate = self
        
        // Setup notification categories and actions
        setupNotificationCategories()
        
        // Check initial authorization status
        getAuthorizationStatus()
        
        // Register for significant location change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveSignificantLocationChange(_:)),
            name: .significantLocationChange,
            object: nil
        )
    }
    
    @objc private func didReceiveSignificantLocationChange(_ notification: Notification) {
        // Handle significant location change
        handleSignificantLocationChange(notification)
    }
    
    /// Set up notification categories with associated actions
    private func setupNotificationCategories() {
        // Project notifications with view action
        let viewAction = UNNotificationAction(
            identifier: NotificationAction.view.rawValue,
            title: "View",
            options: .foreground
        )
        
        // For schedule notifications, allow accept/decline actions
        let acceptAction = UNNotificationAction(
            identifier: NotificationAction.accept.rawValue,
            title: "Accept",
            options: .foreground
        )
        
        let declineAction = UNNotificationAction(
            identifier: NotificationAction.decline.rawValue,
            title: "Decline",
            options: .destructive
        )
        
        // Create categories with the actions
        let projectCategory = UNNotificationCategory(
            identifier: NotificationCategory.project.rawValue,
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )
        
        let scheduleCategory = UNNotificationCategory(
            identifier: NotificationCategory.schedule.rawValue,
            actions: [acceptAction, declineAction],
            intentIdentifiers: [],
            options: []
        )
        
        let teamCategory = UNNotificationCategory(
            identifier: NotificationCategory.team.rawValue,
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )
        
        let generalCategory = UNNotificationCategory(
            identifier: NotificationCategory.general.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        
        // Create categories for our new notification types
        let projectAssignmentCategory = UNNotificationCategory(
            identifier: NotificationCategory.projectAssignment.rawValue,
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )
        
        let projectUpdateCategory = UNNotificationCategory(
            identifier: NotificationCategory.projectUpdate.rawValue,
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )
        
        let projectCompletionCategory = UNNotificationCategory(
            identifier: NotificationCategory.projectCompletion.rawValue,
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )
        
        let projectAdvanceCategory = UNNotificationCategory(
            identifier: NotificationCategory.projectAdvance.rawValue,
            actions: [viewAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register all categories
        notificationCenter.setNotificationCategories([
            projectCategory,
            scheduleCategory,
            teamCategory,
            generalCategory,
            projectAssignmentCategory,
            projectUpdateCategory,
            projectCompletionCategory,
            projectAdvanceCategory
        ])
    }
    
    /// Get the current notification authorization status
    func getAuthorizationStatus() {
        notificationCenter.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
                self.isNotificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }
    
    /// Request permission to send notifications if not already determined
    func requestPermission(completion: @escaping (Bool) -> Void = { _ in }) {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false)
                    return
                }
                
                // Update our stored status
                self.isNotificationsEnabled = granted
                
                if granted {
                    // Register for remote notifications if permission is granted
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                } else {
                }
                
                completion(granted)
                
                // Reset the updated status
                self.getAuthorizationStatus()
            }
        }
    }
    
    /// Register with APNs for remote notifications
    func registerForRemoteNotifications() {
        if isNotificationsEnabled {
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
    
    /// Schedule a local notification for a project
    func scheduleProjectNotification(
        projectId: String,
        title: String,
        body: String,
        date: Date? = nil,
        repeats: Bool = false,
        sound: UNNotificationSound = .default
    ) -> String {
        // Create content
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.categoryIdentifier = NotificationCategory.project.rawValue
        
        // Include project ID in the user info
        content.userInfo = ["projectId": projectId]
        
        // Create trigger: immediately if no date provided
        let trigger: UNNotificationTrigger
        if let date = date {
            // Create date components for the specified date (removing seconds for stability)
            var dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            
            if repeats {
                // For daily repeating notifications, only keep hour and minute
                dateComponents = Calendar.current.dateComponents([.hour, .minute], from: date)
            }
            
            trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: repeats)
        } else {
            // Immediate notification with a small delay (1 second)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }
        
        // Create identifier
        let identifier = "project-\(projectId)-\(UUID().uuidString)"
        
        // Create request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // Add request to notification center
        notificationCenter.add(request) { error in
            if let error = error {
            } else {
            }
        }
        
        // Return the notification identifier in case it needs to be removed later
        return identifier
    }
    
    /// Schedule a team notification
    func scheduleTeamNotification(
        teamMemberId: String,
        title: String,
        body: String,
        date: Date? = nil
    ) -> String {
        // Create content
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.team.rawValue
        
        // Include team member ID in the user info
        content.userInfo = ["teamMemberId": teamMemberId]
        
        // Create trigger
        let trigger: UNNotificationTrigger
        if let date = date {
            let dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }
        
        // Create identifier
        let identifier = "team-\(teamMemberId)-\(UUID().uuidString)"
        
        // Create request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // Add request to notification center
        notificationCenter.add(request) { error in
            if let error = error {
            } else {
            }
        }
        
        return identifier
    }
    
    /// Schedule a reminder notification for a specific day's schedule
    func scheduleReminderNotification(
        date: Date,
        projectCount: Int,
        title: String = "Today's Schedule",
        body: String? = nil
    ) -> String {
        // Create content
        let content = UNMutableNotificationContent()
        content.title = title
        
        // If body is provided, use it; otherwise, create a default message
        if let customBody = body {
            content.body = customBody
        } else {
            if projectCount == 0 {
                content.body = "You have no scheduled projects today."
            } else if projectCount == 1 {
                content.body = "You have 1 project scheduled today."
            } else {
                content.body = "You have \(projectCount) projects scheduled today."
            }
        }
        
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.schedule.rawValue
        
        // Format date for user info
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        content.userInfo = ["date": dateString, "projectCount": projectCount]
        
        // Create date components for 7:00 AM on the specified date
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        dateComponents.hour = 7
        dateComponents.minute = 0
        
        // Create trigger
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        // Create identifier
        let identifier = "schedule-\(dateString)"
        
        // Create request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // Add request to notification center
        notificationCenter.add(request) { error in
            if let error = error {
            } else {
            }
        }
        
        return identifier
    }
    
    /// Remove a specific notification by ID
    func removeNotification(identifier: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
    
    /// Remove all notifications for a specific project
    func removeAllNotificationsForProject(projectId: String) {
        // Get all pending notification requests
        notificationCenter.getPendingNotificationRequests { requests in
            // Filter for those that are for this project
            let projectNotificationIds = requests.filter { request in
                guard let requestProjectId = request.content.userInfo["projectId"] as? String else {
                    return false
                }
                return requestProjectId == projectId
            }.map { $0.identifier }
            
            // Remove them if any found
            if !projectNotificationIds.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: projectNotificationIds)
            }
        }
    }
    
    /// Remove all pending notifications
    func removeAllPendingNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }
    
    /// Get all pending notifications
    func getAllPendingNotifications() {
        notificationCenter.getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                self.pendingNotifications = requests
            }
        }
    }
    
    /// Handle device token registration for remote notifications
    func handleDeviceTokenRegistration(deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()

        print("[NOTIFICATIONS] Device token received: \(token.prefix(20))...")

        // Check if token changed from previous value
        let previousToken = UserDefaults.standard.string(forKey: "apns_device_token")

        // Store device token in UserDefaults
        UserDefaults.standard.set(token, forKey: "apns_device_token")

        // Sync to Bubble if token changed or first time
        if token != previousToken {
            print("[NOTIFICATIONS] Token changed, syncing to Bubble...")
            Task {
                await syncDeviceTokenToBubble(token: token)
            }
        } else {
            print("[NOTIFICATIONS] Token unchanged, skipping sync")
        }
    }

    /// Sync the device token to the Bubble backend
    @MainActor
    func syncDeviceTokenToBubble(token: String) async {
        // Get current user ID from UserDefaults
        guard let userId = UserDefaults.standard.string(forKey: "currentUserId") else {
            print("[NOTIFICATIONS] Cannot sync token - no user ID found")
            return
        }

        print("[NOTIFICATIONS] Syncing device token for user: \(userId)")

        do {
            try await updateUserDeviceToken(userId: userId, token: token)
            print("[NOTIFICATIONS] ✅ Device token synced to Bubble successfully")
        } catch {
            print("[NOTIFICATIONS] ❌ Failed to sync device token: \(error.localizedDescription)")
            // Token will be re-synced on next app launch when token registration is called again
        }
    }

    /// Update user's device token on Bubble backend
    private func updateUserDeviceToken(userId: String, token: String) async throws {
        let baseURL = "https://opsapp.co/api/1.1/obj/user/"

        guard let url = URL(string: baseURL + userId) else {
            throw NSError(domain: "NotificationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            BubbleFields.User.deviceToken: token
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "NotificationManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        print("[NOTIFICATIONS] Device token PATCH response: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            if let responseString = String(data: data, encoding: .utf8) {
                print("[NOTIFICATIONS] Error response: \(responseString)")
            }
            throw NSError(domain: "NotificationManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP error \(httpResponse.statusCode)"])
        }
    }
    
    /// Open app settings for notification permissions
    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - OneSignal User Linking

    /// Link current user to OneSignal for targeted push notifications
    /// Call this after user logs in successfully
    func linkUserToOneSignal() {
        guard let userId = UserDefaults.standard.string(forKey: "currentUserId") else {
            print("[ONESIGNAL] Cannot link user - no user ID found")
            return
        }

        // Login to OneSignal with external user ID
        OneSignal.login(userId)
        print("[ONESIGNAL] Linked user ID: \(userId)")

        // Add tags for segmentation (optional but useful)
        // Try multiple keys since user type can be stored in different places
        let userRole = UserDefaults.standard.string(forKey: "selected_user_type")
            ?? UserDefaults.standard.string(forKey: "user_type")
            ?? UserDefaults.standard.string(forKey: "user_type_raw")

        if let role = userRole {
            OneSignal.User.addTag(key: "role", value: role)
            print("[ONESIGNAL] Added role tag: \(role)")
        }

        // Try multiple keys for company ID
        let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId")
            ?? UserDefaults.standard.string(forKey: "company_id")

        if let company = companyId {
            OneSignal.User.addTag(key: "companyId", value: company)
            print("[ONESIGNAL] Added companyId tag: \(company)")
        }
    }

    /// Unlink user from OneSignal when logging out
    /// Call this when user logs out
    func unlinkUserFromOneSignal() {
        OneSignal.logout()
        print("[ONESIGNAL] User unlinked from OneSignal")
    }

    // MARK: - Notification Filtering

    /// Check if notifications should be sent based on user settings (DND, mute, priority filter)
    /// - Parameter priority: The priority level of the notification
    /// - Returns: true if notification should be sent, false if it should be silenced
    func shouldSendNotification(priority: NotificationPriorityLevel = .normal) -> Bool {
        // Check temporary mute first (overrides everything)
        let isMuted = UserDefaults.standard.bool(forKey: "isMuted")
        let muteUntil = UserDefaults.standard.double(forKey: "muteUntil")
        if isMuted && muteUntil > Date().timeIntervalSince1970 {
            print("[NOTIFICATIONS] Silenced: Temporarily muted until \(Date(timeIntervalSince1970: muteUntil))")
            return false
        }

        // Auto-disable expired mute
        if isMuted && muteUntil > 0 && muteUntil < Date().timeIntervalSince1970 {
            UserDefaults.standard.set(false, forKey: "isMuted")
            UserDefaults.standard.set(0.0, forKey: "muteUntil")
        }

        // Check quiet hours (Do Not Disturb)
        let quietHoursEnabled = UserDefaults.standard.bool(forKey: "quietHoursEnabled")
        if quietHoursEnabled {
            let quietStart = UserDefaults.standard.integer(forKey: "quietHoursStart")
            let quietEnd = UserDefaults.standard.integer(forKey: "quietHoursEnd")
            let currentHour = Calendar.current.component(.hour, from: Date())

            let isInQuietHours: Bool
            if quietStart > quietEnd {
                // Quiet hours span midnight (e.g., 22:00 - 07:00)
                isInQuietHours = currentHour >= quietStart || currentHour < quietEnd
            } else if quietStart < quietEnd {
                // Quiet hours within same day (e.g., 13:00 - 14:00)
                isInQuietHours = currentHour >= quietStart && currentHour < quietEnd
            } else {
                // Start equals end - no quiet hours
                isInQuietHours = false
            }

            if isInQuietHours {
                print("[NOTIFICATIONS] Silenced: Currently in quiet hours (\(quietStart):00 - \(quietEnd):00)")
                return false
            }
        }

        // Check priority filter
        let priorityFilter = UserDefaults.standard.string(forKey: "notificationPriority") ?? "all"
        switch priorityFilter {
        case "important":
            if priority == .normal {
                print("[NOTIFICATIONS] Filtered: Only important notifications enabled")
                return false
            }
        case "critical":
            if priority != .critical {
                print("[NOTIFICATIONS] Filtered: Only critical notifications enabled")
                return false
            }
        default:
            break  // "all" - send everything
        }

        return true
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Called when a notification is received while the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Check if notification should be silenced based on user settings
        // Determine priority based on notification category
        let category = notification.request.content.categoryIdentifier
        let priority: NotificationPriorityLevel
        switch category {
        case NotificationCategory.projectAssignment.rawValue:
            priority = .important
        case NotificationCategory.projectAdvance.rawValue:
            priority = .important
        case NotificationCategory.projectCompletion.rawValue:
            priority = .normal
        default:
            priority = .normal
        }

        guard shouldSendNotification(priority: priority) else {
            print("[NOTIFICATIONS] Notification silenced by user settings")
            completionHandler([])  // Don't show the notification
            return
        }

        // Forward the notification to our publisher
        notificationSubject.send(notification)

        // Show the notification alert, play sound, and update badge
        completionHandler([.banner, .sound, .badge])
    }
    
    /// Called when a user interacts with a notification (taps on it)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Get the notification
        let notification = response.notification

        // Get user info from the notification
        let userInfo = notification.request.content.userInfo

        // Get the action identifier
        let actionIdentifier = response.actionIdentifier

        // Get the category identifier
        let categoryIdentifier = notification.request.content.categoryIdentifier

        print("[NOTIFICATIONS] Response received - Category: \(categoryIdentifier)")
        print("[NOTIFICATIONS] UserInfo: \(userInfo)")

        // Check for batch notification first
        if let _ = userInfo["batchType"] as? String {
            handleBatchNotificationResponse(userInfo: userInfo)
            completionHandler()
            return
        }

        // Check if this is a remote notification (has "aps" key)
        if userInfo["aps"] != nil {
            handleRemoteNotificationResponse(userInfo: userInfo, actionIdentifier: actionIdentifier)
        } else {
            // Handle local notification based on category
            switch categoryIdentifier {
            case NotificationCategory.project.rawValue:
                handleProjectNotificationResponse(userInfo: userInfo, actionIdentifier: actionIdentifier)

            case NotificationCategory.schedule.rawValue:
                handleScheduleNotificationResponse(userInfo: userInfo, actionIdentifier: actionIdentifier)

            case NotificationCategory.team.rawValue:
                handleTeamNotificationResponse(userInfo: userInfo, actionIdentifier: actionIdentifier)

            case NotificationCategory.projectAssignment.rawValue,
                 NotificationCategory.projectUpdate.rawValue,
                 NotificationCategory.projectCompletion.rawValue,
                 NotificationCategory.projectAdvance.rawValue:
                // Check if this is a task advance notice (has taskId)
                if let taskId = userInfo["taskId"] as? String {
                    handleTaskNotificationResponse(userInfo: userInfo, actionIdentifier: actionIdentifier)
                } else {
                    // Project notification - open project details
                    handleProjectNotificationResponse(userInfo: userInfo, actionIdentifier: actionIdentifier)
                }

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

        print("[NOTIFICATIONS] Handling remote notification response - screen: \(screen ?? "none"), type: \(type ?? "none")")

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

    /// Handle tap on task notification (advance notices)
    private func handleTaskNotificationResponse(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        guard let taskId = userInfo["taskId"] as? String else { return }
        let projectId = userInfo["projectId"] as? String

        print("[NOTIFICATIONS] Task notification tapped - Task: \(taskId), Project: \(projectId ?? "none")")

        switch actionIdentifier {
        case NotificationAction.view.rawValue, UNNotificationDefaultActionIdentifier:
            if let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenTaskDetails"),
                    object: nil,
                    userInfo: ["taskId": taskId, "projectId": projectId]
                )
            }
        default:
            break
        }
    }

    /// Handle tap on batched notification
    private func handleBatchNotificationResponse(userInfo: [AnyHashable: Any]) {
        let batchType = userInfo["batchType"] as? String
        let projectIds = userInfo["projectIds"] as? [String]
        let batchCount = userInfo["batchCount"] as? Int ?? 0

        print("[NOTIFICATIONS] Batch notification tapped - Type: \(batchType ?? "unknown"), Count: \(batchCount)")

        if batchCount == 1, let projectId = projectIds?.first {
            // Single item in batch - go to project details
            NotificationCenter.default.post(
                name: Notification.Name("OpenProjectDetails"),
                object: nil,
                userInfo: ["projectId": projectId]
            )
        } else {
            // Multiple items - go to Job Board
            NotificationCenter.default.post(
                name: Notification.Name("OpenJobBoard"),
                object: nil,
                userInfo: ["filter": batchType ?? "all"]
            )
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
            if let taskId = taskId, let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenTaskDetails"),
                    object: nil,
                    userInfo: ["taskId": taskId, "projectId": projectId]
                )
            }
        case "schedule", "calendar":
            NotificationCenter.default.post(name: Notification.Name("OpenSchedule"), object: nil)
        case "jobBoard":
            NotificationCenter.default.post(name: Notification.Name("OpenJobBoard"), object: nil)
        default:
            print("[NOTIFICATIONS] Unknown screen: \(screen)")
        }
    }

    /// Route based on notification type
    private func routeByType(_ type: String, projectId: String?, taskId: String?) {
        switch type {
        case "assignment", "update", "completion", "projectCompletion":
            if let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenProjectDetails"),
                    object: nil,
                    userInfo: ["projectId": projectId]
                )
            }
        case "taskAssignment", "taskUpdate", "scheduleChange", "advanceNotice":
            if let taskId = taskId, let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenTaskDetails"),
                    object: nil,
                    userInfo: ["taskId": taskId, "projectId": projectId]
                )
            } else if let projectId = projectId {
                // Fallback to project details
                NotificationCenter.default.post(
                    name: Notification.Name("OpenProjectDetails"),
                    object: nil,
                    userInfo: ["projectId": projectId]
                )
            }
        default:
            print("[NOTIFICATIONS] Unknown type: \(type)")
        }
    }
    
    // MARK: - Notification Response Handlers
    
    private func handleProjectNotificationResponse(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        guard let projectId = userInfo["projectId"] as? String else {
            return
        }
        
        
        switch actionIdentifier {
        case NotificationAction.view.rawValue:
            // Post notification to open project details
            NotificationCenter.default.post(
                name: Notification.Name("OpenProjectDetails"),
                object: nil,
                userInfo: ["projectId": projectId]
            )
            
        case UNNotificationDefaultActionIdentifier:
            // Post notification to open project details
            NotificationCenter.default.post(
                name: Notification.Name("OpenProjectDetails"),
                object: nil,
                userInfo: ["projectId": projectId]
            )
            
        default:
            break
        }
    }
    
    private func handleScheduleNotificationResponse(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        guard let dateString = userInfo["date"] as? String else {
            return
        }
        
        
        switch actionIdentifier {
        case NotificationAction.accept.rawValue:
            // Post notification to acknowledge schedule
            NotificationCenter.default.post(
                name: Notification.Name("ScheduleAccepted"),
                object: nil,
                userInfo: ["date": dateString]
            )
            
        case NotificationAction.decline.rawValue:
            // Post notification to decline schedule
            NotificationCenter.default.post(
                name: Notification.Name("ScheduleDeclined"),
                object: nil,
                userInfo: ["date": dateString]
            )
            
        case UNNotificationDefaultActionIdentifier:
            // Post notification to open schedule for the day
            NotificationCenter.default.post(
                name: Notification.Name("OpenSchedule"),
                object: nil,
                userInfo: ["date": dateString]
            )
            
        default:
            break
        }
    }
    
    private func handleTeamNotificationResponse(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        guard let teamMemberId = userInfo["teamMemberId"] as? String else {
            return
        }
        
        
        switch actionIdentifier {
        case NotificationAction.view.rawValue:
            // Post notification to open team member details
            NotificationCenter.default.post(
                name: Notification.Name("OpenTeamMemberDetails"),
                object: nil,
                userInfo: ["teamMemberId": teamMemberId]
            )
            
        case UNNotificationDefaultActionIdentifier:
            // Post notification to open team member details
            NotificationCenter.default.post(
                name: Notification.Name("OpenTeamMemberDetails"),
                object: nil,
                userInfo: ["teamMemberId": teamMemberId]
            )
            
        default:
            break
        }
    }

    /// Schedule an advance notice notification for a project
    func scheduleProjectAdvanceNotice(
        projectId: String,
        projectTitle: String,
        startDate: Date,
        daysInAdvance: Int
    ) -> String {
        // Calculate the notification date based on days in advance
        guard let notificationDate = Calendar.current.date(byAdding: .day, value: -daysInAdvance, to: startDate) else {
            return ""
        }
        
        // Only schedule if the notification date is in the future
        guard notificationDate > Date() else {
            return ""
        }
        
        // Create content
        let content = UNMutableNotificationContent()
        content.title = "Upcoming Project Reminder"
        content.body = "\(projectTitle) starts in \(daysInAdvance) day\(daysInAdvance > 1 ? "s" : "")"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.projectAdvance.rawValue
        
        // Include project ID and days in advance in the user info
        content.userInfo = [
            "projectId": projectId,
            "daysInAdvance": daysInAdvance
        ]
        
        // Get user's preferred notification time
        let hour = UserDefaults.standard.integer(forKey: "advanceNoticeHour")
        let minute = UserDefaults.standard.integer(forKey: "advanceNoticeMinute")
        
        // Use user preference or default to 8:00 AM
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: notificationDate)
        dateComponents.hour = hour > 0 ? hour : 8
        dateComponents.minute = minute
        
        // Create trigger
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        // Create identifier
        let identifier = "project-advance-\(projectId)-\(daysInAdvance)"
        
        // Create request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // Add request to notification center
        notificationCenter.add(request) { error in
            if let error = error {
            } else {
            }
        }
        
        return identifier
    }
    
    /// Schedule a project assignment notification
    func scheduleProjectAssignmentNotification(
        projectId: String,
        projectTitle: String,
        assignedBy: String? = nil
    ) -> String {
        // Create content
        let content = UNMutableNotificationContent()
        content.title = "New Project Assignment"
        
        if let assigner = assignedBy {
            content.body = "You've been assigned to \(projectTitle) by \(assigner)"
        } else {
            content.body = "You've been assigned to \(projectTitle)"
        }
        
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.projectAssignment.rawValue
        
        // Include project ID in the user info
        content.userInfo = ["projectId": projectId]
        
        // Create trigger for immediate notification
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        // Create identifier
        let identifier = "project-assignment-\(projectId)"
        
        // Create request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // Add request to notification center
        notificationCenter.add(request) { error in
            if let error = error {
            } else {
            }
        }
        
        return identifier
    }
    
    /// Schedule a project schedule change notification
    func scheduleProjectUpdateNotification(
        projectId: String,
        projectTitle: String,
        updateType: String,
        previousDate: Date? = nil,
        newDate: Date? = nil
    ) -> String {
        // Create content
        let content = UNMutableNotificationContent()
        content.title = "Project Update"
        
        if updateType == "schedule" && previousDate != nil && newDate != nil {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let oldDateString = dateFormatter.string(from: previousDate!)
            let newDateString = dateFormatter.string(from: newDate!)
            
            content.body = "\(projectTitle) has been rescheduled from \(oldDateString) to \(newDateString)"
        } else {
            content.body = "\(projectTitle) has been updated"
        }
        
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.projectUpdate.rawValue
        
        // Include project ID and update type in the user info
        content.userInfo = [
            "projectId": projectId,
            "updateType": updateType
        ]
        
        // Create trigger for immediate notification
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        // Create identifier
        let identifier = "project-update-\(projectId)-\(UUID().uuidString)"
        
        // Create request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // Add request to notification center
        notificationCenter.add(request) { error in
            if let error = error {
            } else {
            }
        }
        
        return identifier
    }
    
    /// Schedule a project completion notification
    func scheduleProjectCompletionNotification(
        projectId: String,
        projectTitle: String
    ) -> String {
        // Create content
        let content = UNMutableNotificationContent()
        content.title = "Project Completed"
        content.body = "\(projectTitle) has been marked as complete"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.projectCompletion.rawValue
        
        // Include project ID in the user info
        content.userInfo = ["projectId": projectId]
        
        // Create trigger for immediate notification
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        // Create identifier
        let identifier = "project-completion-\(projectId)"
        
        // Create request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // Add request to notification center
        notificationCenter.add(request) { error in
            if let error = error {
            } else {
            }
        }
        
        return identifier
    }
}

// MARK: - Location-based notifications
extension NotificationManager {
    /// Schedule a notification when a user is near a project location
    func scheduleLocationBasedNotification(
        projectId: String,
        projectTitle: String,
        projectLocation: CLLocationCoordinate2D,
        radius: Double = 500 // meters
    ) -> String {
        // Create content
        let content = UNMutableNotificationContent()
        content.title = "Nearby Project"
        content.body = "You're near \(projectTitle)"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.project.rawValue
        
        // Include project ID in the user info
        content.userInfo = ["projectId": projectId]
        
        // Create identifier
        let identifier = "location-project-\(projectId)"
        
        // Create request with a time interval trigger (will be triggered by significant location change)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        // Add request to notification center
        notificationCenter.add(request) { error in
            if let error = error {
            } else {
            }
        }
        
        return identifier
    }
    
    /// Handle significant location changes by checking for nearby projects
    func handleSignificantLocationChange(_ notification: Notification) {
        guard let location = notification.userInfo?["location"] as? CLLocation else {
            return
        }
        
        
        // Here you would:
        // 1. Check if there are any projects near this location
        // 2. If yes, trigger a notification for those projects
        
        // Example implementation (requires a ProjectsViewModel or similar to be implemented)
        // ProjectsViewModel.shared.getNearbyProjects(location: location.coordinate, maxDistance: 500) { projects in
        //     for project in projects {
        //         self.scheduleLocationBasedNotification(
        //             projectId: project.id,
        //             projectTitle: project.title,
        //             projectLocation: project.location
        //         )
        //     }
        // }
    }
}

// MARK: - Bulk Operations for Project Notifications
extension NotificationManager {
    
    /// Schedule notifications for all future projects based on user preferences
    func scheduleNotificationsForAllProjects(using modelContext: ModelContext) async {
        // First, clear all existing project notifications
        await cancelAllProjectNotifications()
        
        // Check if user wants advance notifications
        guard UserDefaults.standard.bool(forKey: "notifyProjectAdvance") else {
            return
        }
        
        do {
            // Fetch all projects and filter for future start dates
            let now = Date()
            let descriptor = FetchDescriptor<Project>(
                sortBy: [SortDescriptor(\.startDate)]
            )
            
            let allProjects = try modelContext.fetch(descriptor)
            
            // Filter for projects with future start dates
            let futureProjects = allProjects.filter { project in
                guard let startDate = project.startDate else { return false }
                return startDate > now
            }
            
            
            // Get user's advance notice preferences
            let advanceDays = getAdvanceNoticeDays()
            
            // Schedule notifications for each project
            for project in futureProjects {
                for daysBefore in advanceDays {
                    scheduleProjectAdvanceNotice(
                        project: project,
                        daysBefore: daysBefore
                    )
                }
            }
            
            
        } catch {
        }
    }
    
    /// Get the user's configured advance notice days
    private func getAdvanceNoticeDays() -> [Int] {
        return [
            UserDefaults.standard.integer(forKey: "advanceNoticeDays1"),
            UserDefaults.standard.integer(forKey: "advanceNoticeDays2"),
            UserDefaults.standard.integer(forKey: "advanceNoticeDays3")
        ].filter { $0 > 0 }
    }
    
    /// Cancel all project-related notifications
    func cancelAllProjectNotifications() async {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        
        // Find all project notification IDs
        let projectNotificationIds = requests.filter { request in
            // Check if it's a project notification by category or user info
            request.content.categoryIdentifier == "PROJECT" ||
            request.content.categoryIdentifier == "PROJECT_ADVANCE_NOTIFICATION" ||
            request.content.userInfo["projectId"] != nil
        }.map { $0.identifier }
        
        if !projectNotificationIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: projectNotificationIds)
        }
    }
    
    /// Cancel notifications for a specific project
    func cancelProjectNotifications(projectId: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let idsToRemove = requests
                .filter { $0.content.userInfo["projectId"] as? String == projectId }
                .map { $0.identifier }
            
            if !idsToRemove.isEmpty {
                UNUserNotificationCenter.current()
                    .removePendingNotificationRequests(withIdentifiers: idsToRemove)
            }
        }
    }
    
    /// Convenience method to schedule advance notice for a project
    func scheduleProjectAdvanceNotice(project: Project, daysBefore: Int) {
        guard let startDate = project.startDate else { return }

        _ = scheduleProjectAdvanceNotice(
            projectId: project.id,
            projectTitle: project.title,
            startDate: startDate,
            daysInAdvance: daysBefore
        )
    }
}

// MARK: - Task-Based Local Notifications
extension NotificationManager {

    /// Schedule advance notice for a task
    /// - Parameters:
    ///   - task: The task to schedule notification for
    ///   - projectName: Name of the project (for notification body)
    ///   - daysBefore: Days before task start to notify
    func scheduleTaskAdvanceNotice(task: ProjectTask, projectName: String, daysBefore: Int) {
        // Get task start date from calendar event
        guard let taskStartDate = task.scheduledDate else {
            print("[NOTIFICATIONS] Task \(task.id) has no start date - skipping advance notice")
            return
        }

        // Check user preferences
        guard UserDefaults.standard.bool(forKey: "notifyAdvanceNotice") else {
            print("[NOTIFICATIONS] Advance notice disabled by user")
            return
        }

        // Get user's preferred notification time
        let noticeHour = UserDefaults.standard.integer(forKey: "advanceNoticeHour")
        let noticeMinute = UserDefaults.standard.integer(forKey: "advanceNoticeMinute")

        // Calculate notification date
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

        let taskName = task.displayTitle
        if daysBefore == 1 {
            content.body = "\(taskName) on \(projectName) starts tomorrow"
        } else {
            content.body = "\(taskName) on \(projectName) starts in \(daysBefore) days"
        }

        content.sound = .default
        content.categoryIdentifier = NotificationCategory.projectAdvance.rawValue
        content.userInfo = [
            "taskId": task.id,
            "projectId": task.project?.id ?? task.projectId,
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

        // Check if advance notices are enabled
        guard UserDefaults.standard.bool(forKey: "notifyAdvanceNotice") else {
            print("[NOTIFICATIONS] Advance notices disabled")
            return
        }

        // Filter to only tasks user is assigned to (check teamMemberIdsString)
        let assignedTasks = tasks.filter { task in
            task.getTeamMemberIds().contains(currentUserId)
        }

        print("[NOTIFICATIONS] Scheduling advance notices for \(assignedTasks.count) assigned tasks with lead times: \(leadTimes)")

        for task in assignedTasks {
            let projectName = task.project?.title ?? "Project"

            for days in leadTimes {
                scheduleTaskAdvanceNotice(task: task, projectName: projectName, daysBefore: days)
            }
        }
    }

    /// Remove all advance notices for a specific task
    func removeAdvanceNoticesForTask(taskId: String) {
        // Remove all possible advance notice identifiers for this task
        let possibleDays = [1, 2, 3, 4, 5, 6, 7, 14, 30]  // Cover all reasonable lead times
        let identifiers = possibleDays.map { "advance-\(taskId)-\($0)d" }

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        print("[NOTIFICATIONS] Removed advance notices for task \(taskId)")
    }

    /// Remove all advance notices (e.g., when rescheduling all)
    func removeAllAdvanceNotices() async {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()

        let advanceIds = requests
            .filter { $0.identifier.hasPrefix("advance-") }
            .map { $0.identifier }

        if !advanceIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: advanceIds)
            print("[NOTIFICATIONS] Removed \(advanceIds.count) advance notices")
        }
    }

    /// Schedule advance notices for all tasks using ModelContext
    /// Call this after sync or when preferences change
    func scheduleAdvanceNoticesForAllTasks(using modelContext: ModelContext) async {
        // First, clear all existing advance notices
        await removeAllAdvanceNotices()

        // Check if user wants advance notifications
        guard UserDefaults.standard.bool(forKey: "notifyAdvanceNotice") else {
            print("[NOTIFICATIONS] Advance notices disabled by user")
            return
        }

        guard let currentUserId = UserDefaults.standard.string(forKey: "currentUserId") else {
            print("[NOTIFICATIONS] No current user ID found")
            return
        }

        do {
            // Fetch all tasks
            let descriptor = FetchDescriptor<ProjectTask>()
            let allTasks = try modelContext.fetch(descriptor)

            // Filter for non-deleted tasks with future start dates
            let now = Date()
            let futureTasks = allTasks.filter { task in
                guard task.deletedAt == nil,
                      let startDate = task.scheduledDate else { return false }
                return startDate > now
            }

            print("[NOTIFICATIONS] Found \(futureTasks.count) future tasks")

            // Schedule notifications for assigned tasks
            scheduleAdvanceNoticesForUserTasks(tasks: futureTasks, currentUserId: currentUserId)

        } catch {
            print("[NOTIFICATIONS] Failed to fetch tasks: \(error)")
        }
    }
}

// MARK: - Notification.Name Extensions
extension Notification.Name {
    static let openProjectDetails = Notification.Name("OpenProjectDetails")
    static let openSchedule = Notification.Name("OpenSchedule")
    static let openTeamMemberDetails = Notification.Name("OpenTeamMemberDetails")
    static let scheduleAccepted = Notification.Name("ScheduleAccepted")
    static let scheduleDeclined = Notification.Name("ScheduleDeclined")
}
