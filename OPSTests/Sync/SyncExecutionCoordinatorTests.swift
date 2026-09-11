import UIKit
import XCTest
@testable import OPS

@MainActor
final class SyncExecutionCoordinatorTests: XCTestCase {
    func testAllowanceStartsBeforeWorkAndEndsAfterWork() async throws {
        let allowance = ControlledSyncAllowance()
        let coordinator = SyncExecutionCoordinator(allowance: allowance)
        var events: [String] = []
        allowance.onBegin = { events.append("begin") }
        allowance.onEnd = { events.append("end") }

        try await coordinator.run(name: "delta") {
            try SyncExecutionContext.checkCurrent()
            events.append("save")
        }
        await allowance.waitForEnds(1)
        XCTAssertEqual(events, ["begin", "save", "end"])
    }

    func testDeniedAllowanceNeverStartsOperation() async {
        let allowance = ControlledSyncAllowance()
        allowance.deniesRequests = true
        let coordinator = SyncExecutionCoordinator(allowance: allowance)
        do {
            try await coordinator.run(name: "delta") { XCTFail("Denied work started") }
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(allowance.endCount, 0)
    }

    func testBackgroundAdmissionPreservesForegroundResume() async throws {
        let allowance = ControlledSyncAllowance()
        let coordinator = SyncExecutionCoordinator(allowance: allowance)
        coordinator.enterBackground()
        XCTAssertFalse(coordinator.acceptsOrdinaryWork)
        do {
            try await coordinator.run(name: "follow-up") { XCTFail("Background follow-up started") }
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(allowance.beginCount, 0)
        coordinator.enterForeground()
        try await coordinator.run(name: "resumed") { }
        await allowance.waitForEnds(1)
        XCTAssertEqual(allowance.beginCount, 1)
    }

    func testNestedOperationsShareAnAllowance() async throws {
        let allowance = ControlledSyncAllowance()
        let coordinator = SyncExecutionCoordinator(allowance: allowance)
        try await coordinator.run(name: "cycle") {
            try await coordinator.run(name: "delta") {
                try SyncExecutionContext.withTransaction { }
            }
            XCTAssertEqual(allowance.endCount, 0)
        }
        await allowance.waitForEnds(1)
        XCTAssertEqual(allowance.beginCount, 1)
        XCTAssertEqual(allowance.endCount, 1)
    }

    func testExpiredNetworkResponseCannotStartTransactionOrReturnSuccess() async {
        let allowance = ControlledSyncAllowance()
        let coordinator = SyncExecutionCoordinator(allowance: allowance)
        let entered = expectation(description: "network wait entered")
        let gate = SyncExecutionTestGate()
        let operation = Task {
            try await coordinator.run(name: "delta") {
                entered.fulfill()
                await gate.wait()
                try SyncExecutionContext.withTransaction { XCTFail("Expired response wrote data") }
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        allowance.expire()
        await gate.release()
        do { try await operation.value; XCTFail("Expired work reported success") }
        catch { XCTAssertTrue(error is CancellationError) }
        await allowance.waitForEnds(1)
        XCTAssertEqual(allowance.endCount, 1)
    }

    func testExpirationEndsAllowancePromptlyWithoutClaimingTransactionDrained() async {
        let allowance = ControlledSyncAllowance()
        let coordinator = SyncExecutionCoordinator(allowance: allowance)
        let entered = expectation(description: "transaction entered")
        let release = DispatchSemaphore(value: 0)
        var transactionScope: SyncExecutionScope?
        var operationFinished = false
        let operation = Task {
            defer { operationFinished = true }
            try await coordinator.run(name: "delta") {
                let scope = try XCTUnwrap(SyncExecutionContext.scope)
                transactionScope = scope
                try await Task.detached {
                    try scope.withTransaction {
                        entered.fulfill()
                        XCTAssertEqual(release.wait(timeout: .now() + 3), .success, "Transaction test release timed out")
                    }
                }.value
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        allowance.expire()
        // Reaching these statements proves expiration did not synchronously
        // wait on the actor/transaction from the main thread.
        XCTAssertEqual(allowance.endCount, 1, "UIKit expiration must end promptly")
        XCTAssertEqual(transactionScope?.isDrained, false)
        XCTAssertFalse(operationFinished, "An ended assertion is not a completed save")
        release.signal()
        do { try await operation.value; XCTFail("Expected interruption") }
        catch { XCTAssertTrue(error is CancellationError) }
        await allowance.waitForEnds(1)
        XCTAssertEqual(transactionScope?.isDrained, true)
        XCTAssertEqual(allowance.endCount, 1)
    }

    func testBackgroundTimeWithoutCommitHeadroomRejectsNextTransaction() async {
        let allowance = ControlledSyncAllowance()
        allowance.remainingTime = 0
        let coordinator = SyncExecutionCoordinator(allowance: allowance)
        let entered = expectation(description: "operation entered")
        let gate = SyncExecutionTestGate()
        let operation = Task {
            try await coordinator.run(name: "delta") {
                entered.fulfill()
                await gate.wait()
                try SyncExecutionContext.withTransaction { XCTFail("No remaining execution time") }
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        coordinator.enterBackground()
        await gate.release()
        do { try await operation.value; XCTFail("Expected interruption") }
        catch { XCTAssertTrue(error is CancellationError) }
        await allowance.waitForEnds(1)
    }

    func testPositiveHeadroomDeadlineStopsWritesBeforeOSExpiration() async {
        let allowance = ControlledSyncAllowance()
        allowance.remainingTime = 10
        let clock = SyncExecutionTestClock()
        let coordinator = SyncExecutionCoordinator(allowance: allowance, transactionHeadroom: 2, uptime: { clock.now })
        defer { coordinator.enterForeground() }
        var saves = 0
        do {
            try await coordinator.run(name: "delta") {
                coordinator.enterBackground()
                clock.advance(by: 7)
                try SyncExecutionContext.withTransaction { saves += 1 }
                clock.advance(by: 1)
                try SyncExecutionContext.withTransaction { saves += 1 }
            }
            XCTFail("Headroom cutoff must interrupt the pass")
        } catch { XCTAssertTrue(error is CancellationError) }
        await allowance.waitForEnds(1)
        XCTAssertEqual(saves, 1)
    }

    func testCallerCancellationClosesScopeBeforeLateContinuation() async {
        let allowance = ControlledSyncAllowance()
        let coordinator = SyncExecutionCoordinator(allowance: allowance)
        let entered = expectation(description: "operation entered")
        let gate = SyncExecutionTestGate()
        let operation = Task {
            try await coordinator.run(name: "delta") {
                entered.fulfill()
                await gate.wait()
                try SyncExecutionContext.withTransaction { XCTFail("Cancelled response wrote") }
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        operation.cancel()
        await gate.release()
        do { try await operation.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        await allowance.waitForEnds(1)
    }

    func testSystemGrantedTaskCanRunInBackgroundAndExpiresWithoutAnotherAssertion() async {
        let allowance = ControlledSyncAllowance()
        let coordinator = SyncExecutionCoordinator(allowance: allowance)
        coordinator.enterBackground()
        let gate = SyncExecutionTestGate()
        let entered = expectation(description: "system task entered")
        var expiration: (@Sendable () -> Void)?
        let task = Task {
            try await coordinator.runSystemTask(installExpiration: { expiration = $0 }) {
                entered.fulfill()
                await gate.wait()
                try SyncExecutionContext.checkCurrent()
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        expiration?()
        await gate.release()
        do { try await task.value; XCTFail("Expired system task reported success") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(allowance.beginCount, 0)
    }

    func testSystemExpirationBeforeMainActorStartsRejectsAllWork() async {
        let coordinator = SyncExecutionCoordinator(allowance: ControlledSyncAllowance())
        let scope = SyncExecutionScope()
        scope.close() // Synchronous BG callback expiration, before actor admission.
        do {
            try await coordinator.runSystemTask(scope: scope) { XCTFail("Expired queued task started") }
            XCTFail("Expected interruption")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}

@MainActor
final class ControlledSyncAllowance: SyncBackgroundAllowance {
    var remainingTime: TimeInterval = 30
    var deniesRequests = false
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private var expirations: [Int: @MainActor @Sendable () -> Void] = [:]
    private var endWaiters: [(Int, XCTestExpectation)] = []

    func begin(name: String, expiration: @escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier {
        beginCount += 1
        onBegin?()
        guard !deniesRequests else { return .invalid }
        expirations[beginCount] = expiration
        return UIBackgroundTaskIdentifier(rawValue: beginCount)
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        endCount += 1
        XCTAssertNotNil(expirations.removeValue(forKey: identifier.rawValue))
        onEnd?()
        let ready = endWaiters.filter { $0.0 <= endCount }
        endWaiters.removeAll { $0.0 <= endCount }
        ready.forEach { $0.1.fulfill() }
    }

    func expire() { Array(expirations.values).forEach { $0() } }

    func waitForEnds(_ count: Int) async {
        guard endCount < count else { return }
        let ended = XCTestExpectation(description: "allowance ended \(count) times")
        endWaiters.append((count, ended))
        let result = await XCTWaiter.fulfillment(of: [ended], timeout: 3)
        XCTAssertEqual(result, .completed)
        endWaiters.removeAll { $0.1 === ended }
    }
}

actor SyncExecutionTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        guard !released else { return }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            XCTFail("Sync test gate was not released")
            self.release()
        }
        await withCheckedContinuation { continuation = $0 }
        timeout.cancel()
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private final class SyncExecutionTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 100
    var now: TimeInterval { lock.lock(); defer { lock.unlock() }; return value }
    func advance(by duration: TimeInterval) { lock.lock(); value += duration; lock.unlock() }
}
