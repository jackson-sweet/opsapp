//
//  MapViewAlternative.swift
//  OPS
//
//  Alternative implementation using iOS 17+ Map selection pattern
//

import SwiftUI
import MapKit

struct MapViewAlternative: View {
    @ObservedObject var coordinator: MapCoordinator
    
    // Map interaction state
    @State private var mapCameraPosition: MapCameraPosition
    @State private var isUserInteracting = false
    @State private var selectedProject: Project? = nil
    @State private var mapSelection: String? = nil // Use project ID for selection
    
    // Map settings
    @AppStorage("map3DBuildings") private var show3DBuildings = true
    @AppStorage("mapTrafficDisplay") private var showTraffic = false
    @AppStorage("mapDefaultType") private var defaultMapType = "standard"
    
    // Environment
    @EnvironmentObject private var appState: AppState
    
    init(coordinator: MapCoordinator) {
        self.coordinator = coordinator
        self._mapCameraPosition = State(initialValue: coordinator.mapCameraPosition)
    }
    
    var body: some View {
        Map(position: $mapCameraPosition, 
            interactionModes: .all,
            selection: $mapSelection) {
            
            // User location annotation
            UserAnnotation()
            
            // Project markers with tag-based selection
            ForEach(coordinator.projects) { project in
                if let coordinate = project.coordinate {
                    Annotation(project.title, coordinate: coordinate) {
                        ProjectMarkerAlternative(
                            project: project,
                            isSelected: project.id == coordinator.selectedProjectId,
                            isNavigating: coordinator.isNavigating && project.id == coordinator.selectedProjectId,
                            isActiveProject: appState.activeProjectID == project.id
                        )
                    }
                    .tag(project.id) // Tag for selection support
                }
            }
            
            // Navigation route
            if let polyline = coordinator.routePolyline {
                MapPolyline(polyline)
                    .stroke(OPSStyle.Colors.primaryText, lineWidth: 5)
            }
        }
        .mapStyle(currentMapStyle)
        .mapControls {
            MapCompass()
                .mapControlVisibility(.visible)
        }
        .onMapCameraChange { context in
            // Track user interaction
            if !isUserInteracting {
                isUserInteracting = true
                coordinator.handleUserInteraction()
            }
        }
        .onChange(of: mapSelection) { oldValue, newValue in
            // Handle selection change
            if let projectId = newValue,
               let project = coordinator.projects.first(where: { $0.id == projectId }) {
                handleProjectSelection(project)
            }
        }
        .sheet(item: $selectedProject) { project in
            // Show project details or popup in a sheet
            ProjectSelectionSheet(
                project: project,
                isActiveProject: appState.activeProjectID == project.id,
                onNavigate: {
                    handleNavigateToProject(project)
                },
                onDismiss: {
                    selectedProject = nil
                    mapSelection = nil
                }
            )
            .presentationDetents([.height(250)])
            .presentationDragIndicator(.visible)
        }
        .onReceive(coordinator.$mapCameraPosition) { newPosition in
            // Update camera when coordinator changes (but not during user interaction)
            if !isUserInteracting {
                withAnimation(.easeInOut(duration: 0.3)) {
                    mapCameraPosition = newPosition
                }
            }
        }
        // Reset interaction flag after a delay
        .task {
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                if isUserInteracting {
                    isUserInteracting = false
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentMapStyle: MapStyle {
        switch defaultMapType {
        case "satellite":
            return .imagery(elevation: show3DBuildings ? .realistic : .flat)
        case "hybrid":
            return .hybrid(elevation: show3DBuildings ? .realistic : .flat)
        default:
            return .standard(elevation: show3DBuildings ? .realistic : .flat, showsTraffic: showTraffic)
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleProjectSelection(_ project: Project) {
        // If in project mode, show popup sheet
        if appState.isInProjectMode {
            selectedProject = project
        } else {
            // Normal selection behavior
            coordinator.selectProject(project)
        }
    }
    
    private func handleNavigateToProject(_ project: Project) {
        selectedProject = nil
        mapSelection = nil
        
        // Exit current project mode
        appState.exitProjectMode()
        
        // Select and navigate to the new project
        coordinator.selectProject(project)
        
        // Trigger navigation start through the normal flow
        NotificationCenter.default.post(
            name: Notification.Name("StartProjectFromMap"),
            object: nil,
            userInfo: ["projectId": project.id]
        )
    }
}

// MARK: - Alternative Project Marker

struct ProjectMarkerAlternative: View {
    let project: Project
    let isSelected: Bool
    let isNavigating: Bool
    let isActiveProject: Bool
    
    private var markerColor: Color {
        if isNavigating || isActiveProject {
            return OPSStyle.Colors.secondaryAccent
        } else if isSelected {
            return OPSStyle.Colors.primaryAccent
        } else {
            return OPSStyle.Colors.primaryText
        }
    }
    
    private var markerSize: CGFloat {
        if isNavigating || isActiveProject {
            return 32
        } else if isSelected {
            return 28
        } else {
            return 24
        }
    }
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(OPSStyle.Colors.cardBackground)
                .frame(width: markerSize + 8, height: markerSize + 8)
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            
            // Icon
            Image(systemName: iconForStatus(project.status))
                .font(.system(size: markerSize * 0.6, weight: .bold))
                .foregroundColor(markerColor)
        }
        .scaleEffect(isSelected || isActiveProject ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActiveProject)
    }
    
    private func iconForStatus(_ status: Status) -> String {
        switch status {
        case .rfq, .estimated:
            return "clock.fill"
        case .accepted, .inProgress:
            return "hammer.fill"
        case .completed, .closed:
            return "checkmark.circle.fill"
        case .archived:
            return "archivebox.fill"
        }
    }
}

// MARK: - Project Selection Sheet

struct ProjectSelectionSheet: View {
    let project: Project
    let isActiveProject: Bool
    let onNavigate: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)
            
            // Content
            VStack(alignment: .leading, spacing: 12) {
                // Title
                Text(project.title)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                
                // Client
                Text(project.effectiveClientName)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
                
                // Address
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    
                    Text(project.address ?? "No address")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(2)
                }
                
                // Status
                HStack {
                    StatusBadge.forJobStatus(project.status)
                    Spacer()
                }
                
                // Action button
                if isActiveProject {
                    // Show current project indicator
                    HStack {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 16))
                        Text("Current Project")
                            .font(OPSStyle.Typography.body)
                        Spacer()
                    }
                    .foregroundColor(OPSStyle.Colors.secondaryAccent)
                    .padding()
                    .background(OPSStyle.Colors.secondaryAccent.opacity(0.2))
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                } else {
                    // Navigate button
                    Button(action: onNavigate) {
                        HStack {
                            Image(systemName: "location.fill")
                                .font(.system(size: 16))
                            Text("Navigate to Project")
                                .font(OPSStyle.Typography.bodyBold)
                            Spacer()
                        }
                        .foregroundColor(.black)
                        .padding()
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(OPSStyle.Colors.cardBackground)
    }
}