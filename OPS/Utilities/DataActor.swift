//
//  DataActor.swift
//  OPS
//
//  Long-lived @ModelActor that owns all background SwiftData writes.
//  Part of the C-pragmatic ModelActor refactor (Phase 1).
//
//  Design invariants:
//   - One instance per app lifetime, created in DataController.setModelContext.
//   - Uses its own ModelContext (created by @ModelActor macro) — NOT mainContext.
//   - All external callers use async methods; internal work uses
//     ModelContext.transaction { } for atomicity.
//   - Accepts PersistentIdentifier across the actor boundary, never @Model.
//
//  Migration note: the methods on this actor replace the previous
//  @MainActor InboundProcessor, OutboundProcessor, and DataController cleanup
//  implementations. Legacy paths remain behind FeatureFlags.useDataActor
//  until verified and removed.
//

import Foundation
import SwiftData

extension Notification.Name {
    /// Posted on MainActor after DataActor's ModelContext saves.
    /// userInfo keys: "inserted" / "updated" / "deleted" ([PersistentIdentifier]).
    /// Subscribed to by MainContextRefreshBridge to close the iOS 18.2
    /// @Query insert-auto-refresh gap without passing ModelContext across
    /// actor boundaries (which would error under Swift 6 strict concurrency).
    static let dataActorDidSave = Notification.Name("DataActorDidSave")
}

@ModelActor
actor DataActor {
    // MARK: - Observer State

    private var didSaveObserver: NSObjectProtocol?

    // MARK: - Configuration

    /// Called once after init to apply per-context configuration and install
    /// the didSave observer that rebroadcasts a Sendable notification to main.
    /// Must be called before any transaction is run.
    func configure() {
        modelContext.autosaveEnabled = false

        // Subscribe to self's didSave and re-broadcast a Sendable notification on main.
        // This avoids passing the non-Sendable ModelContext across the actor boundary,
        // which would error under Swift 6 strict concurrency. Sendable payload is the
        // PersistentIdentifier arrays from userInfo.
        didSaveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: modelContext,
            queue: nil
        ) { notification in
            let userInfo = notification.userInfo ?? [:]
            let inserted = (userInfo[ModelContext.NotificationKey.insertedIdentifiers.rawValue] as? [PersistentIdentifier]) ?? []
            let updated = (userInfo[ModelContext.NotificationKey.updatedIdentifiers.rawValue] as? [PersistentIdentifier]) ?? []
            let deleted = (userInfo[ModelContext.NotificationKey.deletedIdentifiers.rawValue] as? [PersistentIdentifier]) ?? []

            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .dataActorDidSave,
                    object: nil,
                    userInfo: [
                        "inserted": inserted,
                        "updated": updated,
                        "deleted": deleted
                    ]
                )
            }
        }
    }

    deinit {
        if let observer = didSaveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
