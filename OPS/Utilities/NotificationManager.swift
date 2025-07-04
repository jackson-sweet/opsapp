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
                    print("NotificationManager: Error requesting permission: \(error.localizedDescription)")
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
                print("NotificationManager: Error scheduling notification: \(error.localizedDescription)")
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
                print("NotificationManager: Error scheduling team notification: \(error.localizedDescription)")
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
                print("NotificationManager: Error scheduling reminder: \(error.localizedDescription)")
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
            
        case NotificationCategory.projectAssignment.rawValue,
             NotificationCategory.projectUpdate.rawValue,
             NotificationCategory.projectCompletion.rawValue,
             NotificationCategory.projectAdvance.rawValue:
            // All these notification types open the project details page
            handleProjectNotificationResponse(userInfo: userInfo, actionIdentifier: actionIdentifier)
            
        default:
            break
        }
        
        completionHandler()
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
            print("NotificationManager: Error calculating advance notice date")
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
                print("NotificationManager: Error scheduling advance notice: \(error.localizedDescription)")
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
                print("NotificationManager: Error scheduling assignment notification: \(error.localizedDescription)")
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
                print("NotificationManager: Error scheduling update notification: \(error.localizedDescription)")
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
                print("NotificationManager: Error scheduling completion notification: \(error.localizedDescription)")
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
                print("NotificationManager: Error scheduling location-based notification: \(error.localizedDescription)")
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
            print("📵 Project advance notifications are disabled")
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
            
            print("📅 Found \(futureProjects.count) future projects to schedule notifications for")
            
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
            
            print("✅ Scheduled \(futureProjects.count * advanceDays.count) notifications")
            
        } catch {
            print("❌ Failed to schedule project notifications: \(error)")
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
            print("🗑️ Cancelled \(projectNotificationIds.count) project notifications")
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
                print("🗑️ Cancelled \(idsToRemove.count) notifications for project \(projectId)")
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

// MARK: - Notification.Name Extensions
extension Notification.Name {
    static let openProjectDetails = Notification.Name("OpenProjectDetails")
    static let openSchedule = Notification.Name("OpenSchedule")
    static let openTeamMemberDetails = Notification.Name("OpenTeamMemberDetails")
    static let scheduleAccepted = Notification.Name("ScheduleAccepted")
    static let scheduleDeclined = Notification.Name("ScheduleDeclined")
}
