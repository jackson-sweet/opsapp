# Home Screen Map Rebuild — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the MapKit-based home screen map with a Mapbox-powered dark-themed map featuring custom annotations, turn-by-turn navigation, geofencing, speed-adaptive zoom, and live team tracking via Supabase Realtime.

**Architecture:** New `Map/` module built on Mapbox Maps SDK v11 + Navigation SDK v3. The map is a `UIViewRepresentable` wrapping `MapView`. A new `OPSMapCoordinator` manages all map state (camera, annotations, navigation, crew tracking). Supabase Realtime broadcasts crew locations. The new module plugs into the existing `HomeContentView` via the same callback interface (`onProjectSelected`, `onNavigationStarted`), preserving integration with `AppState`, `InProgressManager`, and `LocationManager`.

**Tech Stack:** Mapbox Maps SDK v11, Mapbox Navigation SDK v3, Supabase Realtime (broadcast channels), CoreLocation (geofencing), SwiftUI + UIViewRepresentable

**Design Doc:** `docs/plans/2026-02-27-map-rebuild-design.md`

---

## Phase 1: Foundation

### Task 1: Add Mapbox SDK Dependencies

**Context:** The app uses Swift Package Manager. Mapbox Maps SDK v11 and Navigation SDK v3 must be added. Mapbox SDKs require a secret access token in `~/.netrc` for download and a public token in the app for runtime.

**Files:**
- Modify: `OPS.xcodeproj` (via Xcode SPM UI or Package.swift)
- Create: `OPS/OPS/Map/Core/MapboxConfig.swift`

**Step 1: Add Mapbox SPM packages**

In Xcode: File → Add Package Dependencies:
- `https://github.com/mapbox/mapbox-maps-ios.git` — version 11.x (latest)
- `https://github.com/mapbox/mapbox-navigation-ios.git` — version 3.x (latest)

Both require a Mapbox secret token in `~/.netrc`:
```
machine api.mapbox.com
login mapbox
password <SECRET_TOKEN>
```

**Step 2: Create MapboxConfig.swift**

```swift
// OPS/OPS/Map/Core/MapboxConfig.swift
import Foundation
import MapboxMaps

enum MapboxConfig {
    static let publicToken = "<PUBLIC_MAPBOX_TOKEN>"

    // Custom dark style built in Mapbox Studio
    // If not yet created, use mapbox://styles/mapbox/dark-v11 as placeholder
    static let darkStyleURI = StyleURI(rawValue: "mapbox://styles/mapbox/dark-v11")!

    static func configure() {
        MapboxOptions.accessToken = publicToken
    }
}
```

**Step 3: Call configure() on app launch**

Modify: `OPS/OPS/OPSApp.swift` — add `MapboxConfig.configure()` in the app's `init()` or `.onAppear` of the root view.

**Step 4: Build to verify SDK links**

Run: `Cmd+B` in Xcode. Expected: successful build with Mapbox imported.

**Step 5: Commit**

```
feat: add Mapbox Maps SDK v11 and Navigation SDK v3 dependencies
```

---

### Task 2: Core Map View (UIViewRepresentable)

**Context:** Mapbox Maps SDK v11 uses `MapView` (UIKit). We wrap it in a `UIViewRepresentable` for SwiftUI. This is the base layer — no annotations yet, just the dark map rendering with user location.

**Files:**
- Create: `OPS/OPS/Map/Views/OPSMapView.swift`

**Step 1: Create OPSMapView**

```swift
// OPS/OPS/Map/Views/OPSMapView.swift
import SwiftUI
import MapboxMaps

struct OPSMapView: UIViewRepresentable {
    @ObservedObject var coordinator: OPSMapCoordinator

    func makeUIView(context: Context) -> MapView {
        let options = MapInitOptions(
            styleURI: MapboxConfig.darkStyleURI
        )
        let mapView = MapView(frame: .zero, mapInitOptions: options)

        // Dark background while tiles load (matches #0A0A0A)
        mapView.backgroundColor = UIColor(red: 10/255, green: 10/255, blue: 10/255, alpha: 1)

        // Enable user location puck
        mapView.location.options.puckType = .puck2D(
            Puck2DConfiguration(
                topImage: nil,  // Use default blue dot
                scale: .constant(0.8)
            )
        )
        mapView.location.options.puckBearing = .course
        mapView.location.options.puckBearingEnabled = true

        // Standard gestures (pan, pinch, rotate, tilt, double-tap, two-finger-tap)
        // All enabled by default in Mapbox

        // Store reference in coordinator
        coordinator.mapView = mapView
        coordinator.setupGestureHandlers(mapView)

        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        // Camera updates driven by coordinator, not here
        // Annotation updates driven by coordinator
    }
}
```

**Step 2: Build to verify**

Run: `Cmd+B`. Expected: builds with MapboxMaps imported.

**Step 3: Commit**

```
feat: create OPSMapView UIViewRepresentable wrapper for Mapbox
```

---

### Task 3: New Map Coordinator

**Context:** `OPSMapCoordinator` replaces the old `MapCoordinator`. It owns all map state: camera position, annotations, navigation state, crew locations. It is the single source of truth for the map.

**Files:**
- Create: `OPS/OPS/Map/Core/OPSMapCoordinator.swift`

**Reference files to read first:**
- `OPS/OPS/Map/Core/MapCoordinator.swift` — old coordinator (understand current state shape)
- `OPS/OPS/Utilities/LocationManager.swift` — subscribes to location updates
- `OPS/OPS/AppState.swift` — project mode state

**Step 1: Create OPSMapCoordinator**

```swift
// OPS/OPS/Map/Core/OPSMapCoordinator.swift
import SwiftUI
import MapboxMaps
import Combine

@MainActor
final class OPSMapCoordinator: ObservableObject {

    // MARK: - Map Reference
    weak var mapView: MapView?

    // MARK: - Dependencies
    let locationManager: LocationManager

    // MARK: - Camera State
    @Published var isFollowingUser: Bool = true
    @Published var orientationMode: OrientationMode = .northUp
    @Published var cameraPitch: CGFloat = 0

    enum OrientationMode: String {
        case northUp
        case courseUp
    }

    // MARK: - Annotation State
    @Published var projects: [Project] = []
    @Published var filteredProjects: [Project] = []
    @Published var selectedProjectId: String?
    @Published var showingProjectCard: Bool = false
    @Published var filterMode: FilterMode = .today

    enum FilterMode {
        case today
        case allProjects
    }

    // MARK: - Crew Tracking
    @Published var crewLocations: [String: CrewLocationUpdate] = [:] // userId -> latest
    @Published var selectedCrewId: String?
    @Published var showingCrewTooltip: Bool = false

    // MARK: - Navigation State
    @Published var isNavigating: Bool = false
    @Published var navigationDestination: Project?
    @Published var currentRoute: RouteInfo?
    @Published var currentManeuver: ManeuverInfo?
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var distanceRemaining: CLLocationDistance = 0
    @Published var estimatedArrival: Date?
    @Published var isVoiceEnabled: Bool = true

    struct RouteInfo {
        let coordinates: [CLLocationCoordinate2D]
        let distance: CLLocationDistance
        let duration: TimeInterval
    }

    struct ManeuverInfo {
        let instruction: String
        let distanceToNext: CLLocationDistance
        let maneuverType: String // SF Symbol name
    }

    // MARK: - Geofencing
    @Published var arrivalBanner: GeofenceBanner?
    @Published var departureBanner: GeofenceBanner?

    struct GeofenceBanner {
        let projectName: String
        let address: String
        let type: BannerType
        enum BannerType { case arrival, departure }
    }

    // MARK: - Speed Adaptive Zoom
    private var currentSpeed: CLLocationSpeed = 0

    // MARK: - Combine
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Annotation Managers
    private var projectAnnotationManager: PointAnnotationManager?
    private var crewAnnotationManager: PointAnnotationManager?
    private var routeLineLayerId: String?

    // MARK: - Init
    init(locationManager: LocationManager) {
        self.locationManager = locationManager
        setupLocationSubscription()
    }

    // MARK: - Setup

    func setupMapView(_ mapView: MapView) {
        self.mapView = mapView
        projectAnnotationManager = mapView.annotations.makePointAnnotationManager(id: "project-pins")
        crewAnnotationManager = mapView.annotations.makePointAnnotationManager(id: "crew-dots")
        setupGestureHandlers(mapView)
        centerOnUser(animated: false)
    }

    private func setupLocationSubscription() {
        locationManager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        currentSpeed = location.speed

        if isFollowingUser {
            updateCamera(for: location)
        }

        if isNavigating {
            updateNavigationProgress(location)
        }
    }

    // MARK: - Camera

    func updateCamera(for location: CLLocation, animated: Bool = true) {
        guard let mapView else { return }

        let zoom = zoomForSpeed(currentSpeed)
        let heading: CLLocationDirection

        switch orientationMode {
        case .northUp:
            heading = 0
        case .courseUp:
            heading = location.speed > 1.25 && location.course >= 0
                ? location.course
                : locationManager.deviceHeading
        }

        let pitch = isNavigating ? 45.0 : Double(cameraPitch)

        let cameraOptions = CameraOptions(
            center: location.coordinate,
            zoom: zoom,
            bearing: heading,
            pitch: pitch
        )

        if animated {
            mapView.camera.ease(to: cameraOptions, duration: isNavigating ? 1.0 : 0.3)
        } else {
            mapView.mapboxMap.setCamera(to: cameraOptions)
        }
    }

    private func zoomForSpeed(_ speed: CLLocationSpeed) -> CGFloat {
        guard isNavigating else { return 14.0 } // Default browse zoom

        switch speed {
        case ..<2:    return 15.5  // Walking/stationary
        case 2..<10:  return 14.5  // Urban
        case 10..<25: return 13.5  // Suburban
        case 25..<35: return 12.5  // Highway
        default:      return 11.5  // Fast highway
        }
    }

    func centerOnUser(animated: Bool = true) {
        guard let location = locationManager.currentLocation else { return }
        isFollowingUser = true
        updateCamera(for: location, animated: animated)
    }

    func toggleOrientation() {
        orientationMode = orientationMode == .northUp ? .courseUp : .northUp
        if let location = locationManager.currentLocation {
            updateCamera(for: location)
        }
    }

    func showRouteOverview() {
        guard let mapView, let route = currentRoute else { return }

        let coordinates = route.coordinates
        guard !coordinates.isEmpty else { return }

        let camera = mapView.mapboxMap.camera(
            for: coordinates,
            camera: CameraOptions(),
            coordinatesPadding: UIEdgeInsets(top: 120, left: 60, bottom: 200, right: 60),
            maxZoom: nil,
            offset: nil
        )
        mapView.camera.ease(to: camera, duration: 0.8)
        isFollowingUser = false
    }

    // MARK: - Gesture Handling

    func setupGestureHandlers(_ mapView: MapView) {
        // Detect user pan to disengage follow mode
        mapView.gestures.onMapPan.observe { [weak self] _ in
            self?.isFollowingUser = false
        }
    }

    // MARK: - Filter

    func setFilter(_ mode: FilterMode) {
        filterMode = mode
        updateFilteredProjects()
        refreshProjectAnnotations()
    }

    func updateFilteredProjects() {
        switch filterMode {
        case .today:
            filteredProjects = projects // Already filtered to today's by HomeView
        case .allProjects:
            filteredProjects = projects // Will need all active projects passed in
        }
    }

    // MARK: - Project Selection

    func selectProject(_ project: Project) {
        selectedProjectId = project.id
        showingProjectCard = true
        showingCrewTooltip = false
        selectedCrewId = nil
    }

    func deselectAll() {
        selectedProjectId = nil
        showingProjectCard = false
        selectedCrewId = nil
        showingCrewTooltip = false
    }

    // MARK: - Crew Selection

    func selectCrew(_ userId: String) {
        selectedCrewId = userId
        showingCrewTooltip = true
        showingProjectCard = false
        selectedProjectId = nil
    }

    // MARK: - Navigation (stubs — implemented in Task 10)

    func startNavigation(to project: Project) {
        // Implemented in navigation task
    }

    func stopNavigation() {
        isNavigating = false
        navigationDestination = nil
        currentRoute = nil
        currentManeuver = nil
        cameraPitch = 0
        removeRouteLine()
        if let location = locationManager.currentLocation {
            updateCamera(for: location)
        }
    }

    private func updateNavigationProgress(_ location: CLLocation) {
        // Implemented in navigation task
    }

    // MARK: - Annotations (stubs — implemented in Tasks 5-6)

    func refreshProjectAnnotations() {
        // Implemented in annotations task
    }

    func refreshCrewAnnotations() {
        // Implemented in crew tracking task
    }

    // MARK: - Route Line (stubs — implemented in Task 10)

    func drawRouteLine(_ coordinates: [CLLocationCoordinate2D]) {
        // Implemented in navigation task
    }

    func removeRouteLine() {
        guard let mapView else { return }
        if let layerId = routeLineLayerId {
            try? mapView.mapboxMap.removeLayer(withId: layerId)
            try? mapView.mapboxMap.removeSource(withId: "route-source")
            routeLineLayerId = nil
        }
    }
}
```

