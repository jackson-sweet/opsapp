//
//  AnalyticsManager.swift
//  OPS
//
//  Created for Google Ads conversion tracking via Firebase Analytics
//

import Foundation
import FirebaseAnalytics

/// Centralized analytics manager for tracking conversion events
/// Events flow to Google Ads via Firebase Analytics integration
final class AnalyticsManager {

    static let shared = AnalyticsManager()

    private init() {}

    // MARK: - Conversion Events

    /// Track when a new user completes sign-up
    /// - Parameters:
    ///   - userType: The type of user (employee or company/business owner)
    ///   - method: The sign-up method used (email, apple, google)
    func trackSignUp(userType: UserType?, method: SignUpMethod) {
        var parameters: [String: Any] = [
            AnalyticsParameterMethod: method.rawValue
        ]

        if let userType = userType {
            parameters["user_type"] = userType.rawValue
        }

        Analytics.logEvent(AnalyticsEventSignUp, parameters: parameters)

        print("[ANALYTICS] 📊 Tracked sign_up - method: \(method.rawValue), user_type: \(userType?.rawValue ?? "unknown")")
    }

    /// Track when a user logs in
    /// - Parameters:
    ///   - userType: The type of user (employee or company/business owner)
    ///   - method: The login method used (email, apple, google)
    func trackLogin(userType: UserType?, method: SignUpMethod) {
        var parameters: [String: Any] = [
            AnalyticsParameterMethod: method.rawValue
        ]

        if let userType = userType {
            parameters["user_type"] = userType.rawValue
        }

        Analytics.logEvent(AnalyticsEventLogin, parameters: parameters)

        print("[ANALYTICS] 📊 Tracked login - method: \(method.rawValue), user_type: \(userType?.rawValue ?? "unknown")")
    }

    /// Track app install / first open (automatic via Firebase, but can be called manually if needed)
    func trackFirstOpen() {
        // Firebase tracks first_open automatically
        // This method exists for explicit tracking if needed
        Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)

