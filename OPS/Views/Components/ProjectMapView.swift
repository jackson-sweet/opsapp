//
//  ProjectMapView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//

import SwiftUI
import MapKit

struct ProjectMapView: UIViewRepresentable {
    // MARK: - Style Configuration
    
    // Map appearance - simple and reliable
    private static let mapType: MKMapType = .mutedStandard
    private static let defaultMapPitch: CGFloat = 0.0
    private static let navigationMapPitch: CGFloat = 60.0
    private static let navigationMapHeading: CGFloat = 0.0
    private static let userTrackingMode: MKUserTrackingMode = .none
    private static let navigationTrackingMode: MKUserTrackingMode = .followWithHeading
    
    // Route appearance
    private static let routeColor: UIColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
    private static let routeWidth: CGFloat = 6.0
    private static let routeLineCap: CGLineCap = .round
    private static let routeLineJoin: CGLineJoin = .round
    
    // MARK: - Properties
    @Binding var region: MKCoordinateRegion
    let projects: [Project]
    @Binding var selectedIndex: Int
    var onTapMarker: (Int) -> Void
    var routeOverlay: MKOverlay?
    var isInProjectMode: Bool
    
    // MARK: - UIViewRepresentable Implementation
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        
        // Apply styling
        mapView.mapType = Self.mapType
        mapView.overrideUserInterfaceStyle = .dark
        
        // Explicitly ensure all user interactions are enabled
        mapView.isUserInteractionEnabled = true  // Critical
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        
        // Disable Points of Interest
        mapView.pointOfInterestFilter = .excludingAll
        
        // Ensure gestures are properly setup
        context.coordinator.setupGestures(for: mapView)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Verify user interaction every update
        if !mapView.isUserInteractionEnabled {
            mapView.isUserInteractionEnabled = true
        }
        
        // Update annotations and overlays
        updateAnnotations(for: mapView)
        updateRouteOverlay(for: mapView)
        
