//
//  KalmanHeadingFilter.swift
//  OPS
//
//  Kalman filter implementation for smooth heading tracking
//  Combines compass and gyroscope data for optimal heading estimation

import Foundation
import CoreMotion
import CoreLocation

/// Kalman filter for heading estimation using sensor fusion
class KalmanHeadingFilter {
    // MARK: - State Variables
    
    /// Current estimated heading (degrees)
    private var heading: Double = 0
    
    /// Current estimated angular velocity (degrees/second)
    private var angularVelocity: Double = 0
    
    /// Estimation error covariance matrix (2x2 simplified to 2 values)
    private var covarianceHeading: Double = 1.0
    private var covarianceVelocity: Double = 1.0
    
    // MARK: - Filter Parameters
    
    /// Process noise - how much we trust the model vs measurements
    private let processNoiseHeading: Double = 0.01
    private let processNoiseVelocity: Double = 0.1
    
    /// Measurement noise - how noisy we expect compass readings to be
    private let compassNoise: Double = 5.0 // degrees
    private let gyroNoise: Double = 0.5 // degrees/second
    
    /// Last update timestamp
    private var lastUpdateTime: TimeInterval = 0
    
    // MARK: - Public Methods
    
    /// Initialize filter with optional starting heading
    init(initialHeading: Double = 0) {
        self.heading = initialHeading
    }
    
    /// Update the filter with new sensor data
    /// - Parameters:
    ///   - compassHeading: Magnetometer heading (degrees)
    ///   - gyroZ: Gyroscope Z-axis rotation rate (radians/second)
    ///   - timestamp: Current timestamp
    /// - Returns: Filtered heading estimate (degrees)
    func update(compassHeading: Double?, gyroZ: Double?, timestamp: TimeInterval) -> Double {
        // Calculate time delta
        let dt = lastUpdateTime > 0 ? timestamp - lastUpdateTime : 0.016 // Default to 60Hz
        lastUpdateTime = timestamp
        
        // Prediction step using gyroscope
        if let gyroZ = gyroZ, dt > 0 {
            // Convert gyro from radians/sec to degrees/sec
            let gyroDegreesPerSec = gyroZ * 180.0 / .pi
            
            // Predict new heading
            heading += angularVelocity * dt
            angularVelocity = gyroDegreesPerSec // Update velocity estimate
            
            // Update covariance (uncertainty grows with prediction)
            covarianceHeading += dt * dt * covarianceVelocity + processNoiseHeading
            covarianceVelocity += processNoiseVelocity
        }
        
        // Correction step using compass
        if let compassHeading = compassHeading {
            // Calculate innovation (measurement residual)
            var innovation = compassHeading - heading
            
            // Handle angle wrapping
            if innovation > 180 {
                innovation -= 360
            } else if innovation < -180 {
                innovation += 360
            }
            
            // Calculate Kalman gain
            let innovationCovariance = covarianceHeading + compassNoise * compassNoise
            let kalmanGain = covarianceHeading / innovationCovariance
            
            // Update state estimate
            heading += kalmanGain * innovation
            
            // Update covariance
            covarianceHeading *= (1 - kalmanGain)
        }
        
        // Normalize heading to [0, 360)
        while heading < 0 {
            heading += 360
        }
        while heading >= 360 {
            heading -= 360
        }
        
        return heading
    }
    
    /// Get current angular velocity estimate
    var currentAngularVelocity: Double {
        return angularVelocity
    }
    
    /// Reset the filter
    func reset(heading: Double = 0) {
        self.heading = heading
        self.angularVelocity = 0
        self.covarianceHeading = 1.0
        self.covarianceVelocity = 1.0
        self.lastUpdateTime = 0
    }
    
    /// Get confidence level (0-1) in current estimate
    var confidence: Double {
        // Lower covariance means higher confidence
        let maxCovariance = 10.0
        return max(0, min(1, 1.0 - (covarianceHeading / maxCovariance)))
    }
}