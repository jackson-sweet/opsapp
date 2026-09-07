import Foundation
import SwiftData

/// One container's construction/configuration/bootstrap boundary. The actor is
/// never returned until all preparation finishes, regardless of task ordering.
final class DataActorStartup: @unchecked Sendable {
    typealias Preparation = @Sendable (DataActor, @Sendable () -> Bool) async throws -> Void

    private let modelContainer: ModelContainer
    private let state: State
    private let task: Task<DataActor?, Never>

    init(
        modelContainer: ModelContainer,
        prepare: @escaping Preparation = { actor, isCurrent in
            try await actor.prepareForFirstSync(isCurrent: isCurrent)
        }
    ) {
        self.modelContainer = modelContainer
        let state = State()
        self.state = state
        self.task = Task.detached(priority: .userInitiated) {
            do {
                try Task.checkCancellation()
                let actor = try await DataActor.makeBackgroundConfigured(modelContainer: modelContainer)
                guard state.register(actor) else { return nil }
                try Task.checkCancellation()
                try await prepare(actor, { state.isCurrent && !Task.isCancelled })
                try Task.checkCancellation()
                guard state.isCurrent else { return nil }
                return actor
            } catch {
                state.invalidate()
                if !(error is CancellationError) {
                    print("[DataActor] Startup preparation failed: \(error)")
                }
                return nil
            }
        }
    }

    deinit { task.cancel() }

    var isCurrent: Bool { state.isCurrent }

    func matches(_ container: ModelContainer) -> Bool { modelContainer === container }

    func value() async -> DataActor? {
        guard state.isCurrent, !Task.isCancelled else { return nil }
        let actor = await task.value
        guard state.isCurrent, !Task.isCancelled else { return nil }
        return actor
    }

    /// Synchronous so logout/context replacement can close this boundary before
    /// clearing model data. Cancelling one waiter never cancels other waiters.
    func invalidate() {
        state.invalidate()
        task.cancel()
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var invalidated = false
        private var actor: DataActor?

        var isCurrent: Bool {
            lock.lock(); defer { lock.unlock() }
            return !invalidated
        }

        func register(_ actor: DataActor) -> Bool {
            lock.lock()
            if invalidated {
                lock.unlock()
                actor.invalidateOutboundWork()
                return false
            }
            self.actor = actor
            lock.unlock()
            return true
        }

        func invalidate() {
            lock.lock()
            invalidated = true
            let actor = actor
            lock.unlock()
            actor?.invalidateOutboundWork()
        }
    }
}
