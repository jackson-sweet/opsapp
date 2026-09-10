import XCTest
@testable import OPS

@MainActor
final class SyncRecoverySchedulingTests: XCTestCase {
    func testRecoveryQueuedDuringUploadRunsOnceAndDoesNotReplaceUploadFollowup() async {
        let coordinator = SyncPushDrainCoordinator()
        let gate = RecoveryTestGate()
        let started = expectation(description: "upload started")
        let recoveryQueued = expectation(description: "recovery queued")
        let uploadQueued = expectation(description: "upload queued")
        var uploads = 0
        var recoveries = 0
        let upload = Task {
            await coordinator.run {
                uploads += 1
                if uploads == 1 {
                    started.fulfill()
                    await gate.wait()
                }
            }
        }
        await fulfillment(of: [started], timeout: 1)
        let repair = Task {
            recoveryQueued.fulfill()
            await coordinator.run(recovery: true) { recoveries += 1 }
        }
        await fulfillment(of: [recoveryQueued], timeout: 1)
        let followup = Task {
            uploadQueued.fulfill()
            await coordinator.run { XCTFail("The active upload owns its followup") }
        }
        await fulfillment(of: [uploadQueued], timeout: 1)
        await gate.release()
        await upload.value
        await repair.value
        await followup.value
        XCTAssertEqual(uploads, 2)
        XCTAssertEqual(recoveries, 1)
    }
}

private actor RecoveryTestGate {
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
