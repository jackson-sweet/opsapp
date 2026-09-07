import SwiftData
import XCTest
@testable import OPS

@MainActor
final class DataActorStartupTests: XCTestCase {
    private var previousDefaults: [String: Any] = [:]
    private let defaultKeys = ["feature.useDataActor", "currentUserId", "currentUserCompanyId"]

    override func setUp() {
        super.setUp()
        for key in defaultKeys { previousDefaults[key] = UserDefaults.standard.object(forKey: key) }
        UserDefaults.standard.set(true, forKey: "feature.useDataActor")
        UserDefaults.standard.set("startup-user", forKey: "currentUserId")
        UserDefaults.standard.removeObject(forKey: "currentUserCompanyId")
    }

    override func tearDown() {
        for key in defaultKeys {
            if let value = previousDefaults[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        previousDefaults = [:]
        super.tearDown()
    }

    func testPendingBootstrapCannotClaimThroughLegacyOrUnpreparedActor() async throws {
        let container = try makeContainer()
        let operation = try makeOperation(in: container.mainContext)
        let preparing = expectation(description: "configured actor entered preparation")
        let pushed = expectation(description: "configured actor delivered queued operation")
        let gate = DataActorStartupGate()
        let startup = DataActorStartup(modelContainer: container) { actor, _ in
            let configuredOffMain = await actor.startupConfigurationProbe()
            XCTAssertTrue(configuredOffMain)
            await actor.setOutboundPushForTesting { _, _, _, _ in
                XCTAssertFalse(Thread.isMainThread)
                pushed.fulfill()
            }
            preparing.fulfill()
            await gate.wait()
        }
        let engine = SyncEngine()
        engine.setDataActorStartup(startup)
        engine.configure(modelContext: container.mainContext, connectivity: StartupOnlineConnectivity())
        defer { engine.stopForLogoutSync() }
        await fulfillment(of: [preparing], timeout: 3)
        let pushStarted = expectation(description: "first sync entered")
        let push = Task {
            pushStarted.fulfill()
            await engine.pushPending()
        }
        await fulfillment(of: [pushStarted], timeout: 3)
        XCTAssertEqual(operation.status, "pending", "Neither legacy nor an actor still preparing may claim")
        XCTAssertNil(operation.lastAttemptedAt)
        await gate.release()
        await push.value
        await fulfillment(of: [pushed], timeout: 3)
        let fresh = ModelContext(container)
        let row = try XCTUnwrap(fresh.fetch(FetchDescriptor<SyncOperation>()).first)
        XCTAssertEqual(row.status, "completed")
        XCTAssertEqual(row.retryCount, 0)
    }

    func testInvalidatedStartupCannotPublishAfterPreparationReturns() async throws {
        let container = try makeContainer()
        let preparing = expectation(description: "preparation suspended")
        let gate = DataActorStartupGate()
        let startup = DataActorStartup(modelContainer: container) { _, _ in
            preparing.fulfill()
            await gate.wait()
        }
        let waiting = Task { await startup.value() }
        await fulfillment(of: [preparing], timeout: 3)
        startup.invalidate()
        await gate.release()
        let result = await waiting.value
        XCTAssertNil(result)
        XCTAssertFalse(startup.isCurrent)
    }

    func testAccountChangedDuringReadinessWaitDoesNotSendOldQueue() async throws {
        let container = try makeContainer()
        let operation = try makeOperation(in: container.mainContext)
        let preparing = expectation(description: "preparation suspended")
        let gate = DataActorStartupGate()
        let startup = DataActorStartup(modelContainer: container) { actor, _ in
            await actor.setOutboundPushForTesting { _, _, _, _ in XCTFail("Old-account waiter sent work") }
            preparing.fulfill()
            await gate.wait()
        }
        let engine = SyncEngine()
        engine.setDataActorStartup(startup)
        engine.configure(modelContext: container.mainContext, connectivity: StartupOnlineConnectivity())
        defer { engine.stopForLogoutSync() }
        await fulfillment(of: [preparing], timeout: 3)
        let entered = expectation(description: "sync waiter entered")
        let push = Task { entered.fulfill(); await engine.pushPending() }
        await fulfillment(of: [entered], timeout: 3)
        UserDefaults.standard.set("replacement-user", forKey: "currentUserId")
        await gate.release()
        await push.value
        XCTAssertEqual(operation.status, "pending")
        XCTAssertNil(operation.lastAttemptedAt)
    }

    func testControllerPublishesOnlyTheReplacementContainerAfterDelayedStartup() async throws {
        let first = try makeContainer()
        let replacement = try makeContainer()
        let firstID = ObjectIdentifier(first)
        let preparing = expectation(description: "first container preparation suspended")
        let gate = DataActorStartupGate()
        let controller = DataController(dataActorPreparation: { actor, _ in
            if ObjectIdentifier(actor.modelContainer) == firstID {
                preparing.fulfill()
                await gate.wait()
            }
        })
        controller.setModelContext(first.mainContext)
        await fulfillment(of: [preparing], timeout: 3)
        XCTAssertNil(controller.dataActor, "Construction alone is not readiness")
        let oldWaiterEntered = expectation(description: "old controller waiter entered")
        let oldWaiter = Task {
            oldWaiterEntered.fulfill()
            return await controller.readyDataActor()
        }
        await fulfillment(of: [oldWaiterEntered], timeout: 3)
        controller.setModelContext(replacement.mainContext)
        let readyActor = await controller.readyDataActor()
        let newActor = try XCTUnwrap(readyActor)
        XCTAssertTrue(newActor.modelContainer === replacement)
        let configuredOffMain = await newActor.startupConfigurationProbe()
        XCTAssertTrue(configuredOffMain)
        await gate.release()
        let oldResult = await oldWaiter.value
        XCTAssertNil(oldResult, "Old container waiters must not publish into the replacement session")
        XCTAssertTrue(controller.dataActor?.modelContainer === replacement)
        controller.syncEngine.stopForLogoutSync()
    }

    func testLogoutStopsPendingControllerPublication() async throws {
        let container = try makeContainer()
        let preparing = expectation(description: "controller preparation suspended")
        let gate = DataActorStartupGate()
        let controller = DataController(dataActorPreparation: { _, _ in
            preparing.fulfill()
            await gate.wait()
        })
        controller.setModelContext(container.mainContext)
        await fulfillment(of: [preparing], timeout: 3)
        controller.syncEngine.stopForLogoutSync()
        await gate.release()
        let result = await controller.readyDataActor()
        XCTAssertNil(result)
        XCTAssertNil(controller.dataActor)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(OPSSchemaV26.models)
        return try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    private func makeOperation(in context: ModelContext) throws -> SyncOperation {
        // Valid JSON, deliberately missing required ClientDTO fields: a broken
        // legacy fallback fails decoding before it can make a real request.
        let operation = SyncOperation(entityType: "client", entityId: UUID().uuidString.lowercased(),
            operationType: "create", payload: Data("{}".utf8), changedFields: [])
        context.insert(operation)
        try context.save()
        return operation
    }
}

private extension DataActor {
    func startupConfigurationProbe() -> Bool {
        !Thread.isMainThread && !modelContext.autosaveEnabled
    }
}

@MainActor
private final class StartupOnlineConnectivity: ConnectivityManager {
    override var shouldAttemptSync: Bool { true }
}

private actor DataActorStartupGate {
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
