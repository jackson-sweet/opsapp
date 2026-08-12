//
//  HomeView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//

import SwiftUI
import MapKit
import SwiftData

struct HomeView: View {
    
    @State private var showProjectDetails = false
    @State private var selectedProject: Project? // Not used anymore but keeping for backward compatibility

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.tutorialMode) private var tutorialMode
    /// Home stays mounted for the whole session (MainTabView's keep-alive tab
    /// container), so every per-visit side effect keys off this instead of
    /// `onAppear`, and every hidden-tab trigger bails rather than burning a
    /// full-table fetch nobody can see.
    @Environment(\.isActiveTab) private var isActiveTab
    @StateObject private var inProgressManager = InProgressManager.shared
    @EnvironmentObject private var locationManager: LocationManager
    
    // Track location manager status changes
    @State private var locationStatus: CLAuthorizationStatus = .notDetermined
    
    // No map region state needed - ProjectMapView manages internally
    @State private var todaysScheduledTasks: [ProjectTask] = []
    @State private var todaysProjects: [Project] = [] // Keep for carousel display
    @State private var allProjects: [Project] = [] // All projects for map "All" filter
    @State private var billableRollup: HomeBillableThisWeekRollup = .empty
    @State private var projectsNeedingTasksCount = 0
    @State private var selectedEventIndex = 0
    @State private var showStartConfirmation = false
    @State private var isLoading = true
    @State private var showLocationPrompt = false
    @State private var showLocationPermissionView = false
    
    // Route refresh timer
    @State private var routeRefreshTimer: Timer? = nil
    private let routeRefreshInterval: TimeInterval = 3 // seconds - shorter interval for live navigation
    @State private var showFullDirectionsView = false
    
    // Flag to track if user manually stopped routing for this project
    @State private var userStoppedRouting = false
    
    var body: some View {
        // Extract to smaller components to help compiler
        HomeContentView(
            todaysScheduledTasks: todaysScheduledTasks,
            todaysProjects: todaysProjects,
            allProjects: allProjects,
            selectedEventIndex: $selectedEventIndex,
            showStartConfirmation: $showStartConfirmation,
            selectedProject: $selectedProject,
            showFullDirectionsView: $showFullDirectionsView,
            isLoading: isLoading,
            showLocationPermissionView: $showLocationPermissionView,
            billableRollup: billableRollup,
            projectsNeedingTasksCount: projectsNeedingTasksCount,
            appState: appState,
            inProgressManager: inProgressManager,
            startProject: startProject,
            stopProject: stopProject,
            getActiveProject: getActiveProject,
            openBillableItem: openBillableItem,
            openProjectsNeedingTasks: { appState.showProjectsNeedingTasksReview = true }
        )
        // The needs-tasks strip must clear the moment the operator plans the
        // work: recompute when the review sheet dismisses (tasks were just
        // created into the local store, no sync round-trip needed).
        .onChange(of: appState.showProjectsNeedingTasksReview) { _, showing in
            // Sheet is hosted at the app root, so it can close over any tab.
            // A hidden Home picks the new count up from its activation refresh.
            guard !showing, isActiveTab else { return }
            projectsNeedingTasksCount = ProjectsWithoutTasksDetector
                .projectsWithoutTasks(from: dataController.getProjectsForCurrentUser(for: nil))
                .count
        }
        .trackScreen("Home")
        .environmentObject(locationManager)
        .environmentObject(dataController)
        .preferredColorScheme(.dark) // Enforce dark mode for the entire view
        // Listen for task navigation from event carousel
        // Schedule's day/month grids post this too and ScheduleView answers it
        // as well — only the tab on screen may present the task.
        .onReceiveWhileActive(NotificationCenter.default.publisher(for: Notification.Name("ShowCalendarTaskDetails"))) { notification in
            if let userInfo = notification.userInfo,
               let taskID = userInfo["taskID"] as? String,
               let projectID = userInfo["projectID"] as? String {
                
                // Find the project and task
                if let project = dataController.getProject(id: projectID),
                   let task = project.tasks.first(where: { $0.id == taskID }) {
                    // Show task details using appState
                    appState.viewTaskDetails(task: task, project: project)
                }
            }
        }
        // Listen for task navigation start
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StartTaskNavigation"))) { notification in
            if let userInfo = notification.userInfo,
               let taskId = userInfo["taskId"] as? String,
               let projectId = userInfo["projectId"] as? String,
               let project = dataController.getProject(id: projectId),
               let task = project.tasks.first(where: { $0.id == taskId }) {

                // Start routing to the project location (tasks use project location)
                if let coordinate = project.coordinate,
                   let userLocation = locationManager.userLocation {
                    inProgressManager.startRouting(to: coordinate, from: userLocation)

                    // Also notify MapCoordinator to start navigation
                    NotificationCenter.default.post(
                        name: Notification.Name("StartNavigation"),
                        object: nil,
                        userInfo: ["projectId": projectId]
                    )
                }

                // Hide confirmation
                showStartConfirmation = false

                // Start route refresh timer
                startRouteRefreshTimer()
            }
        }
        // Listen for complete project stop
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("EndNavigation"))) { _ in
            if let activeProject = getActiveProject() {
                stopProject(activeProject)
            }
        }
        // Listen for navigation stop only (keep project active)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StopRouting"))) { _ in
            
            // Stop routing but keep project active
            inProgressManager.stopRouting()
            showFullDirectionsView = false
            stopRouteRefreshTimer()
            
            // Mark that user manually stopped routing to prevent auto-restart
            userStoppedRouting = true
        }
        .onAppear {
            // First visit only. Mount and activation coincide here, so the
            // per-visit work runs once from this handler and `isActiveTab`
            // carries every visit after it — no double-fire.
            locationStatus = locationManager.authorizationStatus
            beginVisit()
            loadTodaysProjects()
        }
        .onDisappear {
            endVisit()
        }
        // Every return to Home. The refresh is silent: the data is already on
        // screen from the last visit, so re-showing the loading state would
        // both flash the carousel and, through `appState.isLoadingProjects`,
        // blink the tab bar and FAB out on every single visit.
        .onChange(of: isActiveTab) { _, active in
            if active {
                beginVisit()
                loadTodaysProjects(silent: true)
            } else {
                endVisit()
            }
        }
        // Watch for changes to locationManager's denied state
        .onChange(of: locationManager.isLocationDenied) { _, isDenied in
            if isDenied && (appState.isInProjectMode || showStartConfirmation) {
                showLocationPermissionView = true
            }
        }
        // Watch for initial sync completion to refresh projects
        .onChange(of: dataController.isPerformingInitialSync) { oldValue, newValue in
            // A hidden Home picks this up from its activation refresh instead.
            guard isActiveTab else { return }
            if oldValue == true && newValue == false {
                // Sync just completed, reload today's projects
                print("[HOME] 🔄 Initial sync completed, reloading today's projects")
                loadTodaysProjects()
            }
        }
        // Sync loading state with appState
        .onChange(of: isLoading) { _, newValue in
            appState.isLoadingProjects = newValue
        }
        // Use onReceive with NotificationCenter for location changes
        .onReceiveWhileActive(NotificationCenter.default.publisher(for: .locationDidChange)) { _ in
            if inProgressManager.isRouting, 
               appState.isInProjectMode, 
               let location = locationManager.userLocation {
                inProgressManager.updateNavigationStep(with: location)
            }
        }
        // Note: StopRouting notifications are handled above to avoid duplication
        .onChange(of: appState.activeProjectID) { _, newProjectID in
            if let newProjectID = newProjectID,
               let _ = todaysProjects.first(where: { $0.id == newProjectID }),
               appState.isInProjectMode {
                
                // No manual zoom logic needed - ProjectMapView handles this automatically
                
            } else if newProjectID == nil {
                // Stop routing and timer when exiting project mode
                inProgressManager.stopRouting()
                stopRouteRefreshTimer()
                showFullDirectionsView = false
                
                // Reset the flag when exiting project mode
                userStoppedRouting = false
            } else {
                
                // Reset the flag when changing projects
                userStoppedRouting = false
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, newStatus in
            // Handle permission changes
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                // Don't automatically start routing when permission is granted
                // User must explicitly start navigation
            } else if newStatus == .denied || newStatus == .restricted {
                // Show location permission view if in project mode or trying to start a project
                if appState.isInProjectMode || showStartConfirmation {
                    showLocationPermissionView = true
                }
            }
        }
        // Add the location permission overlay
        .locationPermissionOverlay(
            isPresented: $showLocationPermissionView,
            locationManager: locationManager,
            onRequestPermission: {
                // Request location permissions when the user taps the button
                locationManager.requestPermissionIfNeeded(requestAlways: true)
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StopRouting"))) { _ in
            inProgressManager.stopRouting()
            userStoppedRouting = true
            stopRouteRefreshTimer()
            showFullDirectionsView = false
        }
        // Posted by ProjectActionBar, which lives in a root-level sheet that
        // opens over any tab. `beginVisit` restarts the timer when Home comes
        // back on screen, so a hidden Home never runs one.
        .onReceiveWhileActive(NotificationCenter.default.publisher(for: Notification.Name("StartRouteRefreshTimer"))) { _ in
            startRouteRefreshTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StopRouteRefreshTimer"))) { _ in
            stopRouteRefreshTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StartProjectFromMap"))) { notification in
            if let projectId = notification.userInfo?["projectId"] as? String,
               let project = dataController.getProject(id: projectId) {
                // Find and select the event for this project
                if let index = todaysScheduledTasks.firstIndex(where: { $0.projectId == projectId }) {
                    selectedEventIndex = index
                    // Start the project
                    startProject(project)
                }
            }
        }
        .onReceiveWhileActive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Reload projects when app returns to foreground. A backgrounded
            // Home that is not the visible tab refreshes on its next visit.
            loadTodaysProjects()
        }
    }
    
    // MARK: - Helper Methods
    
    /// Screen-view analytics + live-navigation refresh are while-you-are-looking
    /// concerns: they start when Home comes on screen and stop when it leaves,
    /// exactly as they did when a tab switch tore the view down.
    private func beginVisit() {
        AnalyticsManager.shared.trackScreenView(screenName: .home, screenClass: "HomeView")
        AnalyticsService.shared.trackScreenView(screenName: "home")
        if appState.isInProjectMode {
            startRouteRefreshTimer()
        }
    }

    private func endVisit() {
        stopRouteRefreshTimer()
        AnalyticsService.shared.endScreenView(screenName: "home")
    }

    /// `silent` skips the loading state so a refresh over data already on
    /// screen never flashes the carousel or, via `appState.isLoadingProjects`,
    /// the tab bar and FAB.
    private func loadTodaysProjects(silent: Bool = false) {
        if !silent { isLoading = true }

        Task {
            let today = Calendar.current.startOfDay(for: Date())

            // Get scheduled tasks for today (tasks with dates spanning today)
            var scheduledTasks = dataController.getScheduledTasksForCurrentUser(for: today)

            // Tutorial mode only shows demo tasks/projects
            if tutorialMode {
                scheduledTasks = scheduledTasks.filter { $0.id.hasPrefix("DEMO_") }
            }

            // Extract unique projects from scheduled tasks
            var uniqueProjects: [Project] = []
            var seenProjectIds = Set<String>()

            for task in scheduledTasks {
                if !seenProjectIds.contains(task.projectId),
                   let project = dataController.getProject(id: task.projectId) {
                    // In tutorial mode, only include demo projects
                    if tutorialMode && !project.id.hasPrefix("DEMO_") {
                        continue
                    }
                    seenProjectIds.insert(task.projectId)
                    uniqueProjects.append(project)
                }
            }

            // Also load all projects (no date filter) for the map's "All" mode
            var everyProject = dataController.getProjectsForCurrentUser(for: nil)
            if tutorialMode {
                everyProject = everyProject.filter { $0.id.hasPrefix("DEMO_") }
            }

            // Merge in projects from the user's scheduled tasks that may not appear
            // in getProjectsForCurrentUser (e.g., field crew assigned to a task but
            // not a project team member). This ensures the Today filter on the map
            // shows pins for all projects where the user has tasks.
            let existingIds = Set(everyProject.map { $0.id })
            for project in uniqueProjects {
                if !existingIds.contains(project.id) {
                    everyProject.append(project)
                }
            }
            let billableRollup = computeBillableRollup(projects: everyProject)
            // Accepted / in-progress projects nobody has broken into tasks —
            // committed work the crew can't see. Data self-scopes: task-less
            // projects have no derived members, so only full-visibility
            // operators ever get a non-zero count. Tutorial demo data is
            // excluded with the same filter as everything else here.
            let needsTasksCount = tutorialMode
                ? 0
                : ProjectsWithoutTasksDetector.projectsWithoutTasks(from: everyProject).count

            await MainActor.run {
                self.todaysScheduledTasks = scheduledTasks
                self.todaysProjects = uniqueProjects
                self.allProjects = everyProject
                self.billableRollup = billableRollup
                self.projectsNeedingTasksCount = needsTasksCount
                HomeBillableThisWeekNotificationDispatcher.dispatchIfNeeded(
                    rollup: billableRollup,
                    userId: dataController.currentUser?.id,
                    companyId: dataController.currentUser?.companyId,
                    permissionCanViewFinances: !tutorialMode && permissionStore.can("finances.view"),
                    onNotificationCreated: {
                        appState.refreshUnreadCount()
                    }
                )

                // Setup active task if needed
                if let activeProjectID = appState.activeProjectID,
                   let index = todaysScheduledTasks.firstIndex(where: { $0.projectId == activeProjectID }) {
                    self.selectedEventIndex = index
                }

                if !silent { self.isLoading = false }
            }
        }
    }

    private func computeBillableRollup(projects: [Project]) -> HomeBillableThisWeekRollup {
        guard let context = dataController.modelContext else { return .empty }
        let companyId = dataController.currentUser?.companyId

        // Both gates ride the fetch rather than a Swift filter. This runs on
        // every Home load — mount, foreground, sync completion, and now every
        // return to the tab — and it used to materialize every invoice and
        // every estimate the device has ever stored, including other companies'
        // rows and tombstones, only to drop most of them.
        //
        // The soft-delete gate is not new behavior: `HomeBillableThisWeekRollupEngine`
        // already dropped `deletedAt != nil` rows before grouping. It moves here
        // so those rows are never materialized in the first place. The company
        // gate keeps its old "no company id means no filter" reading.
        var invoiceDescriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate<Invoice> { $0.deletedAt == nil }
        )
        var estimateDescriptor = FetchDescriptor<Estimate>(
            predicate: #Predicate<Estimate> { $0.deletedAt == nil }
        )
        if let companyId {
            invoiceDescriptor.predicate = #Predicate<Invoice> {
                $0.deletedAt == nil && $0.companyId == companyId
            }
            estimateDescriptor.predicate = #Predicate<Estimate> {
                $0.deletedAt == nil && $0.companyId == companyId
            }
        }
        let invoices = (try? context.fetch(invoiceDescriptor)) ?? []
        let estimates = (try? context.fetch(estimateDescriptor)) ?? []

        return HomeBillableThisWeekRollupEngine.compute(
            projects: projects,
            invoices: invoices,
            estimates: estimates,
            today: Date()
        )
    }

    private func openBillableItem(_ item: HomeBillableProjectCandidate) {
        if let invoiceId = item.invoiceId {
            appState.viewInvoiceDetailsById(invoiceId)
        } else if let estimateId = item.estimateId {
            appState.viewEstimateDetailsById(estimateId)
        } else if let project = allProjects.first(where: { $0.id == item.projectId }) {
            appState.viewProjectDetails(project)
        } else {
            appState.viewProjectDetailsById(item.projectId)
        }
    }
    
    private func startProject(_ project: Project) {

        // Tutorial mode: notify project tapped/started
        if tutorialMode {
            NotificationCenter.default.post(
                name: Notification.Name("TutorialProjectTapped"),
                object: nil
            )
        }

        // Enter project mode
        appState.enterProjectMode(projectID: project.id)
        showStartConfirmation = false
        
        // Cancel any pending notifications for this project since it's starting
        NotificationManager.shared.cancelProjectNotifications(projectId: project.id)
        
        // Reset the user stopped routing flag for new project
        userStoppedRouting = false
        
        // Start route refresh timer when starting project
        startRouteRefreshTimer()
        
        // Update project status to 'in progress'
        if project.status != .inProgress {
            Task {
                do {
                    try await dataController.updateProjectStatus(
                        project: project,
                        to: .inProgress
                    )

                    // Update local status immediately for UI consistency
                    await MainActor.run {
                        project.status = .inProgress
                        project.needsSync = false
                        project.lastSyncedAt = Date()

                        // Save to model context
                        if let modelContext = dataController.modelContext {
                            try? modelContext.save()
                        }
                    }
                } catch {
                    print("[START_PROJECT] Failed to update project status: \(error)")
                }
            }
        }
        
        // Handle location permissions
        if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
            showLocationPermissionView = true
        } else if locationManager.authorizationStatus == .notDetermined {
            showLocationPermissionView = true
        }
        
        // Always request location permission when starting a project
        locationManager.requestPermissionIfNeeded(requestAlways: true)
        
        // Start routing if we have coordinates and permissions
        if let coordinate = project.coordinate {
            
            switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                
                // Post notification to start navigation in the new map
                NotificationCenter.default.post(
                    name: Notification.Name("StartNavigation"),
                    object: nil,
                    userInfo: ["projectId": project.id]
                )
                
                // The new map will handle starting InProgressManager routing for consistency
                
                // Start the route refresh timer for live navigation updates
                startRouteRefreshTimer()
                
            case .notDetermined:
                break
                
            case .denied, .restricted:
                break
                
            @unknown default:
                break
            }
        } else {
        }
    }
    
    private func stopProject(_ project: Project) {
        appState.exitProjectMode()
        showStartConfirmation = false
        inProgressManager.stopRouting()
        stopRouteRefreshTimer()
        showFullDirectionsView = false
    }
    
    // MARK: - Timer Methods
    
    private func startRouteRefreshTimer() {
        // Stop any existing timer first
        stopRouteRefreshTimer()
        
        // Create new timer
        routeRefreshTimer = Timer.scheduledTimer(withTimeInterval: routeRefreshInterval, repeats: true) { _ in
            self.refreshRouteIfNeeded()
        }
        
        // Make sure it runs even when scrolling
        if let timer = routeRefreshTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        
    }
    
    private func stopRouteRefreshTimer() {
        routeRefreshTimer?.invalidate()
        routeRefreshTimer = nil
    }
    
    private func refreshRouteIfNeeded() {
        // Only refresh if we're actively routing
        guard appState.isInProjectMode, inProgressManager.isRouting else { return }
        
        // Update navigation step with current user location if available
        if let userLocation = locationManager.userLocation {
            inProgressManager.updateNavigationStep(with: userLocation)
        }
        
        // Don't refresh the entire route - just update navigation steps
    }
    
    private func getActiveProject() -> Project? {
        guard let projectId = appState.activeProjectID else { return nil }
        return todaysProjects.first { $0.id == projectId }
    }
}
