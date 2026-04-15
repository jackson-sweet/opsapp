//
//  SpotlightBackfillCoordinator.swift
//  OPS
//
//  Runs the initial Spotlight backfill with a live-updating local notification.
//  Called once after login when SpotlightIndexManager.hasCompletedInitialBackfill == false.
//  Uses UIApplication.beginBackgroundTask to keep indexing alive if the user backgrounds
//  the app mid-run.
//

import Foundation
import UIKit
import UserNotifications
import SwiftData

@MainActor
final class SpotlightBackfillCoordinator {
    static let shared = SpotlightBackfillCoordinator()

    private let notificationId = "spotlight-backfill-progress"
    private let completionNotificationId = "spotlight-backfill-complete"
    private var isRunning = false

    private init() {}

    func runIfNeeded(context: ModelContext) async {
        guard !isRunning else { return }
        guard !SpotlightIndexManager.shared.hasCompletedInitialBackfill else { return }
        isRunning = true
        defer { isRunning = false }

        // Request a background task so indexing can continue if the user backgrounds the app.
        // On expiration we simply let the current pass finish — the completion flag is only
        // set at the end of backfill, so a partial run will resume on next launch.
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "spotlight-backfill") {
            // Expiration handler — nothing to clean up; indexing is resumable on next launch
            print("[SpotlightBackfill] Background task expired")
        }
        defer {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }

        let granted = await requestNotificationPermission()
        if granted {
            await postProgressNotification(title: "Indexing your OPS data…", body: "Preparing search")
        }

        await SpotlightIndexManager.shared.backfill(context: context) { progress, currentPhase in
            Task { @MainActor in
                let pct = Int(progress * 100)
                await self.updateProgressNotification(
                    title: "Indexing your OPS data…",
                    body: "\(currentPhase) • \(pct)%"
                )
            }
        }

        if granted {
            await postCompletionNotification()
        }
    }

    // MARK: - Notification Helpers

    private func requestNotificationPermission() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false  // Indexing still runs, just silently
        case .notDetermined:
            do {
                return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    private func postProgressNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.interruptionLevel = .passive

        let req = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: nil // deliver immediately
        )
        try? await UNUserNotificationCenter.current().add(req)
    }

    private func updateProgressNotification(title: String, body: String) async {
        // Replace existing notification by removing + re-adding with same id
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationId])
        await postProgressNotification(title: title, body: body)
    }

    private func postCompletionNotification() async {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationId])

        let content = UNMutableNotificationContent()
        content.title = "Search ready"
        content.body = "Your OPS data is now searchable from iPhone Spotlight."
        content.sound = nil
        content.interruptionLevel = .passive

        let req = UNNotificationRequest(
            identifier: completionNotificationId,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(req)
    }
}
