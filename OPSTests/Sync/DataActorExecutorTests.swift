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
        XCTAssertFalse(result.autosaveEnabled)
        XCTAssertEqual(result.persistedCount, 1)
    }

    func testBackgroundConstructedActorKeepsTransactionOffMainWhenCalledFromMain() async throws {
        let container = try makeContainer()
        let actor = await Task.detached {
            let actor = DataActor(modelContainer: container)
            await actor.configure()
            return actor
        }.value
        let result = try await actor.transactionExecutorProbe()
        XCTAssertFalse(result.ranOnMain, "Awaiting from MainActor must not move this context to main")
        XCTAssertFalse(result.autosaveEnabled)
        XCTAssertEqual(result.persistedCount, 1)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: SyncOperation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}

private struct DataActorExecutorProbe: Sendable {
    let ranOnMain: Bool
    let autosaveEnabled: Bool
    let persistedCount: Int
}

private extension DataActor {
    func transactionExecutorProbe() throws -> DataActorExecutorProbe {
        var ranOnMain = false
        try modelContext.transaction {
            ranOnMain = Thread.isMainThread
            let operation = SyncOperation(entityType: "client", entityId: UUID().uuidString.lowercased(),
                operationType: "create", payload: Data("{}".utf8), changedFields: [])
            operation.status = "completed"
            modelContext.insert(operation)
        }
        return DataActorExecutorProbe(ranOnMain: ranOnMain,
            autosaveEnabled: modelContext.autosaveEnabled,
            persistedCount: try modelContext.fetchCount(FetchDescriptor<SyncOperation>()))
    }
}
