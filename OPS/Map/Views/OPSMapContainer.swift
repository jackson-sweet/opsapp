//
//  OPSMapContainer.swift
//  OPS
//
//  Container view that assembles the Mapbox map with all overlay
//  controls.  Matches the callback interface of the old MapContainer
//  so HomeContentView can swap in with zero changes.
//

import SwiftUI
import UIKit
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

    /// Drag offset for the stacked group sheet (dismiss gesture)
    @State private var stackedGroupDragOffset: CGFloat = 0

    /// Whether the top NavigationManeuverCard is expanded to show the
    /// full turn-by-turn list. Collapses automatically when navigation
    /// stops or project mode ends.
    @State private var isManeuverExpanded: Bool = false

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
        coordinator.showingProjectCard || coordinator.showingCrewTooltip || coordinator.showingStackedGroup
    }

    /// The currently selected project, if any.
    private var selectedProject: Project? {
        coordinator.selectedProject
    }

    /// The device's top safe area inset, read directly from the key
    /// window. `GeometryReader` inside this container returns 0 for the
    /// top inset because the parent `mapLayer` applies `.ignoresSafeArea`.
    /// Reading from the window is the reliable path for portrait iOS.
    private var topSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets.top
        ?? 47 // notch-era fallback
    }

    // ──────────────────────────────────────────────
    // MARK: - Top project overlay
    // ──────────────────────────────────────────────

    /// The project to display in the top project overlay. Prefers the
    /// coordinator's selected project; falls back to looking up the
    /// active project id on AppState (covers the brief window where
    /// project mode is entered from outside the map).
    private var topOverlayProject: Project? {
        if let selected = coordinator.selectedProject {
            return selected
        }
        if let id = appState.activeProjectID {
            return projects.first(where: { $0.id == id })
        }
        return nil
    }

    /// The top card shown in the project overlay. Crossfades between the
    /// routing maneuver card and the static active project card.
    @ViewBuilder
    private var topProjectCard: some View {
        if coordinator.isNavigating {
            NavigationManeuverCard(
                navigationManager: coordinator.navigationManager,
                destinationName: topOverlayProject?.title,
                isExpanded: $isManeuverExpanded
            )
            .transition(.opacity)
        } else if let project = topOverlayProject {
            ActiveProjectCard(project: project)
                .transition(.opacity)
        }
    }

    /// Exit pill shown below the top project overlay. Auto-sizing width,
    /// 44pt tall (HIG touch target), inverted fill so it reads as the
    /// primary action on the dark card stack above it.
    private var exitProjectPill: some View {
        Button(action: exitProjectMode) {
            HStack(spacing: 8) {
                Text("EXIT PROJECT")
                    .font(OPSStyle.Typography.smallButton)
                    .foregroundColor(OPSStyle.Colors.cardBackground)
                Image("ops.close")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(OPSStyle.Colors.cardBackground)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(OPSStyle.Colors.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Exit project")
    }

    /// Teardown action for the EXIT pill. Stops routing (if active),
    /// posts the legacy StopNavigation notification, exits project mode,
    /// and collapses the maneuver list. Medium impact haptic fires at
    /// the moment of commitment.
    private func exitProjectMode() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if InProgressManager.shared.isRouting {
            InProgressManager.shared.stopRouting()
        }
        NotificationCenter.default.post(
            name: Notification.Name("StopNavigation"),
            object: nil
        )

        withAnimation(OPSStyle.Animation.standard) {
            isManeuverExpanded = false
            appState.exitProjectMode()
        }
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

            // 5. Stacked group list — when tapping a multi-project pin
            // Styled to match ProjectPinCard: ultraThinMaterial, rounded top corners, drag handle
            // Supports drag-to-dismiss (swipe down) matching ProjectPinCard behavior
            if coordinator.showingStackedGroup && !coordinator.stackedGroupProjects.isEmpty {
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 0) {

                        // ── Drag indicator (matches ProjectPinCard) ──
                        HStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                                .fill(Color.white.opacity(0.20))
                                .frame(width: 36, height: 4)
                            Spacer()
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                        // ── Header ──
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(coordinator.stackedGroupProjects.count) PROJECTS")
                                    .font(OPSStyle.Typography.caption)
                                    .tracking(0.5)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                Text("at this location")
                                    .font(OPSStyle.Typography.smallBody)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)

                        // ── Divider ──
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                            .padding(.vertical, 12)

                        // ── Project list ──
                        ForEach(coordinator.stackedGroupProjects) { project in
                            Button {
                                withAnimation(OPSStyle.Animation.standard) {
                                    coordinator.showingStackedGroup = false
                                    coordinator.stackedGroupProjects = []
                                    coordinator.selectProject(project)
                                    coordinator.refreshProjectAnnotations()
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(Color(ProjectAnnotationRenderer.statusUIColor(for: project.status)))
                                        .frame(width: 8, height: 8)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.title.uppercased())
                                            .font(OPSStyle.Typography.caption)
                                            .tracking(0.5)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                            .lineLimit(1)

                                        if let client = project.client {
                                            Text(client.displayName)
                                                .font(OPSStyle.Typography.cardBody)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    // Status badge (matching ProjectPinCard)
                                    Text(project.status.displayName.uppercased())
                                        .font(OPSStyle.Typography.miniLabel)
                                        .tracking(0.3)
                                        .foregroundColor(project.status.color)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(project.status.color.opacity(0.15))
                                        )

                                    Image(OPSStyle.Icons.chevronRight)
                                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if project.id != coordinator.stackedGroupProjects.last?.id {
                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 1)
                                    .padding(.leading, 34)
                            }
                        }

                        Spacer().frame(height: 14)
                    }
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 4,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 4
                        )
                        .fill(.ultraThinMaterial)
                        .overlay(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 4,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 4
                            )
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    )
                    .offset(y: stackedGroupDragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let translation = value.translation.height
                                if translation > 0 {
                                    // Dragging down — allow with rubber-band feel
                                    stackedGroupDragOffset = translation
                                }
                            }
                            .onEnded { value in
                                let translation = value.translation.height
                                if translation > 50 {
                                    // Swipe down past threshold — dismiss
                                    withAnimation(OPSStyle.Animation.standard) {
                                        stackedGroupDragOffset = 400
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        coordinator.showingStackedGroup = false
                                        coordinator.stackedGroupProjects = []
                                        stackedGroupDragOffset = 0
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } else {
                                    // Snap back
                                    withAnimation(OPSStyle.Animation.standard) {
                                        stackedGroupDragOffset = 0
                                    }
                                }
                            }
                    )
                    .padding(.bottom, 90)
                }
                .transition(.move(edge: .bottom))
                .animation(OPSStyle.Animation.standard, value: coordinator.showingStackedGroup)
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

            // 7. Top project overlay — shown whenever the user is in project mode.
            //    - Routing → NavigationManeuverCard (expandable turn list)
            //    - Not routing → ActiveProjectCard (static project summary)
            //    - Below either card → right-aligned EXIT PROJECT pill
            // AppHeader is hidden by HomeContentView while in project mode, so
            // this overlay owns the top of the screen. Positioned at the
            // window's top safe area inset + 8pt breathing room.
            if appState.isInProjectMode {
                VStack(spacing: 10) {
                    topProjectCard
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        exitProjectPill
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, topSafeAreaInset + 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(OPSStyle.Animation.standard, value: appState.isInProjectMode)
                .animation(OPSStyle.Animation.spring, value: coordinator.isNavigating)
                .animation(OPSStyle.Animation.spring, value: isManeuverExpanded)
            }

            // 7b. Trip info strip — above the ProjectActionBar while navigating.
            // No horizontal padding: the strip uses a soft vertical gradient
            // that bleeds edge-to-edge into the map. Bottom padding sits it
            // tight to the action bar (~8pt visual gap accounting for the
            // gradient falloff).
            if coordinator.isNavigating {
                VStack {
                    Spacer()
                    NavigationTripStrip(navigationManager: coordinator.navigationManager)
                        .padding(.bottom, appState.isInProjectMode ? 208 : 92)
                }
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .bottom))
                .animation(OPSStyle.Animation.standard, value: coordinator.isNavigating)
            }

            // 8. Geofence banners — below the top project overlay when in
            // project mode, below the AppHeader otherwise.
            if geofenceManager.pendingArrival != nil || geofenceManager.pendingDeparture != nil {
                VStack {
                    Spacer().frame(height: appState.isInProjectMode ? 240 : 100)

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
                if filterMode == .today {
                    // Today's tasks mode: show the pin card for assigned tasks
                    coordinator.selectProject(project)
                    onProjectSelected(project)
                } else {
                    // Other filter modes: update selected pin silently (no popup)
                    coordinator.selectedProjectId = project.id
                }
            }
        }
        .onChange(of: coordinator.showingProjectCard) { _, newValue in
            appState.isShowingMapOverlay = newValue || coordinator.showingCrewTooltip || coordinator.showingStackedGroup
        }
        .onChange(of: coordinator.showingCrewTooltip) { _, newValue in
            appState.isShowingMapOverlay = coordinator.showingProjectCard || newValue || coordinator.showingStackedGroup
        }
        .onChange(of: coordinator.showingStackedGroup) { _, newValue in
            appState.isShowingMapOverlay = coordinator.showingProjectCard || coordinator.showingCrewTooltip || newValue
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
        // Auto-collapse the expanded maneuver list whenever navigation
        // stops or project mode ends — stale expansion state across
        // sessions would be jarring.
        .onChange(of: coordinator.isNavigating) { _, isNavigating in
            if !isNavigating, isManeuverExpanded {
                withAnimation(OPSStyle.Animation.standard) {
                    isManeuverExpanded = false
                }
            }
        }
        .onChange(of: appState.isInProjectMode) { _, inProjectMode in
            if !inProjectMode, isManeuverExpanded {
                isManeuverExpanded = false
            }
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

            // Zoom to fit all visible markers — only outside navigation.
            // Uses the current filter mode (Today / Active / All) to decide
            // which pins to frame.
            if !coordinator.isNavigating {
                controlButton(
                    icon: "arrow.up.left.and.arrow.down.right",
                    isActive: false
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    coordinator.zoomToFitVisibleMarkers()
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
