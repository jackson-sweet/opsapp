//
//  ShareDarwinNotifier.swift
//  Shared between the OPS app and the OPSShareExtension.
//
//  Cross-process "wake up" signal. The extension posts after it enqueues work
//  so a foregrounded app can drain the share inbox immediately instead of
//  waiting for the next launch/foreground. Darwin notifications carry no
//  payload and are delivered process-wide; the app registers an observer (see
//  ShareUploadCoordinator) and re-reads the manifest on receipt.
//

import Foundation

enum ShareDarwinNotifier {
    /// Posts the "share inbox updated" Darwin notification. Safe to call from the
    /// extension; a no-op if no app process is observing.
    static func post() {
        let name = CFNotificationName(AppGroupConfig.inboxUpdatedDarwinName as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name,
            nil,
            nil,
            true
        )
    }
}
