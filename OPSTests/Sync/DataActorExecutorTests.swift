import SwiftData
import XCTest
@testable import OPS

@MainActor
final class DataActorExecutorTests: XCTestCase {
    func testMainConstructedActorKeepsItsTransactionOnMain() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()
        let result = try await actor.transactionExecutorProbe()
        XCTAssertTrue(result.ranOnMain, "Control reproduces setModelContext's old construction site")
        XCTAssertTrue(result.bodyStartedOnMain)
        XCTAssertFalse(result.autosaveEnabled)
        XCTAssertEqual(result.persistedCount, 1)
    }

    func testBackgroundConstructedActorKeepsTransactionOffMainWhenCalledFromMain() async throws {
        let container = try makeContainer()
        let construction = await Task.detached {
            let constructedOnMain = Thread.isMainThread
            let actor = DataActor(modelContainer: container)
            await actor.configure()
            return (actor, constructedOnMain)
        }.value
        XCTAssertFalse(construction.1, "Constructor itself must run off main")
        let actor = construction.0
        let result = try await actor.transactionExecutorProbe()
        XCTAssertFalse(result.ranOnMain, "bodyStartedOnMain=\(result.bodyStartedOnMain); transaction must stay off main")
        XCTAssertFalse(result.autosaveEnabled)
        XCTAssertEqual(result.persistedCount, 1)
    }

    func testExplicitSerialModelExecutorTransactsOffMainWhenCalledFromMain() async throws {
        let container = try makeContainer()
        let actor = await Task.detached { ExplicitQueueModelActorProbe(modelContainer: container) }.value
        let result = try await actor.transactionExecutorProbe()
        XCTAssertFalse(result.bodyStartedOnMain)
        XCTAssertFalse(result.ranOnMain)
        XCTAssertFalse(result.autosaveEnabled)
        XCTAssertEqual(result.persistedCount, 1)
    }

    func testBackgroundContainerAndActorKeepTransactionOffMainWhenCalledFromMain() async throws {
        let construction = try await Task.detached {
            let constructedOnMain = Thread.isMainThread
            let container = try ModelContainer(for: SyncOperation.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let actor = DataActor(modelContainer: container)
            await actor.configure()
            return (container, actor, constructedOnMain)
        }.value
        XCTAssertFalse(construction.2)
        let result = try await construction.1.transactionExecutorProbe()
        XCTAssertFalse(result.ranOnMain, "background container; bodyStartedOnMain=\(result.bodyStartedOnMain)")
        XCTAssertFalse(result.autosaveEnabled)
        XCTAssertEqual(result.persistedCount, 1)
        withExtendedLifetime(construction.0) {}
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: SyncOperation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}

private struct DataActorExecutorProbe: Sendable {
    let bodyStartedOnMain: Bool
    let ranOnMain: Bool
    let autosaveEnabled: Bool
    let persistedCount: Int
}

private extension DataActor {
    func transactionExecutorProbe() throws -> DataActorExecutorProbe {
        let bodyStartedOnMain = Thread.isMainThread
        var ranOnMain = false
        try modelContext.transaction {
            ranOnMain = Thread.isMainThread
            let operation = SyncOperation(entityType: "client", entityId: UUID().uuidString.lowercased(),
                operationType: "create", payload: Data("{}".utf8), changedFields: [])
            operation.status = "completed"
            modelContext.insert(operation)
        }
        return DataActorExecutorProbe(bodyStartedOnMain: bodyStartedOnMain, ranOnMain: ranOnMain,
            autosaveEnabled: modelContext.autosaveEnabled,
            persistedCount: try modelContext.fetchCount(FetchDescriptor<SyncOperation>()))
    }
}

private actor ExplicitQueueModelActorProbe: ModelActor {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        (modelExecutor as! ExplicitQueueModelExecutorProbe).asUnownedSerialExecutor()
    }
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        self.modelExecutor = ExplicitQueueModelExecutorProbe(modelContext: context)
    }
    func transactionExecutorProbe() throws -> DataActorExecutorProbe {
        let bodyStartedOnMain = Thread.isMainThread
        var ranOnMain = false
        try modelContext.transaction {
            ranOnMain = Thread.isMainThread
            let operation = SyncOperation(entityType: "client", entityId: UUID().uuidString.lowercased(),
                operationType: "create", payload: Data("{}".utf8), changedFields: [])
            operation.status = "completed"
            modelContext.insert(operation)
        }
        return DataActorExecutorProbe(bodyStartedOnMain: bodyStartedOnMain, ranOnMain: ranOnMain,
            autosaveEnabled: modelContext.autosaveEnabled,
            persistedCount: try modelContext.fetchCount(FetchDescriptor<SyncOperation>()))
    }
}

private final class ExplicitQueueModelExecutorProbe: SerialModelExecutor, @unchecked Sendable {
    let modelContext: ModelContext
    private let queue = DispatchQueue(label: "com.ops.tests.model-executor", qos: .userInitiated)
    init(modelContext: ModelContext) { self.modelContext = modelContext }
    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        queue.async { job.runSynchronously(on: self.asUnownedSerialExecutor()) }
    }
    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}
