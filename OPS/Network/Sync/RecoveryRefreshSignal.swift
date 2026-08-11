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

import Combine
import Foundation
import SwiftData

enum RecoveryRefreshSignal {

    /// Long enough that a sync pass's save storm collapses into one load, short
    /// enough that a single local edit still reads as immediate.
    static let debounceWindow: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(500)

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
    static func publisher(
        center: NotificationCenter = .default
    ) -> AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            center.publisher(for: .dataActorDidSave),
            center.publisher(for: ModelContext.didSave),
            center.publisher(for: .opsLeadsDidChange)
        )
        .map { _ in () }
        .debounce(for: debounceWindow, scheduler: DispatchQueue.main)
        .eraseToAnyPublisher()
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
    init(center: NotificationCenter = .default) {
        let fallback = Timer
            .publish(every: RecoveryRefreshSignal.fallbackInterval, on: .main, in: .default)
            .autoconnect()
            .map { _ in () }

        subscription = RecoveryRefreshSignal.publisher(center: center)
            .merge(with: fallback)
            .sink { [output] _ in output.send(()) }
    }
}