        print("[ANALYTICS] 📊 Tracked app_open")
    }

    // MARK: - Trial & Subscription Events

    /// Track when a user starts their free trial
    /// - Parameters:
    ///   - userType: The type of user
    ///   - trialDays: Number of days in the trial (default 30)
    func trackBeginTrial(userType: UserType?, trialDays: Int = 30) {
        var parameters: [String: Any] = [
            "trial_days": trialDays
        ]

        if let userType = userType {
            parameters["user_type"] = userType.rawValue
        }

        Analytics.logEvent("begin_trial", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked begin_trial - user_type: \(userType?.rawValue ?? "unknown"), trial_days: \(trialDays)")
    }

    /// Track when a user subscribes (converts to paid)
    /// - Parameters:
    ///   - planName: Name of the subscription plan
    ///   - price: Price of the subscription
    ///   - currency: Currency code (default USD)
    ///   - userType: The type of user
    func trackSubscribe(planName: String, price: Double, currency: String = "USD", userType: UserType?) {
        var parameters: [String: Any] = [
            AnalyticsParameterItemName: planName,
            AnalyticsParameterPrice: price,
            AnalyticsParameterCurrency: currency
        ]

        if let userType = userType {
            parameters["user_type"] = userType.rawValue
        }

        // Use Firebase's standard purchase event for better Google Ads integration
        Analytics.logEvent(AnalyticsEventPurchase, parameters: parameters)

        // Also log custom subscribe event for flexibility
        Analytics.logEvent("subscribe", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked subscribe - plan: \(planName), price: \(price) \(currency), user_type: \(userType?.rawValue ?? "unknown")")
    }

    // MARK: - Onboarding & Engagement Events

    /// Track when a user completes onboarding
    /// - Parameters:
    ///   - userType: The type of user
    ///   - hasCompany: Whether the user has/created a company
    func trackCompleteOnboarding(userType: UserType?, hasCompany: Bool) {
        var parameters: [String: Any] = [
            "has_company": hasCompany
        ]

        if let userType = userType {
            parameters["user_type"] = userType.rawValue
        }

        Analytics.logEvent("complete_onboarding", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked complete_onboarding - user_type: \(userType?.rawValue ?? "unknown"), has_company: \(hasCompany)")
    }

    /// Track when a user creates their first project (high-intent signal)
    /// - Parameter userType: The type of user
    func trackCreateFirstProject(userType: UserType?) {
        var parameters: [String: Any] = [:]

        if let userType = userType {
            parameters["user_type"] = userType.rawValue
        }

        Analytics.logEvent("create_first_project", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked create_first_project - user_type: \(userType?.rawValue ?? "unknown")")
    }

    /// Track when a user creates a project (general tracking)
    /// - Parameters:
    ///   - projectCount: Total number of projects the user now has
    ///   - userType: The type of user
    func trackCreateProject(projectCount: Int, userType: UserType?) {
        var parameters: [String: Any] = [
            "project_count": projectCount
        ]

        if let userType = userType {
            parameters["user_type"] = userType.rawValue
        }

        Analytics.logEvent("create_project", parameters: parameters)

        // Track first project separately for conversion optimization
        if projectCount == 1 {
            trackCreateFirstProject(userType: userType)
        }

        print("[ANALYTICS] 📊 Tracked create_project - count: \(projectCount), user_type: \(userType?.rawValue ?? "unknown")")
    }

    // MARK: - User Properties

    /// Set the user type as a user property for segmentation
    /// - Parameter userType: The type of user
    func setUserType(_ userType: UserType?) {
        if let userType = userType {
            Analytics.setUserProperty(userType.rawValue, forName: "user_type")
            print("[ANALYTICS] 📊 Set user property user_type: \(userType.rawValue)")
        }
    }

    /// Set the user ID for analytics
    /// - Parameter userId: The user's unique ID
    func setUserId(_ userId: String?) {
        Analytics.setUserID(userId)
        if let userId = userId {
            print("[ANALYTICS] 📊 Set user ID: \(userId)")
        }
    }

    /// Set subscription status as a user property
    /// - Parameter isSubscribed: Whether user has active subscription
    func setSubscriptionStatus(_ isSubscribed: Bool) {
        Analytics.setUserProperty(isSubscribed ? "subscribed" : "free", forName: "subscription_status")
        print("[ANALYTICS] 📊 Set user property subscription_status: \(isSubscribed ? "subscribed" : "free")")
    }

    // MARK: - Screen View Tracking

    /// Track when a screen is viewed
    /// - Parameters:
    ///   - screenName: The name of the screen being viewed
    ///   - screenClass: The class name of the screen (optional)
    func trackScreenView(screenName: ScreenName, screenClass: String? = nil) {
        var parameters: [String: Any] = [
            AnalyticsParameterScreenName: screenName.rawValue
        ]

        if let screenClass = screenClass {
            parameters[AnalyticsParameterScreenClass] = screenClass
        }

        Analytics.logEvent(AnalyticsEventScreenView, parameters: parameters)

        print("[ANALYTICS] 📊 Tracked screen_view - screen: \(screenName.rawValue)")
    }

    /// Track tab selection in main navigation
    /// - Parameter tabName: The name of the selected tab
    func trackTabSelected(tabName: TabName) {
        let parameters: [String: Any] = [
            "tab_name": tabName.rawValue,
            "tab_index": tabName.index
        ]

        Analytics.logEvent("tab_selected", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked tab_selected - tab: \(tabName.rawValue)")
    }

    // MARK: - Task CRUD Events

    /// Track when a task is created
    /// - Parameters:
    ///   - taskType: The type of task created
    ///   - hasSchedule: Whether the task has scheduled dates
    ///   - teamSize: Number of team members assigned
    func trackTaskCreated(taskType: String?, hasSchedule: Bool, teamSize: Int) {
        var parameters: [String: Any] = [
            "has_schedule": hasSchedule,
            "team_size": teamSize
        ]

        if let taskType = taskType {
            parameters["task_type"] = taskType
        }

        Analytics.logEvent("task_created", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked task_created - type: \(taskType ?? "unknown"), hasSchedule: \(hasSchedule), teamSize: \(teamSize)")
    }

    /// Track when a task is edited
    /// - Parameter taskId: The ID of the edited task
    func trackTaskEdited(taskId: String) {
        let parameters: [String: Any] = [
            "task_id": taskId
        ]

        Analytics.logEvent("task_edited", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked task_edited - taskId: \(taskId)")
    }

    /// Track when a task is deleted
    func trackTaskDeleted() {
        Analytics.logEvent("task_deleted", parameters: nil)

        print("[ANALYTICS] 📊 Tracked task_deleted")
    }

    /// Track when a task status changes
    /// - Parameters:
    ///   - oldStatus: The previous status
    ///   - newStatus: The new status
    func trackTaskStatusChanged(oldStatus: String, newStatus: String) {
        let parameters: [String: Any] = [
            "old_status": oldStatus,
            "new_status": newStatus
        ]

        Analytics.logEvent("task_status_changed", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked task_status_changed - from: \(oldStatus) to: \(newStatus)")
    }

    /// Track when a task is completed (high-value event)
    /// - Parameter taskType: The type of task completed
    func trackTaskCompleted(taskType: String?) {
        var parameters: [String: Any] = [:]

        if let taskType = taskType {
            parameters["task_type"] = taskType
        }

        Analytics.logEvent("task_completed", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked task_completed - type: \(taskType ?? "unknown")")
    }

    // MARK: - Client CRUD Events

    /// Track when a client is created
    /// - Parameters:
    ///   - hasEmail: Whether client has email
    ///   - hasPhone: Whether client has phone
    ///   - hasAddress: Whether client has address
    ///   - importMethod: How the client was added (manual or contact_import)
    func trackClientCreated(hasEmail: Bool, hasPhone: Bool, hasAddress: Bool, importMethod: ClientImportMethod = .manual) {
        let parameters: [String: Any] = [
            "has_email": hasEmail,
            "has_phone": hasPhone,
            "has_address": hasAddress,
            "import_method": importMethod.rawValue
        ]

        Analytics.logEvent("client_created", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked client_created - email: \(hasEmail), phone: \(hasPhone), address: \(hasAddress), method: \(importMethod.rawValue)")
    }

    /// Track when a client is edited
    /// - Parameter clientId: The ID of the edited client
    func trackClientEdited(clientId: String) {
        let parameters: [String: Any] = [
            "client_id": clientId
        ]

        Analytics.logEvent("client_edited", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked client_edited - clientId: \(clientId)")
    }

    /// Track when a client is deleted
    func trackClientDeleted() {
        Analytics.logEvent("client_deleted", parameters: nil)

        print("[ANALYTICS] 📊 Tracked client_deleted")
    }

    // MARK: - Project Status Events

    /// Track when a project status changes
    /// - Parameters:
    ///   - oldStatus: The previous status
    ///   - newStatus: The new status
    func trackProjectStatusChanged(oldStatus: String, newStatus: String) {
        let parameters: [String: Any] = [
            "old_status": oldStatus,
            "new_status": newStatus
        ]

        Analytics.logEvent("project_status_changed", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked project_status_changed - from: \(oldStatus) to: \(newStatus)")
    }

    /// Track when a project is edited
    /// - Parameter projectId: The ID of the edited project
    func trackProjectEdited(projectId: String) {
        let parameters: [String: Any] = [
            "project_id": projectId
        ]

        Analytics.logEvent("project_edited", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked project_edited - projectId: \(projectId)")
    }

    /// Track when a project is deleted
    func trackProjectDeleted() {
        Analytics.logEvent("project_deleted", parameters: nil)

        print("[ANALYTICS] 📊 Tracked project_deleted")
    }

    // MARK: - Team Member Events

    /// Track when a team member is invited
    /// - Parameters:
    ///   - role: The role assigned to the team member
    ///   - teamSize: Current team size after invitation
    func trackTeamMemberInvited(role: String, teamSize: Int) {
        let parameters: [String: Any] = [
            "role": role,
            "team_size": teamSize
        ]

        Analytics.logEvent("team_member_invited", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked team_member_invited - role: \(role), teamSize: \(teamSize)")
    }

    /// Track when a team member is removed
    func trackTeamMemberRemoved() {
        Analytics.logEvent("team_member_removed", parameters: nil)

        print("[ANALYTICS] 📊 Tracked team_member_removed")
    }

    /// Track when a team member role is changed
    /// - Parameters:
    ///   - oldRole: The previous role
    ///   - newRole: The new role
    func trackTeamMemberRoleChanged(oldRole: String, newRole: String) {
        let parameters: [String: Any] = [
            "old_role": oldRole,
            "new_role": newRole
        ]

        Analytics.logEvent("team_member_role_changed", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked team_member_role_changed - from: \(oldRole) to: \(newRole)")
    }

    // MARK: - Navigation & Engagement Events

    /// Track when navigation to a project is started
    /// - Parameter projectId: The ID of the project being navigated to
    func trackNavigationStarted(projectId: String) {
        let parameters: [String: Any] = [
            "project_id": projectId
        ]

        Analytics.logEvent("navigation_started", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked navigation_started - projectId: \(projectId)")
    }

    /// Track when a search is performed
    /// - Parameters:
    ///   - section: Where the search was performed (projects, tasks, clients, etc.)
    ///   - resultsCount: Number of results returned
    func trackSearchPerformed(section: SearchSection, resultsCount: Int) {
        let parameters: [String: Any] = [
            "section": section.rawValue,
            "results_count": resultsCount
        ]

        Analytics.logEvent("search_performed", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked search_performed - section: \(section.rawValue), results: \(resultsCount)")
    }

    /// Track when a filter is applied
    /// - Parameters:
    ///   - section: Where the filter was applied
    ///   - filterType: The type of filter applied
    func trackFilterApplied(section: SearchSection, filterType: String) {
        let parameters: [String: Any] = [
            "section": section.rawValue,
            "filter_type": filterType
        ]

        Analytics.logEvent("filter_applied", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked filter_applied - section: \(section.rawValue), filter: \(filterType)")
    }

    /// Track when an image is uploaded
    /// - Parameters:
    ///   - count: Number of images uploaded
    ///   - context: Where the image was uploaded (project, client, etc.)
    func trackImageUploaded(count: Int, context: String) {
        let parameters: [String: Any] = [
            "image_count": count,
            "context": context
        ]

        Analytics.logEvent("image_uploaded", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked image_uploaded - count: \(count), context: \(context)")
    }

    /// Track when a form is abandoned without saving
    /// - Parameters:
    ///   - formType: The type of form (project, task, client)
    ///   - fieldsFilled: Number of fields that had data
    func trackFormAbandoned(formType: FormType, fieldsFilled: Int) {
        let parameters: [String: Any] = [
            "form_type": formType.rawValue,
            "fields_filled": fieldsFilled
        ]

        Analytics.logEvent("form_abandoned", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked form_abandoned - type: \(formType.rawValue), fieldsFilled: \(fieldsFilled)")
    }

    // MARK: - Calendar Events

    /// Track calendar view mode changes
    /// - Parameter viewMode: The new view mode (month or week)
    func trackCalendarViewModeChanged(viewMode: String) {
        let parameters: [String: Any] = [
            "view_mode": viewMode
        ]

        Analytics.logEvent("calendar_view_mode_changed", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked calendar_view_mode_changed - mode: \(viewMode)")
    }

    /// Track when a calendar day is selected
    /// - Parameter eventsCount: Number of events on the selected day
    func trackCalendarDaySelected(eventsCount: Int) {
        let parameters: [String: Any] = [
            "events_count": eventsCount
        ]

        Analytics.logEvent("calendar_day_selected", parameters: parameters)

        print("[ANALYTICS] 📊 Tracked calendar_day_selected - events: \(eventsCount)")
    }
}

// MARK: - Supporting Types

enum SignUpMethod: String {
    case email = "email"
    case apple = "apple"
    case google = "google"
}

/// Screen names for analytics tracking
enum ScreenName: String {
    // Main tabs
    case home = "home"
    case jobBoard = "job_board"
    case schedule = "schedule"
    case settings = "settings"

    // Job Board sections
    case jobBoardDashboard = "job_board_dashboard"
    case jobBoardProjects = "job_board_projects"
    case jobBoardTasks = "job_board_tasks"
    case jobBoardClients = "job_board_clients"

    // Detail views
    case projectDetails = "project_details"
    case taskDetails = "task_details"
    case clientDetails = "client_details"

    // Forms
    case projectForm = "project_form"
    case taskForm = "task_form"
    case clientForm = "client_form"

    // Settings sections
    case profileSettings = "profile_settings"
    case organizationSettings = "organization_settings"
    case notificationSettings = "notification_settings"
    case appSettings = "app_settings"
    case manageTeam = "manage_team"
    case manageSubscription = "manage_subscription"

    // Subscription
    case planSelection = "plan_selection"
    case subscriptionLockout = "subscription_lockout"

    // Auth
    case login = "login"
    case forgotPassword = "forgot_password"
}

/// Tab names for analytics tracking
enum TabName: String {
    case home = "home"
    case pipeline = "pipeline"
    case jobBoard = "job_board"
    case schedule = "schedule"
    case settings = "settings"

    var index: Int {
        switch self {
        case .home: return 0
        case .pipeline: return 1
        case .jobBoard: return 2
        case .schedule: return 3
        case .settings: return 4
        }
    }
}

/// Client import method for analytics
enum ClientImportMethod: String {
    case manual = "manual"
    case contactImport = "contact_import"
}

/// Search section for analytics
enum SearchSection: String {
    case projects = "projects"
    case tasks = "tasks"
    case clients = "clients"
    case calendar = "calendar"
    case settings = "settings"
}

/// Form type for analytics
enum FormType: String {
    case project = "project"
    case task = "task"
    case client = "client"
}
