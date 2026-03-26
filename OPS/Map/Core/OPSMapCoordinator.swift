//
//  OPSMapCoordinator.swift
//  OPS
//
//  Central state manager for the Mapbox-based map.
//  Owns camera state, project / crew annotations, navigation,
//  selection, speed-adaptive zoom, and orientation mode.
//

import SwiftUI
import MapboxMaps
import CoreLocation
import Combine
import MapKit

// MARK: - Supporting Types

/// Which projects are shown on the map.
enum MapFilterMode: String {
    case today
    case active
    case all
}

/// North-up vs course-up.
enum OrientationMode: String {
    case northUp
    case courseUp
}

// MARK: - OPSMapCoordinator

@MainActor
final class OPSMapCoordinator: ObservableObject {

    // ──────────────────────────────────────────────
    // MARK: - Published State
    // ──────────────────────────────────────────────

    // Camera
    @Published var cameraCenter: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    @Published var cameraZoom: Double = 14.0
    @Published var cameraHeading: CLLocationDirection = 0
    @Published var cameraPitch: CGFloat = 0

    // Projects
    @Published var projects: [Project] = []
    @Published var filterMode: MapFilterMode = .today

    // Selection
    @Published var selectedProjectId: String?
    @Published var selectedCrewMemberId: String?
    @Published var showingProjectCard: Bool = false
    @Published var showingCrewTooltip: Bool = false

    // Stacked project groups (multiple projects at same location)
    @Published var showingStackedGroup: Bool = false
    @Published var stackedGroupProjects: [Project] = []

    /// Maps a location group annotation ID → array of project IDs at that location
    private var locationGroupMap: [String: [String]] = [:]

    // Crew locations (keyed by userId)
    @Published var crewLocations: [String: CrewLocationUpdate] = [:]

    // Navigation
    @Published var isNavigating: Bool = false
    @Published var navigationDestination: CLLocationCoordinate2D?
    @Published var isFollowingUser: Bool = true

    // Orientation
    @Published var orientationMode: OrientationMode = .northUp

    // Map style & display
    @Published var mapStyle: OPSMapStyle = .dark
    @Published var show3DBuildings: Bool = true
    @Published var speedZoomEnabled: Bool = true

    // ──────────────────────────────────────────────
    // MARK: - Dependencies
    // ──────────────────────────────────────────────

    let locationManager: LocationManager

    /// Navigation manager — owns route calculation and turn-by-turn progress.
    private(set) lazy var navigationManager = OPSNavigationManager(locationManager: locationManager)

    /// Crew location subscriber — polls Supabase for team positions.
    let crewSubscriber = CrewLocationSubscriber()

    // ──────────────────────────────────────────────
    // MARK: - Internal / Private
    // ──────────────────────────────────────────────

    /// Raw reference to the Mapbox MapView — set once via `setupMapView(_:)`.
    private(set) var mapView: MapView?

    /// Annotation managers — created after the map view is available.
    private var projectAnnotationManager: PointAnnotationManager?
    private var crewAnnotationManager: PointAnnotationManager?

    private var cancellables = Set<AnyCancellable>()
    private var styleLoadedCancellable: (any Cancelable)?
    private var crewTrackingCancellable: AnyCancellable?
    private var arrivalCancellable: AnyCancellable?

    /// Tracks whether we have centred on the user at least once.
    private var hasInitializedCamera = false

    /// Last zoom level set by speed-adaptive logic (avoids redundant camera moves).
    private var lastSpeedZoom: Double?

    // ──────────────────────────────────────────────
    // MARK: - Constants
    // ──────────────────────────────────────────────

    private enum CameraDuration {
        static let following: TimeInterval    = 0.3
        static let speedZoom: TimeInterval    = 1.0
        static let recenter: TimeInterval     = 0.6
        static let routeOverview: TimeInterval = 0.8
    }

    private enum BrowseDefaults {
        static let zoom: Double = 14.0
        static let pitch: CGFloat = 0
    }

    private enum NavigationDefaults {
        static let pitch: CGFloat = 45
    }

    private enum RouteLineIds {
        static let source = "ops-route-line-source"
        static let layer  = "ops-route-line-layer"
    }

    /// Minimum speed (m/s) before we use GPS course instead of device heading.
    private let courseSpeedThreshold: Double = 1.25

    // ──────────────────────────────────────────────
    // MARK: - Computed
    // ──────────────────────────────────────────────