**Step 2: Build to verify**

Run: `Cmd+B`. Expected: builds (stubs compile, no runtime test yet).

**Step 3: Commit**

```
feat: create OPSMapCoordinator with camera, state, and stub methods
```

---

### Task 4: Map Container Shell

**Context:** New `OPSMapContainer` replaces the old `MapContainer` + `SafeMapContainer`. It assembles the map view with all overlay layers (controls, cards, tooltips, banners). Initially just the map + controls — cards and navigation UI added in later tasks.

**Files:**
- Create: `OPS/OPS/Map/Views/OPSMapContainer.swift`

**Reference:** Read `OPS/OPS/Map/Views/MapContainer.swift` (lines 54-109) for the old structure and callback interface.

**Step 1: Create OPSMapContainer**

```swift
// OPS/OPS/Map/Views/OPSMapContainer.swift
import SwiftUI

struct OPSMapContainer: View {
    // Same callback interface as old MapContainer
    let projects: [Project]
    let selectedIndex: Int
    let selectedTask: ProjectTask?
    let onProjectSelected: (Project) -> Void
    let onNavigationStarted: (Project) -> Void

    @ObservedObject var appState: AppState
    @ObservedObject var locationManager: LocationManager

    @StateObject private var coordinator: OPSMapCoordinator

    init(
        projects: [Project],
        selectedIndex: Int,
        selectedTask: ProjectTask?,
        onProjectSelected: @escaping (Project) -> Void,
        onNavigationStarted: @escaping (Project) -> Void,
        appState: AppState,
        locationManager: LocationManager
    ) {
        self.projects = projects
        self.selectedIndex = selectedIndex
        self.selectedTask = selectedTask
        self.onProjectSelected = onProjectSelected
        self.onNavigationStarted = onNavigationStarted
        self.appState = appState
        self.locationManager = locationManager
        self._coordinator = StateObject(wrappedValue: OPSMapCoordinator(locationManager: locationManager))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Layer 1: Mapbox map (full screen)
            OPSMapView(coordinator: coordinator)
                .ignoresSafeArea()

            // Layer 2: Filter chips (below header area)
            // Added in Task 7

            // Layer 3: Map controls (right side)
            mapControls

            // Layer 4: Project detail card (bottom)
            // Added in Task 8

            // Layer 5: Crew tooltip
            // Added in Task 9

            // Layer 6: Navigation header (top)
            // Added in Task 11

            // Layer 7: Geofence banners
            // Added in Task 14
        }
        .onAppear {
            coordinator.projects = projects
            coordinator.updateFilteredProjects()
            coordinator.refreshProjectAnnotations()
        }
        .onChange(of: projects) { _, newProjects in
            coordinator.projects = newProjects
            coordinator.updateFilteredProjects()
            coordinator.refreshProjectAnnotations()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StartNavigation"))) { notification in
            if let projectId = notification.userInfo?["projectId"] as? String,
               let project = projects.first(where: { $0.id == projectId }) {
                coordinator.startNavigation(to: project)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StopNavigation"))) { _ in
            coordinator.stopNavigation()
        }
    }

    // MARK: - Map Controls

    private var mapControls: some View {
        VStack(spacing: 12) {
            Spacer()

            // Re-center button (only when not following)
            if !coordinator.isFollowingUser {
                mapControlButton(icon: "location.fill") {
                    coordinator.centerOnUser()
                }
            }

            // Route overview (only during navigation)
            if coordinator.isNavigating {
                mapControlButton(icon: "arrow.up.left.and.arrow.down.right") {
                    coordinator.showRouteOverview()
                }

                mapControlButton(icon: "xmark") {
                    coordinator.stopNavigation()
                    NotificationCenter.default.post(name: Notification.Name("StopRouting"), object: nil)
                }
            }

            // Orientation toggle (always visible)
            mapControlButton(
                icon: coordinator.orientationMode == .northUp
                    ? "location.north.line.fill"
                    : "location.heading.line.fill",
                isActive: coordinator.orientationMode == .courseUp
            ) {
                coordinator.toggleOrientation()
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 100) // Above tab bar
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func mapControlButton(icon: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isActive ? Color(hex: "597794") : .white.opacity(0.8))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
        }
    }
}
```

**Step 2: Build to verify**

Run: `Cmd+B`. Expected: builds.

**Step 3: Commit**

```
feat: create OPSMapContainer with map controls and notification handling
```

---

## Phase 2: Annotations

### Task 5: Project Pin Annotations

**Context:** Project pins are small white dots with a colored status ring and project name label. Uses Mapbox PointAnnotationManager. Each annotation is a custom-rendered UIImage (Mapbox requires images, not SwiftUI views).

**Files:**
- Create: `OPS/OPS/Map/Annotations/ProjectAnnotationRenderer.swift`
- Modify: `OPS/OPS/Map/Core/OPSMapCoordinator.swift` — implement `refreshProjectAnnotations()`

**Reference:** Read the design doc annotation section. Read `OPS/OPS/Styles/OPSStyle.swift` for pipeline status colors.

**Step 1: Create ProjectAnnotationRenderer**

This renders project pins as UIImages for Mapbox. Each image is: white 12pt dot + 2pt gap + 2pt colored ring + project name label above.

