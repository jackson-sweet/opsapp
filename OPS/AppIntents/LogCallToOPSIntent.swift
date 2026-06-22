//
//  LogCallToOPSIntent.swift
//  OPS
//
//  Around-call lead capture (iOS feature 154cb8a3). An App Intent + App
//  Shortcut so "Log a call to OPS" is one tap from Siri, Spotlight, the Action
//  Button (iPhone 15 Pro+), and Control Center — with NO setup, NO new
//  extension target, and NO special entitlement. The intent lives in the main
//  app target; `openAppWhenRun` brings OPS forward and `perform()` runs in-app,
//  routing through the shared capture coordinator into LogCallSheet.
//

import AppIntents
import Foundation

struct LogCallToOPSIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a call to OPS"
    static var description = IntentDescription(
        "Capture a phone call as a lead in OPS — attach it to an existing lead or start a new one."
    )

    /// Bring OPS to the foreground so the capture sheet can present.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Only meaningful when the pipeline is enabled for this operator. If
        // not, OPS still opens (so they see where they are); we present nothing.
        if PermissionStore.shared.isFeatureEnabled("pipeline"),
           PermissionStore.shared.can("pipeline.manage") {
            CallCaptureCoordinator.shared.present(.capture(.appShortcut))
        }
        return .result()
    }
}

struct OPSAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogCallToOPSIntent(),
            phrases: [
                "Log a call to \(.applicationName)",
                "Log a call in \(.applicationName)",
                "Log an \(.applicationName) call",
            ],
            shortTitle: "Log a Call",
            systemImageName: "phone.badge.plus"
        )
    }
}
