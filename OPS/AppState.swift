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

    // MARK: - Bug Reporting
    @Published var showingBugReport: Bool = false
    @Published var bugReportScreenshot: UIImage?

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
        // Check for incomplete tasks (excluding cancelled)
        let incompleteTasks = project.tasks.filter { $0.status != .completed && $0.status != .cancelled }

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
        self.isLoadingProjects = false
        self.projectPendingCompletion = nil
        self.showingGlobalCompletionChecklist = false
        self.unreadNotificationCount = 0
        self.showingNotifications = false
        self.showingBugReport = false
        self.bugReportScreenshot = nil
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
        let allProjects = dataController.getProjects()
        let companyId = dataController.currentUser?.companyId
        let company: Company? = companyId.flatMap { dataController.getCompany(id: $0) }
        let threshold = company?.overdueReviewThresholdDays ?? 14
        let frequency = company?.overdueReminderFrequencyDays ?? 7

        let overdueCount = OverdueProjectDetector.overdueProjects(
            from: allProjects,
            thresholdDays: threshold
        ).count

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

        // Stacked-review rail notifications: upsert a persistent rail entry
        // whenever any review queue crosses the 5-item threshold, auto-clear
        // when it drops below. Runs after all other review checks so the
        // condensed stack notification reflects the freshest data.
        ReviewThresholdService.evaluate(dataController: dataController)
    }

    // MARK: - Stale Estimate Check

    /// Find projects stuck in .estimated status past the staleness threshold
    /// and surface an in-app notification so the admin can follow up before
    /// the lead goes cold. Runs on the same periodic review-check cadence.
    func checkStaleEstimates(dataController: DataController, frequencyDays: Int) {
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
        guard staleCount > 0 else { return }

        createInAppReviewNotification(
            dataController: dataController,
            throttleKey: "lastStaleEstimateInAppNotification",
            frequencyDays: frequencyDays,
            type: "stale_estimate_review",
            title: "Stale Estimates",
            body: "\(staleCount) estimate\(staleCount == 1 ? "" : "s") sitting \(threshold)+ days without follow-up",
            deepLinkType: "jobBoard"
        )
    }

    // MARK: - Overdue Task Review Check

    /// Check for tasks past their scheduled completion date and notify if there are any
    /// stacking up in the completion review queue. Called from checkOverdueProjects.
    func checkOverdueTasks(dataController: DataController, frequencyDays: Int) {
        let allTasks = dataController.getAllTasks()
        let calendar = Calendar.current
        let endOfToday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())

        // Match the filter used by JobBoardView.computeReviewableTasks and
        // FloatingActionMenu so the count agrees with the badge.
        let reviewableCount = allTasks.filter { task in
            guard task.status == .active, task.deletedAt == nil else { return false }
            guard let scheduledDate = task.endDate ?? task.startDate else { return false }
            return scheduledDate < endOfToday
        }.count

        NotificationManager.shared.checkAndScheduleTaskReviewNotifications(
            taskCount: reviewableCount,
            reminderFrequencyDays: frequencyDays
        )

        // The in-app rail entry for task review is now handled by
        // ReviewThresholdService (fires at 5+, persistent, auto-clears).
        // The local push above remains in place as a periodic iOS reminder.
    }

    /// Creates an in-app notification for a review queue, throttled by frequencyDays
    /// so the bell rail doesn't accumulate duplicate entries.
    private func createInAppReviewNotification(
        dataController: DataController,
        throttleKey: String,
        frequencyDays: Int,
        type: String,
        title: String,
        body: String,
        deepLinkType: String
    ) {
        // Throttle: only create a new in-app notification once per frequency window
        if let last = UserDefaults.standard.object(forKey: throttleKey) as? Date {
            let daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            guard daysSince >= frequencyDays else { return }
        }

        guard let userId = dataController.currentUser?.id,
              let companyId = dataController.currentUser?.companyId else { return }

        UserDefaults.standard.set(Date(), forKey: throttleKey)

        Task {
            let dto = NotificationRepository.CreateNotificationDTO(
                userId: userId,
                companyId: companyId,
                type: type,
                title: title,
                body: body,
                projectId: nil,
                noteId: nil,
                expenseId: nil,
                batchId: nil,
                deepLinkType: deepLinkType
            )
            do {
                try await NotificationRepository().createNotification(dto)
                await MainActor.run {
                    self.refreshUnreadCount()
                }
                print("[REVIEW_NOTIF] In-app notification created: \(title)")
            } catch {
                print("[REVIEW_NOTIF] Failed to create in-app notification: \(error)")
            }
        }
    }

    // MARK: - Overdue Invoice Check

    /// Check for overdue invoices and send in-app + push notifications to admin/office users.
    /// Throttled to once per day to avoid spam.
    private func checkOverdueInvoices(dataController: DataController) {
        guard let context = dataController.modelContext,
              let companyId = dataController.currentUser?.companyId else { return }

        // Throttle: only check once per day
        let lastCheckKey = "lastOverdueInvoiceCheck"
        if let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date {
            let hoursSince = Date().timeIntervalSince(lastCheck) / 3600
            guard hoursSince >= 24 else { return }
        }

        let descriptor = FetchDescriptor<Invoice>()
        guard let allInvoices = try? context.fetch(descriptor) else { return }

        let overdueInvoices = allInvoices.filter { $0.isOverdue }
        guard !overdueInvoices.isEmpty else { return }

        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        let overdueCount = overdueInvoices.count
        let totalOverdue = overdueInvoices.reduce(0.0) { $0 + $1.balanceDue }
        let formattedTotal = String(format: "$%.2f", totalOverdue)

        Task {
            // Find admin/office users to notify
            struct UserIdRow: Codable { let id: String }
            guard let admins = try? await SupabaseService.shared.client
                .from("users")
                .select("id")
                .eq("company_id", value: companyId)
                .in("role", values: ["admin", "owner", "office"])
                .execute()
                .value as [UserIdRow] else { return }

            let notifRepo = NotificationRepository()
            let currentId = UserDefaults.standard.string(forKey: "currentUserId")

            for admin in admins {
                let dto = NotificationRepository.CreateNotificationDTO(
                    userId: admin.id,
                    companyId: companyId,
                    type: "invoice_overdue",
                    title: "Overdue Invoices",
                    body: "\(overdueCount) invoice\(overdueCount == 1 ? "" : "s") overdue totalling \(formattedTotal)",
                    projectId: nil,
                    noteId: nil,
                    expenseId: nil,
                    batchId: nil,
                    deepLinkType: "invoices"
                )
                try? await notifRepo.createNotification(dto)
            }

            // Send push
            let adminIds = admins.map(\.id).filter { $0 != currentId }
            if !adminIds.isEmpty {
                try? await OneSignalService.shared.sendToUsers(
                    userIds: adminIds,
                    title: "Overdue Invoices",
                    body: "\(overdueCount) invoice\(overdueCount == 1 ? "" : "s") overdue totalling \(formattedTotal)",
                    data: ["type": "invoice_overdue", "screen": "expenses"]
                )
            }
            print("[OVERDUE_CHECK] 📬 Invoice overdue notification sent to \(admins.count) admins (\(overdueCount) invoices, \(formattedTotal))")
        }
    }
}