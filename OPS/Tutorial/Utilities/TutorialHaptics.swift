import UIKit

/// Haptic feedback for the tutorial. Each method is intentional.
/// Light = arrivals. Medium = commits. Success = milestones.
enum TutorialHaptics {

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() {
        light.prepare()
        medium.prepare()
        notification.prepare()
    }

    /// Card arrivals, step transitions, subtle confirmations
    static func arrival() {
        light.impactOccurred()
        light.prepare()
    }

    /// Swipe commits, button taps, sends
    static func commit() {
        medium.impactOccurred()
        medium.prepare()
    }

    /// Estimate approved, invoice paid, all caught up
    static func milestone() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    /// Ultra-light tap for rapid-fire strikethrough sequence (intensity 0.3)
    static func strikethrough() {
        light.impactOccurred(intensity: 0.3)
        light.prepare()
    }

    // MARK: - Compat (old tutorial code in real views still calls these)

    static func lightTap() { arrival() }
    static func success() { milestone() }
    static func error() { /* no-op */ }
}
