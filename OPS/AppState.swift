//
//  AppState.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// AppState.swift
import Foundation
import Combine
import SwiftUI
import SwiftData

// MARK: - Notification Creation Seams
//
// The 2026-07-15 notification-creation hardening revoked app-role INSERT on
// `notifications` — every rail row is created by a narrow SECURITY DEFINER RPC
// that derives the actor from the JWT, derives recipients from server rows, and
// renders the copy server-side. The two protocols below are the seams AppState's
// review surfaces cross; `NotificationRepository` conforms with the concrete RPC
// bindings, tests substitute a spy.

/// Throttled periodic review reminders (`sync_review_reminder_notification`).
/// The client supplies a kind, an honest count, and — for the stale-estimate
/// kind — the company's staleness threshold; the server renders the copy and
/// holds at most one unread reminder per kind, so a second device inside the
/// client's throttle window cannot stack a duplicate rail row.
protocol ReviewReminderSyncing {
    /// Returns the server's verdict: `created`, `kept`, or `noop`.
    @discardableResult
    func syncReviewReminder(kind: String, count: Int, thresholdDays: Int?) async throws -> String
}

/// Overdue-invoice rail (`sync_overdue_invoice_notifications`). The server
/// computes the overdue set AND the `invoices.record_payment` recipient list
/// itself, and returns only the user ids that received NEW rail rows under its
/// own 24h dedupe — the companion push must target exactly that list so push
/// can never fire for a recipient whose rail row was deduped away.
protocol OverdueInvoiceSyncing {
    @discardableResult
    func syncOverdueInvoiceNotifications() async throws -> [String]
}

extension NotificationRepository: ReviewReminderSyncing {}
extension NotificationRepository: OverdueInvoiceSyncing {}

class AppState: ObservableObject {
    @Published var activeProjectID: String?
    @Published var activeTaskID: String? // Store only task ID, not the model

    // New flag to differentiate between showing details and starting project
    @Published var isViewingDetailsOnly: Bool = false

    // Track when home view is loading projects
    @Published var isLoadingProjects: Bool = false

    // Track when inventory view is in selection mode (hides FAB)
    @Published var isInventorySelectionMode: Bool = false

    // Track when schedule view is in selection mode (hides FAB)
    @Published var isScheduleSelectionMode: Bool = false

    // Track when a map pin card/tooltip is showing (hides FAB)
    @Published var isShowingMapOverlay: Bool = false

    /// True while the map is presenting a PROJECT surface over Home — the pin
    /// card or the stacked-group sheet. Mirrored here by `OPSMapContainer`
    /// because the map coordinator that owns those flags is a private
    /// `@StateObject` that Home cannot observe. Deliberately narrower than
    /// `isShowingMapOverlay`, which also counts the crew tooltip: a crew
    /// tooltip is not a project surface and must not clear Home's cards.
    @Published var isMapProjectSurfacePresented: Bool = false

    // Tutorial restart flag - when true, ContentView should show the tutorial
    @Published var shouldRestartTutorial: Bool = false

    // MARK: - In-App Notifications
    @Published var unreadNotificationCount: Int = 0
    @Published var showingNotifications: Bool = false

    // MARK: - Search
    @Published var showingJobBoardSearch: Bool = false
    @Published var showingUniversalSearch: Bool = false

    // Bug G5 — Settings-scoped search lives in the AppHeader for the Settings
    // tab. The header owns the input field (so it can animate from icon to
    // full-width), SettingsView owns the results list (so the ScrollView
    // below the header can be replaced). Sharing state through AppState is
    // the lightest coupling between the two that still lets each side keep
    // its own view hierarchy.
    @Published var isSettingsSearchActive: Bool = false
    @Published var settingsSearchQuery: String = ""

    // MARK: - Payment Review
    @Published var showPaymentReview: Bool = false

    // MARK: - Subscription
    @Published var showingPlanSelection: Bool = false
    @Published var pendingPromoCode: String? = nil

    // MARK: - Photo Storage
    /// Present the Photo Storage management sheet. Attached at PINGatedView
    /// level so the sheet-to-sheet transition from the notification rail
    /// actually presents instead of racing the dismissing notification sheet.
    @Published var showPhotoStorage: Bool = false

