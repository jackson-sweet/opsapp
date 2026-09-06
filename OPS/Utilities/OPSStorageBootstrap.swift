import Combine
import Foundation
import OSLog
import SwiftData

/// Owns one store-opening attempt at a time. Failure retains the configured
/// store and never provides a substitute container to the app or sync services.
@MainActor
final class OPSStorageBootstrap: ObservableObject {
    enum State {
        case loading
        case ready(ModelContainer)
        case failed(Failure)
    }

    /// Keep diagnostics structural. NSError.userInfo can contain customer data
    /// and filesystem paths; neither belongs in the recovery view or logs.
    struct Failure: Error, Sendable {
        let domain: String
        let code: Int
    }

    @Published private(set) var state: State = .loading
    private let configuration: ModelConfiguration
    private var openTask: Task<Result<ModelContainer, Failure>, Never>?
    private var generation: UInt64 = 0

    init(configuration: ModelConfiguration) {
        self.configuration = configuration
    }

    /// A canceled view waiter does not cancel a store migration. Later waiters
    /// join the same task, and a successful container is retained for app life.
    func open() async {
        if case .ready = state { return }

        let task: Task<Result<ModelContainer, Failure>, Never>
        if let existing = openTask {
            task = existing
        } else {
            generation &+= 1
            state = .loading
            let configuration = configuration
            task = Task.detached(priority: .userInitiated) {
                do {
                    // Only immutable, Sendable configuration crosses the boundary.
                    // No context or live PersistentModel leaves its owning actor.
                    let schema = Schema(versionedSchema: OPSSchemaCurrent.self)
                    let container = try ModelContainer(
                        for: schema,
                        migrationPlan: OPSMigrationPlan.self,
                        configurations: [configuration]
                    )
                    return .success(container)
                } catch {
                    let nsError = error as NSError
                    let failure = Failure(domain: nsError.domain, code: nsError.code)
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "OPS", category: "StorageBootstrap")
                        .error("Store open failed; preserved in place. Domain: \(failure.domain, privacy: .public), code: \(failure.code)")
                    return .failure(failure)
                }
            }
            openTask = task
        }

        let attempt = generation
        let result = await task.value
        // Another waiter may already have published this result, or a deliberate
        // retry may have begun. An old waiter must never clear the new attempt.
        guard generation == attempt, openTask != nil else { return }
        openTask = nil
        switch result {
        case .success(let container): state = .ready(container)
        case .failure(let failure): state = .failed(failure)
        }
    }
}
