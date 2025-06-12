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
    // Shared instance for app-wide access
    static let shared = InProgressManager()
    
    @Published var isRouting = false
    @Published var routeDirections: [String] = []
    @Published var estimatedArrival: String?
    @Published var routeDistance: String?
    @Published var currentNavStep: NavigationStep?
    @Published var activeRoute: MKRoute?
    
    // Current step index in the route
    private var currentStepIndex: Int = 0
    
    func startRouting(to destination: CLLocationCoordinate2D, from userLocation: CLLocationCoordinate2D? = nil) {
        print("InProgressManager: Starting routing to: \(destination.latitude), \(destination.longitude)")
        print("InProgressManager: Before setting - isRouting = \(self.isRouting)")
        
        // Make sure routing is initially set to true to show loading state
        self.isRouting = true
        print("InProgressManager: After setting - isRouting = \(self.isRouting)")
            
        // Publish explicit notification that routing has started
        NotificationCenter.default.post(name: Notification.Name("RoutingStateChanged"), object: nil, userInfo: ["isRouting": true])
        print("InProgressManager: Posted RoutingStateChanged notification")
        
        let request = MKDirections.Request()
        
        // Set destination with helpful name for better directions
        let destinationPlacemark = MKPlacemark(coordinate: destination)
        let destinationItem = MKMapItem(placemark: destinationPlacemark)
        destinationItem.name = "Project Site" // Give the destination a meaningful name
        request.destination = destinationItem
        
        // Set start location - either user location or default
        if let userLocation = userLocation {
            print("InProgressManager: Using provided user location: \(userLocation.latitude), \(userLocation.longitude)")
            let sourcePlacemark = MKPlacemark(coordinate: userLocation)
            request.source = MKMapItem(placemark: sourcePlacemark)
        } else {
            print("InProgressManager: Using current location")
            request.source = MKMapItem.forCurrentLocation()
        }
        
        // Route settings
        request.transportType = .automobile
        request.requestsAlternateRoutes = true // Request alternatives for better options
        
        // Calculate route
        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("InProgressManager: ⚠️ Routing error: \(error.localizedDescription)")
                    self.isRouting = false
                    
                    // Retry after a delay if it's a network issue
                    if (error as NSError).domain == MKErrorDomain {
                        print("InProgressManager: Will retry routing in 2 seconds")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.startRouting(to: destination, from: userLocation)
                        }
                    }
                    return
                }
                
                guard let response = response, !response.routes.isEmpty else {
                    print("InProgressManager: ⚠️ No route found")
                    self.isRouting = false
                    return
                }
                
                // Get the fastest route
                if let fastestRoute = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) {
                    print("InProgressManager: Found route with \(fastestRoute.steps.count) steps, ETA: \(fastestRoute.expectedTravelTime/60) min")
                    
                    // Store and process route
                    self.activeRoute = fastestRoute
                    self.processRouteDetails(fastestRoute)
                    self.isRouting = true
                    
                    // Post notification again to confirm route found
                    NotificationCenter.default.post(
                        name: Notification.Name("RoutingStateChanged"),
                        object: nil,
                        userInfo: ["isRouting": true]
                    )
                } else if let firstRoute = response.routes.first {
                    // Fallback to first route if we can't determine fastest
                    print("InProgressManager: Using first available route")
                    self.activeRoute = firstRoute
                    self.processRouteDetails(firstRoute)
                    self.isRouting = true
                    
                    // Post notification again to confirm route found
                    NotificationCenter.default.post(
                        name: Notification.Name("RoutingStateChanged"),
                        object: nil,
                        userInfo: ["isRouting": true]
                    )
                }
            }
        }
    }
    
    func stopRouting() {
        // Ensure routing state is fully cleared
        print("InProgressManager: Stopping all routing operations")
        
        // Clear all navigation data
        self.isRouting = false
        self.activeRoute = nil
        self.routeDirections = []
        self.estimatedArrival = nil
        self.routeDistance = nil
        self.currentNavStep = nil
        self.currentStepIndex = 0
        
        // Publish explicit notification that routing has stopped
        NotificationCenter.default.post(name: Notification.Name("RoutingStateChanged"), object: nil, userInfo: ["isRouting": false])
    }
    
    private func processRouteDetails(_ route: MKRoute) {
        // Format the expected travel time
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .pad
        let travelTimeFormatted = formatter.string(from: route.expectedTravelTime) ?? "Unknown"
        print("InProgressManager: Travel time: \(travelTimeFormatted)")
        
        // Format distance
        let distanceFormatter = MKDistanceFormatter()
        distanceFormatter.unitStyle = .abbreviated
        let distance = distanceFormatter.string(fromDistance: route.distance)
        print("InProgressManager: Distance: \(distance)")
        
        // Process route steps
        let validSteps = route.steps.filter { !$0.instructions.isEmpty }
        
        // Clean up and enhance directions
        var cleanDirections = validSteps.map { step -> String in
            // Replace "Project Site" with a more descriptive destination
            var instruction = step.instructions
            if instruction.contains("Project Site") {
                instruction = instruction.replacingOccurrences(of: "Project Site", with: "the project site")
            }
            // Add distance to each step for better context
            if let stepDistance = distanceFormatter.string(fromDistance: step.distance).nilIfEmpty() {
                instruction += " (\(stepDistance))"
            }
            return instruction
        }
        
        // Ensure we have at least one direction
        if cleanDirections.isEmpty {
            cleanDirections = ["Navigate to the project site (\(distance))"]
        }
        
        routeDirections = cleanDirections
        
        // Calculate ETA with more context
        let arrivalDate = Date().addingTimeInterval(route.expectedTravelTime)
        
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let arrivalTime = timeFormatter.string(from: arrivalDate)
        
        // Add travel time to ETA for better context
        estimatedArrival = "\(arrivalTime) (\(travelTimeFormatted))"
        
        // Store distance
        routeDistance = distance
        
        // Reset current step index
        currentStepIndex = 0
        
        // Set the current navigation step if we have valid steps
        if !validSteps.isEmpty {
            setCurrentNavigationStep(for: validSteps)
        } else {
            // Fallback if no steps available
            currentNavStep = NavigationStep(
                instruction: "Navigate to the project site",
                distance: distance,
                distanceValue: route.distance,
                isLastStep: true
            )
        }
    }
    
    /// Sets the current navigation step based on user location and route steps
    private func setCurrentNavigationStep(for steps: [MKRoute.Step]) {
        // Default to first step if user location isn't available
        guard steps.count > currentStepIndex else {
            currentNavStep = nil
            return
        }
        
        let step = steps[currentStepIndex]
        let distanceFormatter = MKDistanceFormatter()
        distanceFormatter.unitStyle = .abbreviated
        
        // Format distance for this step
        let stepDistance = distanceFormatter.string(fromDistance: step.distance)
        
        // Create a clean instruction
        var instruction = step.instructions
        if instruction.contains("Project Site") {
            instruction = instruction.replacingOccurrences(of: "Project Site", with: "the project site")
        }
        
        // Create navigation step
        currentNavStep = NavigationStep(
            instruction: instruction,
            distance: stepDistance,
            distanceValue: step.distance,
            isLastStep: currentStepIndex == steps.count - 1
        )
        
        print("InProgressManager: Set navigation step: \(instruction) (\(stepDistance))")
    }
    
    // Helper method to refresh route when needed
    func refreshRoute() {
        guard let route = activeRoute,
              let destination = route.polyline.getDestinationCoordinate() else {
            return
        }
        
        // Start a new routing request
        startRouting(to: destination)
    }
    
    /// Updates the current navigation step based on user location
    func updateNavigationStep(with userLocation: CLLocationCoordinate2D) {
        guard isRouting,
              let route = activeRoute,
              !route.steps.isEmpty else {
            return
        }
        
        // Get the valid steps
        let validSteps = route.steps.filter { !$0.instructions.isEmpty }
        guard !validSteps.isEmpty else { return }
        
        // Check if we should advance to the next step
        if currentStepIndex < validSteps.count - 1 {
            let currentStep = validSteps[currentStepIndex]
            let userLocationCL = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            
            // Get the end location of the current step
            if let endLocation = currentStep.polyline.getDestinationCoordinate() {
                let endLocationCL = CLLocation(latitude: endLocation.latitude, longitude: endLocation.longitude)
                
                // Calculate distance to the end of the current step
                let distance = userLocationCL.distance(from: endLocationCL)
                
                // If user is close to the end of the step, advance to the next step
                if distance < 50 { // 50 meters threshold
                    currentStepIndex += 1
                    setCurrentNavigationStep(for: validSteps)
                    print("InProgressManager: Advanced to step \(currentStepIndex)")
                }
            }
        }
        
        // Update distance for current step
        if currentStepIndex < validSteps.count {
            let currentStep = validSteps[currentStepIndex]
            if let stepCoordinate = currentStep.polyline.coordinate as CLLocationCoordinate2D? {
                let distanceToStep = userLocation.distance(to: stepCoordinate)
                
                // Update the current navigation step with live distance
                currentNavStep = NavigationStep(
                    instruction: currentStep.instructions,
                    distance: formatDistance(distanceToStep),
                    distanceValue: distanceToStep,
                    isLastStep: currentStepIndex == validSteps.count - 1
                )
            }
        }
    }
    
    // Helper to format distance
    private func formatDistance(_ distance: CLLocationDistance) -> String {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: distance)
    }
    
    func getRouteOverlay() -> MKOverlay? {
        return activeRoute?.polyline
    }
}

