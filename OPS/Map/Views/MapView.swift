//
//  MapView.swift
//  OPS
//
//  Created by Claude on 2025-06-24.
//
//  Main SwiftUI Map view using iOS 17+ Map API

import SwiftUI
import MapKit

struct MapView: View {
    @ObservedObject var coordinator: MapCoordinator

    // Callbacks
    let onProjectSelected: (Project) -> Void

    // Map interaction state - removed duplicate mapCameraPosition
    @State private var showingMarkerPopup: String? = nil // Project ID of popup
    @State private var selectedAnnotationId: String? = nil // Track selected annotation

    // Map settings
    @AppStorage("map3DBuildings") private var show3DBuildings = true
    @AppStorage("mapTrafficDisplay") private var showTraffic = false
    @AppStorage("mapDefaultType") private var defaultMapType = "standard"

    // Environment
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Map(
            position: $coordinator.mapCameraPosition,
            interactionModes: [.pan, .zoom], // REMOVED .all to disable single-finger zoom
            selection: $selectedAnnotationId  // Use native selection for reliable taps
        ) {
            // User location annotation
            UserAnnotation()
            
            // Project markers
            ForEach(coordinator.projects) { project in
                if let coordinate = project.coordinate {
                    Annotation(project.title, coordinate: coordinate) {
                        ZStack {
                            ProjectMarker(
                                project: project,
                                isSelected: project.id == coordinator.selectedProjectId,
                                isNavigating: coordinator.isNavigating && project.id == coordinator.selectedProjectId
                            )

                            // Show popup below marker if this project's popup is active
                            if showingMarkerPopup == project.id {
                                ProjectMarkerPopup(
                                    project: project,
                                    isActiveProject: appState.activeProjectID == project.id,
                                    onNavigate: {
                                        showingMarkerPopup = nil
                                        
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
                                    },
                                    onDismiss: {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            showingMarkerPopup = nil
                                        }
                                    }
                                )
                                .offset(y: 35) // Position below marker
                                .zIndex(2000) // Ensure it's on top
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .tag(project.id)  // CRITICAL: Enable native selection for this annotation
                }
            }
            
            // Navigation route
            if let polyline = coordinator.routePolyline {
                MapPolyline(polyline)
                    .stroke(OPSStyle.Colors.primaryText, lineWidth: 5)
            }
        }
        .mapStyle(currentMapStyle)
        .onChange(of: selectedAnnotationId) { oldValue, newValue in
            // Handle annotation selection (pin tap)
            guard let projectId = newValue,
                  let project = coordinator.projects.first(where: { $0.id == projectId }) else {
                return
            }

            print("[MAP] 📍 Pin tapped via native selection: \(project.title)")

            // Haptic feedback (async to not block)
            Task {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }

            // Deselect immediately to allow repeated taps on same pin
            selectedAnnotationId = nil

            // Handle the tap asynchronously to avoid blocking
            Task { @MainActor in
                handleMarkerTap(for: project)
            }
        }
        .onTapGesture { location in
            // Only dismiss popup when tapping on map background
            // This ensures the tap doesn't interfere with annotation taps
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if showingMarkerPopup != nil {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showingMarkerPopup = nil
                    }
                }
            }
        }
        .gesture(
            RotationGesture()
                .onChanged { value in
                    handleRotationGesture(value)
                }
                .onEnded { _ in
                    endRotationGesture()
                }
        )
        .mapControls {
            // Minimal controls - just compass when rotated
            MapCompass()
                .mapControlVisibility(.visible)
            
            // No scale or other controls
        }
        .onMapCameraChange { context in
            // Notify coordinator of user interaction
            coordinator.handleUserInteraction()
        }
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { _ in
                    // Additional interaction detection for dragging
                    coordinator.handleUserInteraction()
                }
        )
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
    
    private func handleMarkerTap(for project: Project) {
        // ALWAYS update carousel selection
        onProjectSelected(project)

        // If in project mode (project is active), show popup below pin
        if appState.isInProjectMode {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingMarkerPopup = project.id
            }
        } else {
            // Not in project mode - select project to show bottom sheet
            coordinator.selectProject(project)
        }
    }
    
    // MARK: - Gesture Handling
    
    private func handleRotationGesture(_ value: RotationGesture.Value) {
        // Only allow manual rotation when not in course mode
        guard coordinator.mapOrientationMode != "course" else { return }
        
        coordinator.handleUserInteraction()
        
        // Apply rotation (convert radians to degrees)
        let rotationDegrees = value.radians * 180.0 / .pi
        applyManualRotation(-rotationDegrees) // Negative for natural rotation direction
    }
    
    private func endRotationGesture() {
        // Rotation gesture ended
    }
    
    private func applyManualRotation(_ heading: Double) {
        guard let center = coordinator.userLocation?.coordinate ?? coordinator.selectedProject?.coordinate else {
            return
        }
        
        // Normalize heading to 0-360
        var normalizedHeading = heading
        while normalizedHeading < 0 { normalizedHeading += 360 }
        while normalizedHeading >= 360 { normalizedHeading -= 360 }
        
        let camera = MapCamera(
            centerCoordinate: center,
            distance: coordinator.zoomDistance * 2,
            heading: normalizedHeading,
            pitch: 0
        )
        
        // Update without animation for smooth gesture response
        coordinator.mapCameraPosition = .camera(camera)
    }
}

// MARK: - Project Marker View

struct ProjectMarker: View {
    let project: Project
    let isSelected: Bool
    let isNavigating: Bool
    
    private var markerColor: Color {
        if isNavigating {
            return OPSStyle.Colors.secondaryAccent
        } else if isSelected {
            return OPSStyle.Colors.primaryAccent
        } else {
            return OPSStyle.Colors.primaryText
        }
    }
    
    private var markerSize: CGFloat {
        if isNavigating {
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
        .contentShape(Circle()) // Ensure the entire area is tappable
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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
