import SwiftData
import XCTest
@testable import OPS

@MainActor
final class SyncSuspensionRegressionTests: XCTestCase {
    private var previous: [String: Any] = [:]
    private var previousSyncDefaults: [String: Any] = [:]
    private let keys = ["feature.useDataActor", "currentUserId", "currentUserCompanyId"]

    override func setUp() {
        super.setUp()
        previousSyncDefaults = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix("sync.") }
        for key in keys { previous[key] = UserDefaults.standard.object(forKey: key) }
        UserDefaults.standard.set(true, forKey: "feature.useDataActor")
        UserDefaults.standard.set("suspension-user", forKey: "currentUserId")
        UserDefaults.standard.set("suspension-company", forKey: "currentUserCompanyId")
    }

    override func tearDown() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("sync.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for (key, value) in previousSyncDefaults { UserDefaults.standard.set(value, forKey: key) }
        for key in keys {
            if let value = previous[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    func testQueuedDeltaDoesNotStartInBackgroundAndRunsOnceOnForeground() async throws {
        let container = try makeContainer()
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: container)
        let counter = SuspensionPullCounter()
        let gate = SyncExecutionTestGate()
        let entered = expectation(description: "first delta response held")
        await actor.setInboundDeltaForTesting {
            if await counter.increment() == 1 { entered.fulfill(); await gate.wait() }
            return []
        }
        let allowance = ControlledSyncAllowance()
        let execution = SyncExecutionCoordinator(allowance: allowance)
        let engine = SyncEngine(dimensionedPendingSyncer: SuspensionNoopDimensions(), execution: execution)
        engine.configure(modelContext: container.mainContext, connectivity: SuspensionOnlineConnectivity(), dataActor: actor)
        defer { engine.stopForLogoutSync() }

        let first = Task { await engine.triggerSync() }
        await fulfillment(of: [entered], timeout: 3)
        await engine.triggerSync() // This is the queued-follow-up trigger in the IPS.
        execution.enterBackground()
        await gate.release()
        await first.value
        let backgroundCalls = await counter.value
        XCTAssertEqual(backgroundCalls, 1)

        execution.enterForeground()
        await engine.triggerSync()
        let foregroundCalls = await counter.value
        XCTAssertEqual(foregroundCalls, 2, "The pending request is consumed by the foreground pass")
        XCTAssertFalse(engine.isSyncing)
    }

    func testExpirationCannotAdvanceDeltaCursorOrAnnounceSynced() async throws {
        let container = try makeContainer()
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: container)
        let gate = SyncExecutionTestGate()
        let entered = expectation(description: "delta response held")
        await actor.setInboundDeltaForTesting { entered.fulfill(); await gate.wait(); return [] }
        let allowance = ControlledSyncAllowance()
        let execution = SyncExecutionCoordinator(allowance: allowance)
        let engine = SyncEngine(dimensionedPendingSyncer: SuspensionNoopDimensions(), execution: execution)
        engine.configure(modelContext: container.mainContext, connectivity: SuspensionOnlineConnectivity(), dataActor: actor)
        defer { engine.stopForLogoutSync() }
        let cursor = Date(timeIntervalSince1970: 123)
        engine.setLastSyncTimestamp(cursor, for: .client)

        let pull = Task { await engine.pullDelta() }
        await fulfillment(of: [entered], timeout: 3)
        allowance.expire()
        await gate.release()
        await pull.value
        XCTAssertEqual(engine.lastSyncTimestamp(for: .client), cursor)
        XCTAssertEqual(engine.statusText, "Sync paused")
        XCTAssertFalse(engine.hasError, "An execution interruption is not a sync failure")
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(OPSSchemaCurrent.models)
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    func testRecoveryRequestedInsideClosedParentStaysPendingWithoutRescheduling() async throws {
        let container = try makeContainer()
        let allowance = ControlledSyncAllowance()
        let execution = SyncExecutionCoordinator(allowance: allowance)
        let engine = SyncEngine(dimensionedPendingSyncer: SuspensionNoopDimensions(), execution: execution)
        // Recovery is explicitly requested below. Real NWPathMonitor events
        // must not schedule a second, independently admitted recovery while
        // this test checks whether the closed parent's task released its slot.
        engine.configure(modelContext: container.mainContext, connectivity: SuspensionRecoveryConnectivity())
        defer { engine.stopForLogoutSync() }
        let parentScope = SyncExecutionScope()
        await SyncExecutionContext.$scope.withValue(parentScope) {
            engine.requestRecovery()
            parentScope.close()
            engine.requestRecovery()
            await engine.awaitScheduledRecoveryForTesting()
        }
        XCTAssertFalse(engine.hasRecoveryTaskForTesting)
        XCTAssertTrue(engine.hasPendingRecoveryForTesting)
        XCTAssertEqual(allowance.beginCount, 0)
        // A new valid boundary owns the pending recovery; the closed parent's
        // task must neither spin nor poison this independent request.
        engine.requestRecovery()
        await engine.awaitScheduledRecoveryForTesting()
        XCTAssertFalse(engine.hasRecoveryTaskForTesting)
        XCTAssertFalse(engine.hasPendingRecoveryForTesting)
        XCTAssertGreaterThan(allowance.beginCount, 0)
    }

    func testBackgroundProcessingCapturesSessionAfterStartupBindsActor() async throws {
        let container = try makeContainer()
        let execution = SyncExecutionCoordinator(allowance: ControlledSyncAllowance(), initiallyAllowsWork: false)
        let pulls = SuspensionPullCounter()
        let startup = DataActorStartup(modelContainer: container, execution: execution) { actor, isCurrent in
            guard isCurrent() else { throw CancellationError() }
            await actor.setInboundDeltaForTesting { _ = await pulls.increment(); return [] }
        }
        let engine = SyncEngine(dimensionedPendingSyncer: SuspensionNoopDimensions(), execution: execution)
        engine.configure(modelContext: container.mainContext, connectivity: SuspensionOnlineConnectivity())
        engine.setDataActorStartup(startup)
        defer { engine.stopForLogoutSync(); startup.invalidate() }
        let callback = try XCTUnwrap(BackgroundSyncScheduler.shared.onProcessingTask)
        let scope = SyncExecutionScope()
        let timeout = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            XCTFail("Background callback did not finish within the test deadline")
            scope.close()
            startup.invalidate()
        }
        defer { timeout.cancel() }
        let completed = try await execution.runSystemTask(scope: scope) { await callback() }
        XCTAssertTrue(completed, "Binding the prepared actor must not invalidate the admitted background session")
        let count = await pulls.value
        XCTAssertEqual(count, 1)
    }
}

private actor SuspensionPullCounter {
    private(set) var value = 0
    func increment() -> Int { value += 1; return value }
}

@MainActor
private final class SuspensionOnlineConnectivity: ConnectivityManager {
    override var shouldAttemptSync: Bool { true }
}

@MainActor
private final class SuspensionRecoveryConnectivity: ConnectivityManager {
    override var shouldAttemptSync: Bool { false }
}

private final class SuspensionNoopDimensions: DimensionedPendingSyncing {
    func pendingDimensionedAnnotationCount(modelContext: ModelContext) -> Int { 0 }
    func syncPendingDimensions(modelContext: ModelContext) async { }
}