// String extension for empty check
fileprivate extension String {
    func nilIfEmpty() -> String? {
        return self.isEmpty ? nil : self
    }
}

// Struct to represent a navigation step for the UI
struct NavigationStep: Equatable {
    let instruction: String
    let distance: String
    let distanceValue: CLLocationDistance
    let isLastStep: Bool
    
    init(instruction: String, distance: String, distanceValue: CLLocationDistance, isLastStep: Bool) {
        self.instruction = instruction
        self.distance = distance
        self.distanceValue = distanceValue
        self.isLastStep = isLastStep
    }
}

// Extension for distance calculation
extension CLLocationCoordinate2D {
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let from = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let to = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return from.distance(from: to)
    }
}

// Extension to get coordinates from a polyline (for refreshing routes and map centering)
extension MKPolyline {
    // Using a different name to avoid conflict with MKAnnotation.coordinate
    func getDestinationCoordinate() -> CLLocationCoordinate2D? {
        guard pointCount > 0 else { return nil }
        
        // For MKPolyline, we can use the points() method which returns the pointer
        // and access the last point directly
        let lastPointIndex = pointCount - 1
        
        // Get coordinate for the last point
        // points() returns a pointer to all points in the polyline
        let lastPoint = self.points()[lastPointIndex]
        let coordinate = lastPoint.coordinate
        
        return coordinate
    }
    
    // Get all coordinates from the polyline
    func coordinates() -> [CLLocationCoordinate2D] {
        guard pointCount > 0 else { return [] }
        
        let points = self.points()
        var coordinates: [CLLocationCoordinate2D] = []
        
        for i in 0..<pointCount {
            let point = points[i]
            coordinates.append(point.coordinate)
        }
        
        return coordinates
    }
}