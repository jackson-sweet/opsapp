//
//  NavigationEngine.swift
//  OPS
//
//  Created by Claude on 2025-06-24.
//
//  Handles route calculation and navigation logic

import Foundation
import MapKit
import CoreLocation
import Combine

/// Navigation state representing current progress
enum NavigationState: Equatable {
    case idle
    case calculating
    case navigating
    case rerouting
    case arrived
    case error(Error)
    
    static func == (lhs: NavigationState, rhs: NavigationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.calculating, .calculating),
             (.navigating, .navigating),
             (.rerouting, .rerouting),
             (.arrived, .arrived):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return (lhsError as NSError) == (rhsError as NSError)
        default:
            return false
        }
    }
}

/// Navigation step information
struct MapNavigationStep {
    let instruction: String
    let distance: CLLocationDistance
    let coordinate: CLLocationCoordinate2D
}

@MainActor
final class NavigationEngine: ObservableObject {
    // MARK: - Published Properties
    
    @Published var navigationState: NavigationState = .idle
    @Published var currentRoute: MKRoute?
    @Published var alternativeRoutes: [MKRoute] = []
    @Published var currentStepIndex: Int = 0
    @Published var distanceToNextStep: CLLocationDistance = 0
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var estimatedArrivalTime: Date?
    
    // MARK: - Private Properties
    
    private var currentRequest: MKDirections.Request?
    private var navigationTimer: Timer?
    private var lastKnownLocation: CLLocation?
    
    // Rerouting logic
    private let rerouteThreshold: CLLocationDistance = 20 // meters - more responsive off-route detection
    private var isRerouting = false
    private var lastRerouteTime = Date()
    private let minRerouteInterval: TimeInterval = 2 // seconds - faster rerouting response
    
    // MARK: - Computed Properties
    
    var currentStep: MKRoute.Step? {
        guard let route = currentRoute,
              currentStepIndex < route.steps.count else { return nil }
        
        return route.steps[currentStepIndex]
    }
    
    var currentNavigationStep: MapNavigationStep? {
        guard let route = currentRoute,
              currentStepIndex < route.steps.count else { return nil }
        
        let step = route.steps[currentStepIndex]
        return MapNavigationStep(
            instruction: step.instructions,
            distance: step.distance,
            coordinate: step.polyline.coordinate
        )
    }
    
    var remainingSteps: [MapNavigationStep] {
        guard let route = currentRoute else { return [] }
        
        return route.steps.dropFirst(currentStepIndex).map { step in
            MapNavigationStep(
                instruction: step.instructions,
                distance: step.distance,
                coordinate: step.polyline.coordinate
            )
        }
    }
    
    var totalDistance: CLLocationDistance {
        currentRoute?.distance ?? 0
    }
    
    var totalTime: TimeInterval {
        currentRoute?.expectedTravelTime ?? 0
    }
    
    // MARK: - Public Methods
    
    /// Calculate route from origin to destination
    func calculateRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async throws {
        // Validate coordinates
        guard CLLocationCoordinate2DIsValid(origin) else {
            throw NavigationError.locationUnavailable
        }
        
        guard CLLocationCoordinate2DIsValid(destination) else {
            throw NavigationError.noDestination
        }
        
        navigationState = .calculating
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = true
        
        currentRequest = request
        
        do {
            let directions = MKDirections(request: request)
            let response = try await directions.calculate()
            
            DispatchQueue.main.async {
                self.handleRouteResponse(response)
            }
        } catch {
            DispatchQueue.main.async {
                self.navigationState = .error(error)
            }
            throw error
        }
    }
    
    /// Recalculate route (for refreshing or rerouting)
    func recalculateRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async throws {
        // Check if we should throttle rerouting
        let timeSinceLastReroute = Date().timeIntervalSince(lastRerouteTime)
        if timeSinceLastReroute < minRerouteInterval {
            return
        }
        
        isRerouting = true
        navigationState = .rerouting
        lastRerouteTime = Date()
        
        do {
            try await calculateRoute(from: origin, to: destination)
            isRerouting = false
            
            // Notify that rerouting completed
            navigationState = .navigating
        } catch {
            isRerouting = false
            throw error
        }
    }
    