    // MARK: - Notification Rail Deep Link Baton
    /// Baton passed from the notification rail to the sheet's `onDismiss`
    /// callback so the next presentation only fires AFTER the notification
    /// sheet is fully gone. Prevents sheet-on-sheet deadlock that shows up as
    /// a frozen UI when presenting from an ancestor while a descendant's
    /// sheet animation is still unwinding.
    @Published var pendingRailDeepLink: String? = nil

    // MARK: - Projects Needing Tasks Review
    /// Sheet presented when the user taps the rail notification for the
    /// "accepted projects with no tasks" alert. Mounted at MainTabView so
    /// it survives notification-rail dismissal.
    @Published var showProjectsNeedingTasksReview: Bool = false

    // MARK: - Lead Notification Deep Link Baton
    /// Opportunity id stashed by the `OpenLeadDetails` handler in MainTabView
    /// before it switches to the LEADS tab. `LeadsTabView` reads and clears it
    /// on appear / load so the matching `LeadDetailView` opens once the tab is
    /// mounted and the pipeline data is in hand. Survives the LEADS tab not yet
    /// being on-screen at tap time (push cold-launch, rail tap from any tab).
    @Published var pendingLeadDeepLinkId: String? = nil

    /// A START-visit intent headed for the leads tab's ONE capture cover —
    /// set by the site_visit_start push tap and the calendar's START NOW.
    /// LeadsTabView drains it exactly like the lead deep link.
    @Published var pendingSiteVisitStartLeadId: String? = nil

    /// Refresh unread notification count from Supabase
    func refreshUnreadCount() {
        guard let userId = UserDefaults.standard.string(forKey: "user_id"), !userId.isEmpty else { return }
        Task {
            do {
                let repo = NotificationRepository()
                let count = try await repo.fetchUnreadCount(userId: userId)
                await MainActor.run {
                    self.unreadNotificationCount = count
                }
            } catch {
                print("[NOTIFICATIONS] Failed to fetch unread count: \(error)")
            }
        }
    }

    // MARK: - Centralized Project Completion Cascade
    // These properties allow any view to trigger the completion checklist sheet
    @Published var projectPendingCompletion: Project?
    @Published var showingGlobalCompletionChecklist: Bool = false

    /// Centralized function to request project completion.
    /// Call this BEFORE updating project status to .completed.
    /// Returns true if completion can proceed directly, false if checklist sheet will be shown.
    @discardableResult
    func requestProjectCompletion(_ project: Project) -> Bool {
        // Check for tasks that genuinely block completion (excludes terminal
        // — completed/cancelled — and soft-deleted tasks). Shares the exact
        // predicate the checklist sheet consumes so the gate and the sheet
        // never disagree.
        let incompleteTasks = project.tasksBlockingCompletion

        if !incompleteTasks.isEmpty {
            // Has incomplete tasks - show checklist sheet
            print("[PROJECT_COMPLETION] 📋 Project '\(project.title)' has \(incompleteTasks.count) incomplete task(s) - showing checklist")
            self.projectPendingCompletion = project
            self.showingGlobalCompletionChecklist = true
            return false
        }

        // No incomplete tasks - can complete directly
        print("[PROJECT_COMPLETION] ✅ Project '\(project.title)' has no incomplete tasks - can complete directly")
        return true
    }

    /// Clear the completion request (called after sheet is dismissed or completion is done)
    func clearCompletionRequest() {
        self.projectPendingCompletion = nil
        self.showingGlobalCompletionChecklist = false
    }
    
    var isInProjectMode: Bool {
        // Only consider in project mode if we're not just viewing details
        activeProjectID != nil && !isViewingDetailsOnly
    }

    /// True while ANY project surface is presented over Home — the map's pin
    /// card, the stacked-group sheet, or the project details surface.
    ///
    /// `isInProjectMode` cannot serve here: it is false whenever a project is
    /// merely being VIEWED (`isViewingDetailsOnly`), which is the state every
    /// one of those surfaces is presented in. Computed rather than stored so
    /// it can never latch out of sync with the flags it reads — the same
    /// shape as `isInProjectMode` directly above.
    var isProjectSurfacePresented: Bool {
        isMapProjectSurfacePresented || isProjectDetailsPresented
    }

