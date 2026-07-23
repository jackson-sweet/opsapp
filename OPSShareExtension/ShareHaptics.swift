//
//  ShareHaptics.swift
//  OPSShareExtension
//
//  Minimal haptics for the share flow. The extension can't import the app's
//  OnboardingHaptics, so it carries its own thin wrapper with the same OPS
//  intent: light on selection, medium on commit, one notification at the final
//  durable outcome. No spam.
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
    /// Failure — nothing was durably queued, so the operator must retry.
    static func failure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
