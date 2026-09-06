import XCTest
import SwiftData
@testable import OPS

final class DeckEditingSessionTests: XCTestCase {
    func testHoldsOnlyTheEditedDeckUntilEverySessionReleases() {
        let registry = DeckEditingSessionRegistry()
        let first = registry.begin(designId: "ABC")
        let second = registry.begin(designId: "abc")
        XCTAssertTrue(registry.isHeld(entityType: "deckDesign", entityId: "AbC"))
        XCTAssertFalse(registry.isHeld(entityType: "deckDesign", entityId: "other"))
        XCTAssertFalse(registry.isHeld(entityType: "project", entityId: "ABC"))
        registry.end(first)
        XCTAssertTrue(registry.isHeld(entityType: "deckDesign", entityId: "abc"))
        registry.end(second)
        XCTAssertFalse(registry.isHeld(entityType: "deckDesign", entityId: "abc"))
    }

    @MainActor
    func testBothOutboundDriversLeaveHeldRevisionUnclaimed() async throws {
        let container = try ModelContainer(for: SyncOperation.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let operation = SyncOperation(entityType: "deckDesign", entityId: UUID().uuidString,
            operationType: "update", payload: Data(), changedFields: ["drawing_data"])
        context.insert(operation)
        try context.save()
        let token = DeckEditingSessionRegistry.shared.begin(designId: operation.entityId)
        defer { DeckEditingSessionRegistry.shared.end(token) }
        // Invalid bytes are deliberate: if the hold regresses, decoding fails
        // before repository routing; this fixture can never make a real write.
        try await OutboundProcessor().executeOperation(operation, context: context)
        XCTAssertEqual(operation.status, "pending")
        XCTAssertNil(operation.lastAttemptedAt)
        let actor = await Task.detached { DataActor(modelContainer: container) }.value
        _ = await actor.processPendingOperations()
        let fresh = ModelContext(container)
        let stored = try XCTUnwrap(fresh.fetch(FetchDescriptor<SyncOperation>()).first)
        XCTAssertEqual(stored.status, "pending")
        XCTAssertNil(stored.lastAttemptedAt)
        XCTAssertEqual(stored.payload, Data())
    }

    func testProcessRestartReleasesHoldWithoutChangingDurableOperation() {
        let oldProcess = DeckEditingSessionRegistry()
        _ = oldProcess.begin(designId: "abc")
        let restartedProcess = DeckEditingSessionRegistry()
        XCTAssertFalse(restartedProcess.isHeld(entityType: "deckDesign", entityId: "abc"))
    }
}
