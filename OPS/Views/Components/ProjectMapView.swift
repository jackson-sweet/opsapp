//
//  ProjectMapView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//

import SwiftUI
import MapKit

// Main map view for displaying projects
struct ProjectMapView: View {
    // MARK: - Properties
    @Binding var region: MKCoordinateRegion
    let projects: [Project]
    @Binding var selectedIndex: Int
    var onTapMarker: (Int) -> Void
    var routeOverlay: MKOverlay?
    var isInProjectMode: Bool
    
    // Location manager
    @StateObject private var locationManager = LocationManager()
    
    // Map configuration for overlays
    @State private var mapConfig = MapViewConfig()
    
    var body: some View {
        ZStack {
            // Base map with project annotations and route overlay
            // Use UIViewRepresentable implementation for older iOS support
            MapViewRepresentable(
                region: $region,
                annotations: projects.indices.map { index in
                    MapAnnotationItem(
                        id: projects[index].id,
                        project: projects[index],
                        coordinate: projects[index].coordinate ?? CLLocationCoordinate2D(latitude: 48.4132, longitude: -123.3650),
                        index: index,
                        isSelected: index == selectedIndex,
                        isActiveProject: isInProjectMode && index == selectedIndex,
                        onTap: {
                            selectedIndex = index
                            onTapMarker(index)
                        }
                    )
                },
                routeOverlay: routeOverlay,
                showsUserLocation: true
            )
            
            // Recenter button when in project mode
            if isInProjectMode, let destination = projects[safe: selectedIndex]?.coordinate {
                VStack {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            centerOnRoute(destination: destination)
                        }) {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.cardBackground.opacity(0.8))
                                    .frame(width: 44, height: 44)
                                    .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
                                
                                Image(systemName: "location.fill")
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    .font(.system(size: 20, weight: .bold))
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 100) // Clear space for the directions view
                    }
                }
            }
        }
        .onAppear {
            // Request location permissions
            locationManager.requestPermissionIfNeeded()
        }
    }
    
    // MARK: - Helper Methods
    
    // Center map on the route between current location and destination
    private func centerOnRoute(destination: CLLocationCoordinate2D) {
        // Get user location
        if let userLocation = locationManager.userLocation {
            // Create a region that includes both user location and destination
            let coordinates = [userLocation, destination]
            let minLat = coordinates.map { $0.latitude }.min() ?? 0
            let maxLat = coordinates.map { $0.latitude }.max() ?? 0
            let minLon = coordinates.map { $0.longitude }.min() ?? 0
            let maxLon = coordinates.map { $0.longitude }.max() ?? 0
            
            // Add padding
            let padding = 0.02
            let latDelta = max(0.01, (maxLat - minLat) + padding * 2)
            let lonDelta = max(0.01, (maxLon - minLon) + padding * 2)
            
            // Create center point
            let centerLat = (minLat + maxLat) / 2
            let centerLon = (minLon + maxLon) / 2
            
            // Update region directly
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            )
        } else {
            // If no user location, just center on destination
            region = MKCoordinateRegion(
                center: destination,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
    }
    
    // Calculate visible region to show all projects
    static func calculateVisibleRegion(for projects: [Project], zoomLevel: Double? = nil) -> MKCoordinateRegion {
        guard !projects.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 48.4132, longitude: -123.3650),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        
        // Get coordinates from projects
        let coordinates = projects.compactMap { $0.coordinate }
        
        // For single project with custom zoom level
        if coordinates.count == 1 && zoomLevel != nil {
            return MKCoordinateRegion(
                center: coordinates[0],
                span: MKCoordinateSpan(
                    latitudeDelta: zoomLevel!,
                    longitudeDelta: zoomLevel!
                )
            )
        }
        
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
}

// Helper structure for map annotations
struct ProjectMapItem: Identifiable {
    let id: String
    let project: Project
    let coordinate: CLLocationCoordinate2D
    let index: Int
    let isSelected: Bool
    let isActiveProject: Bool
}

// Array safe access extension
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// Helper structs and types for map implementation

// Helper struct to configure the map view
struct MapViewConfig {
    var mapStyle: MKStandardMapConfiguration {
        let config = MKStandardMapConfiguration()
        config.pointOfInterestFilter = .excludingAll
        // Use dark map style to match reference design
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
    // Constructor for direct polyline
    init(polyline: MKPolyline, color: UIColor, lineWidth: CGFloat) {
        super.init(polyline: polyline)
        self.strokeColor = color
        self.lineWidth = lineWidth
        self.alpha = 1.0
        self.lineCap = .round
        self.lineJoin = .round
    }
    
    // Required for MKMapViewDelegate
    override init(overlay: MKOverlay) {
        super.init(overlay: overlay)
        
        // Default styling
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
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        
        // Configure map appearance
        mapView.overrideUserInterfaceStyle = .dark
        mapView.pointOfInterestFilter = .excludingAll
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update region
        mapView.setRegion(region, animated: true)
        
        // Update annotations
        let currentAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(currentAnnotations)
        
        // Add new annotations
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
        
        // Handle route overlay
        mapView.removeOverlays(mapView.overlays)
        if let routeOverlay = routeOverlay {
            mapView.addOverlay(routeOverlay)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        
        init(_ parent: MapViewRepresentable) {
            self.parent = parent
        }
        
        // Handle annotation views
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Skip user location annotation
            if annotation is MKUserLocation {
                return nil
            }
            
            // Handle custom annotations
            guard let customAnnotation = annotation as? CustomAnnotation else {
                return nil
            }
            
            let identifier = "ProjectAnnotation"
            let annotationView = MKAnnotationView(annotation: customAnnotation, reuseIdentifier: identifier)
            
            // Create SwiftUI view for the annotation
            let projectAnnotation = ProjectMapAnnotation(
                project: customAnnotation.project,
                isSelected: customAnnotation.isSelected,
                isActiveProject: customAnnotation.isActiveProject,
                onTap: {
                    // Find the corresponding annotation item and call its onTap handler
                    if let item = self.parent.annotations.first(where: { $0.id == customAnnotation.id }) {
                        item.onTap()
                    }
                }
            )
            
            // Convert SwiftUI view to UIView
            let hostingController = UIHostingController(rootView: projectAnnotation)
            hostingController.view.backgroundColor = .clear
            
            // Size the annotation view
            let size = hostingController.sizeThatFits(in: UIView.layoutFittingExpandedSize)
            hostingController.view.frame = CGRect(origin: .zero, size: size)
            
            // Add the SwiftUI view as a subview
            annotationView.addSubview(hostingController.view)
            
            return annotationView
        }
        
        // Handle overlay rendering
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            // For polylines (routes), use our custom renderer
            if overlay is MKPolyline {
                let renderer = CustomPolylineRenderer(overlay: overlay)
                
                // Apply styling here for safety
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 5
                renderer.alpha = 1.0
                
                return renderer
            }
            
            // Fallback for other overlay types
            return MKOverlayRenderer(overlay: overlay)
        }
        
        // Handle region changes
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Update parent region binding when map is panned/zoomed
            parent.region = mapView.region
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