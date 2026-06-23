//
//  ShareSessionBridge.swift
//  Shared between the OPS app and the OPSShareExtension.
//
//  The "session bridge" is the snapshot the main app writes into the App Group
//  container so the share extension can operate WITHOUT running Firebase, the
//  Supabase SDK, or SwiftData. The extension reads it to know who is signed in,
//  which projects it may attach photos to, and (for the instant-upload path) a
//  short-lived Firebase ID token to presign S3 uploads.
//
//  Security note: the ID token here is the SAME short-lived bearer token the app
//  already sends on every API request (~1h lifetime, never refreshed by the
//  extension). It is confined to the sandboxed App Group container shared only
//  by the OPS app and this extension. The app rewrites it on login and on every
//  foreground; on logout the bridge is cleared.
//

import Foundation

/// A lightweight reference to a project the signed-in user may attach photos to.
/// Mirrors only what the picker needs — never the full SwiftData model (which the
/// extension cannot see).
struct ShareProjectRef: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    /// Client / company name for the picker subtitle and search. `nil` when the
    /// project has no client.
    let clientName: String?
}

/// Snapshot of the signed-in session the app publishes for the share extension.
struct ShareSessionBridge: Codable {
    /// Canonical `users.id` UUID (NOT the Firebase uid). Stamped on uploads as
    /// `uploaded_by`.
    let userId: String
    let companyId: String
    /// Short-lived Firebase ID token used to presign S3 uploads from the
    /// extension. Empty when unavailable (extension then falls back to the
    /// app-drains-later path).
    let idToken: String
    /// Absolute expiry of `idToken`.
    let tokenExpiresAt: Date
    /// Whether the user holds `projects.edit` — the same gate that guards every
    /// project-level write in OPS. When false the extension shows a no-permission
    /// state and offers no projects.
    let canEditProjects: Bool
    /// Display name for the uploader, used in the completion copy when the app
    /// finalizes from a background launch and the roster is not yet loaded.
    let userDisplayName: String?
    /// Projects the user may attach photos to, already filtered by the app.
    let editableProjects: [ShareProjectRef]
    /// When this snapshot was written.
    let updatedAt: Date

    /// True when there is a usable signed-in session.
    var hasSession: Bool {
        !userId.isEmpty && !companyId.isEmpty
    }

    /// True when `idToken` is present and has comfortable life left. A 2-minute
    /// skew avoids starting an upload with a token that dies mid-flight; if false
    /// the extension enqueues for the app to presign on next drain.
    var isTokenUsable: Bool {
        !idToken.isEmpty && tokenExpiresAt.timeIntervalSinceNow > 120
    }
}

/// Cross-process reader/writer for the session bridge JSON in the App Group
/// container. Uses `NSFileCoordinator` so the app's writes and the extension's
/// reads never tear.
enum ShareSessionBridgeStore {

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Reads the current bridge, or `nil` if none is written / container missing /
    /// decode fails.
    static func read() -> ShareSessionBridge? {
        guard let url = AppGroupConfig.sessionBridgeURL else { return nil }
        var coordError: NSError?
        var result: ShareSessionBridge?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            guard let data = try? Data(contentsOf: readURL) else { return }
            result = try? decoder.decode(ShareSessionBridge.self, from: data)
        }
        return result
    }

    /// Writes (or overwrites) the bridge. Returns false if the container is
    /// unavailable or the write fails.
    @discardableResult
    static func write(_ bridge: ShareSessionBridge) -> Bool {
        guard let url = AppGroupConfig.sessionBridgeURL,
              let data = try? encoder.encode(bridge) else { return false }
        var coordError: NSError?
        var ok = false
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
            ok = (try? data.write(to: writeURL, options: .atomic)) != nil
        }
        return ok && coordError == nil
    }

    /// Clears the bridge (on logout) so the extension shows the signed-out state.
    static func clear() {
        guard let url = AppGroupConfig.sessionBridgeURL else { return }
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordError) { deleteURL in
            try? FileManager.default.removeItem(at: deleteURL)
        }
    }
}
