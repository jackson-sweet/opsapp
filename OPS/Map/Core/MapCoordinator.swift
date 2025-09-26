//
//  MapCoordinator.swift
//  OPS
//
//  Created by Claude on 2025-06-24.
//
//  Main coordinator for all map-related state and functionality

import SwiftUI
import MapKit
import CoreLocation
import Combine
import QuartzCore

@MainActor
final class MapCoordinator: ObservableObject {
    // MARK: - Published Properties
    
    // Map Display State
    @Published var mapRegion: MKCoordinateRegion
    @Published var mapCameraPosition: MapCameraPosition
    @Published var shouldAnimateNextUpdate = false
    @Published var isUserInteracting = false
    @Published var lastUserInteractionTime = Date()
    
    // Project State
    @Published var projects: [Project] = []
    @Published var selectedProjectId: String?
    @Published var showingProjectDetails = false
    
    // Navigation State
    @Published var isNavigating = false
    @Published var currentRoute: MKRoute?
    @Published var navigationState: NavigationState?
    @Published var routePolyline: MKPolyline?
    
    // User Location
    @Published var userLocation: CLLocation?
    @Published var userHeading: CLHeading?
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // Map Settings (from AppStorage)
    @AppStorage("mapAutoCenter") var autoCenter = true
    @AppStorage("mapAutoCenterTime") var autoCenterTime = "5"
    @AppStorage("mapZoomLevel") var zoomLevel = "medium"
    @AppStorage("map3DBuildings") var show3DBuildings = true
    @AppStorage("mapTrafficDisplay") var showTraffic = false
    @AppStorage("mapDefaultType") var defaultMapType = "standard"
    @AppStorage("mapOrientationMode") var mapOrientationMode = "north" // "north" or "course"
    
    // MARK: - Services (Public for access from views)
    
    var locationManager: LocationManager
    var navigationEngine: NavigationEngine
    
    // MARK: - Private Properties
    
    private var autoCenterTimer: Timer?
    private var routeRefreshTimer: Timer?
    private var hasInitializedWithUserLocation = false
    
    // Heading state
    private var currentHeading: CLLocationDirection = 0
    private var targetHeading: CLLocationDirection = 0
    private var isUpdatingHeading = false
    
    // MARK: - Computed Properties
    
    var selectedProject: Project? {
        guard let selectedProjectId = selectedProjectId else { return nil }
        return projects.first { $0.id == selectedProjectId }
    }
    
    var hasMultipleProjects: Bool {
        projects.count > 1
    }
    
    var mapType: MapStyle {
        switch defaultMapType {
        case "satellite":
            return .imagery
        case "hybrid":
            return .hybrid
        default:
            return .standard
        }
    }
    
    var zoomDistance: CLLocationDistance {
        switch zoomLevel {
        case "close":
            return 500 // meters
        case "far":
            return 5000 // meters
        default: // medium
            return 2000 // meters
        }
    }
    
    /// Get zoom distance for navigation (slightly closer than normal)
    var navigationZoomDistance: CLLocationDistance {
        // Use 75% of normal zoom for navigation (not 50% which is too close)
        return zoomDistance * 0.75
    }
    
    var autoCenterInterval: TimeInterval? {
        switch autoCenterTime {
        case "2":
            return 2.0
        case "5":
            return 5.0
        case "10":
            return 10.0
        default:
            return nil // off
        }
    }
    
    // MARK: - Initialization
    
