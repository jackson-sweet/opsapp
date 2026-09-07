import Foundation
import SwiftData

/// Owns the queue on which its context is created and every isolated actor job
/// runs. A default SwiftData executor can run on the calling main thread even
/// when its context was constructed in Task.detached (iOS 26.5 runtime probe).
final class DataActorModelExecutor: SerialModelExecutor, @unchecked Sendable {
    let modelContext: ModelContext
    private let queue: DispatchQueue

    private init(modelContext: ModelContext, queue: DispatchQueue) {
        self.modelContext = modelContext
        self.queue = queue
    }

    static func make(modelContainer: ModelContainer) async throws -> DataActorModelExecutor {
        let lifetime = OutboundSessionLifetime()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let executor: DataActorModelExecutor? = await withCheckedContinuation { continuation in
                let queue = DispatchQueue(label: "com.ops.data-actor", qos: .userInitiated)
                queue.async {
                    guard lifetime.snapshot() != nil else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let context = ModelContext(modelContainer)
                    context.autosaveEnabled = false
                    continuation.resume(returning: DataActorModelExecutor(modelContext: context, queue: queue))
                }
            }
            try Task.checkCancellation()
            guard let executor else { throw CancellationError() }
            return executor
        } onCancel: {
            lifetime.invalidate()
        }
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        // Retaining self in the dispatch block keeps the unowned executor and
        // its context alive until the job has run exactly once.
        queue.async { job.runSynchronously(on: self.asUnownedSerialExecutor()) }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}