```swift
// OPS/OPS/Map/Annotations/ProjectAnnotationRenderer.swift
import UIKit
import MapboxMaps

enum ProjectAnnotationRenderer {

    /// Renders a project pin image: white dot + gap + status ring + name label
    static func renderPin(
        projectName: String,
        statusColor: UIColor,
        isSelected: Bool = false
    ) -> UIImage {
        let dotSize: CGFloat = 12
        let gap: CGFloat = 2
        let ringWidth: CGFloat = 2
        let totalDotArea = dotSize + (gap + ringWidth) * 2  // 20pt

        // Label
        let labelFont = UIFont(name: "Kosugi-Regular", size: 11) ?? UIFont.systemFont(ofSize: 11)
        let labelColor = isSelected ? UIColor.white : UIColor.white.withAlphaComponent(0.8)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: labelColor
        ]
        let labelSize = (projectName as NSString).size(withAttributes: labelAttributes)

        let labelPadding: CGFloat = 4
        let canvasWidth = max(totalDotArea, labelSize.width)
        let canvasHeight = totalDotArea + labelPadding + labelSize.height

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasWidth, height: canvasHeight))

        return renderer.image { context in
            let ctx = context.cgContext

            // Draw label above dot (top of canvas, centered horizontally)
            let labelX = (canvasWidth - labelSize.width) / 2
            (projectName as NSString).draw(
                at: CGPoint(x: labelX, y: 0),
                withAttributes: labelAttributes
            )

            // Dot center position (below label)
            let dotCenterX = canvasWidth / 2
            let dotCenterY = labelSize.height + labelPadding + totalDotArea / 2

            // Draw status ring
            let ringRadius = totalDotArea / 2
            let ringColor = isSelected ? statusColor.withAlphaComponent(1.0) : statusColor
            ctx.setStrokeColor(ringColor.cgColor)
            ctx.setLineWidth(ringWidth)
            ctx.addArc(center: CGPoint(x: dotCenterX, y: dotCenterY),
                       radius: ringRadius - ringWidth / 2,
                       startAngle: 0, endAngle: .pi * 2, clockwise: true)
            ctx.strokePath()

            // Draw white dot
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.addArc(center: CGPoint(x: dotCenterX, y: dotCenterY),
                       radius: dotSize / 2,
                       startAngle: 0, endAngle: .pi * 2, clockwise: true)
            ctx.fillPath()
        }
    }

    /// Returns the UIColor for a project pipeline status
    static func statusColor(for status: String) -> UIColor {
        switch status.lowercased() {
        case "rfq":         return UIColor(hex: "BCBCBC")
        case "estimated":   return UIColor(hex: "B5A381")
        case "accepted":    return UIColor(hex: "9DB582")
        case "in progress", "in_progress", "inprogress":
                            return UIColor(hex: "8195B5")
        case "completed":   return UIColor(hex: "B58289")
        case "closed":      return UIColor(hex: "E9E9E9")
        case "archived":    return UIColor(hex: "A182B5")
        default:            return UIColor(hex: "BCBCBC")
        }
    }
}

// UIColor hex extension (if not already in project)
extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
```

**Step 2: Implement refreshProjectAnnotations() in OPSMapCoordinator**

Add to `OPS/OPS/Map/Core/OPSMapCoordinator.swift`, replacing the stub:

```swift
func refreshProjectAnnotations() {
    guard let manager = projectAnnotationManager else { return }

    var annotations: [PointAnnotation] = []

    for project in filteredProjects {
        guard let lat = project.latitude, let lng = project.longitude else { continue }

        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        var annotation = PointAnnotation(coordinate: coord)
        annotation.customData = ["projectId": .string(project.id)]

        let isSelected = project.id == selectedProjectId
        let statusColor = ProjectAnnotationRenderer.statusColor(for: project.status ?? "rfq")
        let image = ProjectAnnotationRenderer.renderPin(
            projectName: project.title ?? "Untitled",
            statusColor: statusColor,
            isSelected: isSelected
        )

        annotation.image = .init(image: image, name: "project-\(project.id)-\(isSelected)")
        annotation.iconAnchor = .bottom  // Anchor at bottom of image (dot position)
        annotation.iconAllowOverlap = true
        annotation.textAllowOverlap = true

        annotations.append(annotation)
    }

    manager.annotations = annotations

    // Handle tap
    manager.delegate = self  // OPSMapCoordinator conforms to AnnotationInteractionDelegate
}
```

Also add `AnnotationInteractionDelegate` conformance:

```swift
extension OPSMapCoordinator: AnnotationInteractionDelegate {
    func annotationManager(_ manager: any AnnotationManager, didDetectTappedAnnotations annotations: [any Annotation]) {
        guard let annotation = annotations.first as? PointAnnotation else { return }

        if manager.id == "project-pins" {
            if let projectIdValue = annotation.customData?["projectId"],
               case .string(let projectId) = projectIdValue,
               let project = projects.first(where: { $0.id == projectId }) {
                selectProject(project)
            }
        } else if manager.id == "crew-dots" {
            if let userIdValue = annotation.customData?["userId"],
               case .string(let userId) = userIdValue {
                selectCrew(userId)
            }
        }
    }
}
```

**Step 3: Build and verify**

Run: `Cmd+B`. Expected: builds.

**Step 4: Commit**

```
feat: implement project pin annotations with status-colored rings
```

---

### Task 6: Crew Dot Annotations

**Context:** Crew dots are smaller (10pt) white dots with colored status rings and first name labels. Similar renderer to project pins but smaller.

**Files:**
- Create: `OPS/OPS/Map/Annotations/CrewAnnotationRenderer.swift`
- Modify: `OPS/OPS/Map/Core/OPSMapCoordinator.swift` — implement `refreshCrewAnnotations()`

**Step 1: Create CrewAnnotationRenderer**

```swift
// OPS/OPS/Map/Annotations/CrewAnnotationRenderer.swift
import UIKit
import MapboxMaps

enum CrewAnnotationRenderer {

    static func renderDot(
        firstName: String,
        statusColor: UIColor
    ) -> UIImage {
        let dotSize: CGFloat = 10
        let gap: CGFloat = 2
        let ringWidth: CGFloat = 2
        let totalDotArea = dotSize + (gap + ringWidth) * 2  // 18pt

        let labelFont = UIFont(name: "Kosugi-Regular", size: 11) ?? UIFont.systemFont(ofSize: 11)
        let labelColor = UIColor.white.withAlphaComponent(0.8)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: labelColor
        ]
        let labelSize = (firstName as NSString).size(withAttributes: labelAttributes)

        let labelPadding: CGFloat = 3
        let canvasWidth = max(totalDotArea, labelSize.width)
        let canvasHeight = totalDotArea + labelPadding + labelSize.height

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasWidth, height: canvasHeight))

        return renderer.image { context in
            let ctx = context.cgContext

            // Label above
            let labelX = (canvasWidth - labelSize.width) / 2
            (firstName as NSString).draw(
                at: CGPoint(x: labelX, y: 0),
                withAttributes: labelAttributes
            )

            // Dot center
            let dotCenterX = canvasWidth / 2
            let dotCenterY = labelSize.height + labelPadding + totalDotArea / 2

            // Status ring
            let ringRadius = totalDotArea / 2
            ctx.setStrokeColor(statusColor.cgColor)
            ctx.setLineWidth(ringWidth)
            ctx.addArc(center: CGPoint(x: dotCenterX, y: dotCenterY),
                       radius: ringRadius - ringWidth / 2,
                       startAngle: 0, endAngle: .pi * 2, clockwise: true)
            ctx.strokePath()

            // White dot
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.addArc(center: CGPoint(x: dotCenterX, y: dotCenterY),
                       radius: dotSize / 2,
                       startAngle: 0, endAngle: .pi * 2, clockwise: true)
            ctx.fillPath()
        }
    }

    static func statusColor(for update: CrewLocationUpdate?, nearJobSites: [Project]) -> UIColor {
        guard let update else { return UIColor(hex: "8E8E93") } // Gray — no data

        // Stale check (>5 min)
        if abs(update.timestamp.timeIntervalSinceNow) > 300 {
            return UIColor(hex: "8E8E93") // Gray — idle
        }

        // On-site check (within 100m of any job site)
        let crewLocation = CLLocation(latitude: update.lat, longitude: update.lng)
        for project in nearJobSites {
            guard let lat = project.latitude, let lng = project.longitude else { continue }
            let jobLocation = CLLocation(latitude: lat, longitude: lng)
            if crewLocation.distance(from: jobLocation) < 100 {
                return UIColor(hex: "A5B368") // Green — on-site
            }
        }

        // Moving check
        if update.speed > 2 {
            return UIColor(hex: "C4A868") // Amber — en route
        }

        return UIColor(hex: "A5B368") // Green — stationary near nothing but active
    }
}
```

**Step 2: Implement refreshCrewAnnotations() in OPSMapCoordinator**

```swift
func refreshCrewAnnotations() {
    guard let manager = crewAnnotationManager else { return }

    var annotations: [PointAnnotation] = []

    for (userId, update) in crewLocations {
        let coord = CLLocationCoordinate2D(latitude: update.lat, longitude: update.lng)
        var annotation = PointAnnotation(coordinate: coord)
        annotation.customData = ["userId": .string(userId)]

        let statusColor = CrewAnnotationRenderer.statusColor(for: update, nearJobSites: projects)
        let image = CrewAnnotationRenderer.renderDot(
            firstName: update.firstName,
            statusColor: statusColor
        )

        annotation.image = .init(image: image, name: "crew-\(userId)-\(Int(update.timestamp.timeIntervalSince1970))")
        annotation.iconAnchor = .bottom
        annotation.iconAllowOverlap = true
        annotation.textAllowOverlap = true

        annotations.append(annotation)
    }

    manager.annotations = annotations
}
```

**Step 3: Add CrewLocationUpdate model**

Create: `OPS/OPS/Map/Models/CrewLocationUpdate.swift`

```swift
// OPS/OPS/Map/Models/CrewLocationUpdate.swift
import Foundation

struct CrewLocationUpdate: Codable {
    let userId: String
    let orgId: String
    let firstName: String
    let lat: Double
    let lng: Double
    let heading: Double
    let speed: Double
    let accuracy: Double
    let timestamp: Date
    let batteryLevel: Float
    let isBackground: Bool

    // Optional: current task assignment (for tooltip)
    var currentTaskName: String?
    var currentProjectName: String?
    var currentProjectId: String?
    var currentProjectAddress: String?
    var phoneNumber: String?
}
```

**Step 4: Commit**

```
feat: implement crew dot annotations with status-colored rings and location model
```

---

## Phase 3: Interactions

### Task 7: Filter Chips

**Context:** Two mutually exclusive filter chips below the header: TODAY (default) and ALL PROJECTS. Frosted glass styling.

**Files:**
- Create: `OPS/OPS/Map/Views/MapFilterChips.swift`
- Modify: `OPS/OPS/Map/Views/OPSMapContainer.swift` — add filter chips layer

**Step 1: Create MapFilterChips**

