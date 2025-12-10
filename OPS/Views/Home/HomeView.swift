//
//  HomeView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//

import SwiftUI
import MapKit

struct HomeView: View {
    
    @State private var showProjectDetails = false
    @State private var selectedProject: Project? // Not used anymore but keeping for backward compatibility
    
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @StateObject private var inProgressManager = InProgressManager.shared
    @EnvironmentObject private var locationManager: LocationManager
    
    // Track location manager status changes
    @State private var locationStatus: CLAuthorizationStatus = .notDetermined
    
    // No map region state needed - ProjectMapView manages internally
    @State private var todaysCalendarEvents: [CalendarEvent] = []
    @State private var todaysProjects: [Project] = [] // Keep for map display
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
            todaysCalendarEvents: todaysCalendarEvents,
            todaysProjects: todaysProjects,
            selectedEventIndex: $selectedEventIndex,
            showStartConfirmation: $showStartConfirmation,
            selectedProject: $selectedProject,
            showFullDirectionsView: $showFullDirectionsView,
            isLoading: isLoading,
            showLocationPermissionView: $showLocationPermissionView,
            appState: appState,
            inProgressManager: inProgressManager,
            startProject: startProject,
            stopProject: stopProject,
            getActiveProject: getActiveProject
        )
        .environmentObject(locationManager)
        .environmentObject(dataController)
        .preferredColorScheme(.dark) // Enforce dark mode for the entire view
        // Listen for task navigation from event carousel
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowCalendarTaskDetails"))) { notification in
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
            // Track screen view for analytics
            AnalyticsManager.shared.trackScreenView(screenName: .home, screenClass: "HomeView")

            // Initialize location status
            locationStatus = locationManager.authorizationStatus

            // Load projects
            loadTodaysProjects()

            // Debug log

            // Set up periodic route refreshes for navigation
            if appState.isInProjectMode {
                // Schedule route refresh every 30 seconds while in project mode
                startRouteRefreshTimer()
            }
        }
        .onDisappear {
            // Clean up any timers
            stopRouteRefreshTimer()
        }
        // Watch for changes to locationManager's denied state
        .onChange(of: locationManager.isLocationDenied) { _, isDenied in
            if isDenied && (appState.isInProjectMode || showStartConfirmation) {
                showLocationPermissionView = true
            }
        }
        // Watch for initial sync completion to refresh projects
        .onChange(of: dataController.isPerformingInitialSync) { oldValue, newValue in
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
        .onReceive(NotificationCenter.default.publisher(for: .locationDidChange)) { _ in
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StartRouteRefreshTimer"))) { _ in
            startRouteRefreshTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StopRouteRefreshTimer"))) { _ in
            stopRouteRefreshTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StartProjectFromMap"))) { notification in
            if let projectId = notification.userInfo?["projectId"] as? String,
               let project = dataController.getProject(id: projectId) {
                // Find and select the event for this project
                if let index = todaysCalendarEvents.firstIndex(where: { $0.projectId == projectId }) {
                    selectedEventIndex = index
                    // Start the project
                    startProject(project)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Reload projects when app returns to foreground
            loadTodaysProjects()
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadTodaysProjects() {
        isLoading = true
        
        Task {
            let today = Calendar.current.startOfDay(for: Date())
            
            // Get calendar events for today
            let calendarEvents = dataController.getCalendarEventsForCurrentUser(for: today)
            
            // Extract unique projects from calendar events
            var uniqueProjects: [Project] = []
            var seenProjectIds = Set<String>()
            
            for event in calendarEvents {
                if !seenProjectIds.contains(event.projectId),
                   let project = dataController.getProject(id: event.projectId) {
                    seenProjectIds.insert(event.projectId)
                    uniqueProjects.append(project)
                }
            }
            
            await MainActor.run {
                self.todaysCalendarEvents = calendarEvents
                self.todaysProjects = uniqueProjects
                
                // No manual map region calculation needed - ProjectMapView handles all zoom automatically
                
                // Setup active event if needed
                if let activeProjectID = appState.activeProjectID,
                   let index = todaysCalendarEvents.firstIndex(where: { $0.projectId == activeProjectID }) {
                    self.selectedEventIndex = index
                }
                
                self.isLoading = false
            }
        }
    }
    
    private func startProject(_ project: Project) {
        
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
                    // Use the new API endpoint to start the project
                    let updatedStatus = try await dataController.apiService.startProject(id: project.id)
                    
                    
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
                    // If API call fails, fall back to local update via SyncManager
                    Task {
                        try? await dataController.syncManager.updateProjectStatus(
                            projectId: project.id,
                            status: .inProgress,
                            forceSync: true
                        )
                    }
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