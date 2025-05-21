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
    @Published var isLocationDenied: Bool = false
    @Published var deviceHeading: CLLocationDirection = 0.0
    
    override init() {
        // Initialize with the current status
        self.authorizationStatus = locationManager.authorizationStatus
        
        super.init()
        
        // Configure manager
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        
        // Enable heading updates for compass tracking
        if CLLocationManager.headingAvailable() {
            locationManager.headingFilter = 5.0 // Update every 5 degrees
        }
        
        // Set initial denied state
        self.isLocationDenied = (authorizationStatus == .denied || authorizationStatus == .restricted)
    }
    
    func requestPermissionIfNeeded(requestAlways: Bool = true) {
        // Log current authorization status
        print("LocationManager: Current authorization status: \(authorizationStatus.rawValue)")
        
        // Different approaches based on status
        switch authorizationStatus {
        case .notDetermined:
            // User hasn't made a decision yet
            print("LocationManager: Requesting location permission for the first time")
            if requestAlways {
                locationManager.requestAlwaysAuthorization()
            } else {
                locationManager.requestWhenInUseAuthorization()
            }
            
        case .denied, .restricted:
            // User has previously denied or is restricted - we should inform the app
            // but can't request again from here (needs UI prompt)
            print("LocationManager: Permission denied or restricted - need user to enable in Settings")
            
        case .authorizedWhenInUse:
            // If we have when-in-use but need always, request it
            if requestAlways {
                print("LocationManager: Upgrading from when-in-use to always authorization")
                locationManager.requestAlwaysAuthorization()
            }
            // Start location updates
            locationManager.startUpdatingLocation()
            
        case .authorizedAlways:
            // We have full permission - just start updates
            print("LocationManager: Already have always authorization")
            locationManager.startUpdatingLocation()
            
        @unknown default:
            // Handle any future authorization status
            print("LocationManager: Unknown authorization status: \(authorizationStatus.rawValue)")
            if requestAlways {
                locationManager.requestAlwaysAuthorization()
            } else {
                locationManager.requestWhenInUseAuthorization()
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            let newStatus = manager.authorizationStatus
            self.authorizationStatus = newStatus
            
            print("LocationManager: Authorization changed to: \(self.authorizationStatus.rawValue)")
            
            // Update denied status
            self.isLocationDenied = (newStatus == .denied || newStatus == .restricted)
            
            if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                // Start location updates when authorized
                self.locationManager.startUpdatingLocation()
                
                // Start heading updates if available
                if CLLocationManager.headingAvailable() {
                    self.locationManager.startUpdatingHeading()
                }
            } else if newStatus == .denied {
                print("LocationManager: Permission denied - user needs to enable in Settings")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.userLocation = location.coordinate
            // Post a notification that the location has changed
            NotificationCenter.default.post(name: .locationDidChange, object: nil)
            
            // Check if this is from significant location change monitoring
            if manager.monitoredRegions.isEmpty && !manager.location!.timestamp.timeIntervalSinceNow.isZero {
                // Post a notification for significant location change
                NotificationCenter.default.post(
                    name: .significantLocationChange,
                    object: nil,
                    userInfo: ["location": location]
                )
                print("LocationManager: Significant location change detected")
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
            print("LocationManager: Starting significant location change monitoring")
            locationManager.startMonitoringSignificantLocationChanges()
            
            // Also start heading updates for navigation
            if CLLocationManager.headingAvailable() {
                locationManager.startUpdatingHeading()
            }
        } else {
            print("LocationManager: Cannot start significant location monitoring - insufficient permissions")
            requestPermissionIfNeeded(requestAlways: true)
        }
    }
    
    /// Stops monitoring for significant location changes
    func stopMonitoringSignificantLocationChanges() {
        print("LocationManager: Stopping significant location change monitoring")
        locationManager.stopMonitoringSignificantLocationChanges()
        
        // Also stop heading updates
        locationManager.stopUpdatingHeading()
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
