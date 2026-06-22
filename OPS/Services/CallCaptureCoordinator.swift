//
//  CallCaptureCoordinator.swift
//  OPS
//
//  Around-call lead capture (iOS feature 154cb8a3). Single presentation bus for
//  the LogCallSheet so all three entry points — the post-call prompt, the FAB
//  "Log a call" item, and the Siri / Action-Button App Shortcut — funnel into
//  ONE host (`MainTabView`). A singleton because the App Shortcut's AppIntent
//  runs outside any SwiftUI view and has no AppState to reach.
//

import Foundation
import Combine

/// Where a call-capture was initiated. Persisted to `activities.call_source`.
enum CallCaptureSource: String {
    case postCallPrompt = "post_call_prompt" // returned to OPS after an in-app call
    case fab            = "fab"              // FAB → "Log a call"
    case appShortcut    = "app_shortcut"     // Siri / Action Button / Spotlight
}

/// What kind of capture to open. Identifiable so it can drive `.sheet(item:)`.
enum CallCaptureRequest: Identifiable, Equatable {
    /// Operator returned to OPS after calling a known lead — pre-fill to it.
    case postCall(PendingOutboundCall)
    /// Fresh capture with no lead yet (FAB / App Shortcut).
    case capture(CallCaptureSource)

    var id: String {
        switch self {
        case .postCall(let p):
            return "postCall-\(p.opportunityId ?? p.phoneNumber)-\(Int(p.startedAt.timeIntervalSince1970))"
        case .capture(let source):
            return "capture-\(source.rawValue)"
        }
    }
}

@MainActor
final class CallCaptureCoordinator: ObservableObject {
    static let shared = CallCaptureCoordinator()

    /// The active request `MainTabView` mirrors as a sheet. Setting it presents
    /// the capture sheet; the sheet clears it on dismiss.
    @Published var activeRequest: CallCaptureRequest?

    private init() {}

    func present(_ request: CallCaptureRequest) {
        activeRequest = request
    }

    func dismiss() {
        activeRequest = nil
    }
}
