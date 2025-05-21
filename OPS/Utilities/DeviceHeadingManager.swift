//
//  DeviceHeadingManager.swift
//  OPS
//
//  Created by Claude on 2025-05-20.
//

import Foundation
import CoreLocation
import Combine

/// Manages device heading (compass direction) for map navigation
class DeviceHeadingManager: NSObject, ObservableObject {
    @Published var currentHeading: CLLocationDirection = 0.0
    @Published var isHeadingAvailable: Bool = false
    
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Check if heading is available on this device
        if CLLocationManager.headingAvailable() {
            print("🧭 DeviceHeadingManager: Heading available, starting updates")
            locationManager.startUpdatingHeading()
            isHeadingAvailable = true
        } else {
            print("🧭 DeviceHeadingManager: Heading not available on this device")
            isHeadingAvailable = false
        }
    }
    
    func startHeadingUpdates() {
        guard CLLocationManager.headingAvailable() else {
            print("🧭 DeviceHeadingManager: Cannot start heading updates - not available")
            return
        }
        
        print("🧭 DeviceHeadingManager: Starting heading updates")
        locationManager.startUpdatingHeading()
    }
    
    func stopHeadingUpdates() {
        print("🧭 DeviceHeadingManager: Stopping heading updates")
        locationManager.stopUpdatingHeading()
    }
    
    deinit {
        stopHeadingUpdates()
    }
}

// MARK: - CLLocationManagerDelegate
extension DeviceHeadingManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Use magnetic heading for better accuracy in most situations
        // True heading would require location services and is more complex
        let heading = newHeading.magneticHeading
        
        // Only update if heading is valid (CLLocationManager returns -1 for invalid)
        if heading >= 0 {
            DispatchQueue.main.async {
                self.currentHeading = heading
                print("🧭 DeviceHeadingManager: Updated heading to \(Int(heading))°")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("🧭 DeviceHeadingManager: Failed with error: \(error.localizedDescription)")
    }
}