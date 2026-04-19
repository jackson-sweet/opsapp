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
//  This bridge subscribes to a Sendable notification rebroadcast by the
//  owning background actor after each save. It forces registration of
//  inserted persistentIdentifiers in the main context's object registry
//  and increments a @Published trigger that @Query-observing lists can bind
//  to via .id() or .task(id:).
//
//  The subscription-by-notification-name design avoids crossing the actor
//  boundary with a non-Sendable ModelContext reference; the actor-side
//  rebroadcast (see DataActor.configure) is the producer.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class MainContextRefreshBridge: ObservableObject {
    // MARK: - Published State

    /// Increments each time the background actor saves. Views bind to this via
    /// .id(refreshBridge.refreshCounter) or .task(id: refreshBridge.refreshCounter)
    /// to force a @Query re-evaluation after background inserts.
    @Published private(set) var refreshCounter: Int = 0

    // MARK: - Dependencies

    private let mainContext: ModelContext
    private var cancellable: AnyCancellable?

    // MARK: - Init

    /// Subscribes to a Sendable notification posted by a background actor after save.
    /// The notification's userInfo must contain "inserted" / "updated" / "deleted"
    /// arrays of PersistentIdentifier. See DataActor.configure for the producer side.
    init(mainContext: ModelContext, listeningTo notificationName: Notification.Name) {
        self.mainContext = mainContext
        self.cancellable = NotificationCenter.default
            .publisher(for: notificationName)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleDidSave(notification)
            }
    }

    deinit {
        cancellable?.cancel()
    }

    // MARK: - Refresh Handling

    private func handleDidSave(_ notification: Notification) {
        let userInfo = notification.userInfo ?? [:]

        // Force-register inserted IDs in mainContext's object registry so @Query
        // picks them up. This is the workaround for FB14750050 — no-op if Apple
        // has fixed it (see Task 20 verification).
        if let insertedIds = userInfo["inserted"] as? [PersistentIdentifier] {
            for id in insertedIds {
                _ = mainContext.model(for: id)
            }
        }

        refreshCounter &+= 1  // wrap-safe overflow
    }
}
