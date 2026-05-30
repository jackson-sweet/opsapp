//
//  Animation+Accessible.swift
//  OPS
//
import SwiftUI

extension Animation {
    /// Returns the animation unless Reduce Motion is enabled, in which case returns nil (instant).
    static func accessibleEaseInOut(duration: Double = 0.25) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : OPSStyle.Animation.smooth
    }
}
