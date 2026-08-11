//
//  RecoveryRefreshSignal.swift
//  OPS
//
//  Refresh trigger for the two surfaces that read `RecoveryInventory` — the sync
//  pill (`SyncStatusIndicator`) and the PENDING WORK screen.
//
//  Both used to poll every 2 seconds in `.common` runloop mode, which fires
//  during scroll tracking and ran a six-fetch main-context load forever, whether
//  or not anything had changed and whether or not the pill was even on screen.
//  The inventory only changes when the store changes, so the surfaces listen for
//  that instead, debounced so a sync pass's save storm costs one load.
//
//  Everything here schedules in `.default` runloop mode, never `.common`, and
//  that applies to the debounce as much as to the fallback timer. A main-QUEUE
//  debounce is not equivalent: main-queue blocks drain during scroll tracking
//  too, so a save landing mid-gesture would deliver mid-gesture and run the
//  six-fetch load with the finger down — the exact hitch this file removes.
//  On `RunLoop.main` in `.default` mode, delivery defers to gesture end instead.
//  Nothing is dropped; it arrives when it can be paid for.
//

import Combine
import Foundation
import SwiftData

enum RecoveryRefreshSignal {

    /// Long enough that a sync pass's save storm collapses into one load, short
    /// enough that a single local edit still reads as immediate.
    ///
    /// Trailing-edge with no max-latency bound — a deliberate divergence from
    /// `InboundChangeSignal`'s router, which forces a flush after 1s of
    /// continuous arrivals. Starvation is already bounded twice over here: the
    /// `fallbackInterval` tick refreshes regardless of store traffic, and a
    /// storm long enough to matter is a sync pass, which the pill is displaying
    /// as SYNCING off `DataController` state for its whole duration.
    ///
    /// Expressed in milliseconds rather than a concrete `Stride` because the
    /// scheduler — and therefore the stride type — is injectable below.
    static let debounceMilliseconds = 500

    /// Slow self-heal for inventory inputs that reach no save notification —
    /// notably the recovery vault's quarantine entries, which live outside
    /// SwiftData. `.default` mode, never `.common`: this must never fire while a
    /// scroll gesture is being tracked.
    static let fallbackInterval: TimeInterval = 60

    /// Every event that can change what the inventory would report: background
    /// sync saves (`dataActorDidSave`, the Sendable rebroadcast posted after
    /// `DataActor`'s context saves), main-context saves (outbound operations and
    /// local edits), and realtime lead rows (`opsLeadsDidChange`).
    ///
    /// `ModelContext.didSave` is subscribed name-wide, so DataActor's own saves
    /// arrive twice; the debounce collapses the overlap into a single refresh.
    ///
    /// The scheduler is injectable for the reason `InboundChangeRouter`'s is:
    /// wall-clock debounce tests were outrun by parallel-build load, so timing
    /// belongs under test control. Production always passes `RunLoop.main`.
    static func publisher<S: Scheduler>(
        center: NotificationCenter = .default,
        scheduler: S
    ) -> AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            center.publisher(for: .dataActorDidSave),
            center.publisher(for: ModelContext.didSave),
            center.publisher(for: .opsLeadsDidChange)
        )
        .map { _ in () }
        .debounce(for: .milliseconds(debounceMilliseconds), scheduler: scheduler)
        .eraseToAnyPublisher()
    }

    /// Production shape: `RunLoop.main` schedules in `.default` mode, so a
    /// refresh never lands mid-scroll. See the file header.
    static func publisher(
        center: NotificationCenter = .default
    ) -> AnyPublisher<Void, Never> {
        publisher(center: center, scheduler: RunLoop.main)
    }
}

/// Owns the refresh pipeline so that a SwiftUI re-render cannot destroy it.
///
/// The debounce is what makes ownership load-bearing. Stored on a view struct,
/// the whole chain is rebuilt every time SwiftUI re-evaluates the struct and
/// `.onReceive` drops the previous subscription — along with any event still
/// inside the 500ms window. Both surfaces observe `DataController`, which
/// publishes while a sync pass is saving, so the dropped event is precisely the
/// completion the pill needs to reflect; the surface then stays stale until the
/// fallback tick. Held as `@StateObject`, the pipeline's lifetime is the view's
/// identity instead, and a re-render only resubscribes to `output` — downstream
/// of the debounce, where resubscription carries no state to lose.
@MainActor
final class RecoveryRefreshMonitor: ObservableObject {

    /// An event, not state: the surfaces reload on receipt, and nothing here is
    /// diffed into a view update. Deliberately not `@Published`.
    let output = PassthroughSubject<Void, Never>()

    private var subscription: AnyCancellable?

    /// The fallback timer belongs here for the same reason the debounce does: a
    /// struct-stored timer restarts its 60s countdown on every re-render, and on
    /// a surface that re-renders this often it never reaches its deadline.
    ///
    /// It is merged *after* `publisher(center:)`, never into it — the self-heal
    /// tick has to fire on its own schedule, and feeding it through the debounce
    /// would let continuous store activity postpone it indefinitely.
    init<S: Scheduler>(center: NotificationCenter = .default, scheduler: S) {
        let fallback = Timer
            .publish(every: RecoveryRefreshSignal.fallbackInterval, on: .main, in: .default)
            .autoconnect()
            .map { _ in () }

        subscription = RecoveryRefreshSignal.publisher(center: center, scheduler: scheduler)
            .merge(with: fallback)
            .sink { [output] _ in output.send(()) }
    }

    /// Production shape — see `RecoveryRefreshSignal.publisher(center:)`.
    convenience init(center: NotificationCenter = .default) {
        self.init(center: center, scheduler: RunLoop.main)
    }
}
