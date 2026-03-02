//
//  OPSMapContainer.swift
//  OPS
//
//  Container view that assembles the Mapbox map with all overlay
//  controls.  Matches the callback interface of the old MapContainer
//  so HomeContentView can swap in with zero changes.
//

import SwiftUI
import CoreLocation

struct OPSMapContainer: View {

    // ──────────────────────────────────────────────
    // MARK: - Inputs (same shape as old MapContainer)
    // ──────────────────────────────────────────────

    let projects: [Project]
    let selectedIndex: Int
    let selectedTask: ProjectTask?
    let onProjectSelected: (Project) -> Void
    let onNavigationStarted: (Project) -> Void
    @Binding var filterMode: MapFilterMode

    @ObservedObject var appState: AppState
    @ObservedObject var locationManager: LocationManager

    // ──────────────────────────────────────────────
    // MARK: - Internal State
    // ──────────────────────────────────────────────

    @AppStorage("mapStyle") private var mapStyleRaw = "dark"
    @AppStorage("map3DBuildings") private var map3DBuildings = true
    @AppStorage("mapOrientation") private var mapOrientationRaw = "northUp"
    @AppStorage("mapSpeedZoom") private var mapSpeedZoom = true

    @StateObject private var coordinator: OPSMapCoordinator
    @StateObject private var geofenceManager: GeofenceManager

    // ──────────────────────────────────────────────
    // MARK: - Init
    // ──────────────────────────────────────────────

    init(
        projects: [Project],
        selectedIndex: Int,
        selectedTask: ProjectTask?,
        onProjectSelected: @escaping (Project) -> Void,
        onNavigationStarted: @escaping (Project) -> Void,
        filterMode: Binding<MapFilterMode>,
        appState: AppState,
        locationManager: LocationManager
    ) {
        self.projects = projects
        self.selectedIndex = selectedIndex
        self.selectedTask = selectedTask
        self.onProjectSelected = onProjectSelected
        self.onNavigationStarted = onNavigationStarted
        self._filterMode = filterMode
        self.appState = appState
        self.locationManager = locationManager

        _coordinator = StateObject(
            wrappedValue: OPSMapCoordinator(locationManager: locationManager)
        )
        _geofenceManager = StateObject(
            wrappedValue: GeofenceManager(locationManager: locationManager)
        )
    }

    // ──────────────────────────────────────────────
    // MARK: - Body
    // ──────────────────────────────────────────────

    // ──────────────────────────────────────────────
    // MARK: - Computed Helpers
    // ──────────────────────────────────────────────

    /// True when any overlay card/tooltip is showing.
    private var isShowingOverlay: Bool {
        coordinator.showingProjectCard || coordinator.showingCrewTooltip
    }

    /// The currently selected project, if any.
    private var selectedProject: Project? {
        coordinator.selectedProject
    }

    /// Today's tasks for the selected project.
    private var todaysTasksForSelectedProject: [ProjectTask] {
        guard let project = selectedProject else { return [] }
        let calendar = Calendar.current
        return project.tasks.filter { task in
            guard let start = task.startDate else { return false }
            return calendar.isDateInToday(start)
        }
    }

    /// Team members for the selected project.
    private var teamMembersForSelectedProject: [User] {
        guard let project = selectedProject else { return [] }
        return project.teamMembers
    }

