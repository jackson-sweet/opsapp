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
        execution: SyncExecutionCoordinator? = nil,
        prepare: @escaping Preparation = { actor, isCurrent in
            try await actor.prepareForFirstSync(isCurrent: isCurrent)
        }
    ) {
        self.modelContainer = modelContainer
        let state = State()
        self.state = state
        self.task = Task.detached(priority: .userInitiated) {
            do {
                let coordinator = await MainActor.run { execution ?? SyncExecutionCoordinator.shared }
                var interruptedGeneration: UInt64?
                while state.isCurrent {
                    try Task.checkCancellation()
                    let admission = try await coordinator.waitForStartupAdmission(after: interruptedGeneration)
                    do {
                        return try await SyncExecutionContext.$scope.withValue(admission.scope) {
                            try await coordinator.run(name: "storage-preparation") {
                                let actor = try await DataActor.makeBackgroundConfigured(modelContainer: modelContainer)
                                guard state.register(actor) else { throw CancellationError() }
                                try await prepare(actor, { state.isCurrent && SyncExecutionContext.isCurrent })
                                try SyncExecutionContext.checkCurrent()
                                guard state.isCurrent else { throw CancellationError() }
                                return actor
                            }
                        }
                    } catch is CancellationError {
                        guard state.isCurrent, !Task.isCancelled else { throw CancellationError() }
                        // This detached startup task owns retirement. Do not
                        // synchronously wait for the actor from the UI thread.
                        state.retireCurrentActor()
                        interruptedGeneration = admission.generation
                    }
                }
                return nil
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
        let waiter = ReadinessWaiter()
        let preparation = task
        let actor = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter.install(continuation)
                // Waiting for the shared preparation is independent of this
                // caller. Expiration returns nil promptly without cancelling
                // storage readiness for another foreground/system caller.
                Task { waiter.resolve(await preparation.value) }
            }
        } onCancel: {
            waiter.resolve(nil)
        }
        guard state.isCurrent, !Task.isCancelled else { return nil }
        return actor
    }

    private final class ReadinessWaiter: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<DataActor?, Never>?
        private var resolved = false
        private var result: DataActor?

        func install(_ continuation: CheckedContinuation<DataActor?, Never>) {
            lock.lock()
            let finished = resolved
            let result = result
            if !finished { self.continuation = continuation }
            lock.unlock()
            if finished { continuation.resume(returning: result) }
        }

        func resolve(_ result: DataActor?) {
            lock.lock()
            guard !resolved else { lock.unlock(); return }
            resolved = true
            self.result = result
            let continuation = continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: result)
        }
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
                actor.retireAndDrainModelWork()
                return false
            }
            self.actor = actor
            lock.unlock()
            return true
        }

        func retireCurrentActor() {
            lock.lock()
            let previousActor = actor
            actor = nil
            lock.unlock()
            previousActor?.retireAndDrainModelWork()
        }

        func invalidate() {
            lock.lock()
            invalidated = true
            let actor = actor
            lock.unlock()
            actor?.retireAndDrainModelWork()
        }
    }
}
