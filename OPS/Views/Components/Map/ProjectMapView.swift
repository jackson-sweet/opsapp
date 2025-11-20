//
//  ProjectMapView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//

import SwiftUI
import MapKit
import CoreLocation

// Main map view for displaying projects
struct ProjectMapView: View {
    // MARK: - Properties
    @State private var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.4132, longitude: -123.3650),
        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
    )
    let projects: [Project]
    @Binding var selectedIndex: Int
    var onTapMarker: (Int) -> Void
    var routeOverlay: MKOverlay?
    var isInProjectMode: Bool
    
    // Location manager
    @EnvironmentObject private var locationManager: LocationManager
    
    // Map settings from user preferences
    @AppStorage("mapAutoCenter") private var mapAutoCenter = true
    @AppStorage("mapAutoCenterTime") private var mapAutoCenterTime = "10" // "off", "2", "5", "10" seconds
    @AppStorage("mapZoomLevel") private var mapZoomLevel = "medium" // "close", "medium", "far"
    @AppStorage("map3DBuildings") private var map3DBuildings = false
    @AppStorage("mapTrafficDisplay") private var mapTrafficDisplay = false
    @AppStorage("mapDefaultType") private var mapDefaultType = "standard"
    
    // State for user interaction tracking
    @State private var userHasMovedMap = false
    @State private var lastUserInteraction = Date.distantPast
    @State private var autoZoomTimer: Timer?
    @State private var hasIncludedUserLocationInInitialRegion = false
    
    // MARK: - Computed Properties
    
    // The ideal map region based on current app state
    private var idealMapRegion: MKCoordinateRegion {
        let isRouting = InProgressManager.shared.isRouting
        
        if isRouting {
            // ROUTING MODE: Center on user location when navigating
            return userLocationRegion()
        } else if isInProjectMode {
            // PROJECT MODE: Center on active project
            return activeProjectRegion()
        } else {
            // DEFAULT MODE: Show all projects + user location
            return allProjectsRegion()
        }
    }
    
    // Check if enough time has passed since user interaction to allow auto-zoom
    private var shouldAutoZoom: Bool {
        // Check if auto-center is disabled
        guard mapAutoCenter && mapAutoCenterTime != "off" else { 
            return false 
        }
        
        // During routing, allow auto-zoom but with different behavior (follow user)
        if InProgressManager.shared.isRouting {
            // Only auto-zoom during routing if user hasn't interacted recently
            let timeoutInterval: TimeInterval = 5.0 // Shorter timeout during navigation
            let timeSinceInteraction = Date().timeIntervalSince(lastUserInteraction)
            let result = timeSinceInteraction >= timeoutInterval
            return result
        }
        
        let timeoutInterval: TimeInterval
        switch mapAutoCenterTime {
        case "2": timeoutInterval = 2.0
        case "5": timeoutInterval = 5.0
        case "10": timeoutInterval = 10.0
        default: timeoutInterval = 10.0
        }
        
        let timeSinceInteraction = Date().timeIntervalSince(lastUserInteraction)
        let result = timeSinceInteraction >= timeoutInterval
        
        return result
    }
    
    var body: some View {
        ZStack {
            // Base map with project annotations and route overlay
            MapViewRepresentable(
                region: $region,
                annotations: projects.indices.compactMap { index in
                    guard let coordinate = projects[index].coordinate else { return nil }
                    
                    return MapAnnotationItem(
                        id: projects[index].id,
                        project: projects[index],
                        coordinate: coordinate,
                        index: index,
                        isSelected: index == selectedIndex,
                        isActiveProject: isInProjectMode && index == selectedIndex,
                        onTap: {
                            selectedIndex = index
                            onTapMarker(index)
                            userInteracted()
                        }
                    )
                },
                routeOverlay: routeOverlay,
                showsUserLocation: true,
                showsCompass: false,
                show3DBuildings: map3DBuildings,
                showTraffic: mapTrafficDisplay,
                mapType: mapDefaultType,
                mapZoomLevel: mapZoomLevel,
                onMapUserInteraction: { _ in
                    userInteracted()
                }
            )
            
            // Recenter button
            if shouldShowRecenterButton {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: recenterMap) {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.cardBackground.opacity(0.8))
                                    .frame(width: 44, height: 44)
                                    .shadow(color: OPSStyle.Colors.shadowColor, radius: 3, x: 0, y: 2)
                                
                                Image(systemName: "location.fill")
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    .font(.system(size: 20, weight: .bold))
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, isInProjectMode ? 220 : 120)
                    }
                }
            }
        }
        .onAppear {
            locationManager.requestPermissionIfNeeded()
            userHasMovedMap = false
            lastUserInteraction = Date.distantPast
            hasIncludedUserLocationInInitialRegion = false
            
            // Check if we already have location data
            if locationManager.userLocation != nil {
                // Immediately set region if we have location (includes user + projects)
                hasIncludedUserLocationInInitialRegion = true
                let newRegion = idealMapRegion
                region = newRegion
            }

            // Also schedule a delayed check in case location comes in slightly later
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if locationManager.userLocation != nil {
                    hasIncludedUserLocationInInitialRegion = true
                }
                let newRegion = idealMapRegion
                withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                    region = newRegion
                }
            }
        }
        .onDisappear {
            autoZoomTimer?.invalidate()
            autoZoomTimer = nil
        }
        .onChange(of: InProgressManager.shared.isRouting) { _, isRouting in
            if isRouting {
                // ROUTING STARTED: NO AUTO-ZOOM - let user position map as they prefer
                
                // Cancel any existing timer during routing
                autoZoomTimer?.invalidate()
                autoZoomTimer = nil
            } else {
                // When routing stops, update to appropriate view
                updateRegionIfNeeded()
            }
        }
        .onChange(of: selectedIndex) { _, _ in
            updateRegionIfNeeded()
        }
        .onChange(of: isInProjectMode) { _, _ in
            updateRegionIfNeeded()
        }
        .onChange(of: projects.count) { _, newCount in
            // When projects load for first time, wait for user location then center
            if newCount > 0 {
                // CRITICAL: Wait longer (2 seconds) to ensure user location is available
                // This prevents centering on projects only without user location
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if locationManager.userLocation != nil {
                        print("[MAP] 📍 Projects loaded with user location available - centering on BOTH")
                        hasIncludedUserLocationInInitialRegion = true
                    } else {
                        print("[MAP] ⚠️ Projects loaded but user location NOT available yet")
                    }
                    let newRegion = idealMapRegion
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                        region = newRegion
                    }
                }
            } else {
                updateRegionIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .locationDidChange)) { _ in
            // During routing, NO auto-zoom on location changes - user controls map
            if InProgressManager.shared.isRouting {
                return
            }

            // CRITICAL FIX: When user location becomes available, REBUILD map to include it
            if locationManager.userLocation != nil && !hasIncludedUserLocationInInitialRegion {
                print("[MAP] 🎯 User location became available - REBUILDING map with user location")
                hasIncludedUserLocationInInitialRegion = true

                // Force recalculation by calling the appropriate region method directly
                let newRegion: MKCoordinateRegion
                if !projects.isEmpty {
                    // We have projects - calculate region including BOTH user and projects
                    newRegion = allProjectsRegion()
                    print("[MAP] 📍 Rebuilt map with \(projects.count) projects + user location")
                } else {
                    // No projects yet - center on user only
                    newRegion = userLocationRegion()
                    print("[MAP] 📍 Rebuilt map with user location only")
                }

                withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                    region = newRegion
                }
            } else {
                updateRegionIfNeeded()
            }
        }
        .onChange(of: mapAutoCenter) { _, newValue in
            if newValue {
                // Auto-center was enabled, apply immediately (ignore timer since this is settings change)
                // NEVER during routing - user has complete control
                if !InProgressManager.shared.isRouting {
                    let newRegion = idealMapRegion
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                        region = newRegion
                    }
                } else {
                }
            } else {
                // Auto-center was disabled, cancel any pending timers
                autoZoomTimer?.invalidate()
                autoZoomTimer = nil
            }
        }
        .onChange(of: mapAutoCenterTime) { _, newValue in
            // NEVER restart timers during routing - user has complete control
            if !InProgressManager.shared.isRouting {
                // Restart timer with new duration if there's one running
                if autoZoomTimer != nil {
                    startAutoZoomTimer()
                }
            } else {
            }
            
            // If auto-center time was set to "off", cancel any pending timers
            if newValue == "off" {
                autoZoomTimer?.invalidate()
                autoZoomTimer = nil
            }
        }
        .onChange(of: mapZoomLevel) { _, newValue in
            // NEVER apply zoom changes during routing - user has complete control
            if !InProgressManager.shared.isRouting {
                let newRegion = idealMapRegion
                withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                    region = newRegion
                }
            } else {
            }
        }
        .onChange(of: map3DBuildings) { _, newValue in
            // Map appearance will update automatically through MapViewRepresentable
        }
        .onChange(of: mapTrafficDisplay) { _, newValue in
            // Map appearance will update automatically through MapViewRepresentable
        }
        .onChange(of: mapDefaultType) { _, newValue in
            // Map appearance will update automatically through MapViewRepresentable
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateRegionIfNeeded() {
        // If there was no recent user interaction, auto-zoom immediately
        if shouldAutoZoom {
            let newRegion = idealMapRegion
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                region = newRegion
            }
        } else if userHasMovedMap {
            // User has interacted, start timer for delayed auto-zoom
            startAutoZoomTimer()
        }
    }
    
    private var shouldShowRecenterButton: Bool {
        // Never show recenter button during routing
        if InProgressManager.shared.isRouting {
            return false
        }
        return projects[safe: selectedIndex]?.coordinate != nil
    }
    
    private func userInteracted() {
        userHasMovedMap = true
        lastUserInteraction = Date()
        
        // NEVER start timer during routing - user has complete control
        if !InProgressManager.shared.isRouting {
            startAutoZoomTimer()
        } else {
        }
    }
    
    private func recenterMap() {
        userHasMovedMap = false
        lastUserInteraction = Date.distantPast
        
        // Cancel any pending auto-zoom timer
        autoZoomTimer?.invalidate()
        autoZoomTimer = nil
        
        withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
            region = idealMapRegion
        }
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
    }
    
    private func startAutoZoomTimer() {
        // Cancel existing timer
        autoZoomTimer?.invalidate()
        
        // NEVER start timer during routing - user has complete control
        if InProgressManager.shared.isRouting {
            return
        }
        
        // Don't start timer if auto center is disabled
        guard mapAutoCenter && mapAutoCenterTime != "off" else { return }
        
        let timeoutInterval: TimeInterval
        switch mapAutoCenterTime {
        case "2": timeoutInterval = 2.0
        case "5": timeoutInterval = 5.0
        case "10": timeoutInterval = 10.0
        default: timeoutInterval = 10.0
        }
        
        
        autoZoomTimer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false) { _ in
            DispatchQueue.main.async {
                self.performAutoZoom()
            }
        }
    }
    
    private func performAutoZoom() {
        // NEVER auto-zoom during routing - user has complete control
        if InProgressManager.shared.isRouting {
            return
        }
        
        // Check if we should still auto zoom (settings might have changed)
        guard mapAutoCenter && mapAutoCenterTime != "off" else { return }
        
        let newRegion = idealMapRegion
        withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
            region = newRegion
        }
        
        // Reset interaction tracking
        userHasMovedMap = false
        lastUserInteraction = Date.distantPast
    }
    
    // MARK: - Region Calculation Methods
    
    private func userLocationRegion() -> MKCoordinateRegion {
        guard let userLocation = locationManager.userLocation else {
            return fallbackRegion()
        }
        
        let span = getSpanForZoomLevel()
        return MKCoordinateRegion(center: userLocation, span: span)
    }
    
    private func activeProjectRegion() -> MKCoordinateRegion {
        guard let projectCoordinate = projects[safe: selectedIndex]?.coordinate else {
            return fallbackRegion()
        }

        // If user location is available, create region that includes both user and project
        if let userLocation = locationManager.userLocation {
            // If they're the same location, just center on it
            if userLocation.latitude == projectCoordinate.latitude &&
               userLocation.longitude == projectCoordinate.longitude {
                let span = getSpanForZoomLevel()
                return MKCoordinateRegion(center: projectCoordinate, span: span)
            }

            // Calculate bounds
            let minLat = min(userLocation.latitude, projectCoordinate.latitude)
            let maxLat = max(userLocation.latitude, projectCoordinate.latitude)
            let minLon = min(userLocation.longitude, projectCoordinate.longitude)
            let maxLon = max(userLocation.longitude, projectCoordinate.longitude)

            // Calculate padding based on zoom preference
            let paddingMultiplier: Double
            switch mapZoomLevel {
            case "close": paddingMultiplier = 1.2
            case "medium": paddingMultiplier = 1.4
            case "far": paddingMultiplier = 1.8
            default: paddingMultiplier = 1.4
            }

            let latDelta = max(0.01, (maxLat - minLat) * paddingMultiplier)
            let lonDelta = max(0.01, (maxLon - minLon) * paddingMultiplier)

            let centerLat = (minLat + maxLat) / 2
            let centerLon = (minLon + maxLon) / 2

            // Apply same UI adjustments as allProjectsRegion for focus area
            let expandedLatDelta = latDelta * 2.5
            let expandedLonDelta = lonDelta * 2.5
            let centerAdjustment = expandedLatDelta * 0.05
            let adjustedCenterLat = centerLat - centerAdjustment

            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: adjustedCenterLat, longitude: centerLon),
                span: MKCoordinateSpan(latitudeDelta: expandedLatDelta, longitudeDelta: expandedLonDelta)
            )
        } else {
            // No user location, just center on project
            let span = getSpanForZoomLevel()
            return MKCoordinateRegion(center: projectCoordinate, span: span)
        }
    }
    
    private func allProjectsRegion() -> MKCoordinateRegion {
        var coordinates: [CLLocationCoordinate2D] = []

        // Add user location if available
        if let userLocation = locationManager.userLocation {
            coordinates.append(userLocation)
            print("[MAP] ✅ allProjectsRegion: INCLUDING user location (\(userLocation.latitude), \(userLocation.longitude))")
        } else {
            print("[MAP] ⚠️ allProjectsRegion: User location NOT available")
        }

        // Add project coordinates
        for project in projects {
            if let coordinate = project.coordinate {
                coordinates.append(coordinate)
                print("[MAP] ✅ allProjectsRegion: INCLUDING project \(project.title)")
            }
        }
        
        guard !coordinates.isEmpty else {
            return fallbackRegion()
        }
        
        if coordinates.count == 1 {
            let span = getSpanForZoomLevel()
            return MKCoordinateRegion(center: coordinates[0], span: span)
        }
        
        // Calculate bounds
        let minLat = coordinates.map { $0.latitude }.min()!
        let maxLat = coordinates.map { $0.latitude }.max()!
        let minLon = coordinates.map { $0.longitude }.min()!
        let maxLon = coordinates.map { $0.longitude }.max()!
        
        // Handle case where all coordinates are the same
        if minLat == maxLat && minLon == maxLon {
            let span = getSpanForZoomLevel()
            return MKCoordinateRegion(center: coordinates[0], span: span)
        }
        
        // Calculate padding based on zoom preference
        let paddingMultiplier: Double
        switch mapZoomLevel {
        case "close": paddingMultiplier = 1.2
        case "medium": paddingMultiplier = 1.4
        case "far": paddingMultiplier = 1.8
        default: paddingMultiplier = 1.4
        }
        
        let latDelta = max(0.01, (maxLat - minLat) * paddingMultiplier)
        let lonDelta = max(0.01, (maxLon - minLon) * paddingMultiplier)
        
        
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        
        // Adjust center to account for UI elements:
        // - Top 40% is header area
        // - Bottom 30% is project carousel and tab bar
        // Available viewing area is middle 30% of screen (from 40% to 70% of screen height)
        // Focus area center is at 55% from top (40% + 15%)
        // Map center normally renders at 50% from top
        // To center content in focus area, shift map south by 5% of visible height

        // Expand bounds to ensure all points fit within visible focus area
        // Need to expand by more to account for blocked areas
        let expandedLatDelta = latDelta * 2.5 // Expand significantly to account for 70% of screen being blocked
        let expandedLonDelta = lonDelta * 2.5

        // Shift map center south by 5% of visible height so content appears centered in focus area (at 55%)
        // This moves the geographic bounding box center from screen center (50%) up to focus area center (55%)
        let centerAdjustment = expandedLatDelta * 0.05 // 5% of visible map height
        let adjustedCenterLat = centerLat - centerAdjustment // Subtract to pan south, shifting content up on screen
        
        
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: adjustedCenterLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: expandedLatDelta, longitudeDelta: expandedLonDelta)
        )
    }
    
    private func getSpanForZoomLevel() -> MKCoordinateSpan {
        switch mapZoomLevel {
        case "close":
            return MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        case "medium":
            return MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
        case "far":
            return MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        default:
            return MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
        }
    }
    
    private func fallbackRegion() -> MKCoordinateRegion {
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.4132, longitude: -123.3650),
            span: getSpanForZoomLevel()
        )
    }
    
    private func getRegionDescription(_ region: MKCoordinateRegion) -> String {
        return "center: (\(String(format: "%.4f", region.center.latitude)), \(String(format: "%.4f", region.center.longitude))), span: \(String(format: "%.4f", region.span.latitudeDelta))"
    }
}