    init(locationManager: LocationManager, navigationEngine: NavigationEngine) {
        self.locationManager = locationManager
        self.navigationEngine = navigationEngine
        
        // Initialize with user location if available, otherwise use a default
        let initialCenter: CLLocationCoordinate2D
        if let userLocation = locationManager.currentLocation {
            initialCenter = userLocation.coordinate
        } else {
            // Use current user location if available from location services
            initialCenter = locationManager.location?.coordinate ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        }
        
        let defaultRegion = MKCoordinateRegion(
            center: initialCenter,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        self.mapRegion = defaultRegion
        self.mapCameraPosition = .region(defaultRegion)
        
        // Don't set up observers in init - let the view do it when ready
    }
    
    // MARK: - Setup Methods
    
    func setupCoordinator() {
        setupLocationObservers()
        setupNavigationObservers()
        setupTimers()
    }
    
    private func setupLocationObservers() {
        // Observe full location updates with course data
        locationManager.$currentLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                guard let self = self, let location = location else { return }
                self.userLocation = location
                self.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
        
        // Observe course updates for navigation heading
        locationManager.$userCourse
            .receive(on: DispatchQueue.main)
            .sink { [weak self] course in
                guard let self = self else { return }
                // Update heading when in course mode and we have a valid course
                if self.mapOrientationMode == "course" && course >= 0 {
                    // Debug: Log course updates
                    
                    // Only update if course has changed significantly (more than 3 degrees)
                    let courseDiff = abs(self.currentHeading - course)
                    if courseDiff > 3 || courseDiff > 357 {
                        self.targetHeading = course
                        self.currentHeading = course
                        // Animate course updates for smooth rotation
                        self.updateMapHeading(animated: true)
                    }
                }
            }
            .store(in: &cancellables)
        
        // Observe current location for speed and course data
        locationManager.$currentLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                guard let self = self, let location = location else { return }
                self.userLocation = location
                self.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
        
        // Observe authorization status
        locationManager.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.locationAuthorizationStatus = status
            }
            .store(in: &cancellables)
    }
    
    private func setupNavigationObservers() {
        // Observe navigation state changes
        navigationEngine.$navigationState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.navigationState = state
                self?.handleNavigationStateChange(state)
            }
            .store(in: &cancellables)
        
