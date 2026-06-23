//
//  AppGroupConfig.swift
//  Shared between the OPS app and the OPSShareExtension.
//
//  Single source of truth for the App Group container identifiers, shared file
//  locations, the background-upload URLSession identifier, and the Darwin
//  notification name used to nudge a running app. Compiled into BOTH targets
//  (see the `Shared` synchronized group in project.pbxproj), so the app and the
//  extension agree byte-for-byte on where shared state lives.
//

import Foundation

/// Identifiers and on-disk locations for everything the share extension and the
/// main app exchange through the shared App Group container.
///
/// IMPORTANT: `identifier` must be registered as an App Group capability on BOTH
/// the app's App ID and the extension's App ID in the Apple Developer portal
/// (see the share-extension spec). Until that registration lands the entitlement
/// will fail to provision on device — but the code compiles and runs in the
/// simulator with `CODE_SIGNING_ALLOWED=NO`.
enum AppGroupConfig {

    /// The App Group both targets share. Mirrors the app's bundle prefix
    /// (`co.opsapp.ops`) so it sorts under the same App ID family in the portal.
    static let identifier = "group.co.opsapp.ops"

    /// Background `URLSession` identifier used by the extension to push image
    /// bytes to S3. The app re-creates a session with the SAME identifier so iOS
    /// hands completion events to the app when the extension is gone.
    static let backgroundSessionIdentifier = "co.opsapp.ops.OPS.ShareExtension.upload"

    /// Darwin notification posted by the extension after it enqueues work, so a
    /// foregrounded app can drain immediately instead of waiting for the next
    /// launch. Darwin notifications carry no payload — they are a pure "wake up".
    static let inboxUpdatedDarwinName = "co.opsapp.ops.shareinbox.updated"

    // MARK: - Container locations

    /// Root of the shared App Group container, or `nil` if the entitlement is
    /// not provisioned (e.g. before the portal step on a device build).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Directory holding the raw image bytes queued by the extension, awaiting
    /// upload by either the extension's background session or the app's drain.
    static var inboxDirectoryURL: URL? {
        containerURL?.appendingPathComponent("ShareInbox", isDirectory: true)
    }

    /// JSON file describing every queued/in-flight share upload (the manifest).
    static var manifestURL: URL? {
        containerURL?.appendingPathComponent("share-upload-manifest.json", isDirectory: false)
    }

    /// JSON file holding the session bridge the app writes for the extension.
    static var sessionBridgeURL: URL? {
        containerURL?.appendingPathComponent("share-session-bridge.json", isDirectory: false)
    }

    /// Ensures the inbox directory exists; returns it, or `nil` if the container
    /// is unavailable.
    @discardableResult
    static func ensureInboxDirectory() -> URL? {
        guard let dir = inboxDirectoryURL else { return nil }
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
