//
//  ClientDeletionSyncRegressionTests.swift
//  OPSTests
//
//  A pull racing a pending client delete must never recreate the locally removed
//  SwiftData identity before the outbound soft-delete reaches Supabase.
//

import XCTest
import SwiftData
@testable import OPS

final class ClientDeletionSyncRegressionTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: OPSSchemaV18.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func dto(id: String) -> SupabaseClientDTO {
        SupabaseClientDTO(
            id: id,
            bubbleId: nil,
            companyId: "company-1",
            name: "Server client",
            email: nil,
            phoneNumber: nil,
            address: nil,
            latitude: nil,
            longitude: nil,
            notes: nil,
            profileImageUrl: nil,
            deletedAt: nil
        )
    }

    func testPendingClientDeleteSuppressesInboundReinsertion() async throws {
        let container = try makeContainer()
        let seed = ModelContext(container)
        let clientId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        seed.insert(SyncOperation(
            entityType: SyncEntityType.client.rawValue,
            entityId: clientId,
            operationType: "delete",
            payload: Data(),
            changedFields: ["id"]
        ))
        try seed.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()
        await actor.handleRealtimeUpdate(.client(dto(id: clientId)))

        let check = ModelContext(container)
        let clients = try check.fetch(
            FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientId })
        )
        XCTAssertTrue(
            clients.isEmpty,
            "a server echo must not resurrect a client with a recent local delete"
        )
    }

    func testRemoteClientWithoutRecentLocalWriteStillInserts() async throws {
        let container = try makeContainer()
        let clientId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let actor = DataActor(modelContainer: container)
        await actor.configure()
        await actor.handleRealtimeUpdate(.client(dto(id: clientId)))

        let check = ModelContext(container)
        let clients = try check.fetch(
            FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientId })
        )
        XCTAssertEqual(clients.count, 1)
    }

    @MainActor
    func testConcurrentPushRequestWaitsForCoalescedDrain() async {
        let coordinator = SyncPushDrainCoordinator()
        let releaseFirstPass = ClientDeletionPresentationGate()
        let firstPassStarted = expectation(description: "first push pass started")
        let secondRequestStarted = expectation(description: "second push requested")
        var passCount = 0
        var secondRequestFinished = false

        let firstRequest = Task { @MainActor in
            await coordinator.run {
                passCount += 1
                if passCount == 1 {
                    firstPassStarted.fulfill()
                    await releaseFirstPass.waitUntilDismissed()
                }
            }
        }

        await fulfillment(of: [firstPassStarted], timeout: 1)

        let secondRequest = Task { @MainActor in
            secondRequestStarted.fulfill()
            await coordinator.run {
                XCTFail("The active push owns the coalesced follow-up pass")
            }
            secondRequestFinished = true
        }

        await fulfillment(of: [secondRequestStarted], timeout: 1)
        XCTAssertFalse(secondRequestFinished)

        releaseFirstPass.signalDismissed()
        await firstRequest.value
        await secondRequest.value

        XCTAssertEqual(passCount, 2)
        XCTAssertTrue(secondRequestFinished)
    }
}