    /// The crew location update for the selected crew member.
    private var selectedCrewUpdate: CrewLocationUpdate? {
        guard let id = coordinator.selectedCrewMemberId else { return nil }
        return coordinator.crewLocations[id]
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {

            // 1. Full-screen Mapbox map
            OPSMapView(coordinator: coordinator)
                .ignoresSafeArea()

            // 2. Tap-to-dismiss layer (behind overlays, above map)
            if isShowingOverlay {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(OPSStyle.Animation.standard) {
                            coordinator.deselectAll()
                        }
                    }
            }

            // 3. Right-side map controls — below carousel area in browse, below maneuver card in nav
            VStack {
                Spacer()
                mapControls
                Spacer()
            }
            .frame(maxHeight: .infinity)
            .padding(.trailing, 12)

            // 4. Project pin card — anchored to bottom
            if coordinator.showingProjectCard, let project = selectedProject {
                VStack {
                    Spacer()
                    ProjectPinCard(
                        project: project,
                        todaysTasks: todaysTasksForSelectedProject,
                        teamMembers: teamMembersForSelectedProject,
                        onNavigate: {
                            withAnimation(OPSStyle.Animation.standard) {
                                coordinator.showingProjectCard = false
                            }
                            onNavigationStarted(project)
                            coordinator.startNavigation(to: project)
                        },
                        onDetails: {
                            withAnimation(OPSStyle.Animation.standard) {
                                coordinator.showingProjectCard = false
                            }
                            appState.viewProjectDetailsById(project.id)
                        },
                        onDismiss: {
                            withAnimation(OPSStyle.Animation.standard) {
                                coordinator.deselectAll()
                            }
                        }
                    )
                    .padding(.bottom, 90)
                }
                .transition(.move(edge: .bottom))
                .animation(OPSStyle.Animation.standard, value: coordinator.showingProjectCard)
            }

            // 6. Crew tooltip card — anchored to bottom
            if coordinator.showingCrewTooltip, let update = selectedCrewUpdate {
                VStack {
                    Spacer()
                    HStack {
                        CrewTooltipCard(
                            update: update,
                            onProjectTap: { projectId in
                                // Dismiss tooltip and select the project instead
                                withAnimation(OPSStyle.Animation.standard) {
                                    coordinator.showingCrewTooltip = false
                                    coordinator.selectedCrewMemberId = nil
                                }
                                if let project = projects.first(where: { $0.id == projectId }) {
                                    coordinator.selectProject(project)
                                    onProjectSelected(project)
                                }
                            },
                            onCall: {
                                guard let phone = update.phoneNumber,
                                      let url = URL(string: "tel:\(phone)") else { return }
                                UIApplication.shared.open(url)
                            },
                            onMessage: {
                                guard let phone = update.phoneNumber,
                                      let url = URL(string: "sms:\(phone)") else { return }
                                UIApplication.shared.open(url)
                            },
                            onDismiss: {
                                withAnimation(OPSStyle.Animation.standard) {
                                    coordinator.deselectAll()
                                }
                            }
                        )
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 90)
                }
                .transition(.opacity)
                .animation(OPSStyle.Animation.standard, value: coordinator.showingCrewTooltip)
            }

            // 7. Navigation UI — split into maneuver card (top) + trip strip (bottom)
            if coordinator.isNavigating {
                // 7a. Maneuver card — positioned below ProjectHeader (~120pt from top)
                VStack {
                    NavigationManeuverCard(navigationManager: coordinator.navigationManager)
                        .padding(.horizontal, 16)
                        .padding(.top, 120) // Below ProjectHeader
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .top))
                .animation(OPSStyle.Animation.standard, value: coordinator.isNavigating)

                // 7b. Trip info strip — just above the tab bar
                VStack {
                    Spacer()
                    NavigationTripStrip(navigationManager: coordinator.navigationManager)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 108) // 100pt tab bar + 8pt spacing
                }
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .bottom))
                .animation(OPSStyle.Animation.standard, value: coordinator.isNavigating)
            }

            // 8. Geofence banners — below header
            if geofenceManager.pendingArrival != nil || geofenceManager.pendingDeparture != nil {
                VStack {
                    Spacer().frame(height: coordinator.isNavigating ? 210 : 100)

                    if let arrival = geofenceManager.pendingArrival {
                        GeofenceBannerView(
                            event: arrival,
                            type: .arrival,
                            onAction: {
                                withAnimation(OPSStyle.Animation.standard) {
                                    geofenceManager.clockIn(projectId: arrival.projectId)
                                }
                            },
                            onDismiss: {
                                withAnimation(OPSStyle.Animation.standard) {
                                    geofenceManager.dismissBanner()
                                }
                            }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if let departure = geofenceManager.pendingDeparture {
                        GeofenceBannerView(
                            event: departure,
                            type: .departure,
                            onAction: {
                                withAnimation(OPSStyle.Animation.standard) {
                                    geofenceManager.clockOut()
                                }
                            },
                            onDismiss: {
                                withAnimation(OPSStyle.Animation.standard) {
                                    geofenceManager.dismissBanner()
                                }
                            }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(OPSStyle.Animation.standard, value: geofenceManager.pendingArrival != nil)
                .animation(OPSStyle.Animation.standard, value: geofenceManager.pendingDeparture != nil)
            }

            // 9. Location permission pre-prompt
            if locationManager.authorizationStatus == .notDetermined {
                MapLocationPermissionView(
                    onEnable: {
                        locationManager.requestPermissionIfNeeded(requestAlways: false)
                    },
                    onSkip: {
                        // Map still works but degraded (no user dot, no navigation)
                    }
                )
                .transition(.opacity)
            }
        }

        // ── Lifecycle ──
        .onAppear {
            coordinator.projects = projects
            coordinator.refreshProjectAnnotations()

            if selectedIndex < projects.count {
                coordinator.selectedProjectId = projects[selectedIndex].id
            }

            // Apply initial settings
            coordinator.setFilter(filterMode)
            coordinator.set3DBuildings(map3DBuildings)
            coordinator.speedZoomEnabled = mapSpeedZoom
            if let orientation = OrientationMode(rawValue: mapOrientationRaw) {
                coordinator.setOrientation(orientation)
            }
            if let style = OPSMapStyle(rawValue: mapStyleRaw) {
                coordinator.setMapStyle(style)
            }

            locationManager.requestPermissionIfNeeded(requestAlways: false)

            if let location = locationManager.currentLocation {
                geofenceManager.updateGeofences(for: location, jobSites: projects)
            }
        }

        // ── Data changes ──
        .onChange(of: projects) { _, newProjects in
            coordinator.projects = newProjects
            coordinator.refreshProjectAnnotations()

            if let location = locationManager.currentLocation {
                geofenceManager.updateGeofences(for: location, jobSites: newProjects)
            }
        }
        .onChange(of: mapStyleRaw) { _, newValue in
            if let style = OPSMapStyle(rawValue: newValue) {
                coordinator.setMapStyle(style)
            }
        }
        .onChange(of: map3DBuildings) { _, newValue in
            coordinator.set3DBuildings(newValue)
        }
        .onChange(of: mapOrientationRaw) { _, newValue in
            if let orientation = OrientationMode(rawValue: newValue) {
                coordinator.setOrientation(orientation)
            }
        }
        .onChange(of: mapSpeedZoom) { _, newValue in
            coordinator.speedZoomEnabled = newValue
        }
        .onChange(of: filterMode) { _, newMode in
            coordinator.setFilter(newMode)
        }
        .onChange(of: selectedIndex) { _, newIndex in
            guard newIndex < projects.count else { return }
            let project = projects[newIndex]
            if coordinator.selectedProjectId != project.id {
                coordinator.selectProject(project)
                onProjectSelected(project)
            }
        }

        // ── Notifications ──
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("StartNavigation"))
        ) { notification in
            guard let projectId = notification.userInfo?["projectId"] as? String,
                  let project = projects.first(where: { $0.id == projectId }) else { return }

            coordinator.startNavigation(to: project)
            onNavigationStarted(project)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("StopNavigation"))
        ) { _ in
            coordinator.stopNavigation()
        }
    }

    // ──────────────────────────────────────────────
    // MARK: - Map Controls
    // ──────────────────────────────────────────────

    /// Right-side vertically stacked control buttons.
    @ViewBuilder
    private var mapControls: some View {
        VStack(spacing: 12) {

            // Re-centre — only when not following
            if !coordinator.isFollowingUser {
                controlButton(
                    icon: "location.fill",
                    isActive: false
                ) {
                    coordinator.recenterOnUser()
                }
            }

            // Route overview — only during navigation
            if coordinator.isNavigating {
                controlButton(
                    icon: "map",
                    isActive: false
                ) {
                    coordinator.showRouteOverview()
                }
            }

            // End navigation — only during navigation
            if coordinator.isNavigating {
                controlButton(
                    icon: "xmark",
                    isActive: false
                ) {
                    coordinator.stopNavigation()
                }
            }

            // Orientation toggle — always visible
            controlButton(
                icon: coordinator.orientationMode == .northUp
                    ? "location.north.line.fill"
                    : "location.fill",
                isActive: coordinator.orientationMode == .courseUp
            ) {
                coordinator.toggleOrientation()
            }

        }
    }

    // ──────────────────────────────────────────────
    // MARK: - Control Button
    // ──────────────────────────────────────────────

    /// 44x44 frosted-glass circle with a 1px white@8% border.
    /// Active state tints the icon with the accent color.
    private func controlButton(
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(
                    isActive
                        ? Color(red: 0x59 / 255, green: 0x77 / 255, blue: 0x94 / 255) // #597794
                        : .white
                )
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
