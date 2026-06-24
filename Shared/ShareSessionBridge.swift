//
//  ShareSessionBridge.swift
//  Shared between the OPS app and the OPSShareExtension.
//
//  The "session bridge" is the snapshot the main app writes into the App Group
//  container so the share extension can present its picker WITHOUT running
//  Firebase, the Supabase SDK, or SwiftData. The extension only reads it to know
//  who is signed in and which projects it may attach photos to — it never
//  uploads, so no auth token is ever placed in shared storage.
//
//  Upload is owned entirely by the app: the extension saves the photo to the
//  shared inbox + manifest, and the app uploads it through its proven pipeline on
//  next open / when back online.
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
    /// `uploaded_by` when the app drains the queue.
    let userId: String
    let companyId: String
    /// Whether the user holds `projects.edit` — the same gate that guards every
    /// project-level write in OPS. When false the extension shows a no-permission
    /// state and offers no projects.
    let canEditProjects: Bool
    /// Display name for the uploader (currently informational).
    let userDisplayName: String?
    /// Projects the user may attach photos to, already filtered by the app.
    let editableProjects: [ShareProjectRef]
    /// When this snapshot was written.
    let updatedAt: Date
    /// Short-lived Firebase ID token used ONLY by the extension to authenticate
    /// its best-effort background POST to the share-photo endpoint (the
    /// instant-even-if-OPS-is-closed path). Optional: when absent/expired the
    /// extension just queues and the app uploads on next open. The app always has
    /// its own fresh token, so the queue-drain backstop never depends on this.
    var idToken: String?
    /// Absolute expiry of `idToken`.
    var tokenExpiresAt: Date?

    /// True when there is a usable signed-in session.
    var hasSession: Bool {
        !userId.isEmpty && !companyId.isEmpty
    }

    /// True when the bridged token has comfortable life left for the extension to
    /// presign-free POST. A 2-minute skew avoids starting a transfer with a token
    /// about to die.
    var isTokenUsable: Bool {
        guard let idToken, let tokenExpiresAt, !idToken.isEmpty else { return false }
        return tokenExpiresAt.timeIntervalSinceNow > 120
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
