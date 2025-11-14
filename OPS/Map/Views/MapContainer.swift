//
//  MapContainer.swift
//  OPS
//
//  Created by Claude on 2025-06-24.
//
//  Main container view that orchestrates all map components

import SwiftUI
import MapKit
import CoreLocation

struct MapContainer: View {
    @StateObject private var coordinator: MapCoordinator
    @StateObject private var navigationEngine = NavigationEngine()
    @State private var showArrivalMessage = false
    @ObservedObject var appState: AppState
    @ObservedObject var locationManager: LocationManager
    
    // Projects passed from parent
    let projects: [Project]
    let selectedIndex: Int
    let selectedEvent: CalendarEvent?

    // Callbacks
    let onProjectSelected: (Project) -> Void
    let onNavigationStarted: (Project) -> Void

    init(projects: [Project],
         selectedIndex: Int,
         selectedEvent: CalendarEvent?,
         onProjectSelected: @escaping (Project) -> Void,
         onNavigationStarted: @escaping (Project) -> Void,
         appState: AppState,
         locationManager: LocationManager) {
        self.projects = projects
        self.selectedIndex = selectedIndex
        self.selectedEvent = selectedEvent
        self.onProjectSelected = onProjectSelected
        self.onNavigationStarted = onNavigationStarted
        self.appState = appState
        self.locationManager = locationManager
        
        // Create coordinator with the provided location manager
        let tempNavigationEngine = NavigationEngine()
        let coordinator = MapCoordinator(
            locationManager: locationManager,
            navigationEngine: tempNavigationEngine
        )
        
        self._coordinator = StateObject(wrappedValue: coordinator)
    }
    