        // Observe route updates
        navigationEngine.$currentRoute
            .receive(on: DispatchQueue.main)
            .sink { [weak self] route in
                self?.currentRoute = route
                self?.updateRoutePolyline(route)
                
                // Update InProgressManager with new route (for rerouting)
                if self?.isNavigating == true, let route = route {
                    InProgressManager.shared.activeRoute = route
                    InProgressManager.shared.processRouteDetails(route)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupTimers() {
        // Setup auto-center timer if enabled
        if autoCenter, let interval = autoCenterInterval {
            resetAutoCenterTimer(interval: interval)
        }
    }
    
    // MARK: - Public Methods
    
    /// Load projects for the current day
    func loadTodaysProjects(_ projects: [Project]) {
        self.projects = projects
        
        // Don't auto-select first project - let user choose
        // This prevents showStartConfirmation from appearing on launch
        
        // Update map region to fit all projects
        if !isNavigating {
            updateMapRegionForProjects()
        }
    }
    
    /// Select a project (from carousel or pin tap)
    func selectProject(_ project: Project) {
        selectedProjectId = project.id
        
        // Only show project details if the project is not already in progress
        if project.status != .inProgress {
            showingProjectDetails = true
        } else {
            showingProjectDetails = false
        }
    }
    
    /// Start navigation to the selected project
    func startNavigation() async throws {
        guard let project = selectedProject,
              let destination = project.coordinate else {
            throw NavigationError.noDestination
        }
        
        guard let userLocation = userLocation else {
            throw NavigationError.locationUnavailable
        }
        
        
        // Calculate route first before hiding the card
        try await navigationEngine.calculateRoute(
            from: userLocation.coordinate,
            to: destination
        )
        
        
        // Only now set isNavigating to true and hide the project card
        isNavigating = true
        
        // Sync with InProgressManager for UI consistency
        if !InProgressManager.shared.isRouting {
            InProgressManager.shared.startRouting(to: destination, from: userLocation.coordinate)
        }
        
        // Start navigation tracking
        navigationEngine.startNavigation()
        
        // Location manager is already tracking
        
        // Start route refresh timer
        startRouteRefreshTimer()
        
        // Update map to navigation mode
        updateMapForNavigation()
    }
    
    /// Stop current navigation
    func stopNavigation() {
        isNavigating = false
        navigationEngine.stopNavigation()
        stopRouteRefreshTimer()
        
        // Return to normal accuracy mode
        locationManager.disableNavigationMode()
        
        // Reset to north orientation when stopping navigation
        if mapOrientationMode != "north" {
            mapOrientationMode = "north"
            
            // Update map camera to north orientation
            if let userLocation = userLocation {
                let region = MKCoordinateRegion(
                    center: userLocation.coordinate,
                    latitudinalMeters: zoomDistance,
                    longitudinalMeters: zoomDistance
                )
                withAnimation(.easeInOut(duration: 0.3)) {
                    mapCameraPosition = .region(region)
                    mapRegion = region
                }
            }
        }
        
        // Sync with InProgressManager for UI consistency
        if InProgressManager.shared.isRouting {
            InProgressManager.shared.stopRouting()
        }
        
        // Return to project view mode
        updateMapRegionForProjects()
    }
    
    /// Center map on user location
    func recenterOnUser() {
        guard let userLocation = userLocation else { return }
        
        if mapOrientationMode == "course" {
            // Use camera with current course
            updateMapHeading(animated: true)
        } else {
            // Use standard region without rotation
            let region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: zoomDistance,
                longitudinalMeters: zoomDistance
            )
            
            withAnimation(.easeInOut(duration: 0.5)) {
                mapCameraPosition = .region(region)
                mapRegion = region
            }
        }
    }
    
    /// Fit all projects and user location in view
    func fitAllInView() {
        // If navigating, show route overview instead
        if isNavigating {
            showRouteOverview()
        } else {
            // Normal overview: show all projects and user location
            updateMapRegionForProjects(includeUserLocation: true, extraPadding: true)
        }
    }
    
    /// Show overview of the current navigation route
    func showRouteOverview() {
        guard isNavigating,
              let route = currentRoute,
              let userLocation = userLocation,
              let destination = selectedProject?.coordinate else {
            // Fallback to normal overview if route data is missing
            updateMapRegionForProjects(includeUserLocation: true, extraPadding: true)
            return
        }
        
        // Get all points along the route polyline
        let points = route.polyline.points()
        var coordinates: [CLLocationCoordinate2D] = []
        
        // Add route points (sample every 10th point to avoid too many)
        for i in stride(from: 0, to: route.polyline.pointCount, by: max(1, route.polyline.pointCount / 50)) {
            let point = points[i]
            coordinates.append(point.coordinate)
        }
        
        // Always include start and end points
        coordinates.append(userLocation.coordinate)
        coordinates.append(destination)
        
        // Calculate region that fits the entire route
        let region = regionThatFits(
            coordinates: coordinates,
            extraPadding: true,
            carouselOffset: false // Don't use carousel offset during navigation
        )
        
        // Animate to route overview with north orientation for better context
        withAnimation(.easeInOut(duration: 0.6)) {
            // Temporarily switch to north orientation for overview
            if mapOrientationMode == "course" {
                let camera = MapCamera(
                    centerCoordinate: region.center,
                    distance: max(region.span.latitudeDelta, region.span.longitudeDelta) * 111000, // Convert degrees to meters
                    heading: 0, // North orientation for overview
                    pitch: 0 // No pitch for overview
                )
                mapCameraPosition = .camera(camera)
            } else {
                mapCameraPosition = .region(region)
            }
            mapRegion = region
        }
    }
    
    /// Restore navigation state from InProgressManager (used when returning to map)
    func restoreNavigationState() {
        guard InProgressManager.shared.isRouting,
              let activeRoute = InProgressManager.shared.activeRoute else {
            return
        }
        
        
        // Restore navigation state
        isNavigating = true
        currentRoute = activeRoute
        routePolyline = activeRoute.polyline
        
        // Restore navigation engine state
        navigationEngine.restoreRoute(activeRoute)
        
        // Location manager continues tracking
        
        // Start route refresh timer
        startRouteRefreshTimer()
        
        // Update map to navigation mode
        updateMapForNavigation()
    }
    
    /// Toggle map orientation mode between north-up and course-up
    func toggleOrientationMode() {
        mapOrientationMode = mapOrientationMode == "north" ? "course" : "north"
        
        // Update map immediately based on new mode
        withAnimation(.easeInOut(duration: 0.6)) {
            if mapOrientationMode == "course" {
                // Use GPS course if available and moving, otherwise use device heading
                if locationManager.userCourse >= 0 && userLocation?.speed ?? 0 > 1.25 {
                    targetHeading = locationManager.userCourse
                    currentHeading = locationManager.userCourse
                } else {
                    // Fall back to device heading when stationary
                    targetHeading = locationManager.deviceHeading
                    currentHeading = locationManager.deviceHeading
                }
                // Update immediately with proper zoom for navigation
                if isNavigating {
                    // If navigating, update the whole navigation view
                    updateMapForNavigation()
                } else {
                    // Otherwise just update heading
                    updateMapHeading(animated: true)
                }
            } else {
                // Reset to north immediately
                targetHeading = 0
                currentHeading = 0
                // Update with proper zoom for navigation
                if isNavigating {
                    updateMapForNavigation()
                } else {
                    updateMapHeading(animated: true)
                }
            }
        }
    }
    
    /// Handle user interaction with map
    func handleUserInteraction() {
        isUserInteracting = true
        lastUserInteractionTime = Date()
        
        // Reset auto-center timer
        if autoCenter, let interval = autoCenterInterval {
            resetAutoCenterTimer(interval: interval)
        }
    }
    
    // MARK: - Private Methods
    
    private func handleLocationUpdate(_ location: CLLocation?) {
        guard let location = location else { return }
        
        // If this is the first location update and we haven't centered on user yet, do so now
        if !hasInitializedWithUserLocation && projects.isEmpty {
            hasInitializedWithUserLocation = true
            recenterOnUser()
        }
        
        // Update heading from GPS course when in course mode and moving
        if mapOrientationMode == "course" && location.speed > 1.25 && location.course >= 0 {
            // Use GPS course when moving faster than 1.25 m/s (4.5 km/h, walking speed)
            // This prevents jittery updates at very low speeds
            // Debug: Log speed and course
            
            // Only update if course has changed significantly
            let courseDiff = abs(currentHeading - location.course)
            if courseDiff > 3 || courseDiff > 357 {
                targetHeading = location.course
                currentHeading = location.course
                updateMapHeading(animated: true)  // Animate for smooth tracking
            }
        }
        
        // Update map position smoothly during navigation
        if isNavigating && autoCenter {
            centerOnUserForNavigation()
        }
        
        // Update navigation if active
        if isNavigating {
            navigationEngine.updateUserLocation(location)
        }
        
        // Auto-center if appropriate (non-navigation cases)
        if !isNavigating && shouldAutoCenter() {
            // Check if enough time has passed since last user interaction
            let timeSinceInteraction = Date().timeIntervalSince(lastUserInteractionTime)
            let requiredInterval = autoCenterInterval ?? 5.0
            
            // Only auto-center if user hasn't interacted recently
            if timeSinceInteraction >= requiredInterval {
                if projects.isEmpty {
                    recenterOnUser()
                }
            }
        }
    }
    
    private func handleNavigationStateChange(_ state: NavigationState?) {
        // Update UI based on navigation state changes
        switch state {
        case .arrived:
            // Auto-stop navigation after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.stopNavigation()
                
                // Show arrival message
                NotificationCenter.default.post(
                    name: Notification.Name("ShowArrivalMessage"),
                    object: nil
                )
            }
        default:
            break
        }
    }
    
