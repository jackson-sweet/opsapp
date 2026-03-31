//
//  AnalyticsSession.swift
//  OPS
//
//  Manages per-launch session IDs and screen duration tracking.
//

import Foundation
import UIKit

@MainActor
final class AnalyticsSession {

    static let shared = AnalyticsSession()

    /// Unique ID for this app session (regenerated each cold launch)
    let sessionId: UUID

    /// When this session started
    let sessionStart: Date

    /// Tracks per-screen appear times for duration_ms calculation
    private var screenAppearTimes: [String: Date] = [:]

    private init() {
        self.sessionId = UUID()
        self.sessionStart = Date()
    }

    /// Call when a screen appears. Records the timestamp.
    func screenDidAppear(_ screenName: String) {
        screenAppearTimes[screenName] = Date()
    }

    /// Call when a screen disappears. Returns duration in milliseconds, or nil if no matching appear.
    func screenDidDisappear(_ screenName: String) -> Int? {
        guard let appearTime = screenAppearTimes.removeValue(forKey: screenName) else {
            return nil
        }
        let durationMs = Int(Date().timeIntervalSince(appearTime) * 1000)
        // Ignore durations under 100ms (view lifecycle glitch) or over 30 min (user left app)
        guard durationMs >= 100 && durationMs <= 1_800_000 else {
            return nil
        }
        return durationMs
    }

    /// Total session duration in milliseconds
    var sessionDurationMs: Int {
        Int(Date().timeIntervalSince(sessionStart) * 1000)
    }

    /// Device model identifier (e.g. "iPhone16,1")
    var deviceType: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    /// OS version string (e.g. "iOS 18.3")
    var osVersion: String {
        "iOS \(UIDevice.current.systemVersion)"
    }

    /// App version string from bundle (e.g. "2.4.1")
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}
