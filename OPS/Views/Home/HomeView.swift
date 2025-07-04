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
    @State private var todaysProjects: [Project] = []
    @State private var selectedProjectIndex = 0
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
            todaysProjects: todaysProjects,
            selectedProjectIndex: $selectedProjectIndex,
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
        .preferredColorScheme(.dark) // Enforce dark mode for the entire view
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
            if let project = notification.userInfo?["project"] as? Project {
                print("🟢 HomeView: Received StartProjectFromMap for: \(project.title)")
                // Find and select the project
                if let index = todaysProjects.firstIndex(where: { $0.id == project.id }) {
                    selectedProjectIndex = index
                    // Start the project
                    startProject(project)
                }
            }
        }
        .onAppear {
            loadTodaysProjects()
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
            
            // Get projects for today based on user role
            let userProjects = dataController.getProjectsForCurrentUser(for: today)
            
            await MainActor.run {
                self.todaysProjects = userProjects
                
                // No manual map region calculation needed - ProjectMapView handles all zoom automatically
                
                // Setup active project if needed
                if let activeProjectID = appState.activeProjectID,
                   let index = todaysProjects.firstIndex(where: { $0.id == activeProjectID }) {
                    self.selectedProjectIndex = index
                }
                
                self.isLoading = false
            }
        }
    }
    
    private func startProject(_ project: Project) {
        print("🟢 HomeView: startProject called for: \(project.title)")
        
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
                    print("HomeView: ⚠️ API call failed, using SyncManager as fallback: \(error.localizedDescription)")
                    dataController.syncManager.updateProjectStatus(
                        projectId: project.id,
                        status: .inProgress,
                        forceSync: true
                    )
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
            print("🟢 HomeView: Project has coordinates, checking location permissions...")
            print("🟢 HomeView: Location authorization status: \(locationManager.authorizationStatus)")
            
            switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                print("🟢 HomeView: Location authorized, starting routing...")
                
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
                print("⚠️ HomeView: Location permission not determined")
                break
                
            case .denied, .restricted:
                print("⚠️ HomeView: Location permission denied or restricted")
                break
                
            @unknown default:
                break
            }
        } else {
            print("⚠️ HomeView: Project has no coordinates")
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