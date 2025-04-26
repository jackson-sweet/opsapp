//
//  ProjectMapView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//

import SwiftUI
import MapKit

struct ProjectMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let projects: [Project]
    @Binding var selectedIndex: Int
    var onTapMarker: (Int) -> Void
    
    // Add routing support
    var routeOverlay: MKOverlay?
    var isInProjectMode: Bool
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.isRotateEnabled = false // Simplify interaction for field workers
        
        // Apply dark styling
        mapView.overrideUserInterfaceStyle = .dark
        
        // Adjust map appearance for darker look
        customizeMapAppearance(mapView)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update map region
        mapView.setRegion(region, animated: true)
        
        // Update annotations
        updateAnnotations(for: mapView)
        
        // Update route overlay
        updateRouteOverlay(for: mapView)
    }
    
    private func customizeMapAppearance(_ mapView: MKMapView) {
        // Set map type to muted satellite for darker appearance
        mapView.mapType = .mutedStandard
        
        // Reduce map details for cleaner look
        mapView.showsTraffic = false
        mapView.showsBuildings = false
        mapView.showsCompass = false
        mapView.showsScale = false
    }
    
    private func updateAnnotations(for mapView: MKMapView) {
        // Remove existing annotations (except user location)
        let existingAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(existingAnnotations)
        
        // Add new annotations
        let annotations = projects.enumerated().compactMap { index, project -> ProjectAnnotation? in
            guard let coordinate = project.coordinate else { return nil }
            
            let annotation = ProjectAnnotation(
                coordinate: coordinate,
                project: project,
                index: index,
                isSelected: index == selectedIndex,
                isActiveProject: isInProjectMode && index == selectedIndex
            )
            return annotation
        }
        
        mapView.addAnnotations(annotations)
    }
    
    private func updateRouteOverlay(for mapView: MKMapView) {
        // Remove existing overlays
        mapView.removeOverlays(mapView.overlays)
        
        // Add route overlay if available
        if let routeOverlay = routeOverlay {
            mapView.addOverlay(routeOverlay)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ProjectMapView
        
        init(_ parent: ProjectMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Skip for user location
            if annotation is MKUserLocation {
                return nil
            }
            
            // Custom annotation view for projects
            if let projectAnnotation = annotation as? ProjectAnnotation {
                let identifier = "ProjectAnnotation"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                
                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = false
                }
                
                // Set custom marker image
                annotationView?.glyphImage = nil // Remove system glyph
                
                // Match the design's red pin exactly
                annotationView?.markerTintColor = UIColor(Color("AccentPrimary"))
                
                // Enlarge the selected marker
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
            
            // Deselect to prevent callout
            mapView.deselectAnnotation(annotation, animated: false)
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(OPSStyle.Colors.secondaryAccent)
                renderer.lineWidth = 5
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

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
