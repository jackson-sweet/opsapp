//
//  OnboardingHaptics.swift
//  OPS
//
//  Haptic vocabulary for the rebuilt onboarding flow's shared components.
//
//  Mirrors the house pattern established by `Tutorial/Utilities/TutorialHaptics.swift`:
//  pre-prepared `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`
//  instances, one intentional call per meaningful interaction. Per the OPS field
//  haptics rule — light on arrivals/transitions, medium on commits/confirmations,
//  success notification on key moments. No haptic spam; each one is earned.
//

import UIKit

/// Haptic feedback for shared onboarding components. Each method is intentional.
enum OnboardingHaptics {

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()

    /// Warm up the generators so the first fire has no latency. Call from the
    /// screen's `onAppear` when an imminent interaction is expected.
    static func prepare() {
        light.prepare()
        medium.prepare()
        notification.prepare()
    }

    /// Light selection tick — toggles (password reveal), minor transitions.
    static func selection() {
        light.impactOccurred(intensity: 0.6)
        light.prepare()
    }

    /// Medium commit — primary CTA taps, advancing a step.
    static func commit() {
        medium.impactOccurred()
        medium.prepare()
    }

    /// Success notification — code copied, account created, joined a crew.
    static func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    /// Error notification — a lookup / check failed (no company found, fetch
    /// failed). Reserved for genuine failures the user must act on, never spammed.
    static func error() {
        notification.notificationOccurred(.error)
        notification.prepare()
    }
}
