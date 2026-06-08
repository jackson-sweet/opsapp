//
//  ShakeDetection.swift
//  OPS
//
//  Global shake detection for bug reporting.
//

import UIKit

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        // No `isKeyWindow` gate: when the keyboard is up a text-effects /
        // keyboard window becomes key, so gating on it dropped the shake while
        // editing. Posting unconditionally is safe — `handleShake` debounces
        // and the BugReportPresenter.isPresenting guard collapses any duplicate
        // posts from multiple windows into a single presentation.
        NotificationCenter.default.post(name: .deviceDidShake, object: nil)
    }
}
