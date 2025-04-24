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
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.isRotateEnabled = false // Simplify interaction for field workers
        
        // Apply dark styling
        mapView.overrideUserInterfaceStyle = .dark
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update map region
        mapView.setRegion(region, animated: true)
        
        // Update annotations
        updateAnnotations(for: mapView)
    }
    
    private func updateAnnotations(for mapView: MKMapView) {
        // Remove existing annotations
        let existingAnnotations = mapView.annotations.compactMap { $0 as? ProjectAnnotation }
        mapView.removeAnnotations(existingAnnotations)
        
        // Add new annotations
        let annotations = projects.enumerated().compactMap { index, project -> ProjectAnnotation? in
            guard let coordinate = project.coordinate else { return nil }
            
            let annotation = ProjectAnnotation(
                coordinate: coordinate,
                project: project,
                index: index,
                isSelected: index == selectedIndex
            )
            return annotation
        }
        
        mapView.addAnnotations(annotations)
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
                
                // Apply styling
                annotationView?.markerTintColor = .red
                
                // Enlarge the selected marker
                let scale: CGFloat = projectAnnotation.isSelected ? 1.3 : 1.0
                annotationView?.transform = CGAffineTransform(scaleX: scale, y: scale)
                
                return annotationView
            }
            
            return nil
        }
        
        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            // Handle tap on annotation
            if let projectAnnotation = annotation as? ProjectAnnotation {
                parent.onTapMarker(projectAnnotation.index)
            }
            
            // Deselect to prevent callout
            mapView.deselectAnnotation(annotation, animated: false)
        }
    }
}

class ProjectAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let project: Project
    let index: Int
    let isSelected: Bool
    
    init(coordinate: CLLocationCoordinate2D, project: Project, index: Int, isSelected: Bool) {
        self.coordinate = coordinate
        self.project = project
        self.index = index
        self.isSelected = isSelected
        super.init()
    }
}