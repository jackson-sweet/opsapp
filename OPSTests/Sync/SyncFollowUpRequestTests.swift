import XCTest
@testable import OPS

@MainActor
final class SyncFollowUpRequestTests: XCTestCase {
    func testBackgroundRequestRemainsPendingUntilForegroundAdmission() async {
        let followUp = SyncFollowUpRequest()
        var foreground = false
        var calls = 0
        followUp.request()
        followUp.scheduleIfAdmitted(canStart: { foreground }) { calls += 1; return true }
        XCTAssertTrue(followUp.isPending)
        XCTAssertEqual(calls, 0)
        foreground = true
        followUp.scheduleIfAdmitted(canStart: { foreground }) { calls += 1; return true }
        await followUp.waitForScheduledWork()
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(followUp.isPending)
    }

    func testBackgroundBeforeTaskStartsDoesNotConsumeRequest() async {
        let followUp = SyncFollowUpRequest()
        var foreground = true
        followUp.request()
        followUp.scheduleIfAdmitted(canStart: { foreground }) { XCTFail("Background replay started"); return true }
        foreground = false
        await followUp.waitForScheduledWork()
        XCTAssertTrue(followUp.isPending)
    }

    func testConcurrentRequestsCoalesceWhileOwnedFollowUpIsRunning() async {
        let followUp = SyncFollowUpRequest()
        let entered = expectation(description: "follow-up entered")
        let gate = FollowUpTestGate()
        var calls = 0
        followUp.request()
        followUp.scheduleIfAdmitted(canStart: { true }) {
            calls += 1
            if calls == 1 { entered.fulfill(); await gate.wait() }
            return true
        }
        await fulfillment(of: [entered], timeout: 2)
        followUp.request()
        followUp.request()
        followUp.request()
        await gate.release()
        await followUp.waitForScheduledWork()
        XCTAssertEqual(calls, 2)
        XCTAssertFalse(followUp.isPending)
    }

    func testCancellationPreservesRetryAndCannotClearReplacementOwner() async {
        let followUp = SyncFollowUpRequest()
        let entered = expectation(description: "first replay entered")
        let gate = FollowUpTestGate()
        followUp.request()
        followUp.scheduleIfAdmitted(canStart: { true }) { entered.fulfill(); await gate.wait(); return true }
        await fulfillment(of: [entered], timeout: 2)
        followUp.cancel(preservingRequest: true)
        XCTAssertTrue(followUp.isPending)
        var resumed = 0
        followUp.scheduleIfAdmitted(canStart: { true }) { resumed += 1; return true }
        await gate.release()
        await followUp.waitForScheduledWork()
        XCTAssertEqual(resumed, 1)
        XCTAssertFalse(followUp.isPending)
    }

    func testFollowUpObtainsFreshExecutionScope() async {
        let followUp = SyncFollowUpRequest()
        let retiredPass = SyncExecutionScope()
        followUp.request()
        await SyncExecutionContext.$scope.withValue(retiredPass) {
            followUp.scheduleIfAdmitted(canStart: { true }) {
                XCTAssertNil(SyncExecutionContext.scope, "Replay must acquire its own allowance")
                return true
            }
            retiredPass.close()
            await followUp.waitForScheduledWork()
        }
    }

    func testDeniedOperationKeepsRequestWithoutSpinningAndResumesOnce() async {
        let followUp = SyncFollowUpRequest()
        var attempts = 0
        followUp.request()
        followUp.scheduleIfAdmitted(canStart: { true }) { attempts += 1; return false }
        await followUp.waitForScheduledWork()
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(followUp.isPending)
        followUp.scheduleIfAdmitted(canStart: { true }) { attempts += 1; return true }
        await followUp.waitForScheduledWork()
        XCTAssertEqual(attempts, 2)
        XCTAssertFalse(followUp.isPending)
    }

    func testAnotherCycleWinningBeforeScheduledStartKeepsRequest() async {
        let followUp = SyncFollowUpRequest()
        var busy = false
        var calls = 0
        followUp.request()
        followUp.scheduleIfAdmitted(canStart: { !busy }) { calls += 1; return true }
        busy = true
        await followUp.waitForScheduledWork()
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(followUp.isPending)
        busy = false
        followUp.scheduleIfAdmitted(canStart: { !busy }) { calls += 1; return true }
        await followUp.waitForScheduledWork()
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(followUp.isPending)
    }

    func testSecondCycleHeldDoesNotSpinWhenAnotherOwnerClaimsAdmission() async {
        let followUp = SyncFollowUpRequest()
        let secondEntered = expectation(description: "second cycle held")
        let gate = FollowUpTestGate()
        var busy = false
        var calls = 0
        followUp.request()
        followUp.scheduleIfAdmitted(canStart: { !busy }) {
            calls += 1
            if calls == 1 { followUp.request() }
            if calls == 2 { secondEntered.fulfill(); await gate.wait() }
            return true
        }
        await fulfillment(of: [secondEntered], timeout: 2)
        followUp.request()
        busy = true
        await gate.release()
        await followUp.waitForScheduledWork()
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(followUp.isPending)
        busy = false
        followUp.scheduleIfAdmitted(canStart: { !busy }) { calls += 1; return true }
        await followUp.waitForScheduledWork()
        XCTAssertEqual(calls, 3)
    }

    func testDeniedAllowanceAndBackgroundAtAdmissionPreserveSingleRetry() async {
        let allowance = ControlledSyncAllowance()
        let execution = SyncExecutionCoordinator(allowance: allowance)
        let followUp = SyncFollowUpRequest()
        var writes = 0
        let attempt: @MainActor () async -> Bool = {
            do {
                try await execution.run(name: "follow-up") {
                    try SyncExecutionContext.withTransaction { writes += 1 }
                }
                return true
            } catch { return false }
        }
        allowance.deniesRequests = true
        followUp.request()
        followUp.scheduleIfAdmitted(canStart: { execution.acceptsOrdinaryWork }, operation: attempt)
        await followUp.waitForScheduledWork()
        XCTAssertTrue(followUp.isPending)
        XCTAssertEqual(allowance.beginCount, 1)
        XCTAssertEqual(writes, 0)

        allowance.deniesRequests = false
        allowance.onBegin = { execution.enterBackground() }
        followUp.scheduleIfAdmitted(canStart: { execution.acceptsOrdinaryWork }, operation: attempt)
        await followUp.waitForScheduledWork()
        XCTAssertTrue(followUp.isPending)
        XCTAssertEqual(writes, 0)
        allowance.onBegin = nil
        execution.enterForeground()
        followUp.scheduleIfAdmitted(canStart: { execution.acceptsOrdinaryWork }, operation: attempt)
        await followUp.waitForScheduledWork()
        XCTAssertFalse(followUp.isPending)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(allowance.beginCount, 3)
        await allowance.waitForEnds(2)
    }
}

private actor FollowUpTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        guard !released else { return }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            XCTFail("Follow-up test gate was not released")
            self.release()
        }
        await withCheckedContinuation { continuation = $0 }
        timeout.cancel()
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