```swift
// OPS/OPS/Map/Views/MapFilterChips.swift
import SwiftUI

struct MapFilterChips: View {
    @ObservedObject var coordinator: OPSMapCoordinator

    var body: some View {
        HStack(spacing: 8) {
            filterChip(
                label: "TODAY",
                isActive: coordinator.filterMode == .today
            ) {
                coordinator.setFilter(.today)
            }

            filterChip(
                label: "ALL PROJECTS",
                isActive: coordinator.filterMode == .allProjects
            ) {
                coordinator.setFilter(.allProjects)
            }

            Spacer()
        }
        .padding(.leading, 16)
    }

    private func filterChip(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Font.custom("Kosugi-Regular", size: 12))
                .tracking(0.5)
                .foregroundColor(isActive ? .white : Color(white: 0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 20/255, green: 20/255, blue: 20/255))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(
                                    isActive
                                        ? Color(hex: "597794")
                                        : Color.white.opacity(0.10),
                                    lineWidth: 1
                                )
                        )
                )
        }
    }
}
```

**Step 2: Add to OPSMapContainer body**

In `OPSMapContainer.swift`, add the filter chips in the ZStack (Layer 2 slot):

```swift
// Layer 2: Filter chips
VStack {
    Spacer().frame(height: 100) // Below header
    MapFilterChips(coordinator: coordinator)
    Spacer()
}
```

**Step 3: Commit**

```
feat: add TODAY/ALL PROJECTS filter chips with frosted styling
```

---

### Task 8: Project Detail Card

**Context:** Slide-up frosted glass card from bottom when a project pin is tapped. Shows project info, today's tasks, assigned crew, and NAVIGATE + DETAILS buttons.

**Files:**
- Create: `OPS/OPS/Map/Views/ProjectPinCard.swift`
- Modify: `OPS/OPS/Map/Views/OPSMapContainer.swift` — add card layer

**Step 1: Create ProjectPinCard**

```swift
// OPS/OPS/Map/Views/ProjectPinCard.swift
import SwiftUI

struct ProjectPinCard: View {
    let project: Project
    let todaysTasks: [ProjectTask]
    let crewNames: [String]
    let onNavigate: () -> Void
    let onDetails: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project name
            Text((project.title ?? "UNTITLED").uppercased())
                .font(Font.custom("Kosugi-Regular", size: 14))
                .tracking(0.5)
                .foregroundColor(.white)
                .padding(.bottom, 4)

            // Address
            if let address = project.address {
                Text(address)
                    .font(Font.custom("Mohave-Light", size: 14))
                    .foregroundColor(Color(white: 0.6))
            }

            divider

            // Today's tasks
            if !todaysTasks.isEmpty {
                Text("TODAY'S TASKS")
                    .font(Font.custom("Kosugi-Regular", size: 11))
                    .tracking(0.5)
                    .foregroundColor(Color(white: 0.6))
                    .padding(.bottom, 8)

                ForEach(todaysTasks, id: \.id) { task in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(taskStatusColor(task.status))
                            .frame(width: 6, height: 6)
                        Text(task.title ?? "Untitled task")
                            .font(Font.custom("Mohave-Regular", size: 15))
                            .foregroundColor(.white)
                    }
                    .padding(.bottom, 4)
                }

                divider
            }

            // Crew
            if !crewNames.isEmpty {
                Text("CREW")
                    .font(Font.custom("Kosugi-Regular", size: 11))
                    .tracking(0.5)
                    .foregroundColor(Color(white: 0.6))
                    .padding(.bottom, 4)

                Text(crewNames.joined(separator: " \u{00B7} "))
                    .font(Font.custom("Mohave-Regular", size: 15))
                    .foregroundColor(.white)

                divider
            }

            // Buttons
            HStack(spacing: 12) {
                // NAVIGATE — primary CTA
                Button(action: onNavigate) {
                    Text("NAVIGATE")
                        .font(Font.custom("Kosugi-Regular", size: 13))
                        .tracking(0.5)
                        .foregroundColor(Color(red: 10/255, green: 10/255, blue: 10/255))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white)
                        )
                }

                // DETAILS — ghost
                Button(action: onDetails) {
                    Text("DETAILS")
                        .font(Font.custom("Kosugi-Regular", size: 13))
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 50 { onDismiss() }
                }
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
            .padding(.vertical, 12)
    }

    private func taskStatusColor(_ status: String?) -> Color {
        switch status?.lowercased() {
        case "active":    return Color(hex: "8195B5")
        case "completed": return Color(hex: "B58289")
        case "cancelled": return Color(hex: "8E8E93")
        default:          return Color(hex: "8195B5")
        }
    }
}
```

**Step 2: Add to OPSMapContainer**

In the ZStack, add the project card layer at the bottom:

```swift
// Layer 4: Project detail card
if coordinator.showingProjectCard,
   let project = projects.first(where: { $0.id == coordinator.selectedProjectId }) {
    VStack {
        Spacer()
        ProjectPinCard(
            project: project,
            todaysTasks: todaysTasksForProject(project),
            crewNames: crewNamesForProject(project),
            onNavigate: {
                coordinator.showingProjectCard = false
                onNavigationStarted(project)
                coordinator.startNavigation(to: project)
            },
            onDetails: {
                coordinator.showingProjectCard = false
                appState.viewProjectDetails(projectId: project.id)
            },
            onDismiss: {
                coordinator.deselectAll()
            }
        )
        .padding(.bottom, 90) // Above tab bar
    }
    .transition(.move(edge: .bottom))
    .animation(.easeInOut(duration: 0.3), value: coordinator.showingProjectCard)
}
```

Add helper methods to `OPSMapContainer`:

```swift
private func todaysTasksForProject(_ project: Project) -> [ProjectTask] {
    // Filter tasks scheduled for today from the project's tasks
    // Implementation depends on how tasks are associated — read Project model relationships
    return []  // Placeholder — implement based on data model
}

private func crewNamesForProject(_ project: Project) -> [String] {
    // Get crew member names assigned to this project
    return []  // Placeholder — implement based on data model
}
```

**Step 3: Commit**

```
feat: add project detail slide-up card with NAVIGATE and DETAILS buttons
```

---

### Task 9: Crew Tooltip Card

**Context:** Small frosted card near the tapped crew dot. Shows name, assigned project (tappable), staleness, and CALL + MESSAGE buttons.

**Files:**
- Create: `OPS/OPS/Map/Views/CrewTooltipCard.swift`
- Modify: `OPS/OPS/Map/Views/OPSMapContainer.swift` — add tooltip layer

**Step 1: Create CrewTooltipCard**

```swift
// OPS/OPS/Map/Views/CrewTooltipCard.swift
import SwiftUI

struct CrewTooltipCard: View {
    let update: CrewLocationUpdate
    let onProjectTap: (String) -> Void  // projectId
    let onCall: () -> Void
    let onMessage: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Name
            Text(update.firstName.uppercased() + " " + (update.lastName ?? "").uppercased())
                .font(Font.custom("Kosugi-Regular", size: 13))
                .tracking(0.5)
                .foregroundColor(.white)
                .padding(.bottom, 6)

            // Assigned project (tappable)
            if let projectName = update.currentProjectName,
               let projectId = update.currentProjectId {
                Button(action: { onProjectTap(projectId) }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(projectName)
                                .font(Font.custom("Mohave-Regular", size: 14))
                                .foregroundColor(Color(hex: "597794"))

                            if let address = update.currentProjectAddress {
                                Text("at \(address)")
                                    .font(Font.custom("Mohave-Light", size: 13))
                                    .foregroundColor(Color(white: 0.6))
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "597794"))
                    }
                }
                .padding(.bottom, 6)
            } else {
                Text("No tasks assigned")
                    .font(Font.custom("Mohave-Light", size: 14))
                    .foregroundColor(Color(white: 0.4))
                    .padding(.bottom, 6)
            }

            // Staleness
            Text("Updated \(timeAgo(update.timestamp))")
                .font(Font.custom("Mohave-Light", size: 13))
                .foregroundColor(Color(white: 0.4))

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
                .padding(.vertical, 10)

            // Action buttons
            HStack(spacing: 12) {
                ghostButton(icon: "phone.fill", label: "CALL", action: onCall)
                ghostButton(icon: "message.fill", label: "MESSAGE", action: onMessage)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .frame(maxWidth: 260)
    }

    private func ghostButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(Font.custom("Kosugi-Regular", size: 11))
                    .tracking(0.5)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = abs(date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}
```

**Step 2: Add lastName to CrewLocationUpdate model**

Modify `OPS/OPS/Map/Models/CrewLocationUpdate.swift` — add `lastName: String?` property.

**Step 3: Add to OPSMapContainer**

Position the tooltip near the tapped crew dot (centered horizontally, above the dot):

```swift
// Layer 5: Crew tooltip
if coordinator.showingCrewTooltip,
   let userId = coordinator.selectedCrewId,
   let update = coordinator.crewLocations[userId] {
    VStack {
        Spacer()
        CrewTooltipCard(
            update: update,
            onProjectTap: { projectId in
                coordinator.deselectAll()
                appState.viewProjectDetails(projectId: projectId)
            },
            onCall: {
                if let phone = update.phoneNumber,
                   let url = URL(string: "tel:\(phone)") {
                    UIApplication.shared.open(url)
                }
            },
            onMessage: {
                if let phone = update.phoneNumber,
                   let url = URL(string: "sms:\(phone)") {
                    UIApplication.shared.open(url)
                }
            },
            onDismiss: {
                coordinator.deselectAll()
            }
        )
        .padding(.bottom, 90)
    }
    .transition(.opacity)
    .animation(.easeInOut(duration: 0.2), value: coordinator.showingCrewTooltip)
}
```

**Step 4: Commit**

```
feat: add crew tooltip card with project link, call, and message buttons
```

---

## Phase 4: Navigation

### Task 10: Mapbox Navigation Integration

**Context:** Implement `startNavigation()` using Mapbox Navigation SDK v3. Calculate route, draw route line, start turn-by-turn tracking. The Mapbox Navigation SDK provides `NavigationViewController` (UIKit) or headless `MapboxNavigationProvider` for custom UI.

**Important:** We use the **headless** Mapbox navigation (custom UI), NOT `NavigationViewController` — because we have our own map and header. We use `MapboxNavigationProvider` to get route calculation + progress tracking + voice, then render our own UI.

