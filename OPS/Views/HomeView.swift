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
    @State private var selectedProject: Project?
    
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @StateObject private var inProgressManager = InProgressManager()
    @StateObject private var locationManager = LocationManager()
    
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.4132, longitude: -123.3650),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var todaysProjects: [Project] = []
    @State private var selectedProjectIndex = 0
    @State private var showStartConfirmation = false
    @State private var isLoading = true
    @State private var showLocationPrompt = false
    
    
    
    var body: some View {
        ZStack {
            // Map layer
            ZStack {
                ProjectMapView(
                    region: $mapRegion,
                    projects: todaysProjects,
                    selectedIndex: $selectedProjectIndex,
                    onTapMarker: { index in
                        withAnimation {
                            selectedProjectIndex = index
                            showStartConfirmation = false
                        }
                    },
                    routeOverlay: inProgressManager.getRouteOverlay(),
                    isInProjectMode: appState.isInProjectMode
                )
                
                // Semi-transparent dark overlay to match design
                Color.black.opacity(0.2)
                    .edgesIgnoringSafeArea(.all)
            }
            .edgesIgnoringSafeArea(.all)
            
            // UI overlay layers
            VStack(spacing: 0) {
                // Header layer
                UserHeader()
                /*
                 if appState.isInProjectMode {
                 ProjectHeader(project: getActiveProject())
                 } else {
                 UserHeader()
                 }
                 */
                // Project cards
                if !todaysProjects.isEmpty {
                    
                    ProjectCarousel(
                        projects: todaysProjects,
                        selectedIndex: $selectedProjectIndex,
                        showStartConfirmation: $showStartConfirmation,
                        isInProjectMode: appState.isInProjectMode,
                        activeProjectID: appState.activeProjectID,
                        onStart: startProject,
                        onStop: stopProject,
                        onLongPress: { project in
                            selectedProject = project
                            showProjectDetails = true
                        }
                    )
                } else if !isLoading {
                    // No projects message
                    VStack {
                        Text(AppConfiguration.UX.noProjectQuotes.randomElement() ?? "No projects scheduled for today")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(height: 120)
                    .background(
                        ZStack {
                            Color(.green)
                                .opacity(0.5)
                            Rectangle()
                                .fill(Color.clear)
                                .background(Material.ultraThinMaterial)
                        }
                    )
                }
                
                Spacer()
                
                VStack(spacing: 24){
                    // Routing directions
                    if inProgressManager.isRouting {
                        RouteDirectionsView(
                            directions: inProgressManager.routeDirections,
                            estimatedArrival: inProgressManager.estimatedArrival,
                            distance: inProgressManager.routeDistance
                        )
                        .padding()
                    }
                    
                    // Action buttons for active project
                    if appState.isInProjectMode,
                       let activeProject = getActiveProject() {
                        ProjectActionBar(project: activeProject)
                    }
                }.padding(.vertical, 70)
                
            }
            
            // Loading overlay
            if isLoading {
                Color.black.opacity(0.5)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                        .scaleEffect(1.5)
                    
                    Text("Loading projects...")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.top)
                }
                .padding()
                .background(
                    ZStack {
                        Color(.blue)
                        Rectangle()
                            .fill(Color.clear)
                            .background(Material.ultraThinMaterial)
                    }
                )
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
        .sheet(isPresented: $showProjectDetails, content: {
            if let project = selectedProject {
                NavigationView {
                    ProjectDetailsView(project: project)
                }
            }
        })
        .preferredColorScheme(.dark) // Enforce dark mode for the entire view
        .onAppear {
            loadTodaysProjects()
        }
        .onChange(of: appState.activeProjectID) { _, newProjectID in
            if let newProjectID = newProjectID,
               let project = todaysProjects.first(where: { $0.id == newProjectID }),
               let coordinate = project.coordinate {
                
                // Check location permission before routing
                if locationManager.authorizationStatus == .authorizedWhenInUse ||
                   locationManager.authorizationStatus == .authorizedAlways {
                    // Start routing with user's location
                    if let userLocation = locationManager.userLocation {
                        inProgressManager.startRouting(to: coordinate, from: userLocation)
                    } else {
                        inProgressManager.startRouting(to: coordinate)
                    }
                } else if locationManager.authorizationStatus == .notDetermined {
                    // Show the permission prompt
                    withAnimation {
                        showLocationPrompt = true
                    }
                }
            } else {
                // Stop routing when exiting project mode
                inProgressManager.stopRouting()
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, newStatus in
            // Handle permission changes
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                // Permission granted - start routing if in project mode
                if let projectId = appState.activeProjectID,
                   let project = todaysProjects.first(where: { $0.id == projectId }),
                   let coordinate = project.coordinate {
                    
                    if let userLocation = locationManager.userLocation {
                        inProgressManager.startRouting(to: coordinate, from: userLocation)
                    } else {
                        inProgressManager.startRouting(to: coordinate)
                    }
                }
            }
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
        
        withAnimation {
            mapRegion = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
    }
    
    private func updateMapRegion(for projects: [Project]) {
        let coordinates = projects.compactMap { $0.coordinate }
        guard !coordinates.isEmpty else { return }
        
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
        
        withAnimation {
            mapRegion = MKCoordinateRegion(center: center, span: span)
        }
    }
    
    private func startProject(_ project: Project) {
        // Enter project mode
        appState.enterProjectMode(projectID: project.id)
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
        
        // Always request location permission when starting a project
        // This will do nothing if permission is already granted or denied
        locationManager.requestPermissionIfNeeded()
        
        // Try to start routing if we have coordinates
        if let coordinate = project.coordinate {
            // If we have permission, start routing
            if locationManager.authorizationStatus == .authorizedWhenInUse ||
               locationManager.authorizationStatus == .authorizedAlways {
                
                if let userLocation = locationManager.userLocation {
                    inProgressManager.startRouting(to: coordinate, from: userLocation)
                } else {
                    inProgressManager.startRouting(to: coordinate)
                }
            }
        }
    }
    
    private func stopProject(_ project: Project) {
        appState.exitProjectMode()
        showStartConfirmation = false
        inProgressManager.stopRouting()
    }
    
    private func getActiveProject() -> Project? {
        guard let projectId = appState.activeProjectID else { return nil }
        return todaysProjects.first { $0.id == projectId }
    }
}
