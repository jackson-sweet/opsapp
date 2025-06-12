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
    let todaysProjects: [Project]
    @Binding var selectedProjectIndex: Int
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
            
            // 4. Loading overlay
            if isLoading {
                loadingOverlay
            }
        }
    }
    
    // MARK: - View Components
    
    private var mapLayer: some View {
        ZStack {
            ProjectMapView(
                projects: todaysProjects,
                selectedIndex: $selectedProjectIndex,
                onTapMarker: { index in
                    // Get the project that was tapped
                    guard let project = todaysProjects[safe: index] else { return }
                    
                    // Update the selected project index to navigate carousel
                    if selectedProjectIndex != index {
                        print("HomeContentView: Map marker tapped, updating carousel to index \(index)")
                        selectedProjectIndex = index
                        showStartConfirmation = false
                    } else {
                        // Already selected project was tapped again - show details for 'View Details' button
                        print("HomeContentView: Map marker for already selected project tapped")
                        
                        // Only toggle if not in project mode
                        if !appState.isInProjectMode {
                            // Check if this is from the View Details button in the popup
                            // If the timestamp is very recent (within 0.8 seconds), treat as View Details button tap
                            print("🟩🟩🟩 HOME CONTENT VIEW: CHECKING IF VIEW DETAILS WAS TAPPED 🟩🟩🟩")
                            print("🟩 Project ID: \(project.id)")
                            print("🟩 Project Title: \(project.title)")
                            
                            if let lastTapped = project.lastTapped {
                                let timeDiff = abs(lastTapped.timeIntervalSinceNow)
                                print("🟩 Last tapped time exists: \(lastTapped)")
                                print("🟩 Time difference: \(timeDiff) seconds")
                                
                                // Increased time window to 0.8 seconds to catch more cases
                                if timeDiff < 0.8 {
                                    print("🟩🟩🟩 DETECTED VIEW DETAILS BUTTON TAP! Showing project details 🟩🟩🟩")
                                    // This is a tap on View Details - show project details
                                    showProjectDetails(project)
                                    return
                                } else {
                                    print("🟩 Time difference too large (\(timeDiff) > 0.8), not a View Details tap")
                                }
                            } else {
                                print("🟩 No lastTapped timestamp found on project")
                            }
                            
                            // Normal tap - toggle confirmation
                            print("🟩 Treating as regular pin tap, toggling confirmation")
                            showStartConfirmation.toggle()
                        }
                    }
                    
                    // Update last tapped time to track View Details button taps
                    project.lastTapped = Date()
                    
                    // No manual zoom needed - ProjectMapView handles map marker taps automatically
                },
                routeOverlay: inProgressManager.activeRoute?.polyline,
                isInProjectMode: appState.isInProjectMode
            )
            // No manual zoom handling needed - ProjectMapView handles all map state automatically
            
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
            LinearGradient(
                colors: [Color.black.opacity(1), Color.black.opacity(0)]
                , startPoint: .top
                , endPoint: .bottom)
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
            
            // Navigation controls with tab bar padding
            NavigationControlsView(
                isRouting: inProgressManager.isRouting,
                currentNavStep: inProgressManager.currentNavStep,
                showFullDirectionsView: $showFullDirectionsView,
                routeDirections: inProgressManager.routeDirections,
                estimatedArrival: inProgressManager.estimatedArrival,
                routeDistance: inProgressManager.routeDistance,
                isInProjectMode: appState.isInProjectMode,
                activeProject: getActiveProject()
            )
            .padding(.bottom, 90) // Add padding for tab bar
        }
    }
    
    private var headerView: some View {
        Group {
            if appState.isInProjectMode {
                ProjectHeader(project: getActiveProject())
            } else {
                AppHeader(headerType: .home)
            }
        }
    }
    
    private var projectCarouselView: some View {
        Group {
            if !appState.isInProjectMode {
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
                            print("HomeContentView: Long press handler called for project \(project.id)")
                            
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
        print("🟨🟨🟨 HOME CONTENT VIEW: SHOWING PROJECT DETAILS 🟨🟨🟨")
        print("🟨 Project ID: \(project.id)")
        print("🟨 Project Title: \(project.title)")
        print("🟨 Timestamp: \(Date())")
        
        // Make sure confirmation is turned off to avoid state conflicts
        showStartConfirmation = false
        
        // Call AppState's viewProjectDetails method
        print("🟨 Calling appState.viewProjectDetails...")
        appState.viewProjectDetails(project)
        
        // Log completion
        print("🟨 Project details view should now be shown")
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
        }
        .frame(minHeight: 85) // Set minimum height for the container
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