**Files:**
- Create: `OPS/OPS/Map/Core/OPSNavigationManager.swift`
- Modify: `OPS/OPS/Map/Core/OPSMapCoordinator.swift` — implement navigation methods

**Reference:** Read Mapbox Navigation SDK v3 docs for `MapboxNavigationProvider`, `RoutingProvider`, `NavigationRoutes`, `RouteProgress`.

**Step 1: Create OPSNavigationManager**

```swift
// OPS/OPS/Map/Core/OPSNavigationManager.swift
import Foundation
import MapboxNavigationCore
import MapboxDirections
import CoreLocation
import Combine

@MainActor
final class OPSNavigationManager: ObservableObject {

    private var navigationProvider: MapboxNavigationProvider?
    private var navigation: MapboxNavigation?

    @Published var isActive: Bool = false
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var currentInstruction: String = ""
    @Published var distanceToNextManeuver: CLLocationDistance = 0
    @Published var maneuverType: String = ""  // SF Symbol
    @Published var timeRemaining: TimeInterval = 0
    @Published var distanceRemaining: CLLocationDistance = 0
    @Published var estimatedArrival: Date?
    @Published var hasArrived: Bool = false
    @Published var isVoiceEnabled: Bool = true

    private var cancellables = Set<AnyCancellable>()

    func startNavigation(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws {
        // Create waypoints
        let originWaypoint = Waypoint(coordinate: origin)
        let destinationWaypoint = Waypoint(coordinate: destination)

        // Route options
        var options = NavigationRouteOptions(waypoints: [originWaypoint, destinationWaypoint])
        options.profileIdentifier = .automobile
        options.includesAlternativeRoutes = false

        // Initialize navigation provider
        let config = CoreConfig(routeOptions: options)
        let provider = MapboxNavigationProvider(coreConfig: config)
        self.navigationProvider = provider
        self.navigation = provider.mapboxNavigation

        // Calculate routes
        let routeResponse = try await navigation!.routingProvider().calculateRoutes(options: options)

        // Start active navigation
        await navigation!.tripSession().startActiveGuidance(with: routeResponse, startLegIndex: 0)

        // Extract route coordinates for display
        if let route = routeResponse.mainRoute.route {
            routeCoordinates = route.shape?.coordinates ?? []
            timeRemaining = route.expectedTravelTime
            distanceRemaining = route.distance
            estimatedArrival = Date().addingTimeInterval(route.expectedTravelTime)
        }

        isActive = true
        hasArrived = false

        // Observe progress updates
        setupProgressObserver()
    }

    private func setupProgressObserver() {
        // Mapbox Navigation SDK publishes progress updates
        // Subscribe to navigation state changes
        navigation?.tripSession().navigationRoutes
            .sink { [weak self] _ in
                // Route updated (reroute)
            }
            .store(in: &cancellables)
    }

    func stopNavigation() {
        navigation?.tripSession().startFreeDrive()
        isActive = false
        routeCoordinates = []
        currentInstruction = ""
        cancellables.removeAll()
    }

    func toggleVoice() {
        isVoiceEnabled.toggle()
        // Mute/unmute Mapbox voice controller
    }

    // Convert Mapbox maneuver types to SF Symbols
    static func sfSymbol(for maneuverType: String, modifier: String?) -> String {
        switch maneuverType {
        case "turn":
            switch modifier {
            case "left":         return "arrow.turn.up.left"
            case "right":        return "arrow.turn.up.right"
            case "sharp left":   return "arrow.turn.up.left"
            case "sharp right":  return "arrow.turn.up.right"
            case "slight left":  return "arrow.up.left"
            case "slight right": return "arrow.up.right"
            case "uturn":        return "arrow.uturn.down"
            default:             return "arrow.up"
            }
        case "merge":            return "arrow.merge"
        case "fork":             return "arrow.branch"
        case "roundabout":       return "arrow.triangle.turn.up.right.circle"
        case "arrive":           return "mappin.circle.fill"
        case "depart":           return "arrow.up"
        default:                 return "arrow.up"
        }
    }
}
```

**Step 2: Wire into OPSMapCoordinator**

Replace the `startNavigation()` stub in `OPSMapCoordinator.swift`:

```swift
// Add property
@StateObject var navigationManager = OPSNavigationManager()

// Replace stub
func startNavigation(to project: Project) {
    guard let lat = project.latitude, let lng = project.longitude,
          let userLocation = locationManager.currentLocation?.coordinate else { return }

    let destination = CLLocationCoordinate2D(latitude: lat, longitude: lng)
    navigationDestination = project

    Task {
        do {
            try await navigationManager.startNavigation(from: userLocation, to: destination)
            isNavigating = true
            isFollowingUser = true

            // Draw route line
            drawRouteLine(navigationManager.routeCoordinates)

            // Sync with InProgressManager for PersistentNavigationHeader compatibility
            // (can be removed once old header is fully replaced)

            // Update camera to navigation mode
            if let location = locationManager.currentLocation {
                updateCamera(for: location)
            }
        } catch {
            print("[OPSMap] Navigation error: \(error)")
        }
    }
}

func stopNavigation() {
    navigationManager.stopNavigation()
    isNavigating = false
    navigationDestination = nil
    currentRoute = nil
    currentManeuver = nil
    cameraPitch = 0
    removeRouteLine()
    if let location = locationManager.currentLocation {
        updateCamera(for: location)
    }
}
```

**Step 3: Implement route line drawing**

Replace the `drawRouteLine` stub:

```swift
func drawRouteLine(_ coordinates: [CLLocationCoordinate2D]) {
    guard let mapView, !coordinates.isEmpty else { return }

    // Remove existing
    removeRouteLine()

    // Add GeoJSON source
    var source = GeoJSONSource(id: "route-source")
    let lineString = LineString(coordinates)
    source.data = .geometry(.lineString(lineString))
    try? mapView.mapboxMap.addSource(source)

    // Add line layer
    var layer = LineLayer(id: "route-line", source: "route-source")
    layer.lineColor = .constant(StyleColor(UIColor(hex: "597794")))
    layer.lineWidth = .constant(4)
    layer.lineOpacity = .constant(0.85)
    layer.lineCap = .constant(.round)
    layer.lineJoin = .constant(.round)

    try? mapView.mapboxMap.addLayer(layer)
    routeLineLayerId = "route-line"
}
```

**Step 4: Commit**

```
feat: implement Mapbox navigation with route calculation and route line rendering
```

---

### Task 11: Navigation Header UI

**Context:** Frosted glass navigation header showing turn instruction, distance/time/arrival. Replaces old `PersistentNavigationHeader`.

**Files:**
- Create: `OPS/OPS/Map/Views/NavigationHeader.swift`
- Modify: `OPS/OPS/Map/Views/OPSMapContainer.swift` — add header layer

**Step 1: Create NavigationHeader**

```swift
// OPS/OPS/Map/Views/NavigationHeader.swift
import SwiftUI

struct NavigationHeader: View {
    @ObservedObject var navigationManager: OPSNavigationManager

    var body: some View {
        VStack(spacing: 0) {
            // Top row: maneuver instruction
            HStack(alignment: .center) {
                // Turn icon
                Image(systemName: navigationManager.maneuverType.isEmpty
                      ? "arrow.up" : navigationManager.maneuverType)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 36)

                // Instruction
                Text(navigationManager.currentInstruction.isEmpty
                     ? "Calculating route..."
                     : navigationManager.currentInstruction)
                    .font(Font.custom("Mohave-Regular", size: 16))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Spacer()

                // Distance to next turn
                if navigationManager.distanceToNextManeuver > 0 {
                    Text(formatDistance(navigationManager.distanceToNextManeuver))
                        .font(Font.custom("Mohave-Light", size: 15))
                        .foregroundColor(Color(white: 0.6))
                }

                // Voice toggle
                Button(action: { navigationManager.toggleVoice() }) {
                    Image(systemName: navigationManager.isVoiceEnabled
                          ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)

            // Bottom row: time / distance / arrival
            HStack {
                infoColumn(
                    value: formatTime(navigationManager.timeRemaining),
                    label: "TIME"
                )

                Spacer()

                infoColumn(
                    value: formatDistance(navigationManager.distanceRemaining),
                    label: "DISTANCE"
                )

                Spacer()

                infoColumn(
                    value: formatArrival(navigationManager.estimatedArrival),
                    label: "ARRIVAL"
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }

    private func infoColumn(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Font.custom("Kosugi-Regular", size: 14))
                .tracking(0.5)
                .foregroundColor(.white)
            Text(label)
                .font(Font.custom("Kosugi-Regular", size: 10))
                .tracking(0.5)
                .foregroundColor(Color(white: 0.4))
        }
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters >= 1609.34 {
            return String(format: "%.1f MI", meters / 1609.34)
        } else {
            return String(format: "%.0f FT", meters * 3.28084)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes >= 60 {
            return "\(minutes / 60)H \(minutes % 60)M"
        }
        return "\(minutes) MIN"
    }

    private func formatArrival(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
```

**Step 2: Add to OPSMapContainer**

```swift
// Layer 6: Navigation header
if coordinator.isNavigating {
    VStack {
        NavigationHeader(navigationManager: coordinator.navigationManager)
            .padding(.top, 60) // Below status bar
        Spacer()
    }
    .transition(.move(edge: .top))
    .animation(.easeInOut(duration: 0.3), value: coordinator.isNavigating)
}
```

**Step 3: Commit**

```
feat: add navigation header with turn instructions, time, distance, and arrival
```

---

### Task 12: Arrival Detection

**Context:** When user arrives within 30m of destination, show arrival state and auto-dismiss navigation after 3 seconds.

**Files:**
- Modify: `OPS/OPS/Map/Core/OPSMapCoordinator.swift` — implement arrival in `updateNavigationProgress()`
- Modify: `OPS/OPS/Map/Core/OPSNavigationManager.swift` — publish arrival state

