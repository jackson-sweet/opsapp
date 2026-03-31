//
//  MainTabView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// MainTabView.swift
import SwiftUI
import SwiftData
import Combine
import MapKit

struct MainTabView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.wizardTriggerService) private var wizardTriggerService
    @Environment(\.wizardStateManager) private var wizardStateManager

    @State private var selectedTab = 0
    @State private var hasEvaluatedWizards = false
    @State private var needsWizardRetry = false
    @State private var previousTab = 0
    @State private var keyboardIsShowing = false
    @State private var sheetIsPresented = false
    // PermissionChangeOverlay moved to PINGatedView (ContentView.swift) so it sits above all sheets
    @StateObject private var imageSyncProgressManager = ImageSyncProgressManager()
    @ObservedObject private var inProgressManager = InProgressManager.shared
    @State private var userRole: UserRole? = nil // Track user role changes explicitly

    // Track inventory access for conditional tab
    private var hasInventoryAccess: Bool {
        permissionStore.can("inventory.view", requiredScope: "all")
    }
    
    // Observer for fetch active project notifications
    private let fetchProjectObserver = NotificationCenter.default
        .publisher(for: Notification.Name("FetchActiveProject"))
    
    // Observer for showing project details
    private let showProjectObserver = NotificationCenter.default
        .publisher(for: Notification.Name("ShowProjectDetailsRequest"))
    
    // Observer for navigating to map view
    private let navigateToMapObserver = NotificationCenter.default
        .publisher(for: Notification.Name("NavigateToMapView"))

    // Permission scope contraction observer — moved to PINGatedView

    // Push notification deep linking observers
    private let openProjectDetailsObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenProjectDetails"))

    private let openTaskDetailsObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenTaskDetails"))

    private let openScheduleObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenSchedule"))

    private let openJobBoardObserver = NotificationCenter.default
        .publisher(for: Notification.Name("OpenJobBoard"))
    
    // Keyboard observers
    private let keyboardWillShow = NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillShowNotification)
    
    private let keyboardWillHide = NotificationCenter.default
        .publisher(for: UIResponder.keyboardWillHideNotification)
    
    // Whether the current user has Pipeline access (requires "pipeline" special permission)
    private var hasPipelineAccess: Bool {
        permissionStore.can("pipeline.view")
    }

    // Computed tab indices that adapt based on visible tabs (pipeline + inventory)
    private var pipelineTabIndex: Int? { hasPipelineAccess ? 1 : nil }
    private var jobBoardTabIndex: Int {
        var idx = 1
        if hasPipelineAccess { idx += 1 }
        return idx
    }
    private var inventoryTabIndex: Int? {
        guard hasInventoryAccess else { return nil }
        return jobBoardTabIndex + 1
    }
    private var scheduleTabIndex: Int {
        var idx = jobBoardTabIndex + 1
        if hasInventoryAccess { idx += 1 }
        return idx
    }
    private var settingsTabIndex: Int {
        return scheduleTabIndex + 1
    }

    // Dynamic tabs based on user role
    private var tabs: [TabItem] {
        var baseTabs: [TabItem] = [
            TabItem(iconName: "house.fill", wizardStepId: "welcome_home")
        ]

        // Add Pipeline tab for admin/office crew only
        if hasPipelineAccess {
            baseTabs.append(TabItem(iconName: "chart.line.uptrend.xyaxis", wizardStepId: "welcome_pipeline"))
        }

        // Add Job Board tab for all users (admin, office crew, and field crew)
        baseTabs.append(TabItem(iconName: "briefcase.fill", wizardStepId: "welcome_job_board"))

        // Add Inventory tab if user has inventory access
        if hasInventoryAccess {
            baseTabs.append(TabItem(iconName: "shippingbox.fill", wizardStepId: "welcome_inventory"))
        }

        // Add Schedule and Settings for all users
        baseTabs.append(contentsOf: [
            TabItem(iconName: "calendar", wizardStepId: "welcome_schedule"),
            TabItem(iconName: "gearshape.fill", wizardStepId: "welcome_settings")
        ])

        return baseTabs
    }

    // Check if currently on Settings tab
    private var isSettingsTab: Bool {
        let tabCount = tabs.count
        // Settings is always the last tab
        // For admin/office crew (4 tabs): Settings is tab 3
        // For field crew (3 tabs): Settings is tab 2
        return selectedTab == (tabCount - 1)
    }

    // Check if currently on Pipeline tab (has its own FAB)
    private var isPipelineTab: Bool {
        pipelineTabIndex != nil && selectedTab == pipelineTabIndex
    }

    private var slideTransition: AnyTransition {
        if selectedTab > previousTab {
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        }
    }

    var body: some View {
        ZStack {
            // Main content structure with sliding transitions
            // Dynamic content based on tabs array
            let tabCount = tabs.count

            // Content views with transition - each complete view slides as a unit
            ZStack {
                // Tab content — indices adapt based on role and permissions
                if selectedTab == 0 {
                    HomeView()
                } else if selectedTab == pipelineTabIndex {
                    MoneyTabView()
                } else if selectedTab == jobBoardTabIndex {
                    JobBoardView()
                } else if selectedTab == inventoryTabIndex {
                    InventoryView()
                } else if selectedTab == scheduleTabIndex {
                    ScheduleView()
                } else if selectedTab == settingsTabIndex {
                    SettingsView()
                } else {
                    HomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all, edges: .bottom)
            .transition(slideTransition)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedTab)
            
            // Image sync progress bar and sync status at top
            VStack(spacing: 8) {
                ImageSyncProgressView(syncManager: imageSyncProgressManager)

                // Sync status indicator — hidden when sync restored banner is showing
                if !dataController.showSyncRestoredAlert {
                    HStack {
                        Spacer()
                        SyncStatusIndicator()
                            .environmentObject(dataController)
                            .padding(.trailing, 16)
                    }
                }

                Spacer()
            }
            .ignoresSafeArea(.all, edges: .bottom)
            .zIndex(1) // Ensure it appears above content
            
            // Custom tab bar overlaid at bottom
            VStack {
                Spacer()
                CustomTabBar(selectedTab: $selectedTab, tabs: tabs)
            }
            .ignoresSafeArea(.all, edges: .bottom)
            .preferredColorScheme(.dark)
            .opacity(keyboardIsShowing || dataController.isPerformingInitialSync || appState.isLoadingProjects ? 0 : 1)
            .animation(OPSStyle.Animation.standard, value: keyboardIsShowing)
            .animation(OPSStyle.Animation.standard, value: dataController.isPerformingInitialSync)
            .animation(OPSStyle.Animation.standard, value: appState.isLoadingProjects)

            // Floating action menu - visible across all tabs except Settings and during initial sync/loading
            // IMPORTANT: Always render to preserve @State (sheet presentation) when app goes to background
            // Use opacity and allowsHitTesting instead of conditional rendering to prevent sheet dismissal
            FloatingActionMenu(currentTab: selectedTab, hasInventoryAccess: hasInventoryAccess, isScheduleTab: selectedTab == scheduleTabIndex, isInventoryTab: inventoryTabIndex != nil && selectedTab == inventoryTabIndex)
                .environmentObject(dataController)
                .environmentObject(appState)
                .opacity(!isSettingsTab && !dataController.isPerformingInitialSync && !appState.isLoadingProjects && !appState.isScheduleSelectionMode && !appState.isShowingMapOverlay && !appState.isInProjectMode ? 1 : 0)
                .allowsHitTesting(!isSettingsTab && !dataController.isPerformingInitialSync && !appState.isLoadingProjects && !appState.isScheduleSelectionMode && !appState.isShowingMapOverlay && !appState.isInProjectMode)
                .animation(OPSStyle.Animation.fast, value: isSettingsTab)
                .animation(OPSStyle.Animation.fast, value: dataController.isPerformingInitialSync)
                .animation(OPSStyle.Animation.fast, value: appState.isLoadingProjects)
                .animation(OPSStyle.Animation.fast, value: appState.isInventorySelectionMode)
                .animation(OPSStyle.Animation.fast, value: appState.isScheduleSelectionMode)
                .animation(OPSStyle.Animation.fast, value: appState.isShowingMapOverlay)
                .animation(OPSStyle.Animation.fast, value: appState.isInProjectMode)

            // Project sheet container that overlays the whole app
            ProjectSheetContainer()

            // Permission contraction overlay — moved to PINGatedView (ContentView.swift)
        }
        .sheet(isPresented: $appState.showingUniversalSearch) {
            UniversalSearchSheet()
                .environmentObject(dataController)
                .environmentObject(appState)
        }
        // Add notification handler for project fetching
        .onReceive(fetchProjectObserver) { notification in
            if let projectID = notification.userInfo?["projectID"] as? String {
                if let project = dataController.getProject(id: projectID) {
                    // Update app state with the fetched project
                    DispatchQueue.main.async {
                        appState.setActiveProject(project)
                        
                        // Debug to check project mode after setting
                    }
                } else {
                }
            }
        }
        
        // Add notification handler for showing project details
        .onReceive(showProjectObserver) { notification in
            if let projectID = notification.userInfo?["projectID"] as? String {
                
                // Make sure we're on the main thread
                DispatchQueue.main.async {
                    if let project = dataController.getProject(id: projectID) {
                        
                        // Set the active project before setting showProjectDetails
                        appState.isViewingDetailsOnly = true
                        appState.activeProjectID = project.id
                        
                        // The important part - we set the flag AFTER setting the project
                        appState.showProjectDetails = true
                    } else {
                    }
                }
            }
        }
        
        // Permission scope contraction handler — moved to PINGatedView

        // Handle navigation to map view
        .onReceive(navigateToMapObserver) { _ in
            withAnimation(OPSStyle.Animation.fast) {
                selectedTab = 0 // Switch to home/map tab
            }
        }

        // MARK: - Push Notification Deep Linking Handlers

        // Handle opening project details from push notification
        .onReceive(openProjectDetailsObserver) { notification in
            if let projectId = notification.userInfo?["projectId"] as? String {
                print("[PUSH_NAVIGATION] Opening project details for: \(projectId)")
                Task {
                    await openProjectWithSync(projectId: projectId)
                }
            }
        }

        // Handle opening task details from push notification
        .onReceive(openTaskDetailsObserver) { notification in
            if let taskId = notification.userInfo?["taskId"] as? String,
               let projectId = notification.userInfo?["projectId"] as? String {
                print("[PUSH_NAVIGATION] Opening task details - Task: \(taskId), Project: \(projectId)")
                Task {
                    await openTaskWithSync(taskId: taskId, projectId: projectId)
                }
            }
        }

        // Handle opening schedule view from push notification
        .onReceive(openScheduleObserver) { _ in
            print("[PUSH_NAVIGATION] Opening schedule view")
            withAnimation(OPSStyle.Animation.fast) {
                selectedTab = scheduleTabIndex
            }
        }

        // Handle opening job board from push notification
        .onReceive(openJobBoardObserver) { _ in
            print("[PUSH_NAVIGATION] Opening job board")
            withAnimation(OPSStyle.Animation.fast) {
                selectedTab = jobBoardTabIndex
            }
        }

        // Track tab changes for slide transitions and analytics
        .onChange(of: selectedTab) { oldValue, newValue in
            previousTab = oldValue

            // Track tab selection for analytics — use computed indices for role-adaptive mapping
            let tabName: TabName = {
                if newValue == 0 { return .home }
                if newValue == pipelineTabIndex { return .pipeline }
                if newValue == jobBoardTabIndex { return .jobBoard }
                if newValue == scheduleTabIndex { return .schedule }
                if newValue == settingsTabIndex { return .settings }
                return .home
            }()
            AnalyticsManager.shared.trackTabSelected(tabName: tabName)
            AnalyticsService.shared.track(
                eventType: .action,
                eventName: "tab_selected",
                properties: ["tab_name": tabName.rawValue, "tab_index": tabName.index]
            )
        }

        // Handle keyboard appearance - but ignore if from a sheet
        .onReceive(keyboardWillShow) { notification in
            // Check if keyboard is from current window context
            // Don't hide tab bar if keyboard is from a sheet
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                let keyboardHeight = keyboardFrame.cgRectValue.height
                // Only respond to keyboard if it's substantial (not from sheet)
                if keyboardHeight > 0 && !checkIfSheetIsPresented() {
                    withAnimation(OPSStyle.Animation.standard) {
                        keyboardIsShowing = true
                    }
                }
            }
        }
        .onReceive(keyboardWillHide) { _ in
            withAnimation(OPSStyle.Animation.standard) {
                keyboardIsShowing = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardOpenMostRecentProject"))) { _ in
            if let modelContext = dataController.modelContext {
                // Check if we have a stored project ID from a previous deep-nav (CONTINUE GUIDE)
                if let storedId = wizardStateManager?.deepNavProjectId {
                    let storedDescriptor = FetchDescriptor<Project>(
                        predicate: #Predicate<Project> { $0.id == storedId }
                    )
                    if let existing = (try? modelContext.fetch(storedDescriptor))?.first {
                        appState.viewProjectDetails(existing)
                        return
                    }
                }

                let companyId = dataController.currentUser?.companyId ?? ""
                let userId = dataController.currentUser?.id ?? ""
                let isFieldRole = dataController.currentUser?.role == .crew || dataController.currentUser?.role == .operator

                // Scope-aware fetch: crew/operator see only assigned projects
                let descriptor: FetchDescriptor<Project>
                if isFieldRole {
                    descriptor = FetchDescriptor<Project>(
                        predicate: #Predicate<Project> { project in
                            project.companyId == companyId &&
                            project.teamMemberIdsString.contains(userId)
                        },
                        sortBy: [SortDescriptor(\.startDate, order: .reverse)]
                    )
                } else {
                    descriptor = FetchDescriptor<Project>(
                        predicate: #Predicate<Project> { project in
                            project.companyId == companyId
                        },
                        sortBy: [SortDescriptor(\.startDate, order: .reverse)]
                    )
                }

                if let project = (try? modelContext.fetch(descriptor))?.first {
                    // Store the project ID so CONTINUE GUIDE reopens the same project
                    wizardStateManager?.deepNavProjectId = project.id
                    appState.viewProjectDetails(project)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardNavigateToTarget"))) { notification in
            guard let tabTarget = notification.userInfo?["tabTarget"] as? String else { return }
            switch tabTarget {
            case "Home":
                withAnimation { selectedTab = 0 }
            case "Pipeline":
                if let idx = pipelineTabIndex {
                    withAnimation { selectedTab = idx }
                }
            case "JobBoard":
                withAnimation { selectedTab = jobBoardTabIndex }
            case "Schedule":
                withAnimation { selectedTab = scheduleTabIndex }
            case "Inventory":
                if let idx = inventoryTabIndex {
                    withAnimation { selectedTab = idx }
                }
            case "Settings":
                withAnimation { selectedTab = settingsTabIndex }
            default:
                break
            }
        }
        // Wizard deep nav for settings sub-screens — handled here because SettingsView's
        // modifier stack is too deep for additional .onReceive handlers
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardOpenSecuritySettings"))) { _ in
            withAnimation { selectedTab = settingsTabIndex }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("SettingsOpenSecurity"), object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardOpenNotificationSettings"))) { _ in
            withAnimation { selectedTab = settingsTabIndex }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("SettingsOpenNotifications"), object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardOpenManageTeam"))) { _ in
            withAnimation { selectedTab = settingsTabIndex }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("SettingsOpenOrganization"), object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    NotificationCenter.default.post(name: Notification.Name("WizardOpenManageTeamFromOrg"), object: nil)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardOpenPermissions"))) { _ in
            withAnimation { selectedTab = settingsTabIndex }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("SettingsOpenPermissions"), object: nil)
            }
        }
        .onAppear {
            // Clear all pending image syncs on app bootup
            clearPendingImageSyncs()

            // Initialize user role
            userRole = dataController.currentUser?.role
            print("[MAIN_TAB_VIEW] onAppear - Initial user role: \(String(describing: userRole))")
            print("[MAIN_TAB_VIEW] onAppear - Current user: \(String(describing: dataController.currentUser?.fullName))")
            print("[MAIN_TAB_VIEW] onAppear - Tab count: \(tabs.count)")

            // Check for overdue payment reviews after giving sync time to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                appState.checkOverdueProjects(dataController: dataController)
            }

            // Evaluate wizard triggers after data has had time to load
            if !hasEvaluatedWizards {
                hasEvaluatedWizards = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    evaluateWizardTriggers()
                }
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            // Broadcast current tab name for wizard context tracking
            let tabName: String
            switch newTab {
            case 0: tabName = "Home"
            case jobBoardTabIndex: tabName = "JobBoard"
            case scheduleTabIndex: tabName = "Schedule"
            case settingsTabIndex: tabName = "Settings"
            default:
                if let inv = inventoryTabIndex, newTab == inv { tabName = "Inventory" }
                else if let pip = pipelineTabIndex, newTab == pip { tabName = "Pipeline" }
                else { tabName = "Unknown" }
            }
            NotificationCenter.default.post(
                name: Notification.Name("WizardCurrentTabChanged"),
                object: nil,
                userInfo: ["tabName": tabName]
            )
        }
        .onChange(of: dataController.currentUser?.role) { oldRole, newRole in
            print("[MAIN_TAB_VIEW] User role changed from \(String(describing: oldRole)) to \(String(describing: newRole))")
            userRole = newRole
            print("[MAIN_TAB_VIEW] After role change - Tab count: \(tabs.count)")

            // Ensure selected tab is valid for new tab count
            let newTabCount = tabs.count
            if selectedTab >= newTabCount {
                selectedTab = 0 // Reset to home if current tab no longer exists
            }
        }
        .onChange(of: dataController.currentUser?.id) { oldUserId, newUserId in
            print("[MAIN_TAB_VIEW] currentUser ID changed")
            print("[MAIN_TAB_VIEW]   Old ID: \(String(describing: oldUserId))")
            print("[MAIN_TAB_VIEW]   New ID: \(String(describing: newUserId))")
            let newUser = dataController.currentUser

            // Update userRole when currentUser changes
            if let newRole = newUser?.role {
                userRole = newRole
                print("[MAIN_TAB_VIEW] Updated userRole to: \(newRole)")
            }
        }
        .onChange(of: permissionStore.permissions) { oldValue, newValue in
            print("[MAIN_TAB_VIEW] Permissions changed - Tab count: \(tabs.count)")

            // Ensure selected tab is valid for new tab count
            let newTabCount = tabs.count
            if selectedTab >= newTabCount {
                selectedTab = 0 // Reset to home if current tab no longer exists
            }
        }
        // C2: Re-evaluate wizard triggers once initial sync completes
        .onChange(of: dataController.isPerformingInitialSync) { _, isLoading in
            if !isLoading && needsWizardRetry {
                evaluateWizardTriggers()
            }
        }
        .onChange(of: appState.isLoadingProjects) { _, isLoading in
            if !isLoading && needsWizardRetry {
                evaluateWizardTriggers()
            }
        }
    }
    
    // handlePermissionRefresh moved to PINGatedView (ContentView.swift)

    /// Evaluate wizard triggers based on current data state.
    /// Checks both sequenced wizards (project lifecycle) and data-condition wizards (task/payment review).
    private func evaluateWizardTriggers() {
        guard let triggerService = wizardTriggerService else { return }
        guard let modelContext = dataController.modelContext else { return }

        // C2: Don't evaluate while initial sync is in progress — re-schedule via onChange
        guard !dataController.isPerformingInitialSync, !appState.isLoadingProjects else {
            needsWizardRetry = true
            return
        }
        needsWizardRetry = false

        // C3: Don't start wizards while the interactive tutorial is still in progress
        guard dataController.currentUser?.hasCompletedAppTutorial == true else { return }

        // H2: Don't start wizards for unassigned users (pre-role-assignment)
        guard dataController.currentUser?.role != .unassigned else { return }

        let companyId = dataController.currentUser?.companyId ?? ""

        // Count projects for the current user's company (used by welcome tour + sequenced wizards)
        var projectDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { project in
                project.companyId == companyId
            }
        )
        projectDescriptor.propertiesToFetch = []
        let projectCount = (try? modelContext.fetchCount(projectDescriptor)) ?? 0

        // Welcome tour: auto-start on first app entry or resume if interrupted (C1)
        if let stateManager = wizardStateManager, !stateManager.isActive {
            let welcomeWizard = WelcomeTourWizard(permissionStore: permissionStore)
            if welcomeWizard.steps.count > 0,
               let state = stateManager.wizardState(for: "welcome_tour") {

                if state.status == .notStarted {
                    // Existing users updating to this version already have projects —
                    // silently mark the tour as completed so they don't get an unwanted tour.
                    if projectCount > 0 {
                        state.markCompleted()
                        try? modelContext.save()
                    } else {
                        stateManager.startWizardDirectly(welcomeWizard)
                        return
                    }
                } else if state.status == .inProgress {
                    // Resume an interrupted tour
                    stateManager.startWizardDirectly(welcomeWizard)
                    return
                }
            }
        }

        // Sequenced wizards (e.g., ProjectLifecycleWizard triggers when 0 projects)
        triggerService.evaluateSequencedWizards(projectCount: projectCount)

        // Data-condition wizards: count overdue tasks and completed projects
        // Fetch all tasks for the company and filter in memory (avoids complex #Predicate)
        let taskDescriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { task in
                task.companyId == companyId
            }
        )
        let allTasks = (try? modelContext.fetch(taskDescriptor)) ?? []
        let now = Date()
        let overdueCount = allTasks.filter { task in
            guard let endDate = task.endDate else { return false }
            return endDate < now && task.status != .completed
        }.count

        // Fetch all company projects and filter in memory (enum predicates not supported in #Predicate)
        let allProjectDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { project in
                project.companyId == companyId
            }
        )
        let allProjects = (try? modelContext.fetch(allProjectDescriptor)) ?? []
        let completedCount = allProjects.filter { $0.status == .completed }.count
        let completedTaskCount = allTasks.filter { $0.status == .completed }.count

        triggerService.evaluateDataConditions(
            overdueTaskCount: overdueCount,
            completedProjectCount: completedCount,
            completedTaskCount: completedTaskCount
        )
    }

    private func clearPendingImageSyncs() {
        
        // Get the image sync manager from dataController
        if let imageSyncManager = dataController.imageSyncManager {
            // Get pending uploads before clearing
            let pendingUploads = imageSyncManager.getPendingUploads()
            
            if !pendingUploads.isEmpty {
                
                // Show progress bar for pending uploads
                imageSyncProgressManager.startSync(with: imageSyncManager, pendingUploads: pendingUploads)
                
                // Don't clear them - let the sync complete
                // The sync manager will handle clearing them after successful upload
            } else {
            }
            
            // Clear all pending uploads to prevent issues with large/stuck uploads
            imageSyncManager.clearAllPendingUploads()
        }
    }
    
    private func checkIfSheetIsPresented() -> Bool {
        // Check if any common sheets are presented
        // This is a simple check - you can expand based on your app's sheets
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            // Check if there's a presented view controller (sheet)
            return window.rootViewController?.presentedViewController != nil
        }
        return false
    }

    // MARK: - Push Notification Sync Helpers

    /// Open project details, syncing first if the project isn't in the local database
    private func openProjectWithSync(projectId: String) async {
        // Check if project exists locally
        if dataController.getProject(id: projectId) != nil {
            print("[PUSH_NAVIGATION] Project found locally, opening immediately")
            await MainActor.run {
                appState.viewProjectDetailsById(projectId)
            }
            return
        }

        // Project not found locally - sync first
        print("[PUSH_NAVIGATION] Project not found locally, triggering sync...")
        await syncAndOpenProject(projectId: projectId)
    }

    /// Open task details, syncing first if the task/project isn't in the local database
    private func openTaskWithSync(taskId: String, projectId: String) async {
        // Check if project and task exist locally
        if let project = dataController.getProject(id: projectId),
           project.tasks.contains(where: { $0.id == taskId }) {
            print("[PUSH_NAVIGATION] Task found locally, opening immediately")
            await MainActor.run {
                NotificationCenter.default.post(
                    name: Notification.Name("ShowTaskDetailsFromHome"),
                    object: nil,
                    userInfo: ["taskID": taskId, "projectID": projectId]
                )
            }
            return
        }

        // Task/project not found locally - sync first
        print("[PUSH_NAVIGATION] Task not found locally, triggering sync...")
        await syncAndOpenTask(taskId: taskId, projectId: projectId)
    }

    /// Sync data and then open project details
    private func syncAndOpenProject(projectId: String) async {
        print("[PUSH_NAVIGATION] Starting sync for project: \(projectId)")

        // Perform a full sync via DataController
        await dataController.triggerFullSync()

        // Small delay for SwiftData to process
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Try to open the project again
        await MainActor.run {
            if dataController.getProject(id: projectId) != nil {
                print("[PUSH_NAVIGATION] Project found after sync, opening")
                appState.viewProjectDetailsById(projectId)
            } else {
                print("[PUSH_NAVIGATION] Project still not found after sync")
            }
        }
    }

    /// Sync data and then open task details
    private func syncAndOpenTask(taskId: String, projectId: String) async {
        print("[PUSH_NAVIGATION] Starting sync for task: \(taskId)")

        // Perform a full sync via DataController
        await dataController.triggerFullSync()

        // Small delay for SwiftData to process
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Try to open the task again
        await MainActor.run {
            if let project = dataController.getProject(id: projectId),
               project.tasks.contains(where: { $0.id == taskId }) {
                print("[PUSH_NAVIGATION] Task found after sync, opening")
                NotificationCenter.default.post(
                    name: Notification.Name("ShowTaskDetailsFromHome"),
                    object: nil,
                    userInfo: ["taskID": taskId, "projectID": projectId]
                )
            } else {
                print("[PUSH_NAVIGATION] Task still not found after sync")
            }
        }
    }
}