    var body: some View {
        ZStack {
            // Base map
            GeometryReader { geometry in
                MapView(coordinator: coordinator, onProjectSelected: onProjectSelected)
                    .ignoresSafeArea()
                    .environmentObject(appState)
                    .environmentObject(navigationEngine)
                    // Start map above the screen and extend below to shift center down by 5%
                    .offset(y: +geometry.size.height * 0.075)
                    // Extend frame both above and below screen bounds
                    .frame(height: geometry.size.height * 1.2, alignment: .center)
            }
            
            // Map controls (settings, recenter, etc.)
            MapControlsView(coordinator: coordinator)
                .zIndex(1)
            
            /*
            // Navigation overlay (when navigating)
            if coordinator.isNavigating {
                VStack {
                    // Show NavigationBanner at the top
                    if let navigationState = coordinator.navigationState,
                       case .navigating = navigationState,
                       let route = coordinator.currentRoute,
                       coordinator.navigationEngine.currentStepIndex < route.steps.count {
                        
                        let currentStep = route.steps[coordinator.navigationEngine.currentStepIndex]
                        
                        NavigationBanner(
                            instruction: currentStep.instructions,
                            distance: formatDistance(coordinator.navigationEngine.distanceToNextStep),
                            isLastStep: coordinator.navigationEngine.currentStepIndex >= route.steps.count - 2,
                            onEndNavigation: {
                                coordinator.stopNavigation()
                            }
                        )
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    Spacer()
                }
                .zIndex(4)

            }
            */
            
            // Project details card (when project selected and not navigating)
            // Hide ONLY if app is in project mode (active project uses popup instead)
            if !coordinator.isNavigating,
               coordinator.showingProjectDetails,
               let project = coordinator.selectedProject,
               !appState.isInProjectMode {
                VStack {
                    Spacer()
                    
                    ProjectDetailsCard(
                        project: project,
                        selectedEvent: selectedEvent,
                        coordinator: coordinator,
                        onStartProject: { project in
                            onNavigationStarted(project)
                        }
                    )
                    .padding(.bottom, 100) // Add padding to lift card above tab bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea(edges: .bottom) // Let the container extend to bottom
                .allowsHitTesting(true) // Ensure touches are allowed
                .zIndex(10) // Higher zIndex to ensure it's on top
            }
            
            // Location permission overlay
            if coordinator.locationAuthorizationStatus == .denied ||
               coordinator.locationAuthorizationStatus == .restricted {
                LocationPermissionOverlay()
            }
            
            // Arrival notification overlay
            if showArrivalMessage {
                ArrivalMessageOverlay()
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: coordinator.isNavigating)
        .animation(.easeInOut(duration: 0.3), value: coordinator.showingProjectDetails)
        .onAppear {
            // Update coordinator with environment objects
            coordinator.locationManager = locationManager
            coordinator.navigationEngine = navigationEngine
            
            // Setup coordinator
            coordinator.setupCoordinator()
            
            // Request location permission if needed (this will also start updates)
            locationManager.requestPermissionIfNeeded(requestAlways: false)
            
            // Load projects
            coordinator.loadTodaysProjects(projects)
            
            // Set initial selected project based on carousel
            if selectedIndex < projects.count {
                coordinator.selectedProjectId = projects[selectedIndex].id
            }
            
            // Sync navigation state with InProgressManager
            if InProgressManager.shared.isRouting && appState.isInProjectMode {
                // Restore navigation state
                coordinator.restoreNavigationState()
            }
        }
        .onChange(of: projects) { _, newProjects in
            coordinator.loadTodaysProjects(newProjects)
        }
        .onChange(of: selectedIndex) { oldIndex, newIndex in
            // Update selected project when carousel changes
            if newIndex < projects.count {
                let project = projects[newIndex]
                
                // Only update if actually different
                if coordinator.selectedProjectId != project.id {
                    coordinator.selectedProjectId = project.id
                    // Don't automatically hide details - let the user control this
                }
            }
        }
        .onChange(of: coordinator.selectedProjectId) { _, projectId in
            if let project = coordinator.selectedProject {
                onProjectSelected(project)
            }
        }
        .onChange(of: coordinator.isNavigating) { _, isNavigating in
            if isNavigating, let project = coordinator.selectedProject {
                onNavigationStarted(project)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StopNavigation"))) { _ in
            coordinator.stopNavigation()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StartNavigation"))) { notification in
            
            // Check if we have the right project selected
            if let projectId = notification.userInfo?["projectId"] as? String,
               coordinator.selectedProjectId == projectId {
                Task {
                    do {
                        try await coordinator.startNavigation()
                    } catch {
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowArrivalMessage"))) { _ in
            withAnimation {
                showArrivalMessage = true
            }
            
            // Hide after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    showArrivalMessage = false
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance < 50 {
            return "\(Int(distance)) m"
        } else if distance < 1000 {
            return "\(Int(distance / 10) * 10) m"
        } else {
            let km = distance / 1000
            return String(format: "%.1f km", km)
        }
    }
}

// MARK: - Location Permission Overlay

struct LocationPermissionOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 60))
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                
                Text("LOCATION ACCESS REQUIRED")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(.white)
                
                Text("Enable location services to see your position on the map and navigate to projects.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button(action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "gear")
                        Text("OPEN SETTINGS")
                    }
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                }
            }
            .padding(32)
            .background(
                ZStack {
                    BlurView(style: .systemMaterialDark)
                    OPSStyle.Colors.cardBackground.opacity(0.3)
                }
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .shadow(color: .black.opacity(0.3), radius: 20)
            .padding(40)
        }
    }
}

// MARK: - Arrival Message Overlay

struct ArrivalMessageOverlay: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            
            Text("ARRIVED AT DESTINATION")
                .font(OPSStyle.Typography.title)
                .foregroundColor(.white)
            
            Text("Navigation ended")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(32)
        .background(
            ZStack {
                BlurView(style: .systemMaterialDark)
                OPSStyle.Colors.cardBackground.opacity(0.2)
            }
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .shadow(color: .black.opacity(0.3), radius: 20)
    }
}