**Step 1: Implement arrival in updateNavigationProgress**

```swift
private func updateNavigationProgress(_ location: CLLocation) {
    guard isNavigating, let destination = navigationDestination,
          let lat = destination.latitude, let lng = destination.longitude else { return }

    let destLocation = CLLocation(latitude: lat, longitude: lng)
    let distance = location.distance(from: destLocation)

    if distance < 30 {
        // Arrived
        navigationManager.hasArrived = true

        // Zoom in, flatten pitch
        let camera = CameraOptions(
            center: location.coordinate,
            zoom: 16,
            bearing: 0,
            pitch: 0
        )
        mapView?.camera.ease(to: camera, duration: 0.8)

        // Auto-dismiss after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.stopNavigation()
            NotificationCenter.default.post(
                name: Notification.Name("ShowArrivalMessage"),
                object: nil,
                userInfo: ["projectName": destination.title ?? ""]
            )
        }
    }
}
```

**Step 2: Show arrival state in NavigationHeader**

Add to `NavigationHeader.swift`:

```swift
// Replace top row content when arrived
if navigationManager.hasArrived {
    HStack {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 22))
            .foregroundColor(Color(hex: "A5B368"))
        Text("ARRIVED")
            .font(Font.custom("Kosugi-Regular", size: 16))
            .tracking(1)
            .foregroundColor(.white)
        Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
} else {
    // ... existing maneuver row
}
```

**Step 3: Commit**

```
feat: implement arrival detection with auto-dismiss navigation
```

---

## Phase 5: Geofencing

### Task 13: Geofence Manager

**Context:** Monitor the nearest 18 job sites. Detect entry/exit at 100m radius. Surface banners for clock-in/out prompts.

**Files:**
- Create: `OPS/OPS/Map/Core/GeofenceManager.swift`
- Modify: `OPS/OPS/Utilities/LocationManager.swift` — add region monitoring delegate methods

**Step 1: Create GeofenceManager**

```swift
// OPS/OPS/Map/Core/GeofenceManager.swift
import Foundation
import CoreLocation
import Combine

@MainActor
final class GeofenceManager: ObservableObject {

    @Published var pendingArrival: GeofenceEvent?
    @Published var pendingDeparture: GeofenceEvent?

    struct GeofenceEvent {
        let projectId: String
        let projectName: String
        let address: String
        let timestamp: Date
    }

    private let locationManager: CLLocationManager
    private var monitoredProjectIds: Set<String> = []
    private var projectLookup: [String: (name: String, address: String)] = [:]
    private var clockedInProjectId: String?

    // Auto-dismiss timer
    private var dismissTimer: Timer?

    init(locationManager: CLLocationManager) {
        self.locationManager = locationManager
    }

    func updateGeofences(for currentLocation: CLLocation, jobSites: [Project]) {
        // Sort by distance, take closest 18
        let sorted = jobSites
            .compactMap { project -> (Project, CLLocationDistance)? in
                guard let lat = project.latitude, let lng = project.longitude else { return nil }
                let distance = currentLocation.distance(from: CLLocation(latitude: lat, longitude: lng))
                return (project, distance)
            }
            .sorted { $0.1 < $1.1 }

        let desired = Set(sorted.prefix(18).map { $0.0.id })
        let current = monitoredProjectIds

        // Remove stale
        for id in current.subtracting(desired) {
            if let region = locationManager.monitoredRegions.first(where: { $0.identifier == id }) {
                locationManager.stopMonitoring(for: region)
            }
            projectLookup.removeValue(forKey: id)
        }

        // Add new
        for (project, _) in sorted.prefix(18) where !current.contains(project.id) {
            guard let lat = project.latitude, let lng = project.longitude else { continue }
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                radius: 100,
                identifier: project.id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            locationManager.startMonitoring(for: region)
            projectLookup[project.id] = (
                name: project.title ?? "Job Site",
                address: project.address ?? ""
            )
        }

        monitoredProjectIds = desired
    }

    func handleRegionEntry(_ region: CLRegion) {
        guard let info = projectLookup[region.identifier] else { return }
        pendingArrival = GeofenceEvent(
            projectId: region.identifier,
            projectName: info.name,
            address: info.address,
            timestamp: Date()
        )
        startDismissTimer()
    }

    func handleRegionExit(_ region: CLRegion) {
        guard clockedInProjectId == region.identifier,
              let info = projectLookup[region.identifier] else { return }
        pendingDeparture = GeofenceEvent(
            projectId: region.identifier,
            projectName: info.name,
            address: info.address,
            timestamp: Date()
        )
        startDismissTimer()
    }

    func clockIn(projectId: String) {
        clockedInProjectId = projectId
        pendingArrival = nil
        dismissTimer?.invalidate()
        // TODO: Post clock-in to backend
    }

    func clockOut() {
        clockedInProjectId = nil
        pendingDeparture = nil
        dismissTimer?.invalidate()
        // TODO: Post clock-out to backend
    }

    func dismissBanner() {
        pendingArrival = nil
        pendingDeparture = nil
        dismissTimer?.invalidate()
    }

    private func startDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.pendingArrival = nil
                self?.pendingDeparture = nil
            }
        }
    }
}
```

**Step 2: Add region monitoring delegate methods to LocationManager**

Modify `OPS/OPS/Utilities/LocationManager.swift` — add these delegate methods:

```swift
func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    NotificationCenter.default.post(
        name: Notification.Name("GeofenceEntry"),
        object: nil,
        userInfo: ["region": region]
    )
}

func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    NotificationCenter.default.post(
        name: Notification.Name("GeofenceExit"),
        object: nil,
        userInfo: ["region": region]
    )
}
```

**Step 3: Commit**

```
feat: implement GeofenceManager with dynamic region monitoring for nearest 18 sites
```

---

### Task 14: Geofence Banners

**Context:** Frosted glass banners that slide down for clock-in (arrival) and clock-out (departure) prompts.

**Files:**
- Create: `OPS/OPS/Map/Views/GeofenceBanner.swift`
- Modify: `OPS/OPS/Map/Views/OPSMapContainer.swift` — add banner layer + wire GeofenceManager

**Step 1: Create GeofenceBanner view**

```swift
// OPS/OPS/Map/Views/GeofenceBannerView.swift
import SwiftUI

struct GeofenceBannerView: View {
    let event: GeofenceManager.GeofenceEvent
    let type: BannerType
    let onAction: () -> Void
    let onDismiss: () -> Void

    enum BannerType {
        case arrival
        case departure

        var actionLabel: String {
            switch self {
            case .arrival: return "CLOCK IN"
            case .departure: return "CLOCK OUT"
            }
        }

        var prefix: String {
            switch self {
            case .arrival: return "ARRIVED AT"
            case .departure: return "LEAVING"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color(hex: "A5B368"))
                    .frame(width: 8, height: 8)

                Text("\(type.prefix) \(event.address)")
                    .font(Font.custom("Kosugi-Regular", size: 12))
                    .tracking(0.5)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            HStack {
                // Action button (primary)
                Button(action: onAction) {
                    Text(type.actionLabel)
                        .font(Font.custom("Kosugi-Regular", size: 12))
                        .tracking(0.5)
                        .foregroundColor(Color(red: 10/255, green: 10/255, blue: 10/255))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white)
                        )
                }

                Spacer()

                // Dismiss
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Text("Dismiss")
                            .font(Font.custom("Mohave-Regular", size: 14))
                            .foregroundColor(Color(white: 0.6))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.6))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }
}
```

**Step 2: Add to OPSMapContainer + wire GeofenceManager**

Add `@StateObject private var geofenceManager: GeofenceManager` to OPSMapContainer. Initialize in `init()`. Add notification listeners for `"GeofenceEntry"` and `"GeofenceExit"`.

Add banner layer:

```swift
// Layer 7: Geofence banners
VStack {
    Spacer().frame(height: coordinator.isNavigating ? 160 : 100) // Below nav header or app header

    if let arrival = geofenceManager.pendingArrival {
        GeofenceBannerView(
            event: arrival,
            type: .arrival,
            onAction: { geofenceManager.clockIn(projectId: arrival.projectId) },
            onDismiss: { geofenceManager.dismissBanner() }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    if let departure = geofenceManager.pendingDeparture {
        GeofenceBannerView(
            event: departure,
            type: .departure,
            onAction: { geofenceManager.clockOut() },
            onDismiss: { geofenceManager.dismissBanner() }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    Spacer()
}
.animation(.easeInOut(duration: 0.3), value: geofenceManager.pendingArrival != nil)
.animation(.easeInOut(duration: 0.3), value: geofenceManager.pendingDeparture != nil)
```

**Step 3: Commit**

```
feat: add geofence clock-in/out banners with auto-dismiss
```

---

## Phase 6: Team Tracking

### Task 15: Supabase Database Migration

**Context:** Create the `crew_locations` and `location_history` tables in Supabase.

**Files:**
- Create: Supabase migration (run via Supabase dashboard or CLI)

**Step 1: Apply migration**

Run this SQL in Supabase SQL Editor (or via `supabase db push`):

```sql
-- Current crew positions (one row per member, upserted)
CREATE TABLE IF NOT EXISTS crew_locations (
    user_id UUID PRIMARY KEY,
    org_id UUID NOT NULL,
    first_name TEXT NOT NULL DEFAULT '',
    last_name TEXT,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    accuracy DOUBLE PRECISION,
    battery_level REAL,
    is_background BOOLEAN DEFAULT false,
    current_task_name TEXT,
    current_project_name TEXT,
    current_project_id TEXT,
    current_project_address TEXT,
    phone_number TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_crew_loc_org ON crew_locations(org_id);

-- Historical location log (append-only, 90-day retention)
CREATE TABLE IF NOT EXISTS location_history (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    org_id UUID NOT NULL,
    session_id UUID,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    recorded_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_loc_history_user_time ON location_history(user_id, recorded_at DESC);

-- RLS: users can only see crew_locations for their own org
ALTER TABLE crew_locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own org crew locations"
ON crew_locations FOR SELECT
USING (org_id IN (SELECT company_id FROM users WHERE id = auth.uid()));

CREATE POLICY "Users can upsert own location"
ON crew_locations FOR INSERT
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own location"
ON crew_locations FOR UPDATE
USING (user_id = auth.uid());
```

