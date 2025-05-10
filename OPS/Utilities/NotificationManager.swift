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

/// Notification categories for different types of notifications
enum NotificationCategory: String {
    case project = "PROJECT_NOTIFICATION"
    case schedule = "SCHEDULE_NOTIFICATION"
    case team = "TEAM_NOTIFICATION"
    case general = "GENERAL_NOTIFICATION"
}

/// Notification actions that can be taken on notifications
enum NotificationAction: String {
    case view = "VIEW_ACTION"
    case accept = "ACCEPT_ACTION"
    case decline = "DECLINE_ACTION"
    case dismiss = "DISMISS_ACTION"
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
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    override init() {
        super.init()
        
        // Set delegate to handle notification responses
        notificationCenter.delegate = self
        
        // Setup notification categories and actions
        setupNotificationCategories()
        
        // Check initial authorization status
        getAuthorizationStatus()
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
        
        // Register all categories
        notificationCenter.setNotificationCategories([
            projectCategory,
            scheduleCategory,
            teamCategory,
            generalCategory
        ])
    }
    
    /// Get the current notification authorization status
    func getAuthorizationStatus() {
        notificationCenter.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
                self.isNotificationsEnabled = settings.authorizationStatus == .authorized
                print("NotificationManager: Authorization status: \(settings.authorizationStatus.rawValue)")
            }
        }
    }
    
    /// Request permission to send notifications if not already determined
    func requestPermission(completion: @escaping (Bool) -> Void = { _ in }) {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("NotificationManager: Error requesting permission: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                // Update our stored status
                self.isNotificationsEnabled = granted
                
                if granted {
                    print("NotificationManager: Permission granted")
                    // Register for remote notifications if permission is granted
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                } else {
                    print("NotificationManager: Permission denied")
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
                print("NotificationManager: Registered for remote notifications")
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
                print("NotificationManager: Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("NotificationManager: Successfully scheduled notification with ID: \(identifier)")
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
                print("NotificationManager: Error scheduling team notification: \(error.localizedDescription)")
            } else {
                print("NotificationManager: Successfully scheduled team notification with ID: \(identifier)")
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
                print("NotificationManager: Error scheduling reminder: \(error.localizedDescription)")
            } else {
                print("NotificationManager: Successfully scheduled reminder for \(dateString)")
            }
        }
        
        return identifier
    }
    
    /// Remove a specific notification by ID
    func removeNotification(identifier: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        print("NotificationManager: Removed notification with ID: \(identifier)")
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
                print("NotificationManager: Removed \(projectNotificationIds.count) notifications for project: \(projectId)")
            }
        }
    }
    
    /// Remove all pending notifications
    func removeAllPendingNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        print("NotificationManager: Removed all pending notifications")
    }
    
    /// Get all pending notifications
    func getAllPendingNotifications() {
        notificationCenter.getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                self.pendingNotifications = requests
                print("NotificationManager: Found \(requests.count) pending notifications")
            }
        }
    }
    
    /// Handle device token registration for remote notifications
    func handleDeviceTokenRegistration(deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("NotificationManager: Device token: \(token)")
        
        // Store device token in UserDefaults for later use
        UserDefaults.standard.set(token, forKey: "apns_device_token")
    }
    
    /// Open app settings for notification permissions
    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
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
        // Forward the notification to our publisher
        notificationSubject.send(notification)
        
        // Show the notification alert, play sound, and update badge
        completionHandler([.banner, .sound, .badge])
    }
    
    /// Called when a user interacts with a notification
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
        
        // Handle based on notification category
        switch notification.request.content.categoryIdentifier {
        case NotificationCategory.project.rawValue:
            handleProjectNotificationResponse(userInfo: userInfo, actionIdentifier: actionIdentifier)
            
        case NotificationCategory.schedule.rawValue:
            handleScheduleNotificationResponse(userInfo: userInfo, actionIdentifier: actionIdentifier)
            
        case NotificationCategory.team.rawValue:
            handleTeamNotificationResponse(userInfo: userInfo, actionIdentifier: actionIdentifier)
            
        default:
            print("NotificationManager: Received notification with unknown category: \(notification.request.content.categoryIdentifier)")
        }
        
        completionHandler()
    }
    
    // MARK: - Notification Response Handlers
    
    private func handleProjectNotificationResponse(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        guard let projectId = userInfo["projectId"] as? String else {
            print("NotificationManager: Project notification missing projectId in userInfo")
            return
        }
        
        print("NotificationManager: Handling project notification for project ID: \(projectId)")
        
        switch actionIdentifier {
        case NotificationAction.view.rawValue:
            print("NotificationManager: User tapped VIEW action for project \(projectId)")
            // Post notification to open project details
            NotificationCenter.default.post(
                name: Notification.Name("OpenProjectDetails"),
                object: nil,
                userInfo: ["projectId": projectId]
            )
            
        case UNNotificationDefaultActionIdentifier:
            print("NotificationManager: User tapped notification for project \(projectId)")
            // Post notification to open project details
            NotificationCenter.default.post(
                name: Notification.Name("OpenProjectDetails"),
                object: nil,
                userInfo: ["projectId": projectId]
            )
            
        default:
            print("NotificationManager: Unhandled action for project notification: \(actionIdentifier)")
        }
    }
    
    private func handleScheduleNotificationResponse(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        guard let dateString = userInfo["date"] as? String else {
            print("NotificationManager: Schedule notification missing date in userInfo")
            return
        }
        
        print("NotificationManager: Handling schedule notification for date: \(dateString)")
        
        switch actionIdentifier {
        case NotificationAction.accept.rawValue:
            print("NotificationManager: User accepted schedule for \(dateString)")
            // Post notification to acknowledge schedule
            NotificationCenter.default.post(
                name: Notification.Name("ScheduleAccepted"),
                object: nil,
                userInfo: ["date": dateString]
            )
            
        case NotificationAction.decline.rawValue:
            print("NotificationManager: User declined schedule for \(dateString)")
            // Post notification to decline schedule
            NotificationCenter.default.post(
                name: Notification.Name("ScheduleDeclined"),
                object: nil,
                userInfo: ["date": dateString]
            )
            
        case UNNotificationDefaultActionIdentifier:
            print("NotificationManager: User tapped notification for schedule on \(dateString)")
            // Post notification to open schedule for the day
            NotificationCenter.default.post(
                name: Notification.Name("OpenSchedule"),
                object: nil,
                userInfo: ["date": dateString]
            )
            
        default:
            print("NotificationManager: Unhandled action for schedule notification: \(actionIdentifier)")
        }
    }
    
    private func handleTeamNotificationResponse(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        guard let teamMemberId = userInfo["teamMemberId"] as? String else {
            print("NotificationManager: Team notification missing teamMemberId in userInfo")
            return
        }
        
        print("NotificationManager: Handling team notification for team member ID: \(teamMemberId)")
        
        switch actionIdentifier {
        case NotificationAction.view.rawValue:
            print("NotificationManager: User tapped VIEW action for team member \(teamMemberId)")
            // Post notification to open team member details
            NotificationCenter.default.post(
                name: Notification.Name("OpenTeamMemberDetails"),
                object: nil,
                userInfo: ["teamMemberId": teamMemberId]
            )
            
        case UNNotificationDefaultActionIdentifier:
            print("NotificationManager: User tapped notification for team member \(teamMemberId)")
            // Post notification to open team member details
            NotificationCenter.default.post(
                name: Notification.Name("OpenTeamMemberDetails"),
                object: nil,
                userInfo: ["teamMemberId": teamMemberId]
            )
            
        default:
            print("NotificationManager: Unhandled action for team notification: \(actionIdentifier)")
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