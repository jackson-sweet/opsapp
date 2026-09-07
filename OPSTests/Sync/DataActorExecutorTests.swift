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
        XCTAssertTrue(result.ranOnMain, "Control reproduces the old main-thread execution")
        XCTAssertTrue(result.bodyStartedOnMain)
        XCTAssertFalse(result.autosaveEnabled)
        XCTAssertEqual(result.persistedCount, 1)
    }

    func testProductionFactoryTransactsOffMainWhenCalledFromMain() async throws {
        let container = try makeContainer()
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: container)
        let result = try await actor.transactionExecutorProbe()
        XCTAssertFalse(result.bodyStartedOnMain)
        XCTAssertFalse(result.ranOnMain)
        XCTAssertFalse(result.autosaveEnabled)
        XCTAssertEqual(result.persistedCount, 1)
    }

    func testConcurrentProductionActorCallsSerializeRealTransactions() async throws {
        let container = try makeContainer()
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: container)
        let results = try await withThrowingTaskGroup(of: DataActorExecutorProbe.self) { group in
            for _ in 0..<16 { group.addTask { try await actor.transactionExecutorProbe() } }
            var results: [DataActorExecutorProbe] = []
            for try await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(results.map(\.persistedCount).sorted(), Array(1...16))
        XCTAssertTrue(results.allSatisfy { !$0.bodyStartedOnMain && !$0.ranOnMain && !$0.autosaveEnabled })
        let readback = ModelContext(container)
        XCTAssertEqual(try readback.fetchCount(FetchDescriptor<SyncOperation>()), 16)
    }

    func testProductionActorTransactionPersistsAcrossContainerReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("executor.store")
        try await writeProductionTransaction(url: url)
        let reopened = try ModelContainer(for: SyncOperation.self,
            configurations: ModelConfiguration(url: url))
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<SyncOperation>()), 1)
    }

    private func writeProductionTransaction(url: URL) async throws {
        let container = try ModelContainer(for: SyncOperation.self,
            configurations: ModelConfiguration(url: url))
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: container)
        let result = try await actor.transactionExecutorProbe()
        XCTAssertFalse(result.bodyStartedOnMain)
        XCTAssertFalse(result.ranOnMain)
        XCTAssertEqual(result.persistedCount, 1)
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
