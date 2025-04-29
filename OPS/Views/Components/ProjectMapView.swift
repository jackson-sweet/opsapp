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
    
    // Map appearance
    private static let mapType: MKMapType = .mutedStandard
    private static let usesDarkMode: Bool = true
    private static let defaultMapPitch: CGFloat = 0.0  // Flat view normally
    private static let navigationMapPitch: CGFloat = 60.0  // 3D tilted view for navigation
    private static let navigationMapHeading: CGFloat = 0.0  // North up by default
    private static let userTrackingMode: MKUserTrackingMode = .none  // Default mode
    private static let navigationTrackingMode: MKUserTrackingMode = .followWithHeading  // Follow in navigation
    
    // Map interaction
    private static let allowsZoom: Bool = true
    private static let allowsRotation: Bool = true
    private static let allowsPitch: Bool = true
    private static let showsCompass: Bool = false
    private static let showsScale: Bool = false
    private static let showsTraffic: Bool = false
    private static let showsBuildings: Bool = false
    
    // Marker appearance
    private static let markerColor: UIColor = UIColor(.white)
    private static let markerSymbol = "mappin.and.ellipse.circle"
    private static let markerSize = CGSize(width: 30, height: 30)
    private static let selectedMarkerScale: CGFloat = 1.3
    private static let normalMarkerScale: CGFloat = 1.0
    
    // Route appearance
    private static let routeColor: UIColor = UIColor(Color("AccentSecondary"))
    private static let routeWidth: CGFloat = 5.0
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
        
        // Apply styling that works across iOS versions
        mapView.mapType = Self.mapType
        if Self.usesDarkMode {
            mapView.overrideUserInterfaceStyle = .dark
        }
        
        // Configure map interaction for field use
        mapView.isZoomEnabled = Self.allowsZoom
        mapView.isRotateEnabled = Self.allowsRotation
        mapView.isPitchEnabled = Self.allowsPitch
        mapView.showsCompass = Self.showsCompass
        mapView.showsScale = Self.showsScale
        mapView.showsTraffic = Self.showsTraffic
        mapView.showsBuildings = Self.showsBuildings
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update annotations and overlays
        updateAnnotations(for: mapView)
        updateRouteOverlay(for: mapView)
        
        // Configure map presentation based on routing state
        if routeOverlay != nil {
            // Routing mode - 3D perspective
            if mapView.camera.pitch != Self.navigationMapPitch {
                // Animate to 3D navigation view
                animateToNavigationView(mapView)
            }
            
            // Set user tracking mode for navigation
            if mapView.userTrackingMode != Self.navigationTrackingMode {
                mapView.setUserTrackingMode(Self.navigationTrackingMode, animated: true)
            }
        } else {
            // Normal mode - 2D overview
            if mapView.camera.pitch != Self.defaultMapPitch {
                // Animate back to 2D view
                animateToStandardView(mapView)
            }
            
            // Update region normally when not in navigation mode
            mapView.setRegion(region, animated: true)
            mapView.setUserTrackingMode(Self.userTrackingMode, animated: false)
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
        mapView.removeOverlays(mapView.overlays)
        
        if let routeOverlay = routeOverlay {
            mapView.addOverlay(routeOverlay)
        }
    }
    
    private func animateToNavigationView(_ mapView: MKMapView) {
        // First focus on user location
        if let userLocation = mapView.userLocation.location?.coordinate {
            // Create a camera centered on user
            let camera = MKMapCamera(
                lookingAtCenter: userLocation,
                fromDistance: 500, // Closer zoom for navigation
                pitch: Self.navigationMapPitch,
                heading: Self.navigationMapHeading
            )
            
            // Smooth animation to new camera
            mapView.setCamera(camera, animated: true)
        }
    }
    
    private func animateToStandardView(_ mapView: MKMapView) {
        // Create a standard 2D camera
        let camera = mapView.camera
        camera.pitch = Self.defaultMapPitch
        
        // Smooth animation back to 2D
        mapView.setCamera(camera, animated: true)
    }
    
    // MARK: - Public Utility Methods
    
    /// Calculate a map region that ensures all markers are visible in the bottom 70% of the screen
    static func calculateVisibleRegion(for projects: [Project]) -> MKCoordinateRegion {
        guard !projects.isEmpty else {
            // Default region if no projects
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
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ProjectMapView
        
        init(_ parent: ProjectMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }
            
            if let projectAnnotation = annotation as? ProjectAnnotation {
                // Use standard annotation view
                let identifier = ProjectMapView.markerSymbol
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                
                if annotationView == nil {
                    annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = false
                } else {
                    annotationView?.annotation = annotation
                }
                
                // Create SF Symbol properly with template rendering mode
                let marker = UIImage(systemName: ProjectMapView.markerSymbol)!.withTintColor(ProjectMapView.markerColor, renderingMode: .alwaysTemplate)
                let size = ProjectMapView.markerSize
                let mapmarker = UIGraphicsImageRenderer(size: size).image {
                    _ in marker.draw(in: CGRect(origin: .zero, size: size))
                }
                
                // Set image and proper offset
                annotationView?.image = mapmarker
                annotationView?.centerOffset = CGPoint(x: 0, y: -10)
                
                // Scale selected marker for better visibility
                let scale: CGFloat = projectAnnotation.isSelected ?
                    ProjectMapView.selectedMarkerScale :
                    ProjectMapView.normalMarkerScale
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
                
                // Apply route styling
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