    /// The details surface, including the brief window between the request and
    /// the sheet actually raising: `showProjectDetailsAfterResetById` arms
    /// `isViewingDetailsOnly` + `activeProjectID` synchronously and flips
    /// `showProjectDetails` a runloop later. Without the arming window the
    /// Home cards fade back in for ~100ms between the pin card closing and
    /// details opening — a visible flicker on the commonest path in.
    private var isProjectDetailsPresented: Bool {
        showProjectDetails || (isViewingDetailsOnly && activeProjectID != nil)
    }
    
    func enterProjectMode(projectID: String) {
        self.isViewingDetailsOnly = false // Make sure we're in project mode
        self.activeProjectID = projectID
        
        // When using this function directly, we need to make sure
        // the DataController retrieves the project
        NotificationCenter.default.post(
            name: Notification.Name("FetchActiveProject"),
            object: nil,
            userInfo: ["projectID": projectID]
        )
    }
    
    // Flag to control whether to show the project details - published so it can be observed
    @Published var showProjectDetails: Bool = false

    // Spotlight / deep-link targets for detail sheets
    @Published var selectedClientId: String?
    @Published var showClientDetails: Bool = false
    private var clientDetailsDismissalWaiters: [CheckedContinuation<Void, Never>] = []

    @Published var selectedInvoiceId: String?
    @Published var showInvoiceDetails: Bool = false

    @Published var selectedEstimateId: String?
    @Published var showEstimateDetails: Bool = false

    @Published var accessDeniedMessage: String?
    @Published var showAccessDenied: Bool = false

    @MainActor
    func viewClientDetailsById(_ id: String) {
        selectedClientId = id
        showClientDetails = true
    }

    @MainActor
    func requestClientDetailsDismissal() {
        showClientDetails = false
    }

    @MainActor
    func dismissClientDetails() {
        showClientDetails = false
        selectedClientId = nil

        let waiters = clientDetailsDismissalWaiters
        clientDetailsDismissalWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    @MainActor
    func waitForClientDetailsDismissal() async {
        guard showClientDetails || selectedClientId != nil else { return }

        await withCheckedContinuation { continuation in
            if showClientDetails || selectedClientId != nil {
                clientDetailsDismissalWaiters.append(continuation)
            } else {
                continuation.resume()
            }
        }
    }

    @MainActor
    func viewInvoiceDetailsById(_ id: String) {
        selectedInvoiceId = id
        showInvoiceDetails = true
    }

    @MainActor
    func viewEstimateDetailsById(_ id: String) {
        selectedEstimateId = id
        showEstimateDetails = true
    }

    @MainActor
    func presentAccessDenied(message: String) {
        accessDeniedMessage = message
        showAccessDenied = true
    }
    
    // Function to set a project for viewing details
    func viewProjectDetails(_ project: Project) {
        viewProjectDetailsById(project.id)
    }
    
    func viewProjectDetailsById(_ projectId: String) {
        // IMPORTANT: Make sure we're not already showing this project to avoid sheet flicker
        if self.showProjectDetails && self.activeProjectID == projectId {
            return
        }
        
        // Step 1: Reset sheet state if needed to avoid transition conflicts
        if self.showProjectDetails {
            self.showProjectDetails = false
            
            // Use a delay before showing the new project to allow animation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showProjectDetailsAfterResetById(projectId)
            }
            return
        }
        
        // Normal case - no sheet is currently showing
        self.showProjectDetailsAfterResetById(projectId)
    }
    
