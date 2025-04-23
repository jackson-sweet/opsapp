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
    @State private var projects = [Project]()
    @State private var isLoading = true
    @State private var hasError = false
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.33233141, longitude: -122.03121860),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var body: some View {
        ZStack {
            // Map background - We'll implement the custom MapView later
            Color.black.opacity(0.9) // Placeholder for map
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                if !appState.isInProjectMode {
                    userHeader
                } else if let activeProject = projects.first(where: { $0.id == appState.activeProjectID }) {
                    projectHeader(for: activeProject)
                }
                
                Spacer()
                
                // Project cards or active project UI
                if !appState.isInProjectMode {
                    projectCards
                } else if let activeProject = projects.first(where: { $0.id == appState.activeProjectID }) {
                    // Project mode actions - We'll implement this later
                    VStack {
                        Text("Project Actions")
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            
                        HStack(spacing: OPSStyle.Layout.spacing4) {
                            Button(action: {
                                // Update status
                            }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(OPSStyle.Colors.primaryAccent))
                            }
                            
                            Button(action: {
                                // Notes
                            }) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(OPSStyle.Colors.primaryAccent))
                            }
                            
                            Button(action: {
                                // Pencil/edit
                            }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 24))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(OPSStyle.Colors.primaryAccent))
                            }
                            
                            Button(action: {
                                // Camera
                            }) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(OPSStyle.Colors.primaryAccent))
                            }
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing4)
                        .padding(.horizontal)
                        .background(OPSStyle.Colors.background.opacity(0.7))
                    }
                }
            }
            
            // Loading/error overlays
            if isLoading {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    Text("Loading projects...")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding()
                }
                .frame(width: 200, height: 150)
                .background(OPSStyle.Colors.cardBackground.opacity(0.9))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            } else if hasError {
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .font(.system(size: 40))
                        .padding(.bottom)
                    
                    Text("Unable to load projects")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Button("Retry") {
                        loadProjects()
                    }
                    .padding(.top)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding()
                .frame(width: 250, height: 200)
                .background(OPSStyle.Colors.cardBackground.opacity(0.9))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
        .onAppear {
            loadProjects()
        }
    }
    
    // MARK: - Components
    
    private var userHeader: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Good Morning, \(dataController.currentUser?.firstName ?? "User")")
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                if let company = dataController.getCurrentUserCompany() {
                    Text(company.name.uppercased())
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            
            Spacer()
            
            // Network status indicator
            NetworkStatusIndicator()
                .padding(.trailing, 8)
            
            // User profile image
            if let imageData = dataController.currentUser?.profileImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(dataController.currentUser?.firstName.prefix(1) ?? "U")
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    )
            }
        }
        .padding()
        .background(OPSStyle.Colors.background.opacity(0.7))
    }
    
    private func projectHeader(for project: Project) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(project.status.rawValue.uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                
                Text("\(project.clientName), \(project.title)")
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                
                Text(project.address)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Network status indicator
            NetworkStatusIndicator()
                .padding(.trailing, 8)
            
            Button(action: {
                appState.exitProjectMode()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .padding()
        .background(OPSStyle.Colors.background.opacity(0.7))
    }
    
    private var projectCards: some View {
        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing3) {
                ForEach(projects) { project in
                    projectCard(for: project)
                }
            }
            .padding()
        }
        .background(OPSStyle.Colors.background.opacity(0.2))
    }
    
    private func projectCard(for project: Project) -> some View {
        Button(action: {
            appState.enterProjectMode(projectID: project.id)
        }) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                HStack {
                    Text(project.status.rawValue.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .fontWeight(.bold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(OPSStyle.Colors.statusColor(for: project.status))
                        .cornerRadius(OPSStyle.Layout.cornerRadius / 2)
                    
                    Spacer()
                    
                    if let startDate = project.startDate {
                        Text(formattedDate(startDate))
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Text(project.title)
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.top, OPSStyle.Layout.spacing1)
                
                Text(project.clientName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(project.address)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.top, OPSStyle.Layout.spacing1)
            }
            .padding(OPSStyle.Layout.contentPadding)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Methods
    
    // MARK: - Project Loading Methods

    private func loadProjects() {
        guard !isLoading else { return }
        
        isLoading = true
        hasError = false
        
        Task {
            do {
                // Always try to load from local cache first for immediate response
                let localProjects = try dataController.getProjectsForMap()
                
                // Update UI with local data immediately
                await MainActor.run {
                    self.projects = localProjects
                    
                    // Only show loading indicator if we have no data
                    if !localProjects.isEmpty {
                        self.isLoading = false
                    }
                    
                    // Update map region based on projects
                    updateMapRegion(for: localProjects)
                }
                
                // Then try to sync with server to get fresh data in the background
                if dataController.isConnected {
                    // This will trigger a sync in the background
                    dataController.forceSync()
                    
                    // Wait a bit for sync to potentially complete
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    
                    // Get updated projects after sync
                    let updatedProjects = try dataController.getProjectsForMap()
                    
                    await MainActor.run {
                        self.projects = updatedProjects
                        self.isLoading = false
                        
                        // Update region only if it changed significantly
                        if updatedProjects.count != localProjects.count {
                            updateMapRegion(for: updatedProjects)
                        }
                    }
                } else {
                    // If offline but we have cached data, that's fine
                    if !localProjects.isEmpty {
                        await MainActor.run {
                            self.isLoading = false
                        }
                    } else {
                        // No data and offline - show error
                        await MainActor.run {
                            self.hasError = true
                            self.isLoading = false
                        }
                    }
                }
            } catch {
                print("Error loading projects: \(error.localizedDescription)")
                await MainActor.run {
                    self.hasError = true
                    self.isLoading = false
                }
            }
        }
    }

    private func updateMapRegion(for projects: [Project]) {
        guard !projects.isEmpty else { return }
        
        // Find center of all project coordinates
        var validCoordinates: [CLLocationCoordinate2D] = []
        
        for project in projects {
            if let coordinate = project.coordinate {
                validCoordinates.append(coordinate)
            }
        }
        
        guard !validCoordinates.isEmpty else { return }
        
        // Calculate center
        let sumLat = validCoordinates.reduce(0) { $0 + $1.latitude }
        let sumLng = validCoordinates.reduce(0) { $0 + $1.longitude }
        
        let centerLat = sumLat / Double(validCoordinates.count)
        let centerLng = sumLng / Double(validCoordinates.count)
        
        // Calculate appropriate zoom level
        var maxLatDelta: Double = 0.01 // Default minimum
        var maxLngDelta: Double = 0.01 // Default minimum
        
        if validCoordinates.count > 1 {
            let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng)
            
            for coordinate in validCoordinates {
                let latDelta = abs(coordinate.latitude - center.latitude) * 2.5 // Add some padding
                let lngDelta = abs(coordinate.longitude - center.longitude) * 2.5
                
                maxLatDelta = max(maxLatDelta, latDelta)
                maxLngDelta = max(maxLngDelta, lngDelta)
            }
        }
        
        // Ensure we have a reasonable zoom level
        maxLatDelta = max(0.01, min(maxLatDelta, 5.0))
        maxLngDelta = max(0.01, min(maxLngDelta, 5.0))
        
        // Update the region
        withAnimation {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng),
                span: MKCoordinateSpan(latitudeDelta: maxLatDelta, longitudeDelta: maxLngDelta)
            )
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
