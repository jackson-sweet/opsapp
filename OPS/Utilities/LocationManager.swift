//
//  LocationManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


import CoreLocation
import SwiftUI

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var userLocation: CLLocationCoordinate2D?
    
    override init() {
        // Initialize with the current status
        self.authorizationStatus = locationManager.authorizationStatus
        
        super.init()
        
        // Configure manager
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
    }
    
    func requestPermissionIfNeeded() {
        // Only request if we're in the not determined state
        if authorizationStatus == .notDetermined {
            print("Requesting location permission")
            locationManager.requestWhenInUseAuthorization()
        } else {
            // If already determined, start updates if authorized
            if authorizationStatus == .authorizedWhenInUse ||
               authorizationStatus == .authorizedAlways {
                locationManager.startUpdatingLocation()
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            
            print("Location authorization changed to: \(self.authorizationStatus.rawValue)")
            
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                self.locationManager.startUpdatingLocation()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.userLocation = location.coordinate
        }
    }
}
