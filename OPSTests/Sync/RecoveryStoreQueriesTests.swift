import SwiftData
import XCTest
@testable import OPS

@MainActor
final class RecoveryStoreQueriesTests: XCTestCase {
    func testNeverPopulatedOperationStoreDoesNotEnterPredicatedFetch() throws {
        let container = try ModelContainer(for: SyncOperation.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        XCTAssertTrue(try RecoveryStoreQueries.activeOperations(in: container.mainContext).isEmpty)
    }

    func testBackgroundReadReturnsLiveWorkWithoutMaterializingCompletedHistory() async throws {
        let container = try ModelContainer(for: SyncOperation.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        for index in 0..<2636 {
            let operation = SyncOperation(entityType: "project", entityId: "synthetic-\(index)", operationType: "update", payload: Data("{}".utf8), changedFields: ["title"])
            operation.status = index < 2625 ? "completed" : index < 2634 ? "pending" : index == 2634 ? "inProgress" : "parked"
            context.insert(operation)
        }
        try context.save()
        let snapshot = try await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            let ownedContext = ModelContext(container)
            ownedContext.autosaveEnabled = false
            let rows = try RecoveryStoreQueries.activeOperations(in: ownedContext)
            return (rows.count, rows.filter { $0.status == "parked" }.count)
        }.value
        XCTAssertEqual(snapshot.0, 11)
        XCTAssertEqual(snapshot.1, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SyncOperation>()), 2636)
    }


}
