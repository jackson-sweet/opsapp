//
//  HomeContentView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-03.
//

import SwiftUI
import MapKit

/// A container for the main content of the HomeView
/// Used to reduce expression complexity in HomeView
struct HomeContentView: View {
    // Bindings
    @Binding var mapRegion: MKCoordinateRegion
    let todaysProjects: [Project]
    @Binding var selectedProjectIndex: Int
    @Binding var showStartConfirmation: Bool
    @Binding var selectedProject: Project?
    @Binding var showFullDirectionsView: Bool
    let isLoading: Bool
    @Binding var showLocationPermissionView: Bool
    
    // Environment objects
    @ObservedObject var appState: AppState
    @ObservedObject var inProgressManager: InProgressManager
    
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
                region: $mapRegion,
                projects: todaysProjects,
                selectedIndex: $selectedProjectIndex,
                onTapMarker: { index in
                    selectedProjectIndex = index
                    showStartConfirmation = false
                    
                    // Auto-zoom to the selected project with enhanced animation
                    if let project = todaysProjects[safe: index], let coordinate = project.coordinate {
                        // First get current region
                        let currentRegion = mapRegion
                        
                        // Define target region
                        let targetRegion = ProjectMapView.calculateVisibleRegion(
                            for: [project],
                            zoomLevel: 0.01 // Closer zoom for single project
                        )
                        
                        // Create intermediate region
                        let intermediateRegion = MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(
                                latitudeDelta: (currentRegion.span.latitudeDelta + targetRegion.span.latitudeDelta) / 2,
                                longitudeDelta: (currentRegion.span.longitudeDelta + targetRegion.span.longitudeDelta) / 2
                            )
                        )
                        
                        // Two-stage animation for smoother feel
                        withAnimation(.easeInOut(duration: 0.3)) {
                            mapRegion = intermediateRegion
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeOut(duration: 0.4)) {
                                mapRegion = targetRegion
                            }
                        }
                    }
                },
                routeOverlay: inProgressManager.getRouteOverlay(),
                isInProjectMode: appState.isInProjectMode
            )
            
            // Semi-transparent dark overlay
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
    
    private var gradientOverlay: some View {
        VStack(spacing: 0) {
            // Top gradient overlay
            LinearGradient(
                gradient: Gradient(
                    stops: [
                        .init(color: Color.black.opacity(1), location: 0),
                        .init(color: Color.black.opacity(0.9), location: 0.15),
                        .init(color: Color.black.opacity(0.8), location: 0.25),
                        .init(color: Color.black.opacity(0.7), location: 0.4),
                        .init(color: Color.black.opacity(0.5), location: 0.6),
                        .init(color: OPSStyle.Colors.cardBackground.opacity(0.3), location: 0.8),
                        .init(color: OPSStyle.Colors.cardBackground.opacity(0), location: 1)
                    ]
                ),
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
            
            Spacer()
            
            // Navigation controls as a ZStack component - no bottom padding needed since it handles vertical positioning
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
                            selectedProject = project
                        }
                    )
                } else if !isLoading {
                    emptyProjectsView
                }
            }
        }
    }
    
    private var emptyProjectsView: some View {
        VStack(spacing: 16) {
            Text(AppConfiguration.UX.noProjectQuotes.randomElement() ?? "No projects scheduled for today")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.center)
            
            // Debug button for testing
            #if DEBUG
            Button("Test Location Prompt") {
                print("HomeView: Manual test of location permission view")
                showLocationPermissionView = true
            }
            .padding(8)
            .background(OPSStyle.Colors.primaryAccent)
            .foregroundColor(.white)
            .cornerRadius(8)
            #endif
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
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
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
}