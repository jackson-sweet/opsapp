//
//  LocationManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


import CoreLocation
import SwiftUI

// Extension for location notification name
extension Notification.Name {
    static let locationDidChange = Notification.Name("locationDidChange")
    static let significantLocationChange = Notification.Name("significantLocationChange")
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var currentLocation: CLLocation?  // Full location with course data
    @Published var isLocationDenied: Bool = false
    @Published var deviceHeading: CLLocationDirection = 0.0
    @Published var userCourse: CLLocationDirection = -1.0  // GPS course when moving
    
    // Track if updates are already started to prevent multiple calls
    private var isUpdatingLocation = false
    private var isUpdatingHeading = false
    
    // Public property to check if location updates are active
    var isLocationUpdatesActive: Bool {
        return isUpdatingLocation
    }
    
    // Track if permission has been requested this session
    private var hasRequestedPermissionThisSession = false
    
    // Computed property for easy access to the latest location
    var location: CLLocation? {
        return currentLocation ?? locationManager.location
    }
    
    override init() {
        // Initialize with the current status
        self.authorizationStatus = locationManager.authorizationStatus
        
        super.init()
        
        // Configure manager with optimized settings to prevent excessive API calls
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters  // Good accuracy without excessive updates
        locationManager.distanceFilter = 10  // Update every 10 meters to reduce API calls
        locationManager.activityType = .automotiveNavigation  // Optimize for driving
        locationManager.pausesLocationUpdatesAutomatically = true  // Allow iOS to optimize battery/performance
        
        // Enable heading updates with reasonable filter
        if CLLocationManager.headingAvailable() {
            locationManager.headingFilter = 5.0 // Only update for 5+ degree changes
        }
        
        // Set initial denied state
        self.isLocationDenied = (authorizationStatus == .denied || authorizationStatus == .restricted)
    }
    
