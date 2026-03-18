import SwiftUI

/// Animation constants for the tutorial.
/// Wraps OPSStyle.Animation with tutorial-specific timings.
enum TutorialAnimations {

    // MARK: - Curves (from OPSStyle)

    static let fast: Animation = OPSStyle.Animation.fast           // 0.2s
    static let standard: Animation = OPSStyle.Animation.standard   // 0.3s
    static let spring: Animation = OPSStyle.Animation.spring       // response 0.3, damping 0.7
    static let springFast: Animation = OPSStyle.Animation.springFast // response 0.2, damping 0.7

    // MARK: - Tutorial-Specific

    /// Delay between sequential item reveals (line items, task cards)
    static let staggerDelay: Double = 0.12

    /// Pause between steps (let the previous step breathe)
    static let stepPause: Double = 0.4

    /// Hold time on auto-advancing content before moving on
    static let holdDuration: Double = 1.2

    // MARK: - Accessibility

    static var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }
}