    // Helper method to show project details after any needed reset
    private func showProjectDetailsAfterResetById(_ projectId: String) {
        
        // Check if we're already in project mode for this project
        let wasInProjectMode = self.activeProjectID == projectId && !self.isViewingDetailsOnly
        
        // Check if we're in project mode for a different project
        let isInProjectModeForDifferentProject = self.activeProjectID != nil && 
                                                 self.activeProjectID != projectId && 
                                                 !self.isViewingDetailsOnly
        
        // If we're in project mode for a different project, don't change activeProjectID
        if isInProjectModeForDifferentProject {
            // Just show the details without changing the active project
            self.activeProjectID = projectId
            self.showProjectDetails = true
            return
        }
        
        // Only set isViewingDetailsOnly if we're not already in project mode for this project
        if !wasInProjectMode {
            self.isViewingDetailsOnly = true
        }
        
        // Set active project ID BEFORE showing the sheet
        self.activeProjectID = projectId
        
        // Use a very short delay to ensure UI updates properly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.showProjectDetails = true
        }
    }
    
    func viewTaskDetails(task: ProjectTask, project: Project) {
        // Post notification to show task details
        let userInfo: [String: Any] = [
            "taskID": task.id,
            "projectID": project.id
        ]
        
        NotificationCenter.default.post(
            name: Notification.Name("ShowTaskDetailsFromHome"),
            object: nil,
            userInfo: userInfo
        )
    }
    
    func setActiveProject(_ project: Project) {
        self.activeProjectID = project.id
        
        // Only trigger sheet display if showProjectDetails is true
        if showProjectDetails {
            self.showProjectDetails = true
        }
    }
    
    func exitProjectMode() {
        self.showProjectDetails = false // Reset the details flag
        self.isViewingDetailsOnly = false // Reset viewing details flag
        self.activeProjectID = nil
        self.activeTaskID = nil // Clear active task ID
    }
    
    // Reset all state on logout to prevent stale references
    func resetForLogout() {
        self.showProjectDetails = false
        self.isViewingDetailsOnly = false
        self.activeProjectID = nil
        self.activeTaskID = nil
        self.isMapProjectSurfacePresented = false
        self.isLoadingProjects = false
        self.projectPendingCompletion = nil
        self.showingGlobalCompletionChecklist = false
        self.unreadNotificationCount = 0
        self.showingNotifications = false
        self.showProjectsNeedingTasksReview = false
        // Tear down the shake-to-report overlay window if it's up, so a
        // logout doesn't leave it floating over the login screen.
        Task { @MainActor in
            BugReportPresenter.shared.dismiss()
        }
        // Purge any pending deep link so the next signed-in user cannot
        // inherit a link that was sent to the previous account. The
        // coordinator is MainActor-isolated; resetForLogout is called
        // from DataController on the main actor, so the hop is free.
        Task { @MainActor in
            DeepLinkCoordinator.shared.clear()
        }
    }
    
    // Helper method to dismiss project details without exiting project mode
    func dismissProjectDetails() {
        self.showProjectDetails = false
        
        // Store the current active project ID if we're in project mode
        let currentActiveProjectID = self.isInProjectMode ? self.activeProjectID : nil
        
        // If we were just viewing details and there's no active project mode, clear everything
        if isViewingDetailsOnly && currentActiveProjectID == nil {
            self.isViewingDetailsOnly = false
            self.activeProjectID = nil
        }
        // If we were viewing details of a different project while in project mode, restore the active project
        else if currentActiveProjectID != nil && self.activeProjectID != currentActiveProjectID {
            self.activeProjectID = currentActiveProjectID
            self.isViewingDetailsOnly = false
        }
        // If we were viewing details of the same project we're working on, keep project mode
        else if !isViewingDetailsOnly {
            // Keep activeProjectID as is - we're still in project mode
        }
    }

    // MARK: - Overdue Payment Review Check

    /// Check for overdue projects on app launch and schedule a local notification if needed.
    /// Should be called after initial data sync completes.
    func checkOverdueProjects(dataController: DataController) {
        let companyId = dataController.currentUser?.companyId
        let company: Company? = companyId.flatMap { dataController.getCompany(id: $0) }
        let frequency = company?.overdueReminderFrequencyDays ?? 7

        let overdueCount = ProjectReviewQuery.snapshot(
            dataController: dataController
        ).overdueProjects.count

        NotificationManager.shared.checkAndSchedulePaymentReviewNotifications(
            overdueCount: overdueCount,
            reminderFrequencyDays: frequency
        )

        // The in-app rail entry for payment review is now handled by
        // ReviewThresholdService (fires at 5+, persistent, auto-clears).
        // The local push above remains in place as a periodic iOS reminder.

        // Check for overdue invoices and notify admin/office users
        checkOverdueInvoices(dataController: dataController)

        // Check for tasks stacking up in the completion review queue
        checkOverdueTasks(dataController: dataController, frequencyDays: frequency)

        // Check for projects stuck in the estimated phase — the "rotting
        // quote" problem where a quote is sent and never followed up.
        checkStaleEstimates(dataController: dataController, frequencyDays: frequency)

        // Check for accepted/in-progress projects with zero tasks — work
        // committed to but never broken down for the crew.
        checkProjectsNeedingTasks(dataController: dataController, frequencyDays: frequency)

        // Stacked-review rail notifications: upsert a persistent rail entry
        // whenever any review queue crosses the 5-item threshold, auto-clear
        // when it drops below. Runs after all other review checks so the
        // condensed stack notification reflects the freshest data.
        ReviewThresholdService.evaluate(dataController: dataController)
    }

    // MARK: - Projects Needing Tasks Check

    /// Find accepted/in-progress projects with zero tasks attached and surface
    /// an in-app rail notification so the admin can plan the work before the
    /// crew shows up empty-handed. Throttled by the standard review-frequency
    /// window so it doesn't pile up daily entries for the same backlog.
    /// - Returns: the reporting task, or `nil` when there is nothing to report
    ///   (production call sites discard it; tests await it).
    @discardableResult
    func checkProjectsNeedingTasks(
        dataController: DataController,
        frequencyDays: Int,
        syncer: ReviewReminderSyncing = NotificationRepository.shared
    ) -> Task<Void, Never>? {
        let allProjects = dataController.getProjects()
        let needsTasks = ProjectsWithoutTasksDetector.projectsWithoutTasks(from: allProjects)
        let count = needsTasks.count
        guard count > 0 else { return nil }

        return createInAppReviewNotification(
            dataController: dataController,
            throttleKey: "lastProjectsNeedingTasksInAppNotification",
            frequencyDays: frequencyDays,
            kind: "projects_needing_tasks",
            count: count,
            syncer: syncer
        )
    }

    // MARK: - Stale Estimate Check

    /// Find projects stuck in .estimated status past the staleness threshold
    /// and surface an in-app notification so the admin can follow up before
    /// the lead goes cold. Runs on the same periodic review-check cadence.
    /// - Returns: the reporting task, or `nil` when there is nothing to report
    ///   (production call sites discard it; tests await it).
    @discardableResult
    func checkStaleEstimates(
        dataController: DataController,
        frequencyDays: Int,
        syncer: ReviewReminderSyncing = NotificationRepository.shared
    ) -> Task<Void, Never>? {
        let allProjects = dataController.getProjects()
        let companyId = dataController.currentUser?.companyId
        let company: Company? = companyId.flatMap { dataController.getCompany(id: $0) }
        // Re-use the same threshold config as overdue review for now; the
        // UX intent is identical — "nothing has moved in N days, act on it".
        // Defaults to 30 days when the company hasn't configured a value.
        let threshold = company?.staleEstimateThresholdDays ?? 30

        let staleProjects = StaleEstimateDetector.staleEstimatedProjects(
            from: allProjects,
            thresholdDays: threshold
        )
        let staleCount = staleProjects.count
        guard staleCount > 0 else { return nil }

        return createInAppReviewNotification(
            dataController: dataController,
            throttleKey: "lastStaleEstimateInAppNotification",
            frequencyDays: frequencyDays,
            kind: "stale_estimate_review",
            count: staleCount,
            thresholdDays: threshold,
            syncer: syncer
        )
    }

    // MARK: - Overdue Task Review Check

    /// Check for tasks past their scheduled completion date and notify if there are any
    /// stacking up in the completion review queue. Called from checkOverdueProjects.
    func checkOverdueTasks(dataController: DataController, frequencyDays: Int) {
        // Permission-scoped, identical to the review stack the user opens — a
        // crew member is notified about THEIR overdue tasks, not the whole
        // company's. (Previously this counted every task via getAllTasks() with
        // no scope, so the push read e.g. "15 tasks" while the scoped stack the
        // user then opened showed only their own ~4.)
        let reviewableCount = TaskReviewQuery.overdueReviewTasks(dataController: dataController).count

        NotificationManager.shared.checkAndScheduleTaskReviewNotifications(
            taskCount: reviewableCount,
            reminderFrequencyDays: frequencyDays
        )

        // The in-app rail entry for task review is now handled by
        // ReviewThresholdService (fires at 5+, persistent, auto-clears).
        // The local push above remains in place as a periodic iOS reminder.
    }

    /// Reports one review queue's count to the server, throttled by frequencyDays
    /// so the bell rail doesn't accumulate duplicate entries.
    ///
    /// The rail row is created by the narrow `sync_review_reminder_notification`
    /// RPC — the 2026-07-15 hardening revoked app-role INSERT on `notifications`,
    /// so the legacy direct insert 42501'd. The server owns the recipient (self,
    /// derived from the JWT) and the copy; the client hands over the kind, the
    /// count, and the dimension the copy interpolates.
    ///
    /// - Returns: the reporting task, or `nil` when throttled or no operator is
    ///   resolved (production call sites discard it; tests await it).
    @discardableResult
    private func createInAppReviewNotification(
        dataController: DataController,
        throttleKey: String,
        frequencyDays: Int,
        kind: String,
        count: Int,
        thresholdDays: Int? = nil,
        syncer: ReviewReminderSyncing = NotificationRepository.shared
    ) -> Task<Void, Never>? {
        // Throttle: only create a new in-app notification once per frequency window
        if let last = UserDefaults.standard.object(forKey: throttleKey) as? Date {
            let daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            guard daysSince >= frequencyDays else { return nil }
        }

        guard dataController.currentUser?.id != nil,
              dataController.currentUser?.companyId != nil else { return nil }

        UserDefaults.standard.set(Date(), forKey: throttleKey)

        return Task {
            do {
                let action = try await syncer.syncReviewReminder(
                    kind: kind,
                    count: count,
                    thresholdDays: thresholdDays
                )
                // `kept` / `noop` mean the server already holds an unread
                // reminder for this kind — nothing new landed on the rail, so
                // the badge is already correct.
                if action == "created" {
                    await MainActor.run {
                        self.refreshUnreadCount()
                    }
                    print("[REVIEW_NOTIF] In-app notification created: \(kind)")
                }
            } catch {
                print("[REVIEW_NOTIF] Failed to create in-app notification: \(error)")
            }
        }
    }

    // MARK: - Overdue Invoice Check

    /// Check for overdue invoices and send in-app + push notifications to the
    /// users who can act on them. Throttled to once per day to avoid spam.
    ///
    /// The rail rows are created by `sync_overdue_invoice_notifications` — the
    /// server computes the overdue set and the `invoices.record_payment`
    /// recipient list from its own rows (client input is never trusted for
    /// recipients) and returns only the ids that received NEW rows under its 24h
    /// dedupe. The local fetch below stays because the push copy still quotes
    /// this device's view of the overdue balance.
    ///
    /// - Returns: the notification task, or `nil` when throttled or nothing is
    ///   overdue (production call sites discard it; tests await it).
    @discardableResult
    func checkOverdueInvoices(
        dataController: DataController,
        invoiceSyncer: OverdueInvoiceSyncing = NotificationRepository.shared
    ) -> Task<Void, Never>? {
        guard let context = dataController.modelContext,
              dataController.currentUser?.companyId != nil else { return nil }

        // Throttle: only check once per day
        let lastCheckKey = "lastOverdueInvoiceCheck"
        if let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date {
            let hoursSince = Date().timeIntervalSince(lastCheck) / 3600
            guard hoursSince >= 24 else { return nil }
        }

        let descriptor = FetchDescriptor<Invoice>()
        guard let allInvoices = try? context.fetch(descriptor) else { return nil }

        let overdueInvoices = allInvoices.filter { $0.isOverdue }
        guard !overdueInvoices.isEmpty else { return nil }

        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        let overdueCount = overdueInvoices.count
        let totalOverdue = overdueInvoices.reduce(0.0) { $0 + $1.balanceDue }
        let formattedTotal = BooksFormat.exact(totalOverdue)

        return Task {
            // The server derives the recipients (invoices.record_payment
            // holders, minus the actor) and returns only the ids that received
            // a NEW rail row. An empty list means every eligible recipient was
            // already notified inside the server's 24h window.
            let createdRecipients = (try? await invoiceSyncer.syncOverdueInvoiceNotifications()) ?? []
            guard !createdRecipients.isEmpty else { return }

            // Push targets exactly the ids that got a rail row — rail dedupe
            // IS push dedupe, so the two surfaces can never disagree.
            try? await OneSignalService.shared.sendToUsers(
                userIds: createdRecipients,
                title: "Overdue Invoices",
                body: "\(overdueCount) invoice\(overdueCount == 1 ? "" : "s") overdue totalling \(formattedTotal)",
                data: ["type": "invoice_overdue", "screen": "expenses"]
            )
            print("[OVERDUE_CHECK] 📬 Invoice overdue notification sent to \(createdRecipients.count) recipients (\(overdueCount) invoices, \(formattedTotal))")
        }
    }
}
