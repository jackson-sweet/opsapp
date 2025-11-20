//
//  HomeContentView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-03.
//

import SwiftUI
import MapKit
import Combine
import CoreLocation

/// A container for the main content of the HomeView
/// Used to reduce expression complexity in HomeView
struct HomeContentView: View {
    // Bindings - mapRegion removed, now handled internally by ProjectMapView
    let todaysCalendarEvents: [CalendarEvent]
    let todaysProjects: [Project] // Keep for map
    @Binding var selectedEventIndex: Int
    @Binding var showStartConfirmation: Bool
    @Binding var selectedProject: Project? // Not used anymore but keeping for backward compatibility
    @Binding var showFullDirectionsView: Bool
    let isLoading: Bool
    @Binding var showLocationPermissionView: Bool
    
    // Environment objects
    @ObservedObject var appState: AppState
    @ObservedObject var inProgressManager: InProgressManager
    
    // Location manager to track authorization status
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var dataController: DataController
    
    // Callbacks
    let startProject: (Project) -> Void
    let stopProject: (Project) -> Void
    let getActiveProject: () -> Project?

    // State for project editing
    @State private var showingEditProject = false
    @State private var projectToEdit: Project?

    // State for random quote - only set once on view creation
    @State private var randomQuote: String = AppConfiguration.UX.noProjectQuotes.randomElement() ?? "No projects found"
    
    var body: some View {
        ZStack {
            // 1. Map layer
            mapLayer
            
            // 2. Gradient overlay
            gradientOverlay
            
            // 3. UI content overlay
            contentOverlay
            // Add padding when navigation header is showing
            .padding(.top, inProgressManager.isRouting ? 160 : 0)
            .animation(.easeInOut(duration: 0.5), value: inProgressManager.isRouting)
            
            // 4. Loading overlay
            if isLoading {
                loadingOverlay
                    .transition(.opacity)
                    .zIndex(999)
            }

            // 5. Initial sync loading screen - shows on first login
            if dataController.isPerformingInitialSync {
                TacticalInitialLoadingView(dataController: dataController)
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        // Sheet for editing projects (admin/office crew only)
        .sheet(isPresented: $showingEditProject) {
            if let projectToEdit = projectToEdit {
                ProjectFormSheet(mode: .edit(projectToEdit)) { _ in
                    showingEditProject = false
                    self.projectToEdit = nil
                }
            }
        }
    }
    
    // MARK: - View Components
    
    // Always use new map implementation
    private let useNewMap = true
    
    private var mapLayer: some View {
        ZStack {
            // New map implementation with safety wrapper
            SafeMapContainer(
                projects: todaysProjects,
                selectedIndex: todaysProjects.isEmpty ? 0 :
                    (todaysCalendarEvents.indices.contains(selectedEventIndex) ?
                        todaysProjects.firstIndex(where: { $0.id == todaysCalendarEvents[selectedEventIndex].projectId }) ?? 0 : 0),
                selectedEvent: todaysCalendarEvents.indices.contains(selectedEventIndex) ? todaysCalendarEvents[selectedEventIndex] : nil,
                onProjectSelected: { project in
                    // Find event index for this project
                    if let index = todaysCalendarEvents.firstIndex(where: { $0.projectId == project.id }) {
                        selectedEventIndex = index
                        // Reset confirmation when selecting via map
                        showStartConfirmation = false
                    }
                },
                onNavigationStarted: { project in
                    
                    // Don't immediately enter project mode - let navigation start first
                    // Just update the project status and prepare for navigation
                    showStartConfirmation = false
                    
                    // Update project status to 'in progress' without entering project mode yet
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
                    
                    // Delay entering project mode to allow navigation to start
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Now enter project mode after navigation has started
                        appState.enterProjectMode(projectID: project.id)
                        
                        // For the old system, we also need to start routing
                        if let coordinate = project.coordinate,
                           let userLocation = locationManager.userLocation {
                            inProgressManager.startRouting(to: coordinate, from: userLocation)
                        }
                    }
                },
                appState: appState,
                locationManager: locationManager
            )
            
            // Semi-transparent dark overlay - using clear since we have gradient overlay
            Color.clear
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .overlay(locationDisabledOverlay)
    }
    
    private var gradientOverlay: some View {
        VStack(spacing: 0) {
            // Top gradient overlay
            Color(.black)
                .frame(height: 80)

            OPSStyle.Layout.Gradients.headerFade
                .frame(height: 300)
            
            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
    
    private var contentOverlay: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Project carousel or empty state
            projectCarouselView
                .padding(.top, -8) // Bring carousel closer to header
            
            Spacer()
            
            // Show project action bar when in project mode
            if appState.isInProjectMode, let project = getActiveProject() {
                ProjectActionBar(project: project)
                    //.padding(.horizontal, 24)
                    .padding(.bottom, 120) // Add padding for tab bar
            }
        }
    }
    
    private var headerView: some View {
        Group {
            if appState.isInProjectMode {
                ProjectHeader(project: getActiveProject())
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            } else {
                AppHeader(headerType: .home)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appState.isInProjectMode)
    }
    
    private var projectCarouselView: some View {
        Group {
            if !appState.isInProjectMode {
                if !todaysCalendarEvents.isEmpty {
                    EventCarousel(
                        events: todaysCalendarEvents,
                        selectedIndex: $selectedEventIndex,
                        showStartConfirmation: $showStartConfirmation,
                        isInProjectMode: appState.isInProjectMode,
                        activeProjectID: appState.activeProjectID,
                        onStart: startProject,
                        onStop: stopProject,
                        onLongPress: { project in

                            // EXPLICITLY ensure we don't start the project by turning off confirmation
                            showStartConfirmation = false

                            // Check user role - if admin or office crew, open edit mode, otherwise show details
                            if dataController.currentUser?.role == .admin || dataController.currentUser?.role == .officeCrew {
                                projectToEdit = project
                                showingEditProject = true
                            } else {
                                // Show project details (sheet) for field crew
                                showProjectDetails(project)
                            }
                        }
                    )
                } else if !isLoading {
                    emptyProjectsView
                        .padding(.top, 20)
                }
            }
        }
    }
    
    // Helper method to show project details
    private func showProjectDetails(_ project: Project) {
        
        // Make sure confirmation is turned off to avoid state conflicts
        showStartConfirmation = false
        
        // Call AppState's viewProjectDetails method
        appState.viewProjectDetails(project)
        
        // Log completion
    }
    
    private var emptyProjectsView: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Project title
            Text("NO PROJECTS SCHEDULED FOR TODAY.")
                .font(OPSStyle.Typography.cardTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)

            // Client name - uses the state variable that was set once on view creation
            Text(randomQuote)
                .font(OPSStyle.Typography.cardBody)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true) // Allow text to expand vertically

        }
        .frame(maxWidth: .infinity, alignment: .leading) // Full width
        .padding(OPSStyle.Layout.spacing3) // Use standard spacing
        .background(
            // Custom background with blur effect
            BlurView(style: .dark)
                .cornerRadius(5)
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal, 20) // Match carousel horizontal padding
        .contentShape(Rectangle()) // Make entire card tappable
    }
    
