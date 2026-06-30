//
//  DimensionedCaptureWorkflow.swift
//  OPS
//
//  Pure state decisions for the LiDAR dimensioned capture screen. Keep these
//  rules out of SwiftUI so field-critical affordances stay unit-testable.
//

import Foundation

enum DimensionedCaptureWorkflow {
    static func shutterEnabled(
        for state: LiDARCaptureCoordinator.CaptureState
    ) -> Bool {
        switch state {
        case .ready, .searching, .wallDetected, .openingLocked:
            return true
        case .idle, .warmingUp, .capturing, .captured, .failed:
            return false
        }
    }

    static func showsCenterReticle(
        for state: LiDARCaptureCoordinator.CaptureState
    ) -> Bool {
        switch state {
        case .ready, .searching, .wallDetected, .openingLocked, .capturing:
            return true
        case .idle, .warmingUp, .captured, .failed:
            return false
        }
    }

    static func showsLevelIndicator(
        for state: LiDARCaptureCoordinator.CaptureState,
        userEnabled: Bool
    ) -> Bool {
        guard userEnabled else { return false }
        switch state {
        case .openingLocked:
            return true
        case .idle, .warmingUp, .ready, .searching, .wallDetected, .capturing, .captured, .failed:
            return false
        }
    }
}
