//
//  InProgressManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


// InProgressManager.swift
import SwiftUI
import MapKit

/// Manages the in-progress state of projects, including routing
class InProgressManager: ObservableObject {
    @Published var isRouting = false
    @Published var routeDirections: [String] = []
    @Published var estimatedArrival: String?
    @Published var routeDistance: String?
    private var activeRoute: MKRoute?
    
    func startRouting(to destination: CLLocationCoordinate2D, from userLocation: CLLocationCoordinate2D? = nil) {
        let request = MKDirections.Request()
        
        // Set destination
        let destinationPlacemark = MKPlacemark(coordinate: destination)
        request.destination = MKMapItem(placemark: destinationPlacemark)
        
        // Set start location - either user location or default
        if let userLocation = userLocation {
            let sourcePlacemark = MKPlacemark(coordinate: userLocation)
            request.source = MKMapItem(placemark: sourcePlacemark)
        } else {
            request.source = MKMapItem.forCurrentLocation()
        }
        
        // Route settings
        request.transportType = .automobile
        
        // Calculate route
        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Routing error: \(error.localizedDescription)")
                self.isRouting = false
                return
            }
            
            guard let route = response?.routes.first else {
                print("No route found")
                self.isRouting = false
                return
            }
            
            // Store and process route
            self.activeRoute = route
            self.processRouteDetails(route)
            self.isRouting = true
        }
    }
    
    func stopRouting() {
        isRouting = false
        activeRoute = nil
        routeDirections = []
        estimatedArrival = nil
        routeDistance = nil
    }
    
    private func processRouteDetails(_ route: MKRoute) {
        // Format the expected travel time
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        let _ = formatter.string(from: route.expectedTravelTime) ?? "Unknown"
        
        // Format distance
        let distanceFormatter = MKDistanceFormatter()
        distanceFormatter.unitStyle = .abbreviated
        let distance = distanceFormatter.string(fromDistance: route.distance)
        
        // Store simplified directions
        routeDirections = route.steps.map { $0.instructions }
        .filter { !$0.isEmpty }
        
        // Calculate ETA
        let arrivalDate = Date().addingTimeInterval(route.expectedTravelTime)
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        estimatedArrival = timeFormatter.string(from: arrivalDate)
        
        // Store distance
        routeDistance = distance
    }
    
    func getRouteOverlay() -> MKOverlay? {
        return activeRoute?.polyline
    }
}
