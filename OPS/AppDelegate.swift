//
//  AppDelegate.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-09.
//

import UIKit
import UserNotifications
import GoogleSignIn
import FirebaseCore
import FirebaseAnalytics
import OneSignalFramework
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate, OSNotificationLifecycleListener, OSNotificationClickListener {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        // Register BGTaskScheduler handlers BEFORE anything else can defer them.
        // iOS asserts and terminates the app if any task is registered after
        // application(_:didFinishLaunching) returns. The singleton lets us
        // register identifiers now and have SyncEngine attach handlers later.
        BackgroundSyncScheduler.shared.registerTasks()

        // Bug 68123654 — register iPhone Calendar Mirror refresh handler. Must
        // happen here, before the app finishes launching, per BGTaskScheduler
        // contract.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: CalendarMirrorService.backgroundTaskId,
            using: nil
        ) { task in
            Task { @MainActor in
                await CalendarMirrorService.shared.reconcileAll()
                CalendarMirrorService.shared.scheduleNextRefresh()
                task.setTaskCompleted(success: true)
            }
        }

        // Configure Firebase (must be first)
        FirebaseApp.configure()

        // Configure Stripe SDK
        StripeConfiguration.shared.configure()

        // Configure OneSignal
        configureOneSignal()

        // Register for remote notifications
        // The actual permission request happens elsewhere through the NotificationManager
        registerForRemoteNotifications()

        // Check if app was launched from a push notification
        if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            print("[PUSH] App launched from notification")
            // Delay handling to allow app to fully initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.handleRemoteNotification(userInfo: remoteNotification)
            }
        }

        return true
    }

    // MARK: - OneSignal Configuration

    private func configureOneSignal() {
        // Set log level - use .LL_VERBOSE for debugging, .LL_NONE for production
        #if DEBUG
        OneSignal.Debug.setLogLevel(.LL_WARN)
        #else
        OneSignal.Debug.setLogLevel(.LL_NONE)
        #endif

        // Initialize OneSignal with your App ID
        OneSignal.initialize("0fc0a8e0-9727-49b6-9e37-5d6d919d741f", withLaunchOptions: nil)

        // Set up notification click handler
        OneSignal.Notifications.addClickListener(self)

        // Set up foreground notification handler
        OneSignal.Notifications.addForegroundLifecycleListener(self)

        print("[ONESIGNAL] Initialized successfully")
    }

    // MARK: - OSNotificationClickListener

    /// Called when a notification is tapped/clicked
    func onClick(event: OSNotificationClickEvent) {
        print("[ONESIGNAL] Notification clicked")

        // Extract custom data from the notification
        let additionalData = event.notification.additionalData
        let notificationType = additionalData?["type"] as? String
        let projectId = additionalData?["projectId"] as? String
        let taskId = additionalData?["taskId"] as? String
        let clientId = additionalData?["clientId"] as? String
        let invoiceId = additionalData?["invoiceId"] as? String
        let estimateId = additionalData?["estimateId"] as? String
        let leadId = (additionalData?["leadId"] as? String) ?? (additionalData?["opportunityId"] as? String)
        let screen = additionalData?["screen"] as? String

        print("[ONESIGNAL] Type: \(notificationType ?? "unknown")")
        print("[ONESIGNAL] Project: \(projectId ?? "none"), Task: \(taskId ?? "none")")
        print("[ONESIGNAL] Client: \(clientId ?? "none"), Invoice: \(invoiceId ?? "none"), Estimate: \(estimateId ?? "none")")
        print("[ONESIGNAL] Screen: \(screen ?? "none")")

        // Track push notification opened
        Task { @MainActor in
            AnalyticsService.shared.track(
                eventType: .featureUse,
                eventName: "push_notification_opened",
                properties: ["notification_type": notificationType ?? "unknown"]
            )
        }

        // Delay routing to allow app to fully initialize if cold-launched
        // This gives time for view observers to be set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // member_joined carries additionalData fields that aren't part of
            // routeByType's signature (memberId / wasSeated / roleAssigned),
            // so handle it at the onClick level and post directly.
            if notificationType == "member_joined",
               let memberId = additionalData?["memberId"] as? String {
                let wasSeated = (additionalData?["wasSeated"] as? Bool) ?? false
                let roleAssigned = (additionalData?["roleAssigned"] as? Bool) ?? false
                NotificationCenter.default.post(
                    name: Notification.Name("OpenMemberRoleAssignment"),
                    object: nil,
                    userInfo: [
                        "memberId": memberId,
                        "wasSeated": wasSeated,
                        "roleAssigned": roleAssigned
                    ]
                )
                return
            }

            // Check for client/invoice/estimate direct IDs — these short-circuit the rest
            if let clientId = clientId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenClientDetails"),
                    object: nil,
                    userInfo: ["clientId": clientId]
                )
                return
            }
            if let invoiceId = invoiceId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenInvoiceDetails"),
                    object: nil,
                    userInfo: ["invoiceId": invoiceId]
                )
                return
            }
            if let estimateId = estimateId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenEstimateDetails"),
                    object: nil,
                    userInfo: ["estimateId": estimateId]
                )
                return
            }
            // A lead/opportunity id short-circuits the screen/type routing —
            // MainTabView's OpenLeadDetails handler enforces pipeline.view and
            // the LEADS-tab swap.
            if let leadId = leadId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenLeadDetails"),
                    object: nil,
                    userInfo: ["leadId": leadId]
                )
                return
            }

            if let screen = screen {
                self.routeToScreen(screen, projectId: projectId, taskId: taskId, leadId: leadId)
            } else if let type = notificationType {
                self.routeByType(type, projectId: projectId, taskId: taskId, leadId: leadId)
            } else if let projectId = projectId {
                self.openProjectViaCoordinator(projectId)
            }
        }
    }

    // MARK: - OSNotificationLifecycleListener

    /// Called when a notification is received while app is in foreground
    func onWillDisplay(event: OSNotificationWillDisplayEvent) {
        print("[ONESIGNAL] Notification will display in foreground")

        // Check if we should show the notification based on user settings
        if NotificationManager.shared.shouldSendNotification() {
            // Allow the notification to display
            event.notification.display()
        } else {
            // Prevent display (user has DND or mute enabled)
            event.preventDefault()
            print("[ONESIGNAL] Notification suppressed by user settings")
        }
    }

    // Handle URL — Google Sign-In + ops:// deep links
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        // Google Sign-In gets first chance
        if GoogleSignInManager.handle(url) {
            return true
        }
        // ops:// scheme deep links
        if url.scheme == "ops" {
            return handleDeepLink(url)
        }
        return false
    }

    /// Parse an `ops://<entity>/<id>` deep link and post the matching notification
    /// that MainTabView observes. Supported entities: projects, clients, tasks, invoices, estimates,
    /// catalog (catalog/orders surface).
    @discardableResult
    private func handleDeepLink(_ url: URL) -> Bool {
        let components = url.pathComponents // "/projects/abc" → ["/", "projects", "abc"]
        // Handle "ops://projects/abc" — host is "projects", path is "/abc"
        // Also "ops:projects/abc" forms — be lenient
        let entity: String
        let id: String

        if let host = url.host, !host.isEmpty {
            entity = host
            // Strip the leading "/" from path
            let path = url.path
            id = path.hasPrefix("/") ? String(path.dropFirst()) : path
        } else if components.count >= 3 {
            entity = components[1]
            id = components[2]
        } else {
            print("[DEEP_LINK] Malformed deep link: \(url)")
            return false
        }

        // `catalog` deep links carry a sub-surface in `id` (e.g. "orders") and
        // an optional `?tab=<sub-segment>` query string. Route them directly
        // through MainTabView's notification observers — they don't need the
        // DeepLinkCoordinator's PIN-gated stash because the catalog tab is
        // always available to the signed-in user.
        if entity == "catalog" {
            let surface = id // expect "orders"
            let tabValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "tab" })?
                .value
            print("[DEEP_LINK] Catalog \(surface) tab=\(tabValue ?? "(none)")")
            switch surface {
            case "orders":
                Task { @MainActor in
                    NotificationCenter.default.post(name: Notification.Name("OpenCatalog"), object: nil)
                    let segmentRaw: String = {
                        switch tabValue?.lowercased() {
                        case "draft", "drafts": return "DRAFT"
                        case "sent": return "SENT"
                        default: return "SUGGESTED"
                        }
                    }()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        NotificationCenter.default.post(
                            name: Notification.Name("OpenCatalogOrders"),
                            object: nil,
                            userInfo: ["subSegment": segmentRaw]
                        )
                    }
                }
                return true
            case "setup":
                let missingMapping = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "missingMapping" })?
                    .value
                Task { @MainActor in
                    NotificationCenter.default.post(name: Notification.Name("OpenCatalog"), object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        var userInfo: [String: Any] = [:]
                        if let missingMapping, !missingMapping.isEmpty {
                            userInfo["missingMapping"] = missingMapping
                        }
                        NotificationCenter.default.post(
                            name: Notification.Name("OpenCatalogSetup"),
                            object: nil,
                            userInfo: userInfo
                        )
                    }
                }
                return true
            default:
                print("[DEEP_LINK] Unknown catalog surface: \(surface)")
                return false
            }
        }

        guard !id.isEmpty else {
            print("[DEEP_LINK] Missing id in deep link: \(url)")
            return false
        }

        print("[DEEP_LINK] Routing \(entity)/\(id)")

        switch entity {
        case "projects", "clients", "invoices", "estimates", "leads", "opportunities":
            // Hand to the coordinator — stash + post + analytics happen there.
            // `leads`/`opportunities` both resolve to OpenLeadDetails (leadId).
            Task { @MainActor in
                DeepLinkCoordinator.shared.receive(entity: entity, id: id, scheme: "ops")
            }
            return true
        case "event":
            // ops://event/<calendarUserEventId> — Bug 68123654. iPhone Calendar
            // Mirror writes these into EKEvent.url so tapping the event in iOS
            // Calendar returns the user to OPS. We route to the Schedule tab and
            // post a downstream notification carrying the event id.
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: Notification.Name("OpenCalendarUserEvent"),
                    object: nil,
                    userInfo: ["eventId": id]
                )
                AnalyticsService.shared.track(
                    eventType: .action,
                    eventName: "deep_link_routed",
                    properties: [
                        "entity": entity,
                        "id": id,
                        "scheme": "ops"
                    ]
                )
            }
            return true
        case "tasks":
            // Task deep-links require a projectId — caller should use "ops://projects/<projectId>/tasks/<taskId>"
            // For the simple two-segment form we cannot route — emit malformed so drops are visible.
            print("[DEEP_LINK] Task deep links require projectId context; unsupported in two-segment form")
            Task { @MainActor in
                AnalyticsService.shared.track(
                    eventType: .action,
                    eventName: "deep_link_malformed",
                    properties: [
                        "entity": entity,
                        "id": id,
                        "scheme": "ops",
                        "reason": "task_requires_project_context"
                    ]
                )
            }
            return false
        default:
            print("[DEEP_LINK] Unknown entity: \(entity)")
            Task { @MainActor in
                AnalyticsService.shared.track(
                    eventType: .action,
                    eventName: "deep_link_malformed",
                    properties: [
                        "entity": entity,
                        "id": id,
                        "scheme": "ops",
                        "reason": "unknown_entity"
                    ]
                )
            }
            return false
        }
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        
        // Pass device token to the notification manager
        NotificationManager.shared.handleDeviceTokenRegistration(deviceToken: deviceToken)
        
        // Post notification for any observers
        NotificationCenter.default.post(
            name: UIApplication.didRegisterForRemoteNotificationsWithDeviceTokenNotification,
            object: nil,
            userInfo: ["deviceToken": deviceToken]
        )
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Only log in debug builds - this is expected when push notification entitlements aren't configured
        #if DEBUG
        if (error as NSError).code != 3000 { // 3000 = no valid aps-environment entitlement
        }
        #endif
        
        // Post notification for any observers
        NotificationCenter.default.post(
            name: UIApplication.didFailToRegisterForRemoteNotificationsNotification,
            object: nil,
            userInfo: ["error": error]
        )
    }
    
    // Register for remote notifications
    private func registerForRemoteNotifications() {
        // Only register for remote notifications on real devices (not simulator)
        // This doesn't request authorization, just registers the app with APNs
        #if !targetEnvironment(simulator)
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        #else
        #endif
    }

    // MARK: - Remote Notification Handling

    /// Called when a remote notification arrives (foreground or background with content-available)
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("[PUSH] Received remote notification: \(userInfo)")

        // Parse and route the notification
        handleRemoteNotification(userInfo: userInfo)

        // Tell system we processed the notification
        completionHandler(.newData)
    }

    /// Parse and route remote notification to appropriate screen
    private func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        // Extract standard APNs fields
        let aps = userInfo["aps"] as? [String: Any]
        let alert = aps?["alert"] as? [String: Any]
        let title = alert?["title"] as? String
        let body = alert?["body"] as? String

        // Extract custom data from notification
        let notificationType = userInfo["type"] as? String
        let projectId = userInfo["projectId"] as? String
        let taskId = userInfo["taskId"] as? String
        let leadId = (userInfo["leadId"] as? String) ?? (userInfo["opportunityId"] as? String)
        let screen = userInfo["screen"] as? String

        print("[PUSH] Type: \(notificationType ?? "unknown")")
        print("[PUSH] Title: \(title ?? "none"), Body: \(body ?? "none")")
        print("[PUSH] Project: \(projectId ?? "none"), Task: \(taskId ?? "none")")
        print("[PUSH] Lead: \(leadId ?? "none")")
        print("[PUSH] Screen: \(screen ?? "none")")

        // Route based on screen or type
        if let screen = screen {
            routeToScreen(screen, projectId: projectId, taskId: taskId, leadId: leadId)
        } else if let type = notificationType {
            routeByType(type, projectId: projectId, taskId: taskId, leadId: leadId)
        } else if let leadId = leadId {
            // A bare lead/opportunity id with no screen/type still routes.
            NotificationCenter.default.post(
                name: Notification.Name("OpenLeadDetails"),
                object: nil,
                userInfo: ["leadId": leadId]
            )
        } else if let projectId = projectId {
            // Default: open project details if projectId is provided
            openProjectViaCoordinator(projectId)
        }
    }

    /// Route a project deep link through `DeepLinkCoordinator` so it survives
    /// cold launch and the PIN gate. A bare `NotificationCenter.post` is
    /// dropped when no observer is attached yet (cold start) — that is the
    /// push-tap-lands-on-home bug. The coordinator stashes the intent and
    /// re-posts on `MainTabView.onAppear` / PIN-unlock drain. Only projects
    /// route this way: `openProjectWithSync`/`denyProject` clear the stash,
    /// whereas the client/invoice/estimate/task handlers don't — routing
    /// those through the coordinator could re-fire on a later drain.
    private func openProjectViaCoordinator(_ projectId: String) {
        Task { @MainActor in
            DeepLinkCoordinator.shared.receive(entity: "projects", id: projectId, scheme: "push")
        }
    }

    /// Route to specific screen based on payload
    private func routeToScreen(_ screen: String, projectId: String?, taskId: String?, leadId: String?) {
        switch screen {
        case "projectDetails":
            if let projectId = projectId {
                openProjectViaCoordinator(projectId)
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
        case "projectNotes":
            // Deep link to project details (notes tab) when a mention notification is tapped
            if let projectId = projectId {
                openProjectViaCoordinator(projectId)
            }
        case "pipeline", "leads", "leadDetails", "opportunity", "opportunities":
            // With a lead id, open the matching detail; without one, just land
            // the operator on the LEADS tab (OpenLeadDetails with no id is a
            // no-op, so fall back to the Job Board for a non-dead tap).
            routeToLeadOrJobBoard(leadId: leadId)
        case "subscription", "planSelection":
            NotificationCenter.default.post(
                name: Notification.Name("OpenSubscription"),
                object: nil,
                userInfo: [:]
            )
        default:
            print("[PUSH] Unknown screen: \(screen)")
        }
    }

    /// Open a lead detail when an id is present, otherwise the Job Board — never
    /// a dead tap. MainTabView's OpenLeadDetails handler enforces pipeline.view.
    private func routeToLeadOrJobBoard(leadId: String?) {
        if let leadId = leadId, !leadId.isEmpty {
            NotificationCenter.default.post(
                name: Notification.Name("OpenLeadDetails"),
                object: nil,
                userInfo: ["leadId": leadId]
            )
        } else {
            NotificationCenter.default.post(name: Notification.Name("OpenJobBoard"), object: nil)
        }
    }

    /// Route based on notification type
    private func routeByType(_ type: String, projectId: String?, taskId: String?, leadId: String?) {
        switch type {
        case "leads_waiting", "pipeline_complete",
             "lead", "leads", "opportunity", "opportunities",
             "lead_created", "lead_updated", "lead_follow_up_due",
             "opportunity_created", "opportunity_updated", "opportunity_follow_up_due":
            routeToLeadOrJobBoard(leadId: leadId)
        case "assignment", "update", "completion", "projectCompletion", "taskCompletion":
            if let projectId = projectId {
                openProjectViaCoordinator(projectId)
            }
        case "taskAssignment", "taskUpdate", "scheduleChange":
            if let taskId = taskId, let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenTaskDetails"),
                    object: nil,
                    userInfo: ["taskId": taskId, "projectId": projectId]
                )
            } else if let projectId = projectId {
                // Fallback to project details if no taskId
                openProjectViaCoordinator(projectId)
            }
        case "projectNoteMention", "projectNoteAdded":
            // Someone @mentioned the user or added a note to their project - open project details
            if let projectId = projectId {
                openProjectViaCoordinator(projectId)
            }
        case "dependencyCompleted":
            if let taskId = taskId, let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenTaskDetails"),
                    object: nil,
                    userInfo: ["taskId": taskId, "projectId": projectId]
                )
            } else if let projectId = projectId {
                openProjectViaCoordinator(projectId)
            }
        case "teamJoin":
            NotificationCenter.default.post(
                name: Notification.Name("OpenManageTeam"),
                object: nil
            )
        case "expense_submitted", "expense_approved", "expense_rejected":
            NotificationCenter.default.post(
                name: Notification.Name("OpenExpenses"),
                object: nil
            )
        case "invoice_approved", "invoice_revisions", "invoice_overdue":
            // Bug bb63c37e — invoice notifications were previously routed
            // to OpenExpenses, which landed the user on the wrong list.
            NotificationCenter.default.post(
                name: Notification.Name("OpenInvoices"),
                object: nil
            )
        case "billable_this_week":
            NotificationCenter.default.post(
                name: Notification.Name("NavigateToMap"),
                object: nil
            )
        case "role_assigned":
            NotificationCenter.default.post(
                name: Notification.Name("OpenSettings"),
                object: nil
            )
        case "inventory_warning", "inventory_critical":
            NotificationCenter.default.post(
                name: Notification.Name("OpenInventory"),
                object: nil
            )
        case "time_off_approved", "time_off_denied":
            NotificationCenter.default.post(
                name: Notification.Name("OpenSchedule"),
                object: nil
            )
        case "projects_needing_tasks":
            // Bug 78309d78 — push variant of the rail notification for
            // accepted projects with no tasks.
            NotificationCenter.default.post(
                name: Notification.Name("OpenProjectsNeedingTasks"),
                object: nil
            )
        case "advanceNotice":
            // Local advance notice - open task or project details
            if let taskId = taskId, let projectId = projectId {
                NotificationCenter.default.post(
                    name: Notification.Name("OpenTaskDetails"),
                    object: nil,
                    userInfo: ["taskId": taskId, "projectId": projectId]
                )
            } else if let projectId = projectId {
                openProjectViaCoordinator(projectId)
            }
        case "trial_expiry", "subscription":
            NotificationCenter.default.post(
                name: Notification.Name("OpenSubscription"),
                object: nil
            )
        default:
            print("[PUSH] Unknown type: \(type)")
        }
    }
}

// Add custom notification names as UIApplication extension
extension UIApplication {
    static let didRegisterForRemoteNotificationsWithDeviceTokenNotification = Notification.Name("UIApplicationDidRegisterForRemoteNotificationsWithDeviceToken")
    static let didFailToRegisterForRemoteNotificationsNotification = Notification.Name("UIApplicationDidFailToRegisterForRemoteNotifications")
}