    var selectedProject: Project? {
        guard let id = selectedProjectId else { return nil }
        return projects.first { $0.id == id }
    }

    // ──────────────────────────────────────────────
    // MARK: - Init
    // ──────────────────────────────────────────────

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
        subscribeToLocation()
    }

    // ──────────────────────────────────────────────
    // MARK: - Map View Setup
    // ──────────────────────────────────────────────

    /// Called once from `OPSMapView.makeUIView`.
    func setupMapView(_ mapView: MapView) {
        self.mapView = mapView

        rebuildAnnotationManagers()

        // Apply OPS style customizations after the base style finishes loading
        styleLoadedCancellable = mapView.mapboxMap.onStyleLoaded.observe { [weak self] _ in
            guard let self, let mv = self.mapView else { return }
            MapStyleApplicator.apply(self.mapStyle, to: mv, show3DBuildings: self.show3DBuildings)
        }

        // If we already have a user location, jump to it
        if let loc = locationManager.currentLocation {
            flyTo(
                center: loc.coordinate,
                zoom: BrowseDefaults.zoom,
                heading: 0,
                pitch: BrowseDefaults.pitch,
                duration: 0 // instant on first load
            )
            hasInitializedCamera = true
        }
    }

    /// Switch the map to a different OPS style at runtime.
    /// Reloads the base Mapbox style, then re-applies color overrides and annotations.
    func setMapStyle(_ style: OPSMapStyle) {
        guard style != mapStyle else { return }
        mapStyle = style

        guard let mapView = mapView else { return }
        mapView.backgroundColor = style.backgroundColor

        // Loading a new style URI triggers onStyleLoaded, which calls
        // MapStyleApplicator.apply automatically. We just need to
        // rebuild annotations afterward.
        mapView.mapboxMap.loadStyle(style.baseStyleURI)

        // Annotation managers are invalidated by a style reload —
        // the onStyleLoaded handler applies colors, then we rebuild here.
        // Use a brief delay to ensure the style is fully applied.
        Task { @MainActor [weak self] in
            guard let self, let mv = self.mapView else { return }
            // Wait for style load to settle
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            self.rebuildAnnotationManagers()
            self.refreshProjectAnnotations()
            self.refreshCrewAnnotations()

            // Re-draw route line if navigating
            if self.isNavigating {
                let coords = self.navigationManager.routeCoordinates
                if !coords.isEmpty {
                    self.drawRouteLine(coords)
                }
            }
        }
    }

    /// Enable or disable 3D building extrusions.
    func set3DBuildings(_ enabled: Bool) {
        guard enabled != show3DBuildings else { return }
        show3DBuildings = enabled
        guard let mapView = mapView else { return }
        MapStyleApplicator.set3DBuildings(enabled, mapView: mapView)
    }

    /// Set the default orientation mode.
    func setOrientation(_ mode: OrientationMode) {
        guard mode != orientationMode else { return }
        orientationMode = mode

        // If switching to north-up, snap heading to 0
        if mode == .northUp, let location = locationManager.currentLocation {
            flyTo(
                center: location.coordinate,
                zoom: cameraZoom,
                heading: 0,
                pitch: cameraPitch,
                duration: CameraDuration.recenter
            )
        }
    }

    /// (Re-)create annotation managers and wire delegates.
    /// Called on initial setup and after any style reload.
    private func rebuildAnnotationManagers() {
        guard let mapView = mapView else { return }

        projectAnnotationManager = mapView.annotations.makePointAnnotationManager(id: "ops-project-pins")
        crewAnnotationManager    = mapView.annotations.makePointAnnotationManager(id: "ops-crew-dots")

        projectAnnotationManager?.delegate = self
        crewAnnotationManager?.delegate    = self
    }

    // ──────────────────────────────────────────────
    // MARK: - Combine — Location
    // ──────────────────────────────────────────────

    private func subscribeToLocation() {
        // Full location updates (position + speed + course)
        locationManager.$currentLocation
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)

        // Device heading (compass) — used when stationary in courseUp mode
        locationManager.$deviceHeading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] heading in
                self?.handleHeadingUpdate(heading)
            }
            .store(in: &cancellables)
    }

    // ──────────────────────────────────────────────
    // MARK: - Location Handling
    // ──────────────────────────────────────────────

    private func handleLocationUpdate(_ location: CLLocation) {
        // First location — jump to user
        if !hasInitializedCamera {
            hasInitializedCamera = true
            flyTo(
                center: location.coordinate,
                zoom: BrowseDefaults.zoom,
                heading: 0,
                pitch: BrowseDefaults.pitch,
                duration: 0
            )
        }

        guard isFollowingUser else { return }

        // Resolve heading
        let heading = resolvedHeading(from: location)

        if isNavigating {
            // Speed-adaptive zoom (if enabled in settings)
            let targetZoom: Double
            let duration: TimeInterval
            if speedZoomEnabled {
                targetZoom = zoomForSpeed(location.speed)
                duration = (targetZoom != lastSpeedZoom)
                    ? CameraDuration.speedZoom
                    : CameraDuration.following
                lastSpeedZoom = targetZoom
            } else {
                targetZoom = cameraZoom
                duration = CameraDuration.following
            }

            flyTo(
                center: location.coordinate,
                zoom: targetZoom,
                heading: heading,
                pitch: NavigationDefaults.pitch,
                duration: duration
            )
        } else {
            // Browse mode — follow without pitch
            flyTo(
                center: location.coordinate,
                zoom: cameraZoom, // keep current zoom
                heading: heading,
                pitch: BrowseDefaults.pitch,
                duration: CameraDuration.following
            )
        }
    }

    private func handleHeadingUpdate(_ heading: CLLocationDirection) {
        // Only relevant in courseUp when speed is below threshold
        guard orientationMode == .courseUp,
              isFollowingUser,
              let location = locationManager.currentLocation,
              location.speed <= courseSpeedThreshold else { return }

        let targetHeading = heading
        // Wrap-around-safe angular difference (e.g. 358° → 2° = 4°)
        let rawDiff = abs(cameraHeading - targetHeading)
        let headingDiff = min(rawDiff, 360 - rawDiff)
        // Only update if change is meaningful (> 5 degrees)
        guard headingDiff > 5 else { return }

        flyTo(
            center: location.coordinate,
            zoom: cameraZoom,
            heading: targetHeading,
            pitch: isNavigating ? NavigationDefaults.pitch : BrowseDefaults.pitch,
            duration: CameraDuration.following
        )
    }

    // ──────────────────────────────────────────────
    // MARK: - Heading Resolution
    // ──────────────────────────────────────────────

    /// Returns the heading the camera should use given the current orientation mode.
    private func resolvedHeading(from location: CLLocation) -> CLLocationDirection {
        switch orientationMode {
        case .northUp:
            return 0
        case .courseUp:
            if location.speed > courseSpeedThreshold, location.course >= 0 {
                return location.course
            } else {
                return locationManager.deviceHeading
            }
        }
    }

    // ──────────────────────────────────────────────
    // MARK: - Speed-Adaptive Zoom
    // ──────────────────────────────────────────────

    private func zoomForSpeed(_ speed: CLLocationSpeed) -> Double {
        switch speed {
        case ..<2:      return 15.5   // walking
        case 2..<10:    return 14.5   // urban
        case 10..<25:   return 13.5   // suburban
        case 25..<35:   return 12.5   // highway
        default:        return 11.5   // fast
        }
    }

    // ──────────────────────────────────────────────
    // MARK: - Camera Control
    // ──────────────────────────────────────────────

    /// Central camera-move method. Every camera change goes through here.
    private func flyTo(
        center: CLLocationCoordinate2D,
        zoom: Double,
        heading: CLLocationDirection,
        pitch: CGFloat,
        duration: TimeInterval
    ) {
        guard let mapView = mapView else { return }

        // Keep published state in sync
        cameraCenter  = center
        cameraZoom    = zoom
        cameraHeading = heading
        cameraPitch   = pitch

        let cameraOptions = CameraOptions(
            center: center,
            zoom: zoom,
            bearing: heading,
            pitch: pitch
        )

        if duration > 0 {
            mapView.camera.ease(
                to: cameraOptions,
                duration: duration,
                curve: .easeInOut,
                completion: nil
            )
        } else {
            mapView.mapboxMap.setCamera(to: cameraOptions)
        }
    }

    // ──────────────────────────────────────────────
    // MARK: - Public Actions
    // ──────────────────────────────────────────────

    /// Re-centre the camera on the user's current position.
    func recenterOnUser() {
        guard let location = locationManager.currentLocation else { return }
        isFollowingUser = true
        let heading = resolvedHeading(from: location)
        flyTo(
            center: location.coordinate,
            zoom: isNavigating ? zoomForSpeed(location.speed) : BrowseDefaults.zoom,
            heading: heading,
            pitch: isNavigating ? NavigationDefaults.pitch : BrowseDefaults.pitch,
            duration: CameraDuration.recenter
        )
    }

    /// Toggle between north-up and course-up.
    func toggleOrientation() {
        orientationMode = (orientationMode == .northUp) ? .courseUp : .northUp

        // Immediately apply the new heading
        guard let location = locationManager.currentLocation else { return }
        let heading = resolvedHeading(from: location)
        flyTo(
            center: location.coordinate,
            zoom: cameraZoom,
            heading: heading,
            pitch: isNavigating ? NavigationDefaults.pitch : BrowseDefaults.pitch,
            duration: CameraDuration.recenter
        )
    }

    /// Set the map filter mode (today / all) and refresh annotations.
    func setFilter(_ mode: MapFilterMode) {
        filterMode = mode
        refreshProjectAnnotations()
    }

    /// Clear all selection state (project, crew, cards).
    func deselectAll() {
        selectedProjectId = nil
        selectedCrewMemberId = nil
        showingProjectCard = false
        showingCrewTooltip = false
        showingStackedGroup = false
        stackedGroupProjects = []
        refreshProjectAnnotations()
        refreshCrewAnnotations()
    }

    /// Start subscribing to crew locations for the given org.
    func startCrewTracking(orgId: String) {
        // Cancel any prior subscription to prevent stacking
        crewTrackingCancellable?.cancel()

        Task {
            await crewSubscriber.subscribe(orgId: orgId)
        }

        crewTrackingCancellable = crewSubscriber.$crewLocations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] locations in
                self?.crewLocations = locations
                self?.refreshCrewAnnotations()
            }
    }

    /// Stop subscribing to crew locations.
    func stopCrewTracking() {
        crewTrackingCancellable?.cancel()
        crewTrackingCancellable = nil
        Task {
            await crewSubscriber.unsubscribe()
        }
    }

    /// Select a project by ID. Flies camera to it.
    func selectProject(_ project: Project) {
        selectedProjectId = project.id
        selectedCrewMemberId = nil
        showingProjectCard = true
        showingCrewTooltip = false

        guard let coord = project.coordinate else { return }
        isFollowingUser = false
        flyTo(
            center: coord,
            zoom: 15.5,
            heading: cameraHeading,
            pitch: BrowseDefaults.pitch,
            duration: CameraDuration.recenter
        )
    }

    /// Show a route-overview zoom level (stub calls this).
    func showRouteOverview() {
        guard isNavigating,
              let userCoord = locationManager.currentLocation?.coordinate,
              let destCoord = navigationDestination else { return }

        isFollowingUser = false

        // Compute bounding box
        let minLat = min(userCoord.latitude, destCoord.latitude)
        let maxLat = max(userCoord.latitude, destCoord.latitude)
        let minLon = min(userCoord.longitude, destCoord.longitude)
        let maxLon = max(userCoord.longitude, destCoord.longitude)

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        // Rough zoom from span — good enough for an overview
        let latSpan = maxLat - minLat
        let lonSpan = maxLon - minLon
        let maxSpan = max(latSpan, lonSpan)
        let overviewZoom = max(10.0, 14.0 - log2(max(maxSpan, 0.001) / 0.01))

        flyTo(
            center: center,
            zoom: overviewZoom,
            heading: 0,
            pitch: 0,
            duration: CameraDuration.routeOverview
        )
    }

    // ──────────────────────────────────────────────
    // MARK: - Navigation (core start / stop)
    // ──────────────────────────────────────────────

    /// Start navigation to a project.
    /// Calculates route via MKDirections, draws route line, and starts progress tracking.
    func startNavigation(to project: Project) {
        guard let coord = project.coordinate else { return }
        isNavigating = true
        navigationDestination = coord
        selectedProjectId = project.id
        isFollowingUser = true
        lastSpeedZoom = nil

        // Switch location manager to high-accuracy mode
        locationManager.enableNavigationMode()

        // Fly to the user with navigation pitch
        if let location = locationManager.currentLocation {
            let heading = resolvedHeading(from: location)
            flyTo(
                center: location.coordinate,
                zoom: zoomForSpeed(location.speed),
                heading: heading,
                pitch: NavigationDefaults.pitch,
                duration: CameraDuration.routeOverview
            )
        }

        // Calculate route and draw line asynchronously
        Task { [weak self] in
            guard let self = self else { return }
            guard let origin = self.locationManager.currentLocation?.coordinate else { return }

            do {
                try await self.navigationManager.startNavigation(from: origin, to: coord)

                // Draw route line on map
                let coords = self.navigationManager.routeCoordinates
                if !coords.isEmpty {
                    self.drawRouteLine(coords)
                }

                // Sync with InProgressManager for backward compatibility
                self.syncInProgressManagerStart(route: self.navigationManager.currentRoute, destination: coord)

                // Subscribe to arrival
                self.subscribeToArrival()
            } catch {
                print("[OPSMapCoordinator] Route calculation failed: \(error.localizedDescription)")
                // Navigation UI is already showing; it will just lack a route line
            }
        }
    }

    /// Stop navigation and return to browse mode.
    func stopNavigation() {
        isNavigating = false
        navigationDestination = nil
        lastSpeedZoom = nil

        // Stop navigation manager and remove route line
        navigationManager.stopNavigation()
        removeRouteLine()
        arrivalCancellable?.cancel()
        arrivalCancellable = nil

        // Sync with InProgressManager
        InProgressManager.shared.stopRouting()

        locationManager.disableNavigationMode()

        // Return to browse
        if let location = locationManager.currentLocation {
            flyTo(
                center: location.coordinate,
                zoom: BrowseDefaults.zoom,
                heading: orientationMode == .northUp ? 0 : resolvedHeading(from: location),
                pitch: BrowseDefaults.pitch,
                duration: CameraDuration.recenter
            )
        }

        isFollowingUser = true
    }

    // ──────────────────────────────────────────────
    // MARK: - Annotation Stubs (Tasks 5, 6, 10)
    // ──────────────────────────────────────────────

    /// Rebuild project pin annotations from `self.projects` and `filterMode`.
    func refreshProjectAnnotations() {
        guard let manager = projectAnnotationManager else { return }

        if filterMode == .today {
            // TODAY mode: show task-based annotations
            manager.annotations = buildTodayTaskAnnotations()
        } else {
            // ACTIVE / ALL: show project-based annotations with task-colored rings
            manager.annotations = buildProjectAnnotations()
        }
    }

    /// Build project annotations for ACTIVE / ALL modes.
    /// Groups projects at the same location and renders stacked pins for groups.
    private func buildProjectAnnotations() -> [PointAnnotation] {
        let filteredProjects: [Project]
        switch filterMode {
        case .active:
            filteredProjects = projects.filter { project in
                guard project.coordinate != nil else { return false }
                return project.status == .accepted || project.status == .inProgress
            }
        case .all:
            filteredProjects = projects.filter { $0.coordinate != nil }
        case .today:
            return [] // Handled separately
        }

        // Group projects by location (6 decimal places ≈ 0.1m precision)
        var locationGroups: [String: [Project]] = [:]
        for project in filteredProjects {
            guard let coord = project.coordinate else { continue }
            let key = "\(String(format: "%.6f", coord.latitude)),\(String(format: "%.6f", coord.longitude))"
            locationGroups[key, default: []].append(project)
        }

        var annotations: [PointAnnotation] = []
        var newGroupMap: [String: [String]] = [:]

        for (_, group) in locationGroups {
            guard let first = group.first, let coord = first.coordinate else { continue }

            if group.count == 1 {
                // Single project — standard pin
                let project = first
                let isSelected = (project.id == selectedProjectId)
                let activeTasks = project.tasks.filter { $0.status == .active }
                let taskColorHexes = activeTasks.map { $0.effectiveColor }

                let image = ProjectAnnotationRenderer.renderProject(
                    name: project.title,
                    status: project.status,
                    taskColorHexes: taskColorHexes,
                    isSelected: isSelected
                )

                var annotation = PointAnnotation(id: project.id, coordinate: coord)
                annotation.image = .init(image: image, name: "project-\(project.id)-\(isSelected)")
                annotation.iconAnchor = .bottom
                annotations.append(annotation)
            } else {
                // Multiple projects at same location — stacked pin
                let groupId = "group-\(first.id)"
                let isSelected = group.contains { $0.id == selectedProjectId }

                let stackedInfo = group.map {
                    ProjectAnnotationRenderer.StackedProjectInfo(name: $0.title, status: $0.status)
                }

                let image = ProjectAnnotationRenderer.renderStackedProject(
                    projects: stackedInfo,
                    isSelected: isSelected
                )

                var annotation = PointAnnotation(id: groupId, coordinate: coord)
                annotation.image = .init(image: image, name: "stacked-\(groupId)-\(isSelected)")
                annotation.iconAnchor = .bottom
                annotations.append(annotation)

                // Track which projects belong to this group
                newGroupMap[groupId] = group.map { $0.id }
            }
        }

        locationGroupMap = newGroupMap
        return annotations
    }

    /// Build task-based annotations for TODAY mode.
    /// Groups today's tasks by project location. Label = task name (+ "+N"),
    /// subtitle = project name. Ring = segmented task type colors.
    private func buildTodayTaskAnnotations() -> [PointAnnotation] {
        let calendar = Calendar.current
        var annotations: [PointAnnotation] = []

        // Find all projects that have tasks scheduled today
        for project in projects {
            guard let coord = project.coordinate else { continue }

            let todaysTasks = project.tasks.filter { task in
                guard let start = task.startDate else { return false }
                // Show all tasks scheduled today — active AND completed.
                // Cancelled tasks are excluded since they are no longer relevant.
                guard task.status == .active || task.status == .completed else { return false }
                return calendar.isDateInToday(start)
            }

            guard !todaysTasks.isEmpty else { continue }

            let isSelected = (project.id == selectedProjectId)

            // Build label: first task name, appended with "+N" if multiple
            let firstName = todaysTasks.first?.displayTitle ?? "Task"
            let taskLabel: String
            if todaysTasks.count > 1 {
                taskLabel = "\(firstName) +\(todaysTasks.count - 1)"
            } else {
                taskLabel = firstName
            }

            // Collect all task type colors
            let taskColorHexes = todaysTasks.map { $0.effectiveColor }

            let image = ProjectAnnotationRenderer.renderTask(
                taskName: taskLabel,
                projectName: project.title,
                taskColorHexes: taskColorHexes,
                isSelected: isSelected
            )

            // Use project.id as annotation ID so tapping still selects the project
            var annotation = PointAnnotation(id: project.id, coordinate: coord)
            annotation.image = .init(image: image, name: "task-\(project.id)-\(isSelected)")
            annotation.iconAnchor = .bottom
            annotations.append(annotation)
        }

        return annotations
    }

    /// Rebuild crew-dot annotations from `self.crewLocations`.
    func refreshCrewAnnotations() {
        guard let manager = crewAnnotationManager else { return }

        // Collect active project coordinates for on-site detection
        let projectCoords: [(lat: Double, lng: Double)] = projects.compactMap { project in
            guard let coord = project.coordinate else { return nil }
            return (lat: coord.latitude, lng: coord.longitude)
        }

        // Build annotation array
        var annotations: [PointAnnotation] = []

        for (userId, update) in crewLocations {
            let isSelected = (userId == selectedCrewMemberId)

            // Resolve crew status (on-site / en-route / idle)
            let crewStatus = CrewAnnotationRenderer.resolveStatus(
                from: update,
                projectCoordinates: projectCoords
            )

            // Render the dot image (label + ring + dot)
            let image = CrewAnnotationRenderer.render(
                firstName: update.firstName,
                status: crewStatus,
                isSelected: isSelected
            )

            // Build annotation
            let coord = CLLocationCoordinate2D(latitude: update.lat, longitude: update.lng)
            var annotation = PointAnnotation(id: userId, coordinate: coord)
            annotation.image = .init(image: image, name: "crew-\(userId)-\(isSelected)")
            annotation.iconAnchor = .bottom

            annotations.append(annotation)
        }

        manager.annotations = annotations
    }

    /// Draw a route polyline on the Mapbox map using a GeoJSON source and LineLayer.
    func drawRouteLine(_ coordinates: [CLLocationCoordinate2D]) {
        guard let mapView = mapView, !coordinates.isEmpty else { return }

        // Remove any existing route line first
        removeRouteLine()

        // Build GeoJSON LineString geometry
        let lineCoordinates = coordinates.map { coord in
            [coord.longitude, coord.latitude]
        }

        let geoJSON: [String: Any] = [
            "type": "Feature",
            "geometry": [
                "type": "LineString",
                "coordinates": lineCoordinates
            ],
            "properties": [:] as [String: Any]
        ]

        // Convert to JSON string
        guard let jsonData = try? JSONSerialization.data(withJSONObject: geoJSON),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        // Add GeoJSON source
        var source = GeoJSONSource(id: RouteLineIds.source)
        source.data = .string(jsonString)

        do {
            try mapView.mapboxMap.addSource(source)
        } catch {
            print("[OPSMapCoordinator] Failed to add route source: \(error)")
            return
        }

        // Add LineLayer
        var lineLayer = LineLayer(id: RouteLineIds.layer, source: RouteLineIds.source)
        lineLayer.lineColor = .constant(StyleColor(UIColor(red: 89.0/255.0, green: 119.0/255.0, blue: 148.0/255.0, alpha: 1.0))) // #597794
        lineLayer.lineWidth = .constant(4.0)
        lineLayer.lineOpacity = .constant(0.85)
        lineLayer.lineCap = .constant(.round)
        lineLayer.lineJoin = .constant(.round)

        do {
            try mapView.mapboxMap.addLayer(lineLayer)
        } catch {
            print("[OPSMapCoordinator] Failed to add route layer: \(error)")
        }
    }

    /// Remove the route line source and layer from the map.
    func removeRouteLine() {
        guard let mapView = mapView else { return }

        // Remove layer first, then source (layer depends on source)
        if mapView.mapboxMap.layerExists(withId: RouteLineIds.layer) {
            try? mapView.mapboxMap.removeLayer(withId: RouteLineIds.layer)
        }
        if mapView.mapboxMap.sourceExists(withId: RouteLineIds.source) {
            try? mapView.mapboxMap.removeSource(withId: RouteLineIds.source)
        }
    }

    // ──────────────────────────────────────────────
    // MARK: - Arrival Detection
    // ──────────────────────────────────────────────

    /// Subscribe to the navigation manager's `hasArrived` and stop navigation after a delay.
    private func subscribeToArrival() {
        arrivalCancellable?.cancel()
        arrivalCancellable = navigationManager.$hasArrived
            .removeDuplicates()
            .filter { $0 == true }
            .first()
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Wait 3 seconds, then stop navigation and post arrival notification
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                    self.stopNavigation()
                    NotificationCenter.default.post(
                        name: Notification.Name("ShowArrivalMessage"),
                        object: nil
                    )
                }
            }
    }

    // ──────────────────────────────────────────────
    // MARK: - InProgressManager Sync
    // ──────────────────────────────────────────────

    /// Populate InProgressManager from the already-calculated MKRoute (avoids duplicate request).
    private func syncInProgressManagerStart(route: MKRoute?, destination: CLLocationCoordinate2D) {
        let ipm = InProgressManager.shared
        ipm.isRouting = true

        // Post routing notification
        NotificationCenter.default.post(
            name: Notification.Name("RoutingStateChanged"),
            object: nil,
            userInfo: ["isRouting": true]
        )

        // If we have a route, populate InProgressManager's properties from it
        if let route = route {
            ipm.activeRoute = route
            ipm.processRouteDetails(route)
        }
    }

    // ──────────────────────────────────────────────
    // MARK: - Cleanup
    // ──────────────────────────────────────────────

    deinit {
        cancellables.removeAll()
    }
}

// MARK: - AnnotationInteractionDelegate

extension OPSMapCoordinator: AnnotationInteractionDelegate {
    nonisolated func annotationManager(
        _ manager: any AnnotationManager,
        didDetectTappedAnnotations annotations: [any MapboxMaps.Annotation]
    ) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let tapped = annotations.first as? PointAnnotation else { return }

            let tappedId = tapped.id

            // Check if this is a stacked location group
            if let projectIds = self.locationGroupMap[tappedId] {
                let groupProjects = projectIds.compactMap { id in
                    self.projects.first(where: { $0.id == id })
                }
                if !groupProjects.isEmpty {
                    self.stackedGroupProjects = groupProjects
                    self.showingStackedGroup = true
                    self.showingProjectCard = false
                    self.showingCrewTooltip = false
                    return
                }
            }

            // Check single project annotations
            if let project = self.projects.first(where: { $0.id == tappedId }) {
                self.selectProject(project)
                self.refreshProjectAnnotations()
                return
            }

            // Check crew annotations (id stored in annotation)
            self.selectedCrewMemberId = tappedId
            self.selectedProjectId = nil
            self.showingCrewTooltip = true
            self.showingProjectCard = false
            self.refreshCrewAnnotations()
        }
    }
}
