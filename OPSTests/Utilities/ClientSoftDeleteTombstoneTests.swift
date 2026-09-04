//
//  ClientSoftDeleteTombstoneTests.swift
//  OPSTests
//
//  deleteClient used to hard-delete the local row — `modelContext.delete(client)`
//  — and return immediately while both call sites toasted success. With no row
//  left there was no tombstone for Settings > Trash to show and nothing to
//  restore, and because the server delete was being refused by row security and
//  parked, the client reappeared on the next inbound sync. The app reported a
//  result it had achieved in neither place. Bug 2a55c78f, filed by the founder
//  31 seconds after it happened on his own phone.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class ClientSoftDeleteTombstoneTests: XCTestCase {

    /// A ModelContext does not keep its ModelContainer alive, and inserting into
    /// a context whose container has been released traps inside SwiftData
    /// (uncatchable EXC_BREAKPOINT) before the first assertion runs.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        UserDefaults.standard.removeObject(forKey: "feature.useDataActor")
        super.tearDown()
    }

    func test_deleteClient_setsDeletedAtAndKeepsRowInContext() async throws {
        let (dataController, context) = try makeHarness()
        let client = makeClient()
        context.insert(client)
        try context.save()

        try await dataController.deleteClient(client)

        let surviving = try fetchClient(id: client.id, in: context)
        XCTAssertNotNil(
            surviving,
            "The row must survive the delete — a hard delete leaves nothing for Trash to restore."
        )
        XCTAssertNotNil(surviving?.deletedAt, "The client must carry a tombstone.")
        XCTAssertEqual(surviving?.needsSync, true)
    }

    func test_deleteClient_recordsDeleteOperationCarryingDeletedAt() async throws {
        let (dataController, context) = try makeHarness()
        let client = makeClient()
        context.insert(client)
        try context.save()

        try await dataController.deleteClient(client)

        let operation = try XCTUnwrap(
            context.fetch(FetchDescriptor<SyncOperation>()).first,
            "The delete must be staged for the outbound queue."
        )
        XCTAssertEqual(operation.entityType, SyncEntityType.client.rawValue)
        XCTAssertEqual(operation.entityId, client.id)
        XCTAssertEqual(operation.operationType, "delete")

        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: operation.payload) as? [String: Any]
        )
        // It used to stage `["id": clientId]`, which said nothing about what
        // changed. deleteProject's tombstone convention is the one to match.
        XCTAssertNotNil(
            payload["deleted_at"] as? String,
            "The staged op must name the tombstone it wrote."
        )
        XCTAssertNil(payload["id"])
    }

    func test_deletedClientAppearsInTrashSelection() async throws {
        let (dataController, context) = try makeHarness()
        let deleted = makeClient()
        let kept = makeClient(
            id: "60606060-6060-4060-8060-606060606060",
            name: "Harbourline Mechanical"
        )
        context.insert(deleted)
        context.insert(kept)
        try context.save()

        try await dataController.deleteClient(deleted)

        // The exact predicate TrashView applies to its @Query of every client
        // (TrashView.deletedClients).
        let allClients = try context.fetch(FetchDescriptor<Client>())
        let trashed = allClients.filter { $0.deletedAt != nil }

        XCTAssertEqual(
            trashed.map(\.id),
            [deleted.id],
            "The deleted client must be the one and only row Trash offers to restore."
        )
    }

    // MARK: - Harness

    private func makeHarness() throws -> (DataController, ModelContext) {
        UserDefaults.standard.set(false, forKey: "feature.useDataActor")
        let container = try makeInMemoryContainer()
        retainedContainers.append(container)
        let context = ModelContext(container)
        let dataController = DataController()
        dataController.setModelContext(context)
        dataController.syncEngine.configure(
            modelContext: context,
            connectivity: dataController.connectivity
        )
        return (dataController, context)
    }

    private func makeClient(
        id: String = "30303030-3030-4030-8030-303030303030",
        name: String = "Northline Builders"
    ) -> Client {
        Client(id: id, name: name, companyId: "company-1")
    }

    private func fetchClient(id: String, in context: ModelContext) throws -> Client? {
        try context.fetch(FetchDescriptor<Client>()).first { $0.id == id }
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            TaskReminder.self,
            User.self,
            Client.self,
            SubClient.self,
            SyncOperation.self,
            ProjectVinylOrderMarker.self,
            ProjectPrimaryContactSelection.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
