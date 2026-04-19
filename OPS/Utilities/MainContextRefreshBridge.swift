//
//  MainContextRefreshBridge.swift
//  OPS
//
//  Closes the iOS 18.2 @Query auto-refresh gap for background-actor inserts.
//
//  When DataActor's background ModelContext saves, SwiftUI @Query-observing
//  views bound to mainContext do not auto-refresh for INSERT events (Apple
//  feedback FB12689036, FB14750050, FB15092827 — confirmed by DTS, unfixed
//  as of iOS 18.3).
//
//  This bridge subscribes to ModelContext.didSave notifications from the
//  actor's context, forces registration of inserted persistentIdentifiers in
//  the main context's object registry, and increments a @Published trigger
//  that @Query-observing lists can bind to via .id() or .task(id:).
//

import Foundation
import SwiftData
import Combine

@MainActor
final class MainContextRefreshBridge: ObservableObject {
    // MARK: - Published State

    /// Increments each time the actor context saves. Views bind to this via
    /// .id(refreshBridge.refreshCounter) or .task(id: refreshBridge.refreshCounter)
    /// to force a @Query re-evaluation after background inserts.
    @Published private(set) var refreshCounter: Int = 0

    // MARK: - Dependencies

    private let mainContext: ModelContext
    private var didSaveCancellable: AnyCancellable?

    // MARK: - Init

    init(mainContext: ModelContext) {
        self.mainContext = mainContext
    }

    deinit {
        didSaveCancellable?.cancel()
    }

    // MARK: - Subscription

    /// Subscribes to a background ModelContext's didSave notifications.
    /// Call once after the actor is created, passing the actor's context.
    ///
    /// Implementation: the actor exposes its context synchronously via a
    /// helper; we capture the notification from NotificationCenter filtered
    /// to that specific context instance.
    func subscribe(to actorContext: ModelContext) {
        didSaveCancellable?.cancel()

        // NotificationCenter publisher for ModelContext.didSave notifications.
        // SwiftData fires this on the queue the context is bound to (the actor's),
        // so we explicitly hop to main before touching mainContext.
        didSaveCancellable = NotificationCenter.default
            .publisher(for: ModelContext.didSave, object: actorContext)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleDidSave(notification)
            }
    }

    // MARK: - Refresh Handling

    private func handleDidSave(_ notification: Notification) {
        // userInfo contains `insertedIdentifiers` / `updatedIdentifiers` /
        // `deletedIdentifiers` arrays of PersistentIdentifier values. Keys
        // are public constants on ModelContext.NotificationKey (iOS 17+).
        let userInfo = notification.userInfo ?? [:]

        // Force-register inserted IDs in mainContext's object registry so
        // @Query picks them up. This is the workaround for FB14750050.
        if let insertedIds = userInfo[ModelContext.NotificationKey.insertedIdentifiers.rawValue]
            as? [PersistentIdentifier] {
            for id in insertedIds {
                _ = mainContext.model(for: id)
            }
        }

        // Bump the trigger so views bound to refreshCounter re-query.
        refreshCounter &+= 1  // wrap-safe overflow
    }
}