**Step 2: Verify in Supabase dashboard**

Check that both tables exist with correct columns and RLS policies.

**Step 3: Commit** (commit the migration file if using local Supabase CLI)

```
feat: add crew_locations and location_history Supabase tables
```

---

### Task 16: Location Broadcasting Service

**Context:** When a crew member is clocked in, broadcast their location via Supabase Realtime and persist to `crew_locations` table.

**Files:**
- Create: `OPS/OPS/Map/Services/CrewLocationBroadcaster.swift`

**Reference:** Read `OPS/OPS/Network/Supabase/SupabaseService.swift` for the Supabase client singleton. Read `OPS/OPS/Utilities/LocationManager.swift` for location subscription.

**Step 1: Create CrewLocationBroadcaster**

```swift
// OPS/OPS/Map/Services/CrewLocationBroadcaster.swift
import Foundation
import CoreLocation
import Combine
import Supabase

@MainActor
final class CrewLocationBroadcaster: ObservableObject {

    @Published var isBroadcasting: Bool = false

    private let supabase = SupabaseService.shared.client
    private var locationManager: LocationManager
    private var cancellables = Set<AnyCancellable>()
    private var channel: RealtimeChannelV2?

    private var lastBroadcastTime: Date = .distantPast
    private var lastPersistTime: Date = .distantPast
    private var lastCoordinate: CLLocationCoordinate2D?

    // User info — set on start
    private var userId: String = ""
    private var orgId: String = ""
    private var firstName: String = ""
    private var lastName: String = ""
    private var phoneNumber: String?

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }

    func startBroadcasting(
        userId: String,
        orgId: String,
        firstName: String,
        lastName: String,
        phoneNumber: String?
    ) async {
        self.userId = userId
        self.orgId = orgId
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber

        // Subscribe to location updates
        locationManager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                Task { await self?.handleLocation(location) }
            }
            .store(in: &cancellables)

        // Join Supabase Realtime channel
        channel = supabase.realtimeV2.channel("crew-locations:\(orgId)")
        await channel?.subscribe()

        isBroadcasting = true
    }

    func stopBroadcasting() async {
        isBroadcasting = false
        cancellables.removeAll()
        await channel?.unsubscribe()
        channel = nil
    }

    private func handleLocation(_ location: CLLocation) async {
        // Noise rejection
        guard shouldAcceptLocation(location) else { return }

        // Determine broadcast frequency based on speed
        let interval: TimeInterval = location.speed > 1 ? 10 : 60
        guard abs(lastBroadcastTime.timeIntervalSinceNow) >= interval else { return }

        lastBroadcastTime = Date()
        lastCoordinate = location.coordinate

        let payload: [String: AnyJSON] = [
            "userId": .string(userId),
            "orgId": .string(orgId),
            "firstName": .string(firstName),
            "lastName": .string(lastName),
            "lat": .double(location.coordinate.latitude),
            "lng": .double(location.coordinate.longitude),
            "heading": .double(location.course),
            "speed": .double(location.speed),
            "accuracy": .double(location.horizontalAccuracy),
            "timestamp": .string(ISO8601DateFormatter().string(from: location.timestamp)),
            "batteryLevel": .double(Double(UIDevice.current.batteryLevel)),
            "isBackground": .bool(UIApplication.shared.applicationState == .background),
            "phoneNumber": .string(phoneNumber ?? "")
        ]

        // Broadcast via Realtime (ephemeral)
        await channel?.broadcast(event: "location", message: payload)

        // Persist to DB (throttled: every 10s when moving, 60s when stationary)
        if abs(lastPersistTime.timeIntervalSinceNow) >= interval {
            lastPersistTime = Date()
            await persistLocation(location)
        }
    }

    private func persistLocation(_ location: CLLocation) async {
        do {
            try await supabase.from("crew_locations")
                .upsert([
                    "user_id": AnyJSON.string(userId),
                    "org_id": AnyJSON.string(orgId),
                    "first_name": AnyJSON.string(firstName),
                    "last_name": AnyJSON.string(lastName),
                    "lat": AnyJSON.double(location.coordinate.latitude),
                    "lng": AnyJSON.double(location.coordinate.longitude),
                    "heading": AnyJSON.double(location.course),
                    "speed": AnyJSON.double(location.speed),
                    "accuracy": AnyJSON.double(location.horizontalAccuracy),
                    "battery_level": AnyJSON.double(Double(UIDevice.current.batteryLevel)),
                    "is_background": AnyJSON.bool(UIApplication.shared.applicationState == .background),
                    "phone_number": AnyJSON.string(phoneNumber ?? ""),
                    "updated_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))
                ])
                .execute()
        } catch {
            print("[CrewBroadcaster] Persist error: \(error)")
        }
    }

    private func shouldAcceptLocation(_ location: CLLocation) -> Bool {
        guard abs(location.timestamp.timeIntervalSinceNow) < 10 else { return false }
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 50 else { return false }

        // Skip if identical coordinate
        if let last = lastCoordinate,
           last.latitude == location.coordinate.latitude,
           last.longitude == location.coordinate.longitude {
            return false
        }

        return true
    }
}
```

**Step 2: Commit**

```
feat: implement CrewLocationBroadcaster with Supabase Realtime and DB persistence
```

---

### Task 17: Crew Location Subscription & Display

**Context:** Owner/manager subscribes to the org's Supabase Realtime channel and updates crew dots on the map in real time.

**Files:**
- Create: `OPS/OPS/Map/Services/CrewLocationSubscriber.swift`
- Modify: `OPS/OPS/Map/Core/OPSMapCoordinator.swift` — integrate subscriber, update crew annotations on new data

**Step 1: Create CrewLocationSubscriber**

```swift
// OPS/OPS/Map/Services/CrewLocationSubscriber.swift
import Foundation
import Supabase
import Combine

@MainActor
final class CrewLocationSubscriber: ObservableObject {

    @Published var crewLocations: [String: CrewLocationUpdate] = [:]

    private let supabase = SupabaseService.shared.client
    private var channel: RealtimeChannelV2?

    func subscribe(orgId: String) async {
        // Load initial state from DB
        await loadInitialState(orgId: orgId)

        // Subscribe to Realtime broadcast
        channel = supabase.realtimeV2.channel("crew-locations:\(orgId)")

        let stream = channel!.broadcastStream(event: "location")

        await channel?.subscribe()

        // Listen for updates
        Task {
            for await message in stream {
                if let data = try? JSONSerialization.data(withJSONObject: message),
                   let update = try? JSONDecoder().decode(CrewLocationUpdate.self, from: data) {
                    crewLocations[update.userId] = update
                }
            }
        }
    }

    func unsubscribe() async {
        await channel?.unsubscribe()
        channel = nil
    }

    private func loadInitialState(orgId: String) async {
        do {
            let rows: [CrewLocationRow] = try await supabase.from("crew_locations")
                .select()
                .eq("org_id", value: orgId)
                .execute()
                .value

            for row in rows {
                let update = CrewLocationUpdate(
                    userId: row.user_id,
                    orgId: row.org_id,
                    firstName: row.first_name,
                    lat: row.lat,
                    lng: row.lng,
                    heading: row.heading ?? -1,
                    speed: row.speed ?? 0,
                    accuracy: row.accuracy ?? 0,
                    timestamp: row.updated_at,
                    batteryLevel: row.battery_level ?? 0,
                    isBackground: row.is_background ?? false,
                    currentTaskName: row.current_task_name,
                    currentProjectName: row.current_project_name,
                    currentProjectId: row.current_project_id,
                    currentProjectAddress: row.current_project_address,
                    phoneNumber: row.phone_number
                )
                crewLocations[row.user_id] = update
            }
        } catch {
            print("[CrewSubscriber] Load error: \(error)")
        }
    }
}

// DB row mapping
struct CrewLocationRow: Codable {
    let user_id: String
    let org_id: String
    let first_name: String
    let last_name: String?
    let lat: Double
    let lng: Double
    let heading: Double?
    let speed: Double?
    let accuracy: Double?
    let battery_level: Float?
    let is_background: Bool?
    let current_task_name: String?
    let current_project_name: String?
    let current_project_id: String?
    let current_project_address: String?
    let phone_number: String?
    let updated_at: Date
}
```

**Step 2: Integrate into OPSMapCoordinator**

Add to `OPSMapCoordinator`:

```swift
// Property
let crewSubscriber = CrewLocationSubscriber()

// In setupMapView() or on container appear:
func startCrewTracking(orgId: String) {
    Task {
        await crewSubscriber.subscribe(orgId: orgId)
    }

    // Observe changes
    crewSubscriber.$crewLocations
        .receive(on: DispatchQueue.main)
        .sink { [weak self] locations in
            self?.crewLocations = locations
            self?.refreshCrewAnnotations()
        }
        .store(in: &cancellables)
}

func stopCrewTracking() {
    Task {
        await crewSubscriber.unsubscribe()
    }
}
```

**Step 3: Commit**

```
feat: implement crew location subscriber with Supabase Realtime and initial DB load
```

---

## Phase 7: Integration & Cleanup

### Task 18: Wire New Map into HomeContentView

**Context:** Replace the old `SafeMapContainer` in `HomeContentView.mapLayer` with the new `OPSMapContainer`. Same callback interface, so integration is mostly a swap.

**Files:**
- Modify: `OPS/OPS/Views/Home/HomeContentView.swift` — replace `SafeMapContainer` with `OPSMapContainer`

**Reference:** Read `HomeContentView.swift` lines 111-184 for the current `SafeMapContainer` usage and its callback parameters.

**Step 1: Replace SafeMapContainer with OPSMapContainer**

