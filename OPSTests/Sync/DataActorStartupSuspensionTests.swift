import SwiftData
import XCTest
@testable import OPS

@MainActor
final class DataActorStartupSuspensionTests: XCTestCase {
    func testInterruptedPreparationWaitsForForegroundAndBecomesReady() async throws {
        let schema = Schema(OPSSchemaCurrent.models)
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let allowance = ControlledSyncAllowance()
        let coordinator = SyncExecutionCoordinator(allowance: allowance)
        let entered = expectation(description: "preparation entered")
        let finished = expectation(description: "startup ready after foreground")
        let gate = SyncExecutionTestGate()
        let calls = StartupSuspensionCounter()
        let startup = DataActorStartup(modelContainer: container, execution: coordinator) { _, isCurrent in
            if await calls.increment() == 1 { entered.fulfill(); await gate.wait() }
            guard isCurrent() else { throw CancellationError() }
        }
        defer { startup.invalidate() }
        let reader = Task {
            let actor = await startup.value()
            XCTAssertNotNil(actor)
            finished.fulfill()
        }
        defer { reader.cancel() }
        await fulfillment(of: [entered], timeout: 3)
        coordinator.enterBackground()
        allowance.expire()
        await gate.release()
        coordinator.enterForeground()
        await fulfillment(of: [finished], timeout: 3)
        let attempts = await calls.value
        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(startup.isCurrent)
    }

    func testLogoutCancelsStartupWaitingInBackground() async throws {
        let schema = Schema(OPSSchemaCurrent.models)
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let allowance = ControlledSyncAllowance()
        let coordinator = SyncExecutionCoordinator(allowance: allowance, initiallyAllowsWork: false)
        let startup = DataActorStartup(modelContainer: container, execution: coordinator) { _, _ in XCTFail("Background preparation started") }
        let completed = expectation(description: "cancelled startup waiter returned")
        let reader = Task {
            let actor = await startup.value()
            XCTAssertNil(actor)
            completed.fulfill()
        }
        defer { reader.cancel() }
        startup.invalidate()
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(allowance.beginCount, 0)
    }

    func testColdBackgroundStartupUsesSystemGrantWithoutOrdinaryAssertion() async throws {
        let schema = Schema(OPSSchemaCurrent.models)
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let allowance = ControlledSyncAllowance()
        let coordinator = SyncExecutionCoordinator(allowance: allowance, initiallyAllowsWork: false)
        let grant = SyncExecutionScope()
        let startup = DataActorStartup(modelContainer: container, execution: coordinator) { _, isCurrent in
            XCTAssertTrue(isCurrent())
            XCTAssertTrue(SyncExecutionContext.scope === grant)
        }
        defer { startup.invalidate() }
        let ready = try await boundedSystemReadiness(coordinator, scope: grant, startup: startup)
        XCTAssertNotNil(ready)
        XCTAssertEqual(allowance.beginCount, 0)
        XCTAssertFalse(coordinator.acceptsOrdinaryWork)
    }

    func testExpiredSystemReadinessWaitReturnsBeforeNetworkAndRetriesWithNewGrant() async throws {
        let schema = Schema(OPSSchemaCurrent.models)
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let coordinator = SyncExecutionCoordinator(allowance: ControlledSyncAllowance(), initiallyAllowsWork: false)
        let entered = expectation(description: "background preparation response held")
        let expiredReturned = expectation(description: "expired readiness waiter returned promptly")
        let gate = SyncExecutionTestGate()
        let calls = StartupSuspensionCounter()
        let startup = DataActorStartup(modelContainer: container, execution: coordinator) { _, isCurrent in
            if await calls.increment() == 1 { entered.fulfill(); await gate.wait() }
            guard isCurrent() else { throw CancellationError() }
        }
        defer { startup.invalidate() }
        let grant = SyncExecutionScope()
        let first = Task {
            do {
                _ = try await coordinator.runSystemTask(scope: grant) { await startup.value() }
                XCTFail("Expired readiness reported success")
            } catch { XCTAssertTrue(error is CancellationError) }
            expiredReturned.fulfill()
        }
        defer { first.cancel() }
        await fulfillment(of: [entered], timeout: 2)
        grant.close()
        // The network gate remains held here: caller cancellation must not wait
        // for shared preparation, and also must not retire the startup boundary.
        await fulfillment(of: [expiredReturned], timeout: 2)
        XCTAssertTrue(startup.isCurrent)
        await gate.release()
        let ready = try await boundedSystemReadiness(coordinator, scope: SyncExecutionScope(), startup: startup)
        XCTAssertNotNil(ready)
        let attempts = await calls.value
        XCTAssertEqual(attempts, 2)
    }

    func testExpiredBorrowedGrantResumesUnderAlreadyActiveNewerGrant() async throws {
        let schema = Schema(OPSSchemaCurrent.models)
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let coordinator = SyncExecutionCoordinator(allowance: ControlledSyncAllowance(), initiallyAllowsWork: false)
        let oldGrant = SyncExecutionScope()
        let newGrant = SyncExecutionScope()
        let firstEntered = expectation(description: "startup borrowed old grant")
        let secondEntered = expectation(description: "new grant already waiting for readiness")
        let secondFinished = expectation(description: "new grant completed readiness")
        let gate = SyncExecutionTestGate()
        let calls = StartupSuspensionCounter()
        let startup = DataActorStartup(modelContainer: container, execution: coordinator) { _, isCurrent in
            if await calls.increment() == 1 {
                XCTAssertTrue(SyncExecutionContext.scope === oldGrant)
                firstEntered.fulfill()
                await gate.wait()
            } else {
                XCTAssertTrue(SyncExecutionContext.scope === newGrant)
            }
            guard isCurrent() else { throw CancellationError() }
        }
        defer { startup.invalidate() }
        let first = Task {
            do { _ = try await coordinator.runSystemTask(scope: oldGrant) { await startup.value() } }
            catch { XCTAssertTrue(error is CancellationError) }
        }
        defer { first.cancel() }
        await fulfillment(of: [firstEntered], timeout: 2)
        let second = Task {
            do {
                let ready = try await coordinator.runSystemTask(scope: newGrant) {
                    secondEntered.fulfill()
                    return await startup.value()
                }
                XCTAssertNotNil(ready)
            } catch { XCTFail("Newer live grant failed: \(error)") }
            secondFinished.fulfill()
        }
        defer { second.cancel() }
        await fulfillment(of: [secondEntered], timeout: 2)
        let latest = try await coordinator.waitForStartupAdmission()
        XCTAssertTrue(latest.scope === newGrant, "Selection must prefer the newest live grant")
        oldGrant.close()
        await gate.release()
        await fulfillment(of: [secondFinished], timeout: 3)
        let attempts = await calls.value
        XCTAssertEqual(attempts, 2)
    }

    private func boundedSystemReadiness(
        _ coordinator: SyncExecutionCoordinator,
        scope: SyncExecutionScope,
        startup: DataActorStartup
    ) async throws -> DataActor? {
        let timeout = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            XCTFail("System readiness did not complete within the test deadline")
            scope.close()
            startup.invalidate()
        }
        defer { timeout.cancel() }
        return try await coordinator.runSystemTask(scope: scope) { await startup.value() }
    }
}

private actor StartupSuspensionCounter {
    private(set) var value = 0
    func increment() -> Int { value += 1; return value }
}
