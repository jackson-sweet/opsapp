//
//  AppUpdateGate.swift
//  OPS
//
//  Single source of truth for the Update Gate. Orchestrates the anonymous
//  message fetch + the App Store version lookup, runs the pure AppMessageGate
//  evaluator, and publishes the resolved blocking / dismissable messages.
//
//  Rendering:
//   - `blockingMessage` is rendered at the app ROOT (OPSApp), over everything
//     and BEFORE sign-in, so a force-update reaches users even when a blocker
//     bug breaks login/sync.
//   - `dismissableMessage` is rendered as a post-auth overlay (PINGatedView),
//     where the user's role is known for role-targeted announcements.
//
//  Fail-open by construction: every fetch returns empty/nil on error, so a
//  backend outage or offline device never blocks the app.
//

import Foundation
import SwiftUI

@MainActor
final class AppUpdateGate: ObservableObject {

    @Published private(set) var blockingMessage: AppMessageDTO?
    @Published private(set) var dismissableMessage: AppMessageDTO?

    private let messageService = AppMessageService()
    private let storeService = AppStoreVersionService()

    /// Messages the user dismissed this session — not shown again until relaunch.
    private var dismissedIDs: Set<String> = []
    /// Throttle for foreground re-checks (cold launch / role change force through).
    private var lastNetworkCheck: Date = .distantPast
    private var isChecking = false

    private var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Fetches + evaluates. `force` bypasses the throttle (use on cold launch and
    /// right after sign-in so role-targeted messages resolve); foreground
    /// re-checks pass `force == false` and are rate-limited.
    func refresh(userRole: UserRole?, force: Bool) async {
        let now = Date()
        if !force, now.timeIntervalSince(lastNetworkCheck) < Self.minCheckInterval { return }
        if isChecking { return }
        isChecking = true
        defer { isChecking = false }
        lastNetworkCheck = now

        async let messagesTask = messageService.fetchActiveMessages()
        async let storeTask = storeService.fetchLatest()
        let messages = await messagesTask
        let store = await storeTask

        let resolution = AppMessageGate.resolve(
            messages: messages,
            installedVersion: installedVersion,
            platform: "ios",
            now: now,
            userRole: userRole,
            storeVersion: store?.version,
            appStoreURL: store?.appStoreURL
        )

        blockingMessage = resolution.blocking
        if let candidate = resolution.dismissable, !dismissedIDs.contains(candidate.id) {
            dismissableMessage = candidate
        } else {
            dismissableMessage = nil
        }
    }

    /// Records a dismissal so the overlay does not reappear this session.
    func dismiss(_ message: AppMessageDTO) {
        dismissedIDs.insert(message.id)
        if dismissableMessage?.id == message.id {
            dismissableMessage = nil
        }
    }

    private static let minCheckInterval: TimeInterval = 60
}