        // Configure map presentation based on routing state
        if routeOverlay != nil && isInProjectMode {
            let shouldAnimate = mapView.camera.pitch != Self.navigationMapPitch
            
            if shouldAnimate {
                animateToNavigationView(mapView)
            }
        } else {
            let shouldAnimate = mapView.camera.pitch != Self.defaultMapPitch
            
            if shouldAnimate {
                animateToStandardView(mapView)
            }
            
            if !isInProjectMode {
                mapView.setRegion(region, animated: true)
                mapView.setUserTrackingMode(Self.userTrackingMode, animated: false)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Helper Methods
    
    private func updateAnnotations(for mapView: MKMapView) {
        let existingAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(existingAnnotations)
        
        let annotations = projects.enumerated().compactMap { index, project -> ProjectAnnotation? in
            guard let coordinate = project.coordinate else { return nil }
            
            return ProjectAnnotation(
                coordinate: coordinate,
                project: project,
                index: index,
                isSelected: index == selectedIndex,
                isActiveProject: isInProjectMode && index == selectedIndex
            )
        }
        
        mapView.addAnnotations(annotations)
    }
    
    private func updateRouteOverlay(for mapView: MKMapView) {
        // Remove existing route overlays
        mapView.removeOverlays(mapView.overlays)
        
        if let routeOverlay = routeOverlay {
            mapView.addOverlay(routeOverlay)
        }
    }
    
    private func animateToNavigationView(_ mapView: MKMapView) {
        // Reset animation state first
        mapView.setUserTrackingMode(.none, animated: false)
        
        // First focus on user location if available, otherwise use project location
        let targetCoordinate: CLLocationCoordinate2D
        
        if let userLocation = mapView.userLocation.location?.coordinate,
           CLLocationCoordinate2DIsValid(userLocation) {
            targetCoordinate = userLocation
        } else if let projectCoordinate = projects[safe: selectedIndex]?.coordinate {
            targetCoordinate = projectCoordinate
        } else {
            targetCoordinate = region.center
        }
        
        // Create a camera centered on the target
        let camera = MKMapCamera(
            lookingAtCenter: targetCoordinate,
            fromDistance: 500,
            pitch: Self.navigationMapPitch,
            heading: Self.navigationMapHeading
        )
        
        // Animate to 3D view with longer duration
        UIView.animate(withDuration: 0.75) {
            mapView.camera = camera
        } completion: { finished in
            if finished {
                mapView.setUserTrackingMode(Self.navigationTrackingMode, animated: true)
            }
        }
    }
    
    private func animateToStandardView(_ mapView: MKMapView) {
        // Reset tracking mode
        mapView.setUserTrackingMode(.none, animated: false)
        
        // Create a standard 2D camera focused on the region center
        let camera = MKMapCamera(
            lookingAtCenter: region.center,
            fromDistance: 1000,
            pitch: Self.defaultMapPitch,
            heading: 0
        )
        
        // Smooth animation back to 2D
        UIView.animate(withDuration: 0.5) {
            mapView.camera = camera
        }
    }
    
    // MARK: - Public Utility Methods
    
    static func calculateVisibleRegion(for projects: [Project]) -> MKCoordinateRegion {
        guard !projects.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 48.4132, longitude: -123.3650),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        
        // Get coordinates from projects
        let coordinates = projects.compactMap { $0.coordinate }
        
        // Find bounds
        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0
        
        // Calculate span with generous padding
        let latDelta = max(0.01, (maxLat - minLat) * 1.1)
        let lonDelta = max(0.01, (maxLon - minLon) * 1.5)
        
        // Create space at the top by extending boundary
        let adjustedMaxLat = maxLat + (latDelta * 0.9)
        let adjustedMinLat = minLat - (latDelta * 0.3)
        
        // New center based on adjusted bounds
        let centerLat = (adjustedMinLat + adjustedMaxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        
        // Account for the new larger span
        let finalLatDelta = adjustedMaxLat - minLat
        
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: finalLatDelta, longitudeDelta: lonDelta)
        )
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: ProjectMapView
        
        init(_ parent: ProjectMapView) {
            self.parent = parent
        }
        
        func setupGestures(for mapView: MKMapView) {
            // This is key: make sure all gestures on the map view have us as delegate
            for gestureRecognizer in mapView.gestureRecognizers ?? [] {
                gestureRecognizer.delegate = self
            }
        }
        
        // CRITICAL: Allow all gesture recognizers to work simultaneously
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }
            
            if let projectAnnotation = annotation as? ProjectAnnotation {
                let identifier = "ProjectMarker"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                
                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = false
                } else {
                    annotationView?.annotation = annotation
                }
                
                // Configure marker appearance
                annotationView?.markerTintColor = UIColor.white
                annotationView?.glyphTintColor = ProjectMapView.routeColor
                annotationView?.glyphImage = UIImage(systemName: "circle.fill")
                
                // Scale selected marker for better visibility
                let scale: CGFloat = projectAnnotation.isSelected ? 1.3 : 1.0
                annotationView?.transform = CGAffineTransform(scaleX: scale, y: scale)
                
                return annotationView
            }
            
            return nil
        }
        
        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let projectAnnotation = annotation as? ProjectAnnotation {
                parent.onTapMarker(projectAnnotation.index)
            }
            
            mapView.deselectAnnotation(annotation, animated: false)
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                
                // Apply route styling - bright blue line
                renderer.strokeColor = ProjectMapView.routeColor
                renderer.lineWidth = ProjectMapView.routeWidth
                renderer.lineCap = ProjectMapView.routeLineCap
                renderer.lineJoin = ProjectMapView.routeLineJoin
                
                return renderer
            }
            
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Project Annotation

class ProjectAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let project: Project
    let index: Int
    let isSelected: Bool
    let isActiveProject: Bool
    
    init(coordinate: CLLocationCoordinate2D, project: Project, index: Int, isSelected: Bool, isActiveProject: Bool = false) {
        self.coordinate = coordinate
        self.project = project
        self.index = index
        self.isSelected = isSelected
        self.isActiveProject = isActiveProject
        super.init()
    }
}

// MARK: - Safe Array Extension
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
