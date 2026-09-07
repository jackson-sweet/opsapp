import SwiftData
import XCTest
@testable import OPS

@MainActor
final class DataActorInboundLifetimeTests: XCTestCase {
    private let keys = ["feature.useDataActor", "currentUserId", "currentUserCompanyId", "sync.lastPull.client"]
    private var previous: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in keys { previous[key] = UserDefaults.standard.object(forKey: key) }
        UserDefaults.standard.set(true, forKey: "feature.useDataActor")
        UserDefaults.standard.set("lifetime-user", forKey: "currentUserId")
        UserDefaults.standard.set("lifetime-company", forKey: "currentUserCompanyId")
    }

    override func tearDown() {
        for key in keys {
            if let value = previous[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    func testDelayedSingleClientCannotReappearAfterRetirementAndWipe() async throws {
        let container = try makeContainer()
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: container)
        let dto = try makeClientDTO()
        try await actor.mergeClientSnapshot(dto)
        let started = expectation(description: "single client response held")
        let gate = InboundLifetimeGate()
        await actor.setInboundClientsForTesting { started.fulfill(); await gate.wait(); return [dto] }
        let pull = Task { try await actor.syncClientOnly(clientId: dto.id, companyId: dto.companyId) }
        await fulfillment(of: [started], timeout: 3)
        actor.retireAndDrainModelWork()
        for client in try container.mainContext.fetch(FetchDescriptor<Client>()) { container.mainContext.delete(client) }
        try container.mainContext.save()
        await gate.release()
        do { try await pull.value; XCTFail("Retired response must report cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let check = ModelContext(container)
        XCTAssertEqual(try check.fetchCount(FetchDescriptor<Client>()), 0)
    }

    func testDelayedClientBatchCannotMergeAfterAccountChanges() async throws {
        let container = try makeContainer()
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: container)
        let dto = try makeClientDTO()
        let started = expectation(description: "client batch response held")
        let gate = InboundLifetimeGate()
        await actor.setInboundClientsForTesting { started.fulfill(); await gate.wait(); return [dto] }
        let pull = Task { try await actor.syncClientsForTesting(companyId: dto.companyId) }
        await fulfillment(of: [started], timeout: 3)
        UserDefaults.standard.set("replacement-user", forKey: "currentUserId")
        await gate.release()
        do { try await pull.value; XCTFail("Obsolete batch must report cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Client>()), 0)
    }

    func testRetiredActorRejectsNewInboundAndRealtimeEntries() async throws {
        let container = try makeContainer()
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: container)
        let dto = try makeClientDTO()
        await actor.setInboundClientsForTesting { XCTFail("Retired actor must not fetch"); return [dto] }
        actor.retireAndDrainModelWork()
        do { try await actor.syncClientOnly(clientId: dto.id, companyId: dto.companyId); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        await actor.handleRealtimeUpdate(.client(dto))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Client>()), 0)
    }

    func testOldDeltaCannotAdvanceCursorOrPublishErrorIntoReplacementSession() async throws {
        let container = try makeContainer()
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: container)
        let started = expectation(description: "delta response held")
        let gate = InboundLifetimeGate()
        await actor.setInboundDeltaForTesting { started.fulfill(); await gate.wait(); return [] }
        let engine = SyncEngine()
        engine.configure(modelContext: container.mainContext, connectivity: LifetimeOnlineConnectivity(), dataActor: actor)
        defer { engine.stopForLogoutSync() }
        let cursor = Date(timeIntervalSince1970: 100)
        engine.setLastSyncTimestamp(cursor, for: .client)
        let pull = Task { await engine.pullDelta() }
        await fulfillment(of: [started], timeout: 3)
        engine.stopForLogoutSync()
        engine.statusText = "replacement session"
        await gate.release()
        await pull.value
        XCTAssertEqual(engine.lastSyncTimestamp(for: .client), cursor)
        XCTAssertEqual(engine.statusText, "replacement session")
        XCTAssertFalse(engine.hasError)
    }

    func testRetirementWaitsForExecutingModelTransactionBeforeWipe() async throws {
        let container = try makeContainer()
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: container)
        let entered = expectation(description: "transaction entered")
        let release = DispatchSemaphore(value: 0)
        let retired = DispatchSemaphore(value: 0)
        let writing = Task { try await actor.heldTransactionForLifetimeTest(entered: { entered.fulfill() }, release: release) }
        await fulfillment(of: [entered], timeout: 3)
        let retirement = Task.detached {
            actor.retireAndDrainModelWork()
            retired.signal()
        }
        // A return while the transaction is held would permit a racing wipe.
        XCTAssertEqual(retired.wait(timeout: .now() + 0.05), .timedOut)
        release.signal()
        try await writing.value
        await retirement.value
        XCTAssertEqual(retired.wait(timeout: .now() + 1), .success)
        let check = ModelContext(container)
        XCTAssertEqual(try check.fetchCount(FetchDescriptor<SyncOperation>()), 1)
        for row in try check.fetch(FetchDescriptor<SyncOperation>()) { check.delete(row) }
        try check.save()
        XCTAssertEqual(try check.fetchCount(FetchDescriptor<SyncOperation>()), 0)
    }

    func testScopeChangedBeforeRecoveryStartsDoesNotPermanentlyOccupySlot() async {
        UserDefaults.standard.removeObject(forKey: "currentUserCompanyId")
        let engine = SyncEngine()
        defer { engine.stopForLogoutSync() }
        engine.requestRecovery()
        UserDefaults.standard.set("replacement-user", forKey: "currentUserId")
        engine.requestRecovery()
        await engine.awaitScheduledRecoveryForTesting()
        await engine.awaitScheduledRecoveryForTesting()
        XCTAssertFalse(engine.hasRecoveryTaskForTesting)
        engine.requestRecovery()
        await engine.awaitScheduledRecoveryForTesting()
        XCTAssertFalse(engine.hasRecoveryTaskForTesting)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(OPSSchemaV26.models)
        return try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    private func makeClientDTO() throws -> SupabaseClientDTO {
        try JSONDecoder().decode(SupabaseClientDTO.self,
            from: Data(#"{"id":"client-lifetime","company_id":"lifetime-company","name":"Lifetime fixture"}"#.utf8))
    }
}

private extension DataActor {
    func heldTransactionForLifetimeTest(entered: @Sendable () -> Void, release: DispatchSemaphore) throws {
        try modelContext.transaction {
            let operation = SyncOperation(entityType: "client", entityId: "held-client",
                operationType: "create", payload: Data("{}".utf8), changedFields: [])
            modelContext.insert(operation)
            entered()
            release.wait()
        }
    }
}

@MainActor
private final class LifetimeOnlineConnectivity: ConnectivityManager {
    override var shouldAttemptSync: Bool { true }
}

private actor InboundLifetimeGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
