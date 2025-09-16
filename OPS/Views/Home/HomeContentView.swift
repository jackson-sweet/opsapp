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
                onProjectSelected: { project in
                    print("🟢 HomeContentView: onProjectSelected called for: \(project.title)")
                    // Find event index for this project
                    if let index = todaysCalendarEvents.firstIndex(where: { $0.projectId == project.id }) {
                        print("🟢 HomeContentView: Found event at index \(index)")
                        selectedEventIndex = index
                        // Reset confirmation when selecting via map
                        showStartConfirmation = false
                        print("🟢 HomeContentView: showStartConfirmation = \(showStartConfirmation)")
                    }
                },
                onNavigationStarted: { project in
                    print("🟢 HomeContentView: onNavigationStarted called for project: \(project.title)")
                    
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
                                print("⚠️ API call failed: \(error.localizedDescription)")
                                dataController.syncManager.updateProjectStatus(
                                    projectId: project.id,
                                    status: .inProgress,
                                    forceSync: true
                                )
                            }
                        }
                    }
                    
                    // Delay entering project mode to allow navigation to start
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("🟢 HomeContentView: Now entering project mode")
                        // Now enter project mode after navigation has started
                        appState.enterProjectMode(projectID: project.id)
                        
                        // For the old system, we also need to start routing
                        if let coordinate = project.coordinate,
                           let userLocation = locationManager.userLocation {
                            print("🟢 HomeContentView: Starting routing...")
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
            
            LinearGradient(
                colors: [Color.black.opacity(1), Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
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
                            
                            // Show project details (sheet)
                            showProjectDetails(project)
                        }
                    )
                } else if !isLoading {
                    emptyProjectsView
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
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                // Project title
                Text("NO PROJECTS SCHEDULED FOR TODAY.")
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                    // Client name
                    Text(AppConfiguration.UX.noProjectQuotes.randomElement() ?? "No projects found")
                        .font(OPSStyle.Typography.cardBody)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                
            }
            .padding()
            //.frame(width: geometry.size.width - 40) // Remove fixed height
            .background(
                // Custom background with blur effect
                BlurView(style: .dark)
                    .cornerRadius(5)
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 4) // Center the card
            .contentShape(Rectangle()) // Make entire card tappable
            .frame(width: 362, height: 85)
        }
        .frame(height: 190) // Set height for the container
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
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
                    Color.black.opacity(0.6)
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