    private var loadingOverlay: some View {
        ZStack {
            // Semi-transparent black background
            OPSStyle.Colors.cardBackgroundDark
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Tactical loading bar
                TacticalLoadingBarAnimated(
                    barCount: 8,
                    barWidth: 2,
                    barHeight: 6,
                    spacing: 4,
                    emptyColor: OPSStyle.Colors.pinDotNeutral,
                    fillColor: OPSStyle.Colors.pinDotActive
                )

                // Loading text
                Text("LOADING PROJECTS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .tracking(1.2)
            }
        }
    }
    
    // MARK: - Helper Methods
    // All map zoom/region logic has been moved to ProjectMapView for centralized state management
    
    // MARK: - Navigation Info View
    private var navigationInfoView: some View {
        VStack(spacing: 0) {
            // Progress and arrival info
            HStack {
                // Time remaining
                VStack(alignment: .leading, spacing: 4) {
                    Text("TIME")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    if let travelTime = inProgressManager.activeRoute?.expectedTravelTime {
                        Text(formatTime(travelTime))
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    } else {
                        Text("--")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
                
                Spacer()
                
                // Distance remaining
                VStack(alignment: .center, spacing: 4) {
                    Text("DISTANCE")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    if let distance = inProgressManager.activeRoute?.distance {
                        Text(formatDistance(distance))
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    } else {
                        Text("--")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
                
                Spacer()
                
                // Arrival time
                VStack(alignment: .trailing, spacing: 4) {
                    Text("ARRIVAL")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    if let arrival = inProgressManager.estimatedArrival {
                        Text(arrival.components(separatedBy: " ").first ?? arrival)
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    } else {
                        Text("--:--")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Helper Methods for Navigation Info
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
    
    private func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance < 100 {
            return String(format: "%.0f m", distance)
        } else if distance < 1000 {
            return String(format: "%.0f m", (distance / 10).rounded() * 10)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
    
    // MARK: - Location Disabled Overlay
    private var locationDisabledOverlay: some View {
        Group {
            // Show overlay only when location is denied/restricted and in project mode with routing active
            if (locationManager.authorizationStatus == .denied || 
                locationManager.authorizationStatus == .restricted) &&
                appState.isInProjectMode &&
                inProgressManager.isRouting {
                
                ZStack {
                    // Semi-transparent background
                    OPSStyle.Colors.modalOverlay
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    
                    // Message card
                    VStack(spacing: 16) {
                        // Icon
                        Image(systemName: "location.slash.fill")
                            .font(.system(size: 48))
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                        
                        // Title
                        Text("LOCATION SERVICES DISABLED")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        // Message
                        Text("Enable location services in Settings to see routing and navigation.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        // Open Settings button
                        Button(action: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "gear")
                                    .font(.system(size: 18))
                                
                                Text("OPEN SETTINGS")
                                    .font(OPSStyle.Typography.button)
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                        }
                        .padding(.top, 8)
                    }
                    .padding(32)
                    .background(
                        ZStack {
                            // Blur effect
                            BlurView(style: .systemThinMaterialDark)
                            
                            // Semi-transparent overlay
                            Color(OPSStyle.Colors.cardBackgroundDark)
                                .opacity(0.3)
                        }
                    )
                    .cornerRadius(OPSStyle.Layout.cornerRadius * 2)
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                    .padding(.horizontal, 40)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .animation(.easeInOut(duration: 0.3), value: locationManager.authorizationStatus)
            }
        }
    }
}
