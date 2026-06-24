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

    /// App Shortcut requests are queued (persisted, with a timestamp) rather
    /// than presented directly: the intent's `perform()` can run before
    /// permissions hydrate / before `MainTabView` mounts (cold launch, PIN,
    /// onboarding). `MainTabView` drains this once the surface is ready and the
    /// gate passes, so the shortcut never silently no-ops or ambushes a locked
    /// screen.
    private let shortcutQueueKey = "ops.callCapture.pendingShortcut"

    /// A queued shortcut older than this is dropped (the operator's intent has
    /// gone stale). Wide enough to survive a cold launch + login/PIN before the
    /// surface is ready to present.
    nonisolated static let shortcutMaxAge: TimeInterval = 5 * 60

    private init() {}

    /// Present immediately. No-op when a request is already active so a stray
    /// second invocation can't be silently lost behind a live sheet.
    func present(_ request: CallCaptureRequest) {
        guard activeRequest == nil else { return }
        activeRequest = request
    }

    func dismiss() {
        activeRequest = nil
    }

    /// Queue an App Shortcut capture for the next ready moment.
    func queueShortcutCapture() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: shortcutQueueKey)
        print("[CALL_CAPTURE] App Shortcut queued")
    }

    /// Whether a fresh (un-expired) App Shortcut capture is waiting — peek WITHOUT
    /// consuming, so the drain pump knows to keep retrying until the surface is
    /// ready or the request expires.
    var hasQueuedShortcut: Bool {
        let ts = UserDefaults.standard.double(forKey: shortcutQueueKey)
        guard ts > 0 else { return false }
        return Date().timeIntervalSince1970 - ts <= Self.shortcutMaxAge
    }

    /// Consume a queued shortcut. Returns true only when one was queued AND is
    /// still fresh; always clears the queue.
    func consumeQueuedShortcut(now: Date = Date(), maxAge: TimeInterval = CallCaptureCoordinator.shortcutMaxAge) -> Bool {
        let ts = UserDefaults.standard.double(forKey: shortcutQueueKey)
        guard ts > 0 else { return false }
        UserDefaults.standard.removeObject(forKey: shortcutQueueKey)
        return now.timeIntervalSince1970 - ts <= maxAge
    }
}
