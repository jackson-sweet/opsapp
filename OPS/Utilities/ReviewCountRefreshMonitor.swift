//
//  ReviewCountRefreshMonitor.swift
//  OPS
//
//  Coalescing trigger for the FAB's review-badge counts.
//
//  Three separate signals ask for a recount — the menu appearing, the
//  `DataSyncCompleted` notification, and `DataController.scheduledTasksDidChange`
//  — and they routinely fire together: a sync completion posts the notification
//  AND toggles the flag, and a cascade of inbound task rows toggles the flag once
//  per merge batch. The FAB is mounted on every tab (hidden by opacity, never
//  unmounted), so each of those recounts is paid no matter what the operator is
//  looking at.
//
//  The debounce runs on `RunLoop.main`, never a main QUEUE, for the reason
//  documented in `RecoveryRefreshSignal`: main-queue blocks drain during
//  `UITrackingRunLoopMode`, so a sync landing mid-scroll would recount with the
//  finger down. `RunLoop.main` timers run in `.default` mode only — delivery
//  defers to gesture end, and nothing is dropped on the way.
//

import Combine
import Foundation

/// Owns the debounce so a SwiftUI re-render cannot destroy it.
///
/// `FloatingActionMenu` observes `DataController`, so it is re-evaluated
/// throughout a sync pass — precisely when a recount is pending. Stored on the
/// view struct, the pipeline would be rebuilt on every re-evaluation and
/// `.onReceive` would drop the previous subscription along with any signal still
/// inside the window, leaving the badge stale until the next unrelated event.
/// Held as a `@StateObject`, the pipeline's lifetime is the view's identity and a
/// re-render only resubscribes to `output`, downstream of the debounce.
@MainActor
final class ReviewCountRefreshMonitor: ObservableObject {

    /// Long enough that a sync completion's notification + flag toggle + merge
    /// batches collapse into one recount, short enough that a single local
    /// schedule edit still reads as immediate when the review sheet closes.
    ///
    /// Expressed in milliseconds rather than a concrete `Stride` because the
    /// scheduler — and therefore the stride type — is injectable below.
    static let debounceMilliseconds = 300

    /// An event, not state: the FAB recounts on receipt and nothing here is
    /// diffed into a view update. Deliberately not `@Published`.
    let output = PassthroughSubject<Void, Never>()

    private let input = PassthroughSubject<Void, Never>()
    private var subscription: AnyCancellable?

    /// The scheduler is injectable for the reason `RecoveryRefreshSignal`'s is:
    /// wall-clock debounce tests were outrun by parallel-build load, so timing
    /// belongs under test control. Production always passes `RunLoop.main`.
    init<S: Scheduler>(scheduler: S) {
        subscription = input
            .debounce(
                for: .milliseconds(ReviewCountRefreshMonitor.debounceMilliseconds),
                scheduler: scheduler
            )
            .sink { [output] _ in output.send(()) }
    }

    /// Production shape — see the file header for why `RunLoop.main`.
    convenience init() {
        self.init(scheduler: RunLoop.main)
    }

    /// Requests a recount. Trailing-edge: repeated calls inside the window cost
    /// one recount, delivered once the calls stop.
    func signal() {
        input.send(())
    }
}