    private func updateRoutePolyline(_ route: MKRoute?) {
        if let route = route {
            routePolyline = route.polyline
        } else {
            routePolyline = nil
        }
    }
    
    private func updateMapRegionForProjects(includeUserLocation: Bool = false, extraPadding: Bool = false) {
        var coordinates: [CLLocationCoordinate2D] = []
        
        // Add project coordinates
        for project in projects {
            if let coordinate = project.coordinate {
                coordinates.append(coordinate)
            }
        }
        
        // Add user location if requested
        if includeUserLocation, let userLocation = userLocation {
            coordinates.append(userLocation.coordinate)
        }
        
        // If no coordinates, center on user
        if coordinates.isEmpty {
            recenterOnUser()
            return
        }
        
        // If single coordinate, zoom to it with appropriate offset
        if coordinates.count == 1 {
            // For single project, still apply offset to position it in the safe area
            let singleCoordRegion = regionThatFits(
                coordinates: coordinates,
                extraPadding: true,
                carouselOffset: !isNavigating
            )
            
            withAnimation(.easeInOut(duration: 0.3)) {
                mapCameraPosition = .region(singleCoordRegion)
                mapRegion = singleCoordRegion
            }
            return
        }
        
        // Calculate region to fit all coordinates with appropriate offset
        let region = regionThatFits(
            coordinates: coordinates,
            extraPadding: extraPadding,
            carouselOffset: !isNavigating // Use carousel offset when not navigating
        )
        
        withAnimation(.easeInOut(duration: 0.3)) {
            mapCameraPosition = .region(region)
            mapRegion = region
        }
    }
    
