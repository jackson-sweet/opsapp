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
        if motion == .motionShake && isKeyWindow {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}