    func requestPermissionIfNeeded(requestAlways: Bool = true, completion: ((Bool) -> Void)? = nil) {
        // Skip if already requested this session and we have permission
        if hasRequestedPermissionThisSession && hasSufficientPermission() {
            completion?(true)
            return
        }
        
        // Mark that we've requested permission this session
        hasRequestedPermissionThisSession = true
        
        // Different approaches based on status
        switch authorizationStatus {
        case .notDetermined:
            // User hasn't made a decision yet
            if requestAlways {
                locationManager.requestAlwaysAuthorization()
            } else {
                locationManager.requestWhenInUseAuthorization()
            }
            // Permission result will come through delegate callback
            completion?(true)
            
        case .denied, .restricted:
            // User has previously denied or is restricted - we should inform the app
            // but can't request again from here (needs UI prompt)
            // Call completion with false to indicate permission is denied
            completion?(false)
            
        case .authorizedWhenInUse:
            // If we have when-in-use but need always, request it
            if requestAlways {
                locationManager.requestAlwaysAuthorization()
            }
            // Start location updates only if not already updating
            if !isUpdatingLocation {
                locationManager.startUpdatingLocation()
                isUpdatingLocation = true
            }
            completion?(true)
            
        case .authorizedAlways:
            // We have full permission - just start updates only if not already updating
            if !isUpdatingLocation {
                locationManager.startUpdatingLocation()
                isUpdatingLocation = true
            }
            completion?(true)
            
        @unknown default:
            // Handle any future authorization status
            if requestAlways {
                locationManager.requestAlwaysAuthorization()
            } else {
                locationManager.requestWhenInUseAuthorization()
            }
            completion?(true)
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            let newStatus = manager.authorizationStatus
            self.authorizationStatus = newStatus
            
            
            // Update denied status
            self.isLocationDenied = (newStatus == .denied || newStatus == .restricted)
            
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                // Start location updates when authorized only if not already updating
                if !self.isUpdatingLocation {
                    self.locationManager.startUpdatingLocation()
                    self.isUpdatingLocation = true
                }
                
                // Start heading updates if available and not already updating
                if CLLocationManager.headingAvailable() && !self.isUpdatingHeading {
                    self.locationManager.startUpdatingHeading()
                    self.isUpdatingHeading = true
                }
            } else if newStatus == .denied {
                // Stop updates if denied
                self.isUpdatingLocation = false
                self.isUpdatingHeading = false
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            // Update coordinate for compatibility
            self.userLocation = location.coordinate
            
            // Store full location for course data
            self.currentLocation = location
            
            // Update course if valid (course is -1 when invalid)
            if location.course >= 0 {
                self.userCourse = location.course
            }
            
            // Post a notification that the location has changed
            NotificationCenter.default.post(name: .locationDidChange, object: nil, 
                                          userInfo: ["location": location])
            
            // Check if this is from significant location change monitoring
            if manager.monitoredRegions.isEmpty && !manager.location!.timestamp.timeIntervalSinceNow.isZero {
                // Post a notification for significant location change
                NotificationCenter.default.post(
                    name: .significantLocationChange,
                    object: nil,
                    userInfo: ["location": location]
                )
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            // Use true heading if available, otherwise magnetic heading
            let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            self.deviceHeading = heading
            
            // Post notification for heading updates during navigation
            NotificationCenter.default.post(
                name: .init("headingDidChange"),
                object: nil,
                userInfo: ["heading": heading]
            )
        }
    }
    
    // MARK: - Helper Methods
    
    /// Determines if the app has sufficient permission to use location features
    func hasSufficientPermission() -> Bool {
        return authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }
    
    /// Opens the app settings where user can enable location permissions
    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    /// Starts monitoring for significant location changes
    /// This uses much less battery than standard location updates
    func startMonitoringSignificantLocationChanges() {
        if hasSufficientPermission() {
            locationManager.startMonitoringSignificantLocationChanges()
            
            // Also start heading updates for navigation if not already updating
            if CLLocationManager.headingAvailable() && !isUpdatingHeading {
                locationManager.startUpdatingHeading()
                isUpdatingHeading = true
            }
        } else {
            requestPermissionIfNeeded(requestAlways: true)
        }
    }
    
    /// Stops monitoring for significant location changes
    func stopMonitoringSignificantLocationChanges() {
        locationManager.stopMonitoringSignificantLocationChanges()
        
        // Also stop heading updates
        locationManager.stopUpdatingHeading()
        isUpdatingHeading = false
    }
    
    /// Stop all location updates
    func stopLocationUpdates() {
        if isUpdatingLocation {
            locationManager.stopUpdatingLocation()
            isUpdatingLocation = false
        }
        if isUpdatingHeading {
            locationManager.stopUpdatingHeading()
            isUpdatingHeading = false
        }
    }
    
    /// Enable high accuracy mode for navigation
    func enableNavigationMode() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5  // More frequent updates during navigation
        locationManager.headingFilter = 3.0 // More responsive heading during navigation
        
        // Restart updates if already running to apply new settings
        if isUpdatingLocation {
            locationManager.stopUpdatingLocation()
            locationManager.startUpdatingLocation()
        }
    }
    
    /// Return to normal accuracy mode
    func disableNavigationMode() {
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 10
        locationManager.headingFilter = 5.0
        
        // Restart updates if already running to apply new settings
        if isUpdatingLocation {
            locationManager.stopUpdatingLocation()
            locationManager.startUpdatingLocation()
        }
    }
}

// MARK: - Location Permission Alert
extension View {
    /// Presents an alert when location permission is needed but denied
    func locationPermissionAlert(isPresented: Binding<Bool>, openSettings: @escaping () -> Void) -> some View {
        alert(
            "Location Access Required",
            isPresented: isPresented,
            actions: {
                Button("Open Settings", action: openSettings)
                Button("Cancel", role: .cancel) {}
            },
            message: {
                Text("This app requires location access to help you navigate to projects and track your work. Please enable location access in Settings.")
            }
        )
    }
}
