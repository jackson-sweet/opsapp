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
    @StateObject private var inProgressManager = InProgressManager()
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
            print("HomeView: StopRouting notification received - stopping routing only")
            
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
            print("HomeView: onAppear - location status: \(locationStatus.rawValue)")
            
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
                print("HomeView: Location denied status changed to \(isDenied), showing alert")
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
                
                print("HomeView: activeProjectID changed and isInProjectMode=true")
                // No manual zoom logic needed - ProjectMapView handles this automatically
                
            } else if newProjectID == nil {
                print("HomeView: activeProjectID cleared, stopping routing")
                // Stop routing and timer when exiting project mode
                inProgressManager.stopRouting()
                stopRouteRefreshTimer()
                showFullDirectionsView = false
                
                // Reset the flag when exiting project mode
                userStoppedRouting = false
            } else {
                print("HomeView: activeProjectID changed but isInProjectMode=false")
                
                // Reset the flag when changing projects
                userStoppedRouting = false
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, newStatus in
            // Handle permission changes
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                print("HomeView: Location permission granted - no automatic routing")
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
            print("HomeView: Received notification to stop routing")
            inProgressManager.stopRouting()
            userStoppedRouting = true
            stopRouteRefreshTimer()
            showFullDirectionsView = false
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StartRouteRefreshTimer"))) { _ in
            print("HomeView: Received notification to start route refresh timer")
            startRouteRefreshTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StopRouteRefreshTimer"))) { _ in
            print("HomeView: Received notification to stop route refresh timer")
            stopRouteRefreshTimer()
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadTodaysProjects() {
        isLoading = true
        
        Task {
            let today = Calendar.current.startOfDay(for: Date())
            
            // Get projects for today that are assigned to the current user
            let userProjects = dataController.getProjects(
                for: today,
                assignedTo: dataController.currentUser
            )
            
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
        // Enter project mode
        print("HomeView: Starting project \(project.id)")
        appState.enterProjectMode(projectID: project.id)
        showStartConfirmation = false
        
        // Reset the user stopped routing flag for new project
        userStoppedRouting = false
        
        // Start route refresh timer when starting project
        startRouteRefreshTimer()
        
        // Update project status to 'in progress'
        if project.status != .inProgress {
            Task {
                do {
                    // Use the new API endpoint to start the project
                    print("HomeView: Updating project status to 'In Progress' via API")
                    let updatedStatus = try await dataController.apiService.startProject(id: project.id)
                    
                    print("HomeView: Project status updated successfully to: \(updatedStatus)")
                    
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
            print("HomeView: ⚠️ Location permission already denied, showing permission view immediately")
            showLocationPermissionView = true
        } else if locationManager.authorizationStatus == .notDetermined {
            print("HomeView: 🆕 Location permission not determined yet, showing permission view")
            showLocationPermissionView = true
        }
        
        // Always request location permission when starting a project
        locationManager.requestPermissionIfNeeded(requestAlways: true)
        
        // Start routing if we have coordinates and permissions
        if let coordinate = project.coordinate {
            switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                print("HomeView: Location permission granted, starting routing")
                if let userLocation = locationManager.userLocation {
                    inProgressManager.startRouting(to: coordinate, from: userLocation)
                } else {
                    inProgressManager.startRouting(to: coordinate)
                }
                
                // Start the route refresh timer for live navigation updates
                startRouteRefreshTimer()
                
            case .notDetermined:
                print("HomeView: Requesting location permission for the first time")
                
            case .denied, .restricted:
                print("HomeView: Location permission denied, alert already shown")
                
            @unknown default:
                print("HomeView: Unknown location authorization status")
            }
        } else {
            print("HomeView: Project has no coordinate")
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
        
        print("HomeView: Started route refresh timer at \(routeRefreshInterval) second intervals")
    }
    
    private func stopRouteRefreshTimer() {
        routeRefreshTimer?.invalidate()
        routeRefreshTimer = nil
        print("HomeView: Stopped route refresh timer")
    }
    
    private func refreshRouteIfNeeded() {
        // Only refresh if we're actively routing
        guard appState.isInProjectMode, inProgressManager.isRouting else { return }
        
        // Update navigation step with current user location if available
        if let userLocation = locationManager.userLocation {
            inProgressManager.updateNavigationStep(with: userLocation)
        }
        
        // Don't refresh the entire route - just update navigation steps
        print("HomeView: Updated navigation step based on current location")
    }
    
    private func getActiveProject() -> Project? {
        guard let projectId = appState.activeProjectID else { return nil }
        return todaysProjects.first { $0.id == projectId }
    }
}