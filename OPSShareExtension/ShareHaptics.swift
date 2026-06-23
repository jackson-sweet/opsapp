//
//  ShareHaptics.swift
//  OPSShareExtension
//
//  Minimal haptics for the share flow. The extension can't import the app's
//  OnboardingHaptics, so it carries its own thin wrapper with the same OPS
//  intent: light on selection, medium on commit, success on the win. No spam.
//

import UIKit

enum ShareHaptics {
    /// Light tick — selecting a project.
    static func selection() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    /// Medium — committing the add.
    static func commit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    /// Success — photos captured.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
