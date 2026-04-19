//
//  MainContextRefreshBridge.swift
//  OPS
//
//  Closes the iOS 18.2 @Query auto-refresh gap for background-actor inserts.
//
//  When DataActor's background ModelContext saves, SwiftUI @Query-observing
//  views bound to mainContext do not auto-refresh for INSERT events on
//  affected OS versions (Apple feedback FB12689036, FB14750050, FB15092827 —
//  confirmed by DTS, unfixed as of iOS 18.3).
//
//  This bridge subscribes to a Sendable notification rebroadcast by the
//  owning background actor after each save. On affected OS versions it forces
//  registration of inserted persistentIdentifiers in the main context's
//  object registry. It also increments a @Published trigger that
//  @Query-observing lists can bind to via .id() or .task(id:) as insurance.
//
//  The subscription-by-notification-name design avoids crossing the actor
//  boundary with a non-Sendable ModelContext reference; the actor-side
//  rebroadcast (see DataActor.configure) is the producer.
//
//  iOS 26 device verification on 2026-04-19 confirmed @Query lists populate
//  automatically without the registry-force workaround — the loop became
//  unamortized overhead on main. Gated below so iOS 26+ skips it while
//  iOS 17.6–25.x keep the workaround as correctness insurance. Tracked in
//  Supabase bug_report 914b3945-27f5-4823-9e4b-d42f0407fcc2.
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

    // MARK: - OS Workaround Cache

    /// True when the running OS needs the FB14750050 insert-force workaround.
    /// Evaluated once at app launch; `#available` is a runtime check but the
    /// result is constant for the process lifetime. Cached to avoid per-save
    /// re-evaluation overhead.
    ///
    /// iOS 26 is the confirmed-working baseline (device verified 2026-04-19).
    /// Older versions fall back to the loop as insurance — FB14750050 was
    /// unfixed as of iOS 18.3 per Apple DTS and we have no signal on iOS
    /// 18.4–25.x, so we assume "needs workaround" for safety.
    private static let needsInsertForceWorkaround: Bool = {
        if #available(iOS 26, *) { return false }
        return true
    }()

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

        // On affected OS versions, force-register inserted IDs in mainContext's
        // object registry so @Query picks them up (FB14750050 workaround).
        // iOS 26+ resolves the auto-refresh gap natively; skip the loop to
        // reclaim the small per-save main-thread cost observed in calendar
        // swipe perf verification.
        if Self.needsInsertForceWorkaround,
           let insertedIds = userInfo["inserted"] as? [PersistentIdentifier] {
            for id in insertedIds {
                _ = mainContext.model(for: id)
            }
        }

        refreshCounter &+= 1  // wrap-safe overflow
    }
}
