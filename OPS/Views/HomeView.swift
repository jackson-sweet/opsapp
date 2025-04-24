//
//  HomeView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// HomeView.swift
import SwiftUI
import MapKit

struct HomeView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.4132, longitude: -123.3650),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var todaysProjects: [Project] = []
    @State private var selectedProjectIndex = 0
    @State private var showStartConfirmation = false
    
    var body: some View {
        ZStack {
            // Dark-themed map as the base layer
            ProjectMapView(
                region: $mapRegion,
                projects: todaysProjects,
                selectedIndex: $selectedProjectIndex,
                onTapMarker: { index in
                    withAnimation {
                        selectedProjectIndex = index
                        showStartConfirmation = false
                    }
                }
            )
            .edgesIgnoringSafeArea(.all)
            
            // UI overlay layers
            VStack(spacing: 0) {
                // Header - either user info or project info
                if appState.isInProjectMode {
                    ProjectHeader(project: getActiveProject())
                } else {
                    UserHeader()
                }
                
                // Project cards carousel
                ProjectCarousel(
                    projects: todaysProjects,
                    selectedIndex: $selectedProjectIndex,
                    showStartConfirmation: $showStartConfirmation,
                    isInProjectMode: appState.isInProjectMode,
                    activeProjectID: appState.activeProjectID,
                    onStart: startProject,
                    onStop: stopProject
                )
                
                Spacer()
                
                // Action buttons (only in project mode)
                if appState.isInProjectMode,
                   let activeProject = getActiveProject() {
                    ProjectActionBar(project: activeProject)
                }
            }
            
            // Network status indicator (top right)
            NetworkStatusIndicator()
                .padding(.top, 8)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .onAppear {
            loadTodaysProjects()
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadTodaysProjects() {
        Task {
            do {
                let allProjects = try dataController.getProjectsForMap()
                let today = Calendar.current.startOfDay(for: Date())
                
                await MainActor.run {
                    // Filter for today's projects
                    self.todaysProjects = allProjects.filter { project in
                        guard let startDate = project.startDate else { return false }
                        return Calendar.current.isDate(startDate, inSameDayAs: today)
                    }
                    
                    if let activeProjectID = appState.activeProjectID,
                       let index = todaysProjects.firstIndex(where: { $0.id == activeProjectID }) {
                        self.selectedProjectIndex = index
                        updateMapRegion(for: todaysProjects[index])
                    } else if !todaysProjects.isEmpty {
                        updateMapRegion(for: todaysProjects)
                    }
                }
            } catch {
                print("Error loading projects: \(error.localizedDescription)")
            }
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
        
        // Find bounds to contain all projects
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
        appState.enterProjectMode(projectID: project.id)
        
        // Update project status if needed
        if project.status != .inProgress {
            Task {
                dataController.syncManager.updateProjectStatus(
                    projectId: project.id,
                    status: .inProgress
                )
            }
        }
    }
    
    private func stopProject(_ project: Project) {
        appState.exitProjectMode()
    }
    
    private func getActiveProject() -> Project? {
        guard let projectId = appState.activeProjectID else { return nil }
        return todaysProjects.first { $0.id == projectId }
    }
}
