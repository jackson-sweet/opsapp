//
//  ProjectLocationMapView.swift
//  OPS
//
//  Mapbox-backed map for displaying a project location with nearby projects,
//  user location, and team members. Uses the same dark OPS map style and
//  segmented-ring pin annotation as the main map.
//

import SwiftUI
import MapboxMaps
import CoreLocation

/// Lightweight data for a nearby project pin
struct NearbyProjectPin: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let name: String
    let status: Status
    let taskColorHexes: [String]
}

struct ProjectLocationMapView: UIViewRepresentable {

    let coordinate: CLLocationCoordinate2D
    let projectName: String
    let status: Status
    let taskColorHexes: [String]

    /// Whether the user can pan/zoom/rotate. false for mini map, true for hero map.
    var isInteractive: Bool = true

    /// Zoom level — 13 gives a wider area view showing nearby context.
    var zoomLevel: Double = 13.0

    /// Nearby projects to display on the map
    var nearbyProjects: [NearbyProjectPin] = []

    /// Show user location puck on the map
    var showUserLocation: Bool = false

    // User's map style preference
    @AppStorage("mapStyle") private var mapStyleRaw = "dark"
    @AppStorage("map3DBuildings") private var map3DBuildings = true

    private var opsMapStyle: OPSMapStyle {
        OPSMapStyle(rawValue: mapStyleRaw) ?? .dark
    }

    // MARK: - Make

    func makeUIView(context: Context) -> MapView {
        let style = opsMapStyle
        let camera = CameraOptions(
            center: coordinate,
            zoom: zoomLevel,
            pitch: 0
        )
        let options = MapInitOptions(
            cameraOptions: camera,
            styleURI: style.baseStyleURI
        )
        let mapView = MapView(frame: CGRect(x: 0, y: 0, width: 64, height: 64), mapInitOptions: options)
        mapView.backgroundColor = style.backgroundColor

        // --- Interaction control ---
        if !isInteractive {
            mapView.gestures.options.panEnabled = false
            mapView.gestures.options.pinchEnabled = false
            mapView.gestures.options.rotateEnabled = false
            mapView.gestures.options.pitchEnabled = false
            mapView.gestures.options.doubleTapToZoomInEnabled = false
            mapView.gestures.options.doubleTouchToZoomOutEnabled = false
            mapView.gestures.options.quickZoomEnabled = false
        }

        // --- Hide ornaments ---
        mapView.ornaments.options.compass.visibility = .hidden
        mapView.ornaments.options.scaleBar.visibility = .hidden

        // --- User location puck ---
        if showUserLocation {
            mapView.location.options.puckType = .puck2D(
                Puck2DConfiguration(scale: .constant(0.8))
            )
            mapView.location.options.puckBearing = .course
            mapView.location.options.puckBearingEnabled = true
        }

        // --- Apply OPS style + annotations after base style finishes loading ---
        let coord = context.coordinator
        let mapStyleRef = style
        let show3D = map3DBuildings
        let mainCoord = coordinate
        let mainName = projectName
        let mainStatus = status
        let mainColors = taskColorHexes
        let nearby = nearbyProjects

        coord.styleLoadedCancellable = mapView.mapboxMap.onStyleLoaded.observe { _ in
            MapStyleApplicator.apply(mapStyleRef, to: mapView, show3DBuildings: show3D)
            coord.addAnnotations(
                to: mapView,
                mainCoordinate: mainCoord,
                mainName: mainName,
                mainStatus: mainStatus,
                mainTaskColorHexes: mainColors,
                nearbyProjects: nearby
            )
        }

        return mapView
    }

    // MARK: - Update

    func updateUIView(_ mapView: MapView, context: Context) {
        // Static display — no dynamic reconciliation needed.
    }

    // MARK: - Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var annotationManager: PointAnnotationManager?
        var styleLoadedCancellable: (any Cancelable)?

        func addAnnotations(
            to mapView: MapView,
            mainCoordinate: CLLocationCoordinate2D,
            mainName: String,
            mainStatus: Status,
            mainTaskColorHexes: [String],
            nearbyProjects: [NearbyProjectPin]
        ) {
            let manager = mapView.annotations.makePointAnnotationManager()
            var annotations: [PointAnnotation] = []

            // Main project pin (full opacity, selected look)
            let mainPinImage = ProjectAnnotationRenderer.renderProject(
                name: mainName,
                status: mainStatus,
                taskColorHexes: mainTaskColorHexes,
                isSelected: true
            )
            var mainAnnotation = PointAnnotation(coordinate: mainCoordinate)
            mainAnnotation.image = .init(image: mainPinImage, name: "project-detail-pin-main")
            mainAnnotation.iconAnchor = .bottom
            annotations.append(mainAnnotation)

            // Nearby project pins (dimmer, smaller)
            for (index, nearby) in nearbyProjects.enumerated() {
                let nearbyPinImage = ProjectAnnotationRenderer.renderProject(
                    name: nearby.name,
                    status: nearby.status,
                    taskColorHexes: nearby.taskColorHexes,
                    isSelected: false
                )
                var nearbyAnnotation = PointAnnotation(coordinate: nearby.coordinate)
                nearbyAnnotation.image = .init(image: nearbyPinImage, name: "project-detail-pin-nearby-\(index)")
                nearbyAnnotation.iconAnchor = .bottom
                annotations.append(nearbyAnnotation)
            }

            manager.annotations = annotations
            self.annotationManager = manager
        }
    }
}
