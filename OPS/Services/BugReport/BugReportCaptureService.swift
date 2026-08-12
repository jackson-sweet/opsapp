//
//  BugReportCaptureService.swift
//  OPS
//
//  Continuously captures app context for bug reports:
//  breadcrumbs, network calls, state snapshots, and screenshots.
//

import UIKit
import SwiftUI

// MARK: - Breadcrumb

struct Breadcrumb: Codable {
    let timestamp: String
    let type: String      // "screenView", "tap", "sheetOpen", "sheetClose", "navigation", "custom"
    let label: String
    let metadata: [String: String]?

    init(type: String, label: String, metadata: [String: String]? = nil) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestamp = formatter.string(from: Date())
        self.type = type
        self.label = label
        self.metadata = metadata
    }

    var asDictionary: [String: Any] {
        var dict: [String: Any] = [
            "timestamp": timestamp,
            "type": type,
            "label": label
        ]
        if let metadata = metadata {
            dict["metadata"] = metadata
        }
        return dict
    }
}

// MARK: - Network Log Entry

struct NetworkLogEntry: Codable {
    let timestamp: String
    let method: String
    let url: String
    let statusCode: Int
    let durationMs: Int
    let error: String?

    init(method: String, url: String, statusCode: Int, durationMs: Int, error: String? = nil) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestamp = formatter.string(from: Date())
        self.method = method
        self.url = url
        self.statusCode = statusCode
        self.durationMs = durationMs
        self.error = error
    }

    var asDictionary: [String: Any] {
        var dict: [String: Any] = [
            "timestamp": timestamp,
            "method": method,
            "url": url,
            "statusCode": statusCode,
            "durationMs": durationMs
        ]
        if let error = error {
            dict["error"] = error
        }
        return dict
    }
}

// MARK: - Capture Service

@MainActor
final class BugReportCaptureService {
    static let shared = BugReportCaptureService()

    // MARK: - State

    /// Current screen name, updated by .trackScreen() modifier
    private(set) var currentScreenName: String = "Unknown"

    /// Rolling breadcrumb buffer
    private var breadcrumbs: [Breadcrumb] = []
    private let breadcrumbCapacity = 50

    /// Rolling network log buffer
    private var networkLog: [NetworkLogEntry] = []
    private let networkLogCapacity = 30

    private init() {}

    // MARK: - Screen Tracking

    func updateScreen(_ name: String) {
        let previous = currentScreenName
        currentScreenName = name
        if previous != name {
            addBreadcrumb(type: "screenView", label: name)
        }
    }

    // MARK: - Breadcrumbs

    func addBreadcrumb(type: String, label: String, metadata: [String: String]? = nil) {
        let crumb = Breadcrumb(type: type, label: label, metadata: metadata)
        breadcrumbs.append(crumb)
        if breadcrumbs.count > breadcrumbCapacity {
            breadcrumbs.removeFirst(breadcrumbs.count - breadcrumbCapacity)
        }
    }

    func getBreadcrumbSnapshot() -> [[String: Any]] {
        breadcrumbs.map { $0.asDictionary }
    }

    // MARK: - Network Logging

    func logNetworkCall(
        method: String,
        url: String,
        statusCode: Int,
        durationMs: Int,
        error: String? = nil
    ) {
        let entry = NetworkLogEntry(
            method: method,
            url: url,
            statusCode: statusCode,
            durationMs: durationMs,
            error: error
        )
        networkLog.append(entry)
        if networkLog.count > networkLogCapacity {
            networkLog.removeFirst(networkLog.count - networkLogCapacity)
        }

        // Also log errors to DebugLogger so they appear in console buffer
        if statusCode >= 400 || error != nil {
            DebugLogger.shared.log(
                "\(method) \(url) → \(statusCode) (\(durationMs)ms)\(error.map { " Error: \($0)" } ?? "")",
                level: .error,
                category: "Network"
            )
        }
    }

    func getNetworkLogSnapshot() -> [[String: Any]] {
        networkLog.map { $0.asDictionary }
    }

    // MARK: - State Snapshot

    /// Capture current app state from available sources.
    /// Called at shake-time, not continuously.
    func captureStateSnapshot(
        appState: AppState,
        dataController: DataController
    ) -> [String: Any] {
        var snapshot: [String: Any] = [
            "currentScreen": currentScreenName,
            "activeProjectID": appState.activeProjectID ?? "none",
            "activeTaskID": appState.activeTaskID ?? "none",
            "isInProjectMode": appState.isInProjectMode,
            "isViewingDetailsOnly": appState.isViewingDetailsOnly
        ]

        // User info (non-sensitive)
        if let user = dataController.currentUser {
            snapshot["userRole"] = user.userType ?? "unknown"
            snapshot["companyId"] = user.companyId ?? "none"
        }

        // Connectivity
        if let connectivity = dataController.connectivity {
            snapshot["isConnected"] = connectivity.shouldAttemptSync
            snapshot["connectionQuality"] = "\(connectivity.state.quality)"
        }

        // Sync state
        snapshot["pendingSyncCount"] = dataController.pendingSyncCount

        // Authentication state
        snapshot["isAuthenticated"] = dataController.isAuthenticated

        return snapshot
    }