In `HomeContentView.swift`, find the `mapLayer` computed property (around line 111). Replace:

```swift
// OLD:
SafeMapContainer(
    projects: todaysProjects,
    selectedIndex: selectedEventIndex ?? 0,
    ...
)

// NEW:
OPSMapContainer(
    projects: todaysProjects,
    selectedIndex: selectedEventIndex ?? 0,
    selectedTask: selectedTask,
    onProjectSelected: { project in
        // Same callback logic as old version
        if let index = todaysProjects.firstIndex(where: { $0.id == project.id }) {
            selectedEventIndex = index
        }
    },
    onNavigationStarted: { project in
        // Same callback logic as old version
        startProject(project)
    },
    appState: appState,
    locationManager: locationManager
)
```

The exact callback bodies should match what's currently in `HomeContentView.swift` lines 120-172.

**Step 2: Remove SafeMapContainer import/reference**

Ensure no other file references `SafeMapContainer` or `MapContainer`.

**Step 3: Build and test**

Run: `Cmd+B`. Open simulator, verify map loads with dark tiles.

**Step 4: Commit**

```
feat: wire OPSMapContainer into HomeContentView replacing SafeMapContainer
```

---

### Task 19: Delete Dead Code

**Context:** Remove all old map files that have been replaced.

**Files to delete:**
```
OPS/OPS/Map/Views/MapView.swift
OPS/OPS/Map/Views/MapContainer.swift
OPS/OPS/Map/Views/SafeMapContainer.swift
OPS/OPS/Map/Views/MapControlsView.swift
OPS/OPS/Map/Views/MapViewAlternative.swift
OPS/OPS/Map/Views/NavigationView.swift
OPS/OPS/Map/Views/ProjectDetailsCard.swift
OPS/OPS/Map/Views/ProjectMarkerPopup.swift
OPS/OPS/Map/Core/MapCoordinator.swift
OPS/OPS/Map/Core/NavigationEngine.swift
OPS/OPS/Map/Core/KalmanHeadingFilter.swift
OPS/OPS/Map/Core/LocationService.swift
OPS/OPS/Views/Components/Map/ProjectMapView.swift
OPS/OPS/Views/Components/Map/MiniMapView.swift
OPS/OPS/Views/Components/Map/ProjectMapAnnotation.swift
OPS/OPS/Navigation/NavigationBanner.swift
OPS/OPS/Navigation/PersistentNavigationHeader.swift
OPS/OPS/Utilities/DeviceHeadingManager.swift
```

**Step 1: Delete files**

Remove each file. Fix any remaining compile errors from references to deleted types.

**Step 2: Search for stale references**

Grep for `MapCoordinator`, `NavigationEngine`, `SafeMapContainer`, `ProjectMapView`, `MapViewAlternative`, `KalmanHeadingFilter`, `DeviceHeadingManager`, `NavigationBanner`, `PersistentNavigationHeader` across the project. Remove/update any remaining references.

**Step 3: Build and verify**

Run: `Cmd+B`. Expected: clean build with no references to deleted files.

**Step 4: Commit**

```
chore: remove old MapKit map files replaced by Mapbox implementation
```

---

### Task 20: Location Permission Pre-Prompt

**Context:** Show a branded explanation screen before the iOS system location dialog. Required for App Store compliance and good UX.

**Files:**
- Create: `OPS/OPS/Map/Views/LocationPermissionView.swift`
- Modify: `OPS/OPS/Map/Views/OPSMapContainer.swift` — show when location not authorized

**Step 1: Create LocationPermissionView**

```swift
// OPS/OPS/Map/Views/LocationPermissionView.swift
import SwiftUI

struct LocationPermissionView: View {
    let onEnable: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Image(systemName: "location.fill")
                .font(.system(size: 36))
                .foregroundColor(Color(hex: "597794"))

            Text("LOCATION SHARING")
                .font(Font.custom("Kosugi-Regular", size: 16))
                .tracking(1)
                .foregroundColor(.white)

            Text("OPS uses your location during your shift so your manager can coordinate the team. Location sharing only works when you are clocked in.")
                .font(Font.custom("Mohave-Regular", size: 16))
                .foregroundColor(Color(white: 0.6))
                .lineSpacing(4)

            VStack(spacing: 12) {
                Button(action: onEnable) {
                    Text("ENABLE LOCATION")
                        .font(Font.custom("Kosugi-Regular", size: 13))
                        .tracking(0.5)
                        .foregroundColor(Color(red: 10/255, green: 10/255, blue: 10/255))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white)
                        )
                }

                Button(action: onSkip) {
                    Text("NOT NOW")
                        .font(Font.custom("Kosugi-Regular", size: 13))
                        .tracking(0.5)
                        .foregroundColor(Color(white: 0.6))
                }
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 10/255, green: 10/255, blue: 10/255))
    }
}
```

**Step 2: Show in OPSMapContainer when location not authorized**

```swift
// In OPSMapContainer body, as an overlay:
if locationManager.authorizationStatus == .notDetermined {
    LocationPermissionView(
        onEnable: { locationManager.requestPermissionIfNeeded() },
        onSkip: { /* dismiss, map works without location but degraded */ }
    )
}
```

**Step 3: Commit**

```
feat: add branded location permission pre-prompt view
```

---

### Task 21: Adaptive GPS Accuracy for Broadcasting

**Context:** Extend LocationManager to adjust GPS accuracy based on speed to save battery.

**Files:**
- Modify: `OPS/OPS/Utilities/LocationManager.swift` — add adaptive accuracy method

**Step 1: Add method to LocationManager**

```swift
func adjustAccuracyForSpeed(_ speed: CLLocationSpeed) {
    if speed > 10 {
        // Driving
        locationManager.distanceFilter = 10
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    } else if speed > 1 {
        // Walking
        locationManager.distanceFilter = 20
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    } else {
        // Stationary
        locationManager.distanceFilter = 100
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
}
```

**Step 2: Call from location delegate**

In `locationManager(_:didUpdateLocations:)`, after accepting the location:

```swift
adjustAccuracyForSpeed(location.speed)
```

**Step 3: Commit**

```
feat: add adaptive GPS accuracy based on speed to save battery
```

---

### Task 22: Mapbox Studio Dark Style (Manual Step)

**Context:** Create the custom OPS dark map style in Mapbox Studio. This is a manual step done in the Mapbox Studio web editor.

**Steps:**
1. Log into Mapbox Studio (studio.mapbox.com)
2. Duplicate the `Dark v11` base style
3. Rename to "OPS Dark"
4. Modify layers:
   - Background/land: `#050505`
   - Water: `#0D0D0D`
   - Primary roads: `#1A1A1A`
   - Secondary roads: `#111111`
   - Buildings: `#0D0D0D` fill, `#1A1A1A` stroke
   - Road labels: white @ 50% opacity. Try Kosugi or Mohave if uploadable; else use "DIN Pro" (Mapbox default, clean monospace-ish)
   - Hide all POI labels
   - Parks/green: `#0A0F0A`
5. Publish style
6. Copy the style URL (format: `mapbox://styles/USERNAME/STYLEID`)
7. Update `MapboxConfig.darkStyleURI` with the real URL

**Step 8: Commit**

```
feat: update MapboxConfig with custom OPS dark style URL
```

---

## Summary: File Inventory

### Files to Create (14 new files)
```
OPS/OPS/Map/Core/MapboxConfig.swift
OPS/OPS/Map/Core/OPSMapCoordinator.swift
OPS/OPS/Map/Core/OPSNavigationManager.swift
OPS/OPS/Map/Core/GeofenceManager.swift
OPS/OPS/Map/Views/OPSMapView.swift
OPS/OPS/Map/Views/OPSMapContainer.swift
OPS/OPS/Map/Views/MapFilterChips.swift
OPS/OPS/Map/Views/ProjectPinCard.swift
OPS/OPS/Map/Views/CrewTooltipCard.swift
OPS/OPS/Map/Views/NavigationHeader.swift
OPS/OPS/Map/Views/GeofenceBannerView.swift
OPS/OPS/Map/Views/LocationPermissionView.swift
OPS/OPS/Map/Annotations/ProjectAnnotationRenderer.swift
OPS/OPS/Map/Annotations/CrewAnnotationRenderer.swift
OPS/OPS/Map/Models/CrewLocationUpdate.swift
OPS/OPS/Map/Services/CrewLocationBroadcaster.swift
OPS/OPS/Map/Services/CrewLocationSubscriber.swift
```

### Files to Modify (3 files)
```
OPS/OPS/OPSApp.swift — add MapboxConfig.configure()
OPS/OPS/Views/Home/HomeContentView.swift — swap SafeMapContainer → OPSMapContainer
OPS/OPS/Utilities/LocationManager.swift — add region monitoring delegates + adaptive accuracy
```

### Files to Delete (18 files)
```
OPS/OPS/Map/Views/MapView.swift
OPS/OPS/Map/Views/MapContainer.swift
OPS/OPS/Map/Views/SafeMapContainer.swift
OPS/OPS/Map/Views/MapControlsView.swift
OPS/OPS/Map/Views/MapViewAlternative.swift
OPS/OPS/Map/Views/NavigationView.swift
OPS/OPS/Map/Views/ProjectDetailsCard.swift
OPS/OPS/Map/Views/ProjectMarkerPopup.swift
OPS/OPS/Map/Core/MapCoordinator.swift
OPS/OPS/Map/Core/NavigationEngine.swift
OPS/OPS/Map/Core/KalmanHeadingFilter.swift
OPS/OPS/Map/Core/LocationService.swift
OPS/OPS/Views/Components/Map/ProjectMapView.swift
OPS/OPS/Views/Components/Map/MiniMapView.swift
OPS/OPS/Views/Components/Map/ProjectMapAnnotation.swift
OPS/OPS/Navigation/NavigationBanner.swift
OPS/OPS/Navigation/PersistentNavigationHeader.swift
OPS/OPS/Utilities/DeviceHeadingManager.swift
```
