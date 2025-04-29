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
    
    // Map interaction
    private static let allowsZoom: Bool = true
    private static let allowsRotation: Bool = true
    private static let allowsPitch: Bool = true
    private static let showsCompass: Bool = false
    private static let showsScale: Bool = false
    private static let showsTraffic: Bool = false
    private static let showsBuildings: Bool = false
    
    // Marker appearance
    private static let markerColor: UIColor = UIColor(.white) // FF3B30
    private static let markerSymbol = "mappin.and.ellipse.circle" // SF Symbol name
    private static let markerSize = CGSize(width: 30, height: 30)
    private static let selectedMarkerScale: CGFloat = 1.3
    private static let normalMarkerScale: CGFloat = 1.0
    private static let useCustomMarker: Bool = false
    
    // Route appearance
    private static let routeColor: UIColor = UIColor(Color("AccentSecondary")) // FF9300
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
        
        // Apply simple, reliable styling that works across iOS versions
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
        mapView.setRegion(region, animated: true)
        updateAnnotations(for: mapView)
        updateRouteOverlay(for: mapView)
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
        let latDelta = max(0.01, (maxLat - minLat) * 1.1) // 50% padding
        let lonDelta = max(0.01, (maxLon - minLon) * 1.5) // 50% padding
        
        // Instead of trying to shift the center, we simply add additional space
        // at the top by extending our max latitude boundary
        let adjustedMaxLat = maxLat + (latDelta * 0.9)
        let adjustedMinLat = minLat - (latDelta * 0.3)// Add 50% more space at the top
        
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
                let identifier = markerSymbol
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                
                if annotationView == nil {
                    annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = false
                } else {
                    annotationView?.annotation = annotation
                }
                
                // Create SF Symbol properly with template rendering mode
                let marker = UIImage(systemName:markerSymbol)!.withTintColor(markerColor, renderingMode:.alwaysTemplate)
                let size = markerSize
                let mapmarker = UIGraphicsImageRenderer(size:size).image {
                    _ in marker.draw(in:CGRect(origin:.zero, size:size))
                }
                
                // Set image and tint separately - this is the key to reliable coloring
                annotationView?.image = mapmarker
                
                // Center the annotation on the pin point of the symbol
                annotationView?.centerOffset = CGPoint(x: 0, y: -10)
                
                // Scale selected marker for better visibility
                let scale: CGFloat = projectAnnotation.isSelected ? 1.3 : 1.0
                annotationView?.transform = CGAffineTransform(scaleX: scale, y: scale)
                
                return annotationView
            }
            
            return nil
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
    