    // MARK: - Screenshot Capture

    /// Capture the current screen as a UIImage
    func captureScreenshot() -> UIImage? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            DebugLogger.shared.log("Failed to find window scene for screenshot", level: .error, category: "BugReport")
            return nil
        }

        // Capture the app's primary window — the `.normal`-level window that
        // hosts app content (including any presented sheet). This deliberately
        // excludes keyboard / text-effects windows (which become key while
        // editing) and the bug-report overlay window (which sits above
        // `.normal`), so a shake with the keyboard up still grabs the real
        // screen instead of an empty system window.
        let appWindows = windowScene.windows.filter { !$0.isHidden && $0.windowLevel == .normal }
        guard let window = appWindows.first(where: { $0.isKeyWindow }) ?? appWindows.first else {
            DebugLogger.shared.log("Failed to find app window for screenshot", level: .error, category: "BugReport")
            return nil
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return image
    }

    // MARK: - Device Info

    /// Collect device info for the bug report
    func captureDeviceInfo() -> [String: Any] {
        let device = UIDevice.current
        var info: [String: Any] = [
            "osName": "iOS",
            "osVersion": device.systemVersion,
            "deviceModel": deviceModelIdentifier(),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "buildNumber": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        ]

        // Battery (enable monitoring, read, then disable to avoid battery drain)
        device.isBatteryMonitoringEnabled = true
        info["batteryLevel"] = device.batteryLevel >= 0 ? device.batteryLevel : -1
        device.isBatteryMonitoringEnabled = false

        // Disk space
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSpace = attrs[.systemFreeSize] as? Int64 {
            info["freeDiskMb"] = Double(freeSpace) / (1024 * 1024)
        }

        // RAM
        info["freeRamMb"] = Double(os_proc_available_memory()) / (1024 * 1024)

        // Network type
        info["networkType"] = currentNetworkType()

        return info
    }

    // MARK: - Helpers

    private func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }

    private func currentNetworkType() -> String {
        // Use ConnectivityMonitor if available through DataController
        // Fall back to basic check
        return "unknown" // Will be populated from ConnectivityMonitor in submission
    }
}

// MARK: - Screen Tracking Modifier

/// Claims the "current screen" a filed bug report is stamped with.
///
/// This is mount-based on six tab roots, and MainTabView keeps every visited
/// tab mounted — so `onAppear` alone fires once per tab, for the whole session,
/// and a bug filed after two tab switches would carry whichever screen the
/// operator happened to open first. The foreground re-fire is worse: with six
/// roots alive it runs from all of them on every return to foreground, and the
/// last writer wins nondeterministically — quite possibly a parked tab.
///
/// The claim therefore follows `\.isActiveTab`: a tab takes the breadcrumb when
/// it comes on screen and never while parked. The key defaults to true, so
/// pushed screens, sheets and every non-tab surface using `trackScreen` behave
/// exactly as they did.
///
/// Known residual: a pushed screen and its tab root both track, and on
/// re-activation both fire with no ordering contract between them, so the
/// deeper screen is not guaranteed to win. That is inherent to a per-view
/// breadcrumb and is strictly better than the wrong tab winning.
struct ScreenTrackingModifier: ViewModifier {
    let screenName: String
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isActiveTab) private var isActiveTab

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Mount and activation coincide on a tab's first visit.
                guard isActiveTab else { return }
                BugReportCaptureService.shared.updateScreen(screenName)
            }
            .onChange(of: isActiveTab) { _, active in
                guard active else { return }
                BugReportCaptureService.shared.updateScreen(screenName)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, isActiveTab else { return }
                BugReportCaptureService.shared.updateScreen(screenName)
            }
    }
}

extension View {
    /// Track this view as the current screen for bug reporting
    func trackScreen(_ name: String) -> some View {
        self.modifier(ScreenTrackingModifier(screenName: name))
    }
}

// MARK: - Breadcrumb Tap Modifier

struct BreadcrumbTapModifier: ViewModifier {
    let label: String

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded {
                BugReportCaptureService.shared.addBreadcrumb(type: "tap", label: label)
            }
        )
    }
}

extension View {
    /// Record a breadcrumb when this view is tapped
    func breadcrumb(_ label: String) -> some View {
        self.modifier(BreadcrumbTapModifier(label: label))
    }
}