    /// Start navigation tracking
    func startNavigation() {
        guard currentRoute != nil else { return }
        
        navigationState = .navigating
        currentStepIndex = 0
        
        // Start navigation timer for periodic updates
        navigationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateNavigationProgress()
        }
    }
    
    /// Stop navigation
    func stopNavigation() {
        navigationTimer?.invalidate()
        navigationTimer = nil
        navigationState = .idle
        currentRoute = nil
        alternativeRoutes = []
        currentStepIndex = 0
        lastKnownLocation = nil
    }
    
    /// Update user location during navigation
    func updateUserLocation(_ location: CLLocation) {
        lastKnownLocation = location
        
        guard navigationState == .navigating,
              let route = currentRoute else { return }
        
        // Check if user has arrived at destination
        let points = route.polyline.points()
        let lastPoint = points[route.polyline.pointCount - 1]
        let destination = CLLocation(latitude: lastPoint.coordinate.latitude, 
                                   longitude: lastPoint.coordinate.longitude)
        let distanceToDestination = location.distance(from: destination)
        
        // If within 30 meters of destination, mark as arrived
        if distanceToDestination < 30 {
            navigationState = .arrived
            
            // Post notification that user has arrived
            NotificationCenter.default.post(
                name: Notification.Name("UserArrivedAtDestination"),
                object: nil
            )
            return
        }
        
        // Check if user is on route
        if let distanceFromRoute = distanceFromRoute(location: location, route: route) {
            // Debug: Log distance from route
            // Only log when approaching threshold
            if distanceFromRoute > 15 { // Only log when getting far from route
            }
            
            if distanceFromRoute > rerouteThreshold && !isRerouting {
                // Check if enough time has passed since last reroute
                let timeSinceLastReroute = Date().timeIntervalSince(lastRerouteTime)
                if timeSinceLastReroute >= minRerouteInterval {
                    // User is off route, trigger rerouting
                    Task {
                        try? await recalculateRoute(from: location.coordinate, to: lastPoint.coordinate)
                    }
                }
            }
        }
        
        // Update current step based on location
        updateCurrentStep(for: location)
    }
    
    /// Select an alternative route
    func selectAlternativeRoute(at index: Int) {
        guard index < alternativeRoutes.count else { return }
        
        currentRoute = alternativeRoutes[index]
        currentStepIndex = 0
        
        // Recalculate progress for new route
        if let location = lastKnownLocation {
            updateCurrentStep(for: location)
        }
    }
    
    /// Restore navigation state from an existing route
    func restoreRoute(_ route: MKRoute) {
        currentRoute = route
        navigationState = .navigating
        currentStepIndex = 0
        
        // Update arrival time
        estimatedArrivalTime = Date().addingTimeInterval(route.expectedTravelTime)
        estimatedTimeRemaining = route.expectedTravelTime
        
        // Start navigation timer for periodic updates
        navigationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateNavigationProgress()
        }
    }
    
    // MARK: - Private Methods
    
    private func handleRouteResponse(_ response: MKDirections.Response) {
        guard !response.routes.isEmpty else {
            navigationState = .error(NavigationError.noRoutesFound)
            return
        }
        
        // Set primary route (usually the fastest)
        currentRoute = response.routes.first
        
        // Store alternatives
        alternativeRoutes = response.routes
        
        // Update arrival time
        if let route = currentRoute {
            estimatedArrivalTime = Date().addingTimeInterval(route.expectedTravelTime)
            estimatedTimeRemaining = route.expectedTravelTime
        }
        
        // Update state
        if navigationState == .rerouting {
            navigationState = .navigating
        } else {
            navigationState = .idle
        }
    }
    
    private func updateNavigationProgress() {
        guard let route = currentRoute,
              navigationState == .navigating else { return }
        
        // Update estimated time remaining
        let elapsedTime = Date().timeIntervalSince(lastRerouteTime)
        estimatedTimeRemaining = max(0, route.expectedTravelTime - elapsedTime)
        estimatedArrivalTime = Date().addingTimeInterval(estimatedTimeRemaining)
        
        // Check if arrived
        if let location = lastKnownLocation {
            let points = route.polyline.points()
            let lastPoint = points[route.polyline.pointCount - 1]
            let destinationCoordinate = lastPoint.coordinate
            let distanceToDestination = location.distance(from: CLLocation(
                latitude: destinationCoordinate.latitude,
                longitude: destinationCoordinate.longitude
            ))
            
            if distanceToDestination < 50 { // Within 50 meters
                navigationState = .arrived
                stopNavigation()
            }
        }
    }
    
    private func updateCurrentStep(for location: CLLocation) {
        guard let route = currentRoute,
              currentStepIndex < route.steps.count else { return }
        
        
        // Calculate distance to next step
        let currentStep = route.steps[currentStepIndex]
        let stepLocation = CLLocation(
            latitude: currentStep.polyline.coordinate.latitude,
            longitude: currentStep.polyline.coordinate.longitude
        )
        
        distanceToNextStep = location.distance(from: stepLocation)
        
        // Check if we should advance to next step
        if distanceToNextStep < 20 && currentStepIndex < route.steps.count - 1 {
            currentStepIndex += 1
            
            // Notify InProgressManager of step change
            NotificationCenter.default.post(
                name: Notification.Name("NavigationStepChanged"),
                object: nil,
                userInfo: ["stepIndex": currentStepIndex]
            )
        }
    }
    
    private func distanceFromRoute(location: CLLocation, route: MKRoute) -> CLLocationDistance? {
        // Calculate distance from point to route using point-to-line-segment distance
        var minDistance = CLLocationDistance.infinity
        let polyline = route.polyline
        let points = polyline.points()
        
        // Check distance to each line segment in the route
        for i in 0..<polyline.pointCount - 1 {
            let segmentStart = points[i].coordinate
            let segmentEnd = points[i + 1].coordinate
            
            // Calculate distance from user location to this line segment
            let distance = distanceFromPointToLineSegment(
                point: location.coordinate,
                lineStart: segmentStart,
                lineEnd: segmentEnd
            )
            
            minDistance = min(minDistance, distance)
            
            // Early exit if we're already on the route
            if minDistance < 5 { // Within 5 meters
                return minDistance
            }
        }
        
        return minDistance
    }
    
    /// Calculate the shortest distance from a point to a line segment
    private func distanceFromPointToLineSegment(
        point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        // Convert coordinates to points for calculation
        let p = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let a = CLLocation(latitude: lineStart.latitude, longitude: lineStart.longitude)
        let b = CLLocation(latitude: lineEnd.latitude, longitude: lineEnd.longitude)
        
        // Vector from a to b
        let ab = CLLocationCoordinate2D(
            latitude: b.coordinate.latitude - a.coordinate.latitude,
            longitude: b.coordinate.longitude - a.coordinate.longitude
        )
        
        // Vector from a to p
        let ap = CLLocationCoordinate2D(
            latitude: p.coordinate.latitude - a.coordinate.latitude,
            longitude: p.coordinate.longitude - a.coordinate.longitude
        )
        
        // Calculate the projection parameter t
        let abSquared = ab.latitude * ab.latitude + ab.longitude * ab.longitude
        
        // Handle degenerate case where start == end
        if abSquared == 0 {
            return p.distance(from: a)
        }
        
        let t = max(0, min(1, (ap.latitude * ab.latitude + ap.longitude * ab.longitude) / abSquared))
        
        // Find the closest point on the line segment
        let closestPoint = CLLocation(
            latitude: a.coordinate.latitude + t * ab.latitude,
            longitude: a.coordinate.longitude + t * ab.longitude
        )
        
        // Return distance from point to closest point on segment
        return p.distance(from: closestPoint)
    }
}

// MARK: - Navigation Errors

enum NavigationError: LocalizedError {
    case noDestination
    case noRoutesFound
    case calculationFailed
    case locationUnavailable
    
    var errorDescription: String? {
        switch self {
        case .noDestination:
            return "No destination selected"
        case .noRoutesFound:
            return "No routes found to destination"
        case .calculationFailed:
            return "Failed to calculate route"
        case .locationUnavailable:
            return "Current location unavailable"
        }
    }
}