// MARK: - Supporting Types (kept from original)

// Array safe access extension
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// Helper struct to configure the map view
struct MapViewConfig {
    var mapStyle: MKStandardMapConfiguration {
        let config = MKStandardMapConfiguration()
        config.pointOfInterestFilter = .excludingAll
        config.emphasisStyle = .muted
        return config
    }
}

// Annotation item for map
struct MapAnnotationItem: Identifiable {
    let id: String
    let project: Project
    let coordinate: CLLocationCoordinate2D
    let index: Int
    let isSelected: Bool
    let isActiveProject: Bool
    let onTap: () -> Void
}

// MKPolyline renderer modifier
class CustomPolylineRenderer: MKPolylineRenderer {
    init(polyline: MKPolyline, color: UIColor, lineWidth: CGFloat) {
        super.init(polyline: polyline)
        self.strokeColor = color
        self.lineWidth = lineWidth
        self.alpha = 1.0
        self.lineCap = .round
        self.lineJoin = .round
    }
    
    override init(overlay: MKOverlay) {
        super.init(overlay: overlay)
        self.strokeColor = UIColor.systemBlue
        self.lineWidth = 5.0
        self.alpha = 1.0
        self.lineCap = .round
        self.lineJoin = .round
    }
}

// Custom Map View implementation using UIViewRepresentable
struct MapViewRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let annotations: [MapAnnotationItem]
    let routeOverlay: MKOverlay?
    let showsUserLocation: Bool
    let showsCompass: Bool
    let show3DBuildings: Bool
    let showTraffic: Bool
    let mapType: String
    let mapZoomLevel: String
    var onMapUserInteraction: ((MKMapView) -> Void)? = nil
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        
        context.coordinator.currentMapView = mapView
        
        mapView.overrideUserInterfaceStyle = .dark
        mapView.pointOfInterestFilter = .excludingAll
        
        applySettings(to: mapView)
        
        // Add gesture recognizers
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapPan(_:)))
        panGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(panGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapPinch(_:)))
        pinchGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(pinchGesture)
        
        let rotationGesture = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapRotation(_:)))
        rotationGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(rotationGesture)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Only update region if it's significantly different to avoid competing animations
        let currentRegion = mapView.region
        let regionThreshold = 0.001 // ~100 meters difference
        
        let latitudeChanged = abs(currentRegion.center.latitude - region.center.latitude) > regionThreshold
        let longitudeChanged = abs(currentRegion.center.longitude - region.center.longitude) > regionThreshold
        let spanChanged = abs(currentRegion.span.latitudeDelta - region.span.latitudeDelta) > regionThreshold * 0.5
        
        if latitudeChanged || longitudeChanged || spanChanged {
            mapView.setRegion(region, animated: true)
        }
        
        applySettings(to: mapView)
        
        // Update annotations
        let currentAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(currentAnnotations)
        
        let newAnnotations = annotations.map { item -> CustomAnnotation in
            let annotation = CustomAnnotation(
                id: item.id,
                coordinate: item.coordinate,
                isSelected: item.isSelected,
                isActiveProject: item.isActiveProject
            )
            annotation.project = item.project
            annotation.index = item.index
            return annotation
        }
        mapView.addAnnotations(newAnnotations)
        
        // Update route overlay
        let currentOverlayCount = mapView.overlays.count
        let hasRouteOverlay = routeOverlay != nil
        let needsOverlayUpdate = (currentOverlayCount == 0 && hasRouteOverlay) || (currentOverlayCount > 0 && !hasRouteOverlay)
        
        if needsOverlayUpdate {
            mapView.removeOverlays(mapView.overlays)
            
            if let routeOverlay = routeOverlay {
                mapView.addOverlay(routeOverlay)
                context.coordinator.enableCompassRotation(mapView)
            } else {
                context.coordinator.disableCompassRotation(mapView)
            }
        }
        
        if hasRouteOverlay {
            context.coordinator.enableCompassRotation(mapView)
        }
    }
    
    private func applySettings(to mapView: MKMapView) {
        mapView.showsCompass = showsCompass
        
        switch mapType {
        case "satellite": mapView.mapType = .satellite
        case "hybrid": mapView.mapType = .hybrid
        default: mapView.mapType = .standard
        }
        
        mapView.showsTraffic = showTraffic
        
        if #available(iOS 16.0, *) {
            switch mapView.mapType {
            case .satellite:
                let config = MKHybridMapConfiguration()
                config.showsTraffic = showTraffic
                mapView.preferredConfiguration = config
            case .hybrid:
                let config = MKHybridMapConfiguration()
                config.showsTraffic = showTraffic
                mapView.preferredConfiguration = config
            default:
                let config = MKStandardMapConfiguration()
                config.showsTraffic = showTraffic
                config.elevationStyle = show3DBuildings ? .realistic : .flat
                config.emphasisStyle = show3DBuildings ? .default : .muted
                mapView.preferredConfiguration = config
            }
        } else {
            mapView.showsBuildings = show3DBuildings
            mapView.showsTraffic = showTraffic
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapViewRepresentable
        var currentMapView: MKMapView?
        
        init(_ parent: MapViewRepresentable) {
            self.parent = parent
            super.init()
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            
            guard let customAnnotation = annotation as? CustomAnnotation else { return nil }
            
            let identifier = "ProjectAnnotation"
            let annotationView = MKAnnotationView(annotation: customAnnotation, reuseIdentifier: identifier)
            
            let projectAnnotation = ProjectMapAnnotation(
                project: customAnnotation.project,
                isSelected: customAnnotation.isSelected,
                isActiveProject: customAnnotation.isActiveProject,
                onTap: {
                    if let item = self.parent.annotations.first(where: { $0.id == customAnnotation.id }) {
                        item.onTap()
                    }
                }
            )
            
            let hostingController = UIHostingController(rootView: projectAnnotation)
            hostingController.view.backgroundColor = .clear
            
            // Let the hosting controller size itself naturally
            let size = hostingController.sizeThatFits(in: UIView.layoutFittingExpandedSize)
            hostingController.view.frame = CGRect(origin: .zero, size: size)
            // CRITICAL: Disable user interaction on SwiftUI view so taps reach the annotation view
            hostingController.view.isUserInteractionEnabled = false
            hostingController.view.tag = 1000 + (customAnnotation.index % 1000)
            
            // Set the annotation view frame to match the content
            annotationView.frame = CGRect(origin: .zero, size: size)
            annotationView.addSubview(hostingController.view)
            
            // Set the anchor point to the bottom center of the pin
            // This ensures the pin tip stays at the coordinate during zoom/rotation
            annotationView.centerOffset = CGPoint(x: 0, y: -size.height / 2)

            // CRITICAL: Configure for proper tap handling through delegate
            annotationView.isEnabled = true  // Allow annotation to be tapped
            annotationView.isUserInteractionEnabled = true  // Allow user interaction
            annotationView.canShowCallout = false  // No default callout (we handle selection via delegate)
            
            if customAnnotation.isSelected || customAnnotation.isActiveProject {
                annotationView.displayPriority = .defaultHigh
                annotationView.zPriority = .max
            } else {
                annotationView.displayPriority = .defaultLow
                annotationView.zPriority = .min
            }
            
            return annotationView
        }
        
        // CRITICAL: Handle annotation selection through native MKMapView delegate
        // This is MUCH more reliable than SwiftUI tap gestures inside annotation views
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // Ignore user location
            guard let customAnnotation = view.annotation as? CustomAnnotation else { return }

            print("[MAP] 📍 Annotation selected: \(customAnnotation.project?.title ?? "unknown")")

            // Find and trigger the onTap handler
            if let item = parent.annotations.first(where: { $0.id == customAnnotation.id }) {
                // Deselect the annotation immediately to allow repeated taps
                DispatchQueue.main.async {
                    mapView.deselectAnnotation(customAnnotation, animated: false)
                }

                // Trigger the tap handler
                item.onTap()

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 8.0
                renderer.alpha = 1.0
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.async {
                self.parent.region = mapView.region
            }
        }
        
        @objc func handleMapPan(_ gestureRecognizer: UIPanGestureRecognizer) {
            if gestureRecognizer.state == .began || gestureRecognizer.state == .changed {
                guard let mapView = gestureRecognizer.view as? MKMapView else { return }
                parent.onMapUserInteraction?(mapView)
            }
        }
        
        @objc func handleMapPinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
            if gestureRecognizer.state == .began || gestureRecognizer.state == .changed {
                guard let mapView = gestureRecognizer.view as? MKMapView else { return }
                parent.onMapUserInteraction?(mapView)
            }
        }
        
        @objc func handleMapRotation(_ gestureRecognizer: UIRotationGestureRecognizer) {
            if gestureRecognizer.state == .began || gestureRecognizer.state == .changed {
                guard let mapView = gestureRecognizer.view as? MKMapView else { return }
                parent.onMapUserInteraction?(mapView)
            }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        func enableCompassRotation(_ mapView: MKMapView) {
            // NEVER auto-position during routing - user has complete control
            mapView.userTrackingMode = .none
            
            // Don't change camera position during routing - user controls map completely
            // Only set tracking mode to none to prevent iOS from auto-following
        }
        
        func disableCompassRotation(_ mapView: MKMapView) {
            mapView.userTrackingMode = .none
            let camera = mapView.camera.copy() as! MKMapCamera
            camera.heading = 0
            camera.pitch = 0
            mapView.setCamera(camera, animated: true)
        }
    }
}

// Custom annotation class for map
class CustomAnnotation: NSObject, MKAnnotation {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let isSelected: Bool
    let isActiveProject: Bool
    var project: Project!
    var index: Int = 0
    
    init(id: String, coordinate: CLLocationCoordinate2D, isSelected: Bool, isActiveProject: Bool) {
        self.id = id
        self.coordinate = coordinate
        self.isSelected = isSelected
        self.isActiveProject = isActiveProject
        super.init()
    }
}
