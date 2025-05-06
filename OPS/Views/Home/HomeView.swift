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
    @StateObject private var locationManager = LocationManager()
    
    // Track location manager status changes
    @State private var locationStatus: CLAuthorizationStatus = .notDetermined
    
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.4132, longitude: -123.3650),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var todaysProjects: [Project] = []
    @State private var selectedProjectIndex = 0
    @State private var showStartConfirmation = false
    @State private var isLoading = true
    @State private var showLocationPrompt = false
    @State private var showLocationPermissionView = false
    
    // Route refresh timer
    @State private var routeRefreshTimer: Timer? = nil
    private let routeRefreshInterval: TimeInterval = 30 // seconds
    @State private var showFullDirectionsView = false
    
    var body: some View {
        // Extract to smaller components to help compiler
        HomeContentView(
            mapRegion: $mapRegion,
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
        // No longer need the failsafe since we're properly handling details view via appState
// We now use appState.activeProject and appState.showProjectDetails for details
        // COMPLETELY REMOVE SHEET PRESENTATION
// .sheet was here - REMOVED
// This disables the project details presentation completely
        .preferredColorScheme(.dark) // Enforce dark mode for the entire view
        // Listen for complete project stop
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("EndNavigation"))) { _ in
            if let activeProject = getActiveProject() {
                stopProject(activeProject)
            }
        }
        // Listen for navigation stop only (keep project active)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StopRouting"))) { _ in
            // Only stop routing without ending project
            inProgressManager.stopRouting()
            showFullDirectionsView = false
            
            // Reset zoom flag to allow normal map region updates again
            hasSetInitialZoom = false
            
            // Reset map to show active project if there is one
            if let projectId = appState.activeProjectID,
               let project = todaysProjects.first(where: { $0.id == projectId }) {
                updateMapRegion(for: project)
            }
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
        .onChange(of: appState.activeProjectID) { _, newProjectID in
            // ⭐️ CHECK if we're actually in project mode, not just viewing details
            if let newProjectID = newProjectID,
               let project = todaysProjects.first(where: { $0.id == newProjectID }),
               let coordinate = project.coordinate,
               appState.isInProjectMode {  // ⭐️ CRITICAL: Only do routing if actually in project mode
                
                print("HomeView: activeProjectID changed and isInProjectMode=true, starting routing")
                
                // Start route refresh timer when entering project mode
                startRouteRefreshTimer()
                
                // Check location permission before routing
                if locationManager.authorizationStatus == .authorizedWhenInUse ||
                   locationManager.authorizationStatus == .authorizedAlways {
                    // Start routing with user's location
                    if let userLocation = locationManager.userLocation {
                        inProgressManager.startRouting(to: coordinate, from: userLocation)
                        
                        // IMPORTANT: Zoom to user location for navigation
                        zoomToShowRoute(from: userLocation, to: coordinate)
                    } else {
                        inProgressManager.startRouting(to: coordinate)
                        
                        // Just zoom to destination if user location not available
                        updateMapRegion(for: project)
                    }
                } else if locationManager.authorizationStatus == .notDetermined {
                    // Show the permission view
                    showLocationPermissionView = true
                } else if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                    // Show the permission view for denied state
                    showLocationPermissionView = true
                }
            } else if newProjectID == nil {
                print("HomeView: activeProjectID cleared, stopping routing")
                // Stop routing and timer when exiting project mode
                inProgressManager.stopRouting()
                stopRouteRefreshTimer()
                showFullDirectionsView = false
            } else {
                print("HomeView: activeProjectID changed but isInProjectMode=false, NOT starting routing")
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, newStatus in
            // Handle permission changes
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                // Permission granted - start routing if in project mode
                if let projectId = appState.activeProjectID,
                   let project = todaysProjects.first(where: { $0.id == projectId }),
                   let coordinate = project.coordinate,
                   appState.isInProjectMode {  // ⭐️ Only if actually in project mode
                    
                    print("HomeView: Location permission granted and isInProjectMode=true, starting routing")
                    
                    if let userLocation = locationManager.userLocation {
                        inProgressManager.startRouting(to: coordinate, from: userLocation)
                        
                        // IMPORTANT: Zoom to user location for navigation
                        zoomToShowRoute(from: userLocation, to: coordinate)
                    } else {
                        inProgressManager.startRouting(to: coordinate)
                        
                        // Just zoom to destination if user location not available
                        updateMapRegion(for: project)
                    }
                } else if let projectId = appState.activeProjectID, 
                          !appState.isInProjectMode {
                    print("HomeView: Location permission granted but isInProjectMode=false, NOT starting routing")
                }
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
                
                // Replace the existing map region update code with this:
                            if !todaysProjects.isEmpty {
                                // Use the static method from ProjectMapView to ensure all markers are visible
                                mapRegion = ProjectMapView.calculateVisibleRegion(for: todaysProjects)
                            }
                            
                            // Setup active project if needed (keep this part)
                            if let activeProjectID = appState.activeProjectID,
                               let index = todaysProjects.firstIndex(where: { $0.id == activeProjectID }) {
                                self.selectedProjectIndex = index
                                setupRouting(for: todaysProjects[index])
                            }
                
                self.isLoading = false
            }
        }
    }
    

    // Helper method to clean up routing setup
    private func setupRouting(for project: Project) {
        guard let coordinate = project.coordinate,
              locationManager.authorizationStatus == .authorizedWhenInUse ||
              locationManager.authorizationStatus == .authorizedAlways else {
            return
        }
        
        if let userLocation = locationManager.userLocation {
            inProgressManager.startRouting(to: coordinate, from: userLocation)
        } else {
            inProgressManager.startRouting(to: coordinate)
        }
    }
    
    private func updateMapRegion(for project: Project) {
        guard let coordinate = project.coordinate else { return }
        
        // Skip if we've already set a custom zoom for navigation
        if hasSetInitialZoom {
            print("HomeView: Skipping map region update - already zoomed for navigation")
            return
        }
        
        // Update map region with animation for better user experience
        print("HomeView: Updating map region to show project")
        withAnimation(.easeInOut(duration: 0.5)) {
            mapRegion = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
    }
    
    private func updateMapRegion(for projects: [Project]) {
        let coordinates = projects.compactMap { $0.coordinate }
        guard !coordinates.isEmpty else { return }
        
        // Skip if we've already set a custom zoom for navigation
        if hasSetInitialZoom {
            print("HomeView: Skipping projects map region update - already zoomed for navigation")
            return
        }
        
        if coordinates.count == 1 {
            updateMapRegion(for: projects[0])
            return
        }
        
        // Find bounds for all projects
        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0
        
        // Add padding
        let padding = 0.02
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) + padding),
            longitudeDelta: max(0.01, (maxLon - minLon) + padding)
        )
        
        // Update map region with animation
        print("HomeView: Updating map region to show all projects")
        withAnimation(.easeInOut(duration: 0.5)) {
            mapRegion = MKCoordinateRegion(center: center, span: span)
        }
    }
    
    // Track when we've set a custom zoom region
    @State private var hasSetInitialZoom = false
    
    // Zoom map to show user location for effective navigation
    private func zoomToShowRoute(from userLocation: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) {
        print("HomeView: Zooming to user location for navigation")
        
        // Set flag to prevent other code from overriding our zoom
        hasSetInitialZoom = true
        
        // First, create a starting wide-view region (if we're not already zoomed in)
        let initialRegion = mapRegion
        
        // Then define our target close-up region focused on user location for navigation
        let closeZoom = MKCoordinateRegion(
            center: userLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005) // Street-level detail
        )
        
        // Use a two-step animation for a more engaging zoom effect
        // Step 1: Transition to the location with a slight zoom
        let intermediateRegion = MKCoordinateRegion(
            center: userLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02) // Medium zoom level
        )
        
        // First animation - center on location
        withAnimation(.easeInOut(duration: 0.5)) {
            mapRegion = intermediateRegion
        }
        
        // Step 2: Zoom in further after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Second animation - zoom in closer
            withAnimation(.easeOut(duration: 1.0)) {
                mapRegion = closeZoom
            }
        }
    }
    
    // Calculate distance between two coordinates in meters
    private func calculateDistance(from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> CLLocationDistance {
        let sourceLocation = CLLocation(latitude: source.latitude, longitude: source.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return sourceLocation.distance(from: destinationLocation)
    }
    
    
    private func startProject(_ project: Project) {
        // Enter project mode
        print("HomeView: Starting project \(project.id)")
        appState.enterProjectMode(projectID: project.id)
        // Debug check if we're in project mode
        print("HomeView: After enterProjectMode - isInProjectMode: \(appState.isInProjectMode), activeProjectID: \(String(describing: appState.activeProjectID))")
        showStartConfirmation = false
        
        // Update project status
        if project.status != .inProgress {
            Task {
                dataController.syncManager.updateProjectStatus(
                    projectId: project.id,
                    status: .inProgress
                )
            }
        }
        
        // CRITICAL: Check for denied permissions first for immediate feedback
        if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
            print("HomeView: ⚠️ Location permission already denied, showing permission view immediately")
            showLocationPermissionView = true
            // Still continue with the project but without location features
        } else if locationManager.authorizationStatus == .notDetermined {
            // First time permission request - show our custom UI
            print("HomeView: 🆕 Location permission not determined yet, showing permission view")
            showLocationPermissionView = true
        }
        
        // ALWAYS request location permission when starting a project
        locationManager.requestPermissionIfNeeded(requestAlways: true)
        
        // Try to start routing if we have coordinates
        if let coordinate = project.coordinate {
            // Check permission status
            switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                // We have permission - start routing
                print("HomeView: Location permission granted, starting routing")
                if let userLocation = locationManager.userLocation {
                    inProgressManager.startRouting(to: coordinate, from: userLocation)
                    
                    // Zoom to show both user location and destination
                    zoomToShowRoute(from: userLocation, to: coordinate)
                } else {
                    inProgressManager.startRouting(to: coordinate)
                    
                    // Just zoom to destination if user location not available
                    updateMapRegion(for: project)
                }
                
            case .notDetermined:
                // First-time request - we'll handle in the onChange handler when user responds
                print("HomeView: Requesting location permission for the first time")
                
            case .denied, .restricted:
                // Already handled above - just log
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
        
        // Reset zoom flag to allow normal map region updates
        hasSetInitialZoom = false
        
        // Return to overall project view
        if !todaysProjects.isEmpty {
            updateMapRegion(for: todaysProjects)
        }
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
        
        print("HomeView: Refreshing route automatically")
        inProgressManager.refreshRoute()
    }
    
    private func getActiveProject() -> Project? {
        guard let projectId = appState.activeProjectID else { return nil }
        return todaysProjects.first { $0.id == projectId }
    }
}