    private func updateMapForNavigation() {
        guard let userLocation = userLocation else { return }
        
        // Animate to navigation view with appropriate zoom and pitch
        withAnimation(.easeInOut(duration: 0.8)) {
            if mapOrientationMode == "course" {
                // Use camera view with pitch for navigation
                let camera = MapCamera(
                    centerCoordinate: userLocation.coordinate,
                    distance: navigationZoomDistance,
                    heading: currentHeading,
                    pitch: 45.0 // Tilt for better navigation view
                )
                mapCameraPosition = .camera(camera)
            } else {
                // Use standard region for north-up navigation
                let region = MKCoordinateRegion(
                    center: userLocation.coordinate,
                    latitudinalMeters: navigationZoomDistance,
                    longitudinalMeters: navigationZoomDistance
                )
                mapCameraPosition = .region(region)
                mapRegion = region
            }
        }
    }
    
    private func centerOnUserForNavigation() {
        guard let userLocation = userLocation else { return }
        
        if mapOrientationMode == "course" {
            // In course mode, use updateMapHeading for consistent animation
            updateMapHeading(animated: true)
        } else {
            // During navigation, use navigation zoom for better guidance
            let center = userLocation.coordinate
            
            let region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: navigationZoomDistance,
                longitudinalMeters: navigationZoomDistance
            )
            
            // No animation for smooth continuous updates during navigation
            shouldAnimateNextUpdate = false
            mapCameraPosition = .region(region)
            mapRegion = region
        }
    }
    
    private func shouldAutoCenter() -> Bool {
        guard autoCenter else { return false }
        
        // Don't auto-center if user is interacting
        if isUserInteracting {
            return false
        }
        
        return true
    }
    
    private func regionThatFits(coordinates: [CLLocationCoordinate2D], extraPadding: Bool = false, carouselOffset: Bool = false) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return mapRegion
        }
        
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        
        // Calculate the basic center
        let basicCenter = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        // Calculate latitude and longitude spans
        let latSpan = maxLat - minLat
        let lonSpan = maxLon - minLon
        
        // Determine UI offset based on current state
        var verticalOffset: Double = 0
        var effectivePaddingMultiplier: Double = 1.5
        
        if isNavigating {
            // During navigation: account for navigation header and bottom controls
            // Safe area is roughly 30% from top and 35% from bottom (25% + 10% extra padding)
            // This means we have about 35% of screen height for content
            // Shift center DOWN by 22.5% total (15% to compensate for earlier upward shift - 2.5% for centering + 10% for bottom padding)
            verticalOffset = latSpan * -0.225
            
            // Need more padding during navigation to fit in smaller visible area
            effectivePaddingMultiplier = 2.6
        } else if carouselOffset {
            // Normal home view: account for header and carousel
            // Safe area is roughly 35% from top and 35% from bottom (30% + 5% extra padding)
            // This means we have about 30% of screen height for content
            // Shift center DOWN by 17.5% total (15% to compensate for earlier upward shift - 2.5% for centering + 5% for bottom padding)
            verticalOffset = latSpan * -0.175
            
            // Need significant padding to fit in the safe area
            effectivePaddingMultiplier = 2.8
        }
        
        // Apply extra padding if requested
        if extraPadding {
            effectivePaddingMultiplier *= 1.2
        }
        
        // Calculate adjusted center with offset
        let adjustedCenter = CLLocationCoordinate2D(
            latitude: basicCenter.latitude + verticalOffset,
            longitude: basicCenter.longitude
        )
        
        // Calculate span with padding to ensure all points fit in safe area
        // Add 20% horizontal padding for side margins in route overview
        let horizontalMultiplier = isNavigating ? 1.2 : 1.1
        let span = MKCoordinateSpan(
            latitudeDelta: latSpan * effectivePaddingMultiplier,
            longitudeDelta: lonSpan * effectivePaddingMultiplier * horizontalMultiplier
        )
        
        return MKCoordinateRegion(center: adjustedCenter, span: span)
    }
    
    /// Update map heading with current value
    private func updateMapHeading(animated: Bool) {
        guard !isUpdatingHeading else { return } // Prevent recursive updates
        isUpdatingHeading = true
        defer { isUpdatingHeading = false }
        
        // Skip update if heading hasn't changed significantly (within 5 degrees)
        if abs(currentHeading - targetHeading) < 5.0 && !animated {
            return
        }
        
        guard let userLocation = userLocation else {
            // Fall back to project coordinate if no user location
            if let projectCoordinate = selectedProject?.coordinate {
                let distance = isNavigating ? navigationZoomDistance : zoomDistance
                let camera = MapCamera(
                    centerCoordinate: projectCoordinate,
                    distance: distance,
                    heading: currentHeading,
                    pitch: 0
                )
                if animated {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        mapCameraPosition = .camera(camera)
                    }
                } else {
                    mapCameraPosition = .camera(camera)
                }
            }
            return
        }
        
        let centerCoordinate = userLocation.coordinate
        let finalPitch = mapOrientationMode == "course" && isNavigating ? 45.0 : 0.0
        
        // Create camera with current heading using appropriate zoom
        let distance = isNavigating ? navigationZoomDistance : zoomDistance
        let camera = MapCamera(
            centerCoordinate: centerCoordinate,
            distance: distance,
            heading: currentHeading,
            pitch: finalPitch
        )
        
        // Set animation flag and update camera
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                mapCameraPosition = .camera(camera)
            }
        } else {
            mapCameraPosition = .camera(camera)
        }
    }
    
    // MARK: - Timer Management
    
    private func resetAutoCenterTimer(interval: TimeInterval) {
        autoCenterTimer?.invalidate()
        
        autoCenterTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.isUserInteracting = false
            
            // Trigger appropriate centering
            if self?.isNavigating == true {
                self?.centerOnUserForNavigation()
            } else if self?.hasMultipleProjects == true {
                self?.updateMapRegionForProjects()
            }
        }
    }
    
    private func startRouteRefreshTimer() {
        // Reduced to 10 seconds for more responsive route updates
        routeRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task {
                try? await self?.refreshRoute()
            }
        }
    }
    
    private func stopRouteRefreshTimer() {
        routeRefreshTimer?.invalidate()
        routeRefreshTimer = nil
    }
    
    private func refreshRoute() async throws {
        guard isNavigating,
              let project = selectedProject,
              let destination = project.coordinate,
              let userLocation = userLocation else {
            return
        }
        
        try await navigationEngine.recalculateRoute(
            from: userLocation.coordinate,
            to: destination
        )
    }
    
    // MARK: - Combine
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Helper Methods
    
    private func angleDifference(from angle1: Double, to angle2: Double) -> Double {
        var diff = angle2 - angle1
        
        // Normalize to [-180, 180]
        while diff > 180 {
            diff -= 360
        }
        while diff < -180 {
            diff += 360
        }
        
        return abs(diff)
    }
    
    // MARK: - Heading Updates
    
    // Removed updateHeadingSmooth() method that was causing excessive timer-based updates
    // Heading is now only updated from GPS course when moving > 2 m/s in handleLocationUpdate()
    
    deinit {
        autoCenterTimer?.invalidate()
        routeRefreshTimer?.invalidate()
    }
}

