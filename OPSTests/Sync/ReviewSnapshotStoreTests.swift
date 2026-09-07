import XCTest
@testable import OPS

@MainActor
final class ReviewSnapshotStoreTests: XCTestCase {
    private final class ContainerToken {}
    private let token = ContainerToken()
    private let otherToken = ContainerToken()
    private let now = Date(timeIntervalSince1970: 1_783_345_200)

    private func request(user: String = "operator", company: String = "company", otherContainer: Bool = false,
                         access: ReviewSnapshotAccess? = nil, at: Date? = nil, threshold: Int = 14) -> ReviewSnapshotRequest {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = at ?? now
        return ReviewSnapshotRequest(scope: ReviewSnapshotScope(
            containerID: ObjectIdentifier(otherContainer ? otherToken : token), companyID: company, userID: user,
            access: access ?? ReviewSnapshotAccess(canViewAllTasks: true, taskEditScope: "all", canAssignTasks: true,
                taskStatusScope: "all", calendarEditScope: "all", projectEditScope: "all"),
            calendar: calendar, day: calendar.startOfDay(for: date), overdueThresholdDays: threshold,
            staleEstimateThresholdDays: 30, reminderFrequencyDays: 7, taskUnlockThreshold: 5, paymentUnlockThreshold: 5
        ), now: date)
    }

    private func snapshot(_ request: ReviewSnapshotRequest, count: Int, expiry: Date = .distantFuture) -> ReviewSnapshot {
        ReviewSnapshot(scope: request.scope, counts: ReviewSnapshotCounts(taskReviewCount: count),
            computedAt: request.now, nextEligibilityChangeAt: expiry)
    }

    private final class Gate {
        let started: [XCTestExpectation]
        var requests: [ReviewSnapshotRequest] = []
        var continuations: [Int: CheckedContinuation<ReviewSnapshot?, Error>] = [:]
        init(_ started: [XCTestExpectation]) { self.started = started }
        func read(_ request: ReviewSnapshotRequest) async throws -> ReviewSnapshot? {
            let index = requests.count
            requests.append(request)
            return try await withCheckedThrowingContinuation { continuation in
                continuations[index] = continuation
                if index < started.count { started[index].fulfill() }
            }
        }
        func finish(_ index: Int, _ result: ReviewSnapshot?) { continuations.removeValue(forKey: index)?.resume(returning: result) }
        func fail(_ index: Int) { continuations.removeValue(forKey: index)?.resume(throwing: URLError(.cannotOpenFile)) }
    }

    func testConcurrentConsumersJoinOneReadAndReuseTheCachedValue() async {
        let scope = request()
        let gate = Gate([expectation(description: "read started")])
        let store = ReviewSnapshotStore(requestProvider: { scope }, reader: gate.read)
        let first = Task { await store.value() }
        await fulfillment(of: gate.started, timeout: 2)
        XCTAssertTrue(store.isLoading)
        XCTAssertNil(store.snapshot, "Loading is not a zero count")
        let joined = expectation(description: "second consumer entered")
        let second = Task { joined.fulfill(); return await store.value() }
        await fulfillment(of: [joined], timeout: 2)
        XCTAssertEqual(gate.requests.count, 1)
        let result = snapshot(scope, count: 7)
        gate.finish(0, result)
        let a = await first.value
        let b = await second.value
        let cached = await store.value()
        XCTAssertEqual(a, result)
        XCTAssertEqual(b, result)
        XCTAssertEqual(cached, result)
        XCTAssertEqual(gate.requests.count, 1)
        XCTAssertFalse(store.isLoading)
    }

    func testBurstDuringReadRejectsObsoleteResultAndRunsOneFollowup() async {
        let scope = request()
        let gate = Gate([expectation(description: "first"), expectation(description: "followup")])
        let store = ReviewSnapshotStore(requestProvider: { scope }, reader: gate.read)
        let work = Task { await store.value() }
        await fulfillment(of: [gate.started[0]], timeout: 2)
        for _ in 0..<20 { store.invalidate() }
        gate.finish(0, snapshot(scope, count: 10))
        await fulfillment(of: [gate.started[1]], timeout: 2)
        XCTAssertNil(store.snapshot, "An invalidated intermediate count must never repaint or report")
        gate.finish(1, snapshot(scope, count: 0))
        let result = await work.value
        XCTAssertEqual(result?.counts.taskReviewCount, 0)
        XCTAssertEqual(gate.requests.count, 2)
    }

    func testAccountReplacementClearsCacheAndRejectsLateOldRead() async {
        var current = request()
        let oldRequest = current
        let gate = Gate([expectation(description: "old"), expectation(description: "new")])
        let store = ReviewSnapshotStore(requestProvider: { current }, reader: gate.read)
        let old = Task { await store.value() }
        await fulfillment(of: [gate.started[0]], timeout: 2)
        current = request(user: "other", company: "other-company", otherContainer: true)
        store.scopeDidChange()
        XCTAssertNil(store.snapshot)
        let new = Task { await store.value() }
        await fulfillment(of: [gate.started[1]], timeout: 2)
        let result = snapshot(current, count: 2)
        gate.finish(1, result)
        let fresh = await new.value
        gate.finish(0, snapshot(oldRequest, count: 99))
        let stale = await old.value
        XCTAssertEqual(fresh, result)
        XCTAssertNil(stale)
        XCTAssertEqual(store.snapshot, result)
    }

    func testPermissionContainerThresholdAndDayChangesEachRetireOldSnapshot() async {
        var current = request()
        var reads = 0
        let store = ReviewSnapshotStore(requestProvider: { current }, reader: { request in
            reads += 1
            return ReviewSnapshot(scope: request.scope, counts: .init(), computedAt: request.now)
        })
        _ = await store.value()
        let restricted = ReviewSnapshotAccess(canViewAllTasks: false, taskEditScope: "assigned", canAssignTasks: false,
            taskStatusScope: nil, calendarEditScope: nil, projectEditScope: nil)
        for changed in [request(access: restricted), request(otherContainer: true), request(threshold: 45),
                        request(at: now.addingTimeInterval(86_400))] {
            current = changed
            store.scopeDidChange()
            XCTAssertNil(store.snapshot)
            let result = await store.value()
            XCTAssertEqual(result?.scope, changed.scope)
        }
        XCTAssertEqual(reads, 5)
    }

    func testFailureKeepsLastBadgeButCannotReportItOrInventZero() async {
        let scope = request()
        var fail = false
        let result = snapshot(scope, count: 9)
        let store = ReviewSnapshotStore(requestProvider: { scope }, reader: { _ in
            if fail { throw URLError(.cannotOpenFile) }
            return result
        })
        _ = await store.value()
        fail = true
        store.invalidate()
        let failed = await store.value()
        XCTAssertNil(failed)
        XCTAssertEqual(store.snapshot, result)
        XCTAssertTrue(store.isUnavailable)
        XCTAssertFalse(store.isCurrent(result))
        let spy = SyncSpy()
        await store.report(syncer: spy).value
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testSameDayEligibilityExpiryForcesFreshReadBeforeAnyReport() async {
        var current = request()
        let expiry = now.addingTimeInterval(60)
        var reads = 0
        let store = ReviewSnapshotStore(requestProvider: { current }, reader: { request in
            reads += 1
            return ReviewSnapshot(scope: request.scope, counts: .init(overduePaymentCount: reads - 1),
                computedAt: request.now, nextEligibilityChangeAt: reads == 1 ? expiry : .distantFuture)
        })
        let before = await store.value()
        current = request(at: expiry)
        XCTAssertEqual(current.scope, before?.scope, "Same calendar day and permissions")
        XCTAssertFalse(store.isCurrent(before!))
        let after = await store.value()
        XCTAssertEqual(after?.counts.overduePaymentCount, 1)
        XCTAssertEqual(reads, 2)
    }

    func testLogoutWhileAwaitingReaderPublishesNothing() async {
        var current: ReviewSnapshotRequest? = request()
        let original = current!
        let gate = Gate([expectation(description: "read")])
        let store = ReviewSnapshotStore(requestProvider: { current }, reader: gate.read)
        let work = Task { await store.value() }
        await fulfillment(of: gate.started, timeout: 2)
        current = nil
        gate.finish(0, snapshot(original, count: 12))
        let result = await work.value
        XCTAssertNil(result)
        XCTAssertNil(store.snapshot)
    }

    private final class SyncSpy: ReviewStackSyncing {
        var calls: [(String, Int)] = []
        var afterCall: (() -> Void)?
        func syncReviewStack(stack: String, count: Int) async throws -> String {
            calls.append((stack, count))
            afterCall?()
            return "kept"
        }
    }

    private final class PausingSyncer: ReviewStackSyncing {
        let started: XCTestExpectation
        var calls: [(String, Int)] = []
        var continuation: CheckedContinuation<Void, Never>?
        init(started: XCTestExpectation) { self.started = started }
        func syncReviewStack(stack: String, count: Int) async throws -> String {
            calls.append((stack, count))
            if calls.count == 1 {
                await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    started.fulfill()
                }
            }
            return "kept"
        }
    }

    func testReportsSerializeAndCoalesceWhileNewerCountsReplaceOldSequence() async {
        let request = request()
        var count = 8
        let store = ReviewSnapshotStore(requestProvider: { request }, reader: { request in
            ReviewSnapshot(scope: request.scope, counts: .init(taskReviewCount: count), computedAt: request.now)
        })
        _ = await store.value()
        let syncer = PausingSyncer(started: expectation(description: "transport paused"))
        let reporting = store.report(syncer: syncer)
        await fulfillment(of: [syncer.started], timeout: 2)
        for _ in 0..<20 { store.report(syncer: syncer) }
        count = 0
        store.invalidate()
        _ = await store.value()
        XCTAssertEqual(syncer.calls.count, 1, "A second report cannot overlap the suspended first RPC")
        syncer.continuation?.resume()
        syncer.continuation = nil
        await reporting.value
        XCTAssertEqual(syncer.calls.map(\.0), ["task_review_stack", "task_review_stack", "payment_review_stack", "unscheduled_review_stack"])
        XCTAssertEqual(syncer.calls.map(\.1), [8, 0, 0, 0], "Only one fresh three-stack follow-up serves the burst")
    }

    func testValidZeroReportsAllStacksAndAccountChangeStopsRemainingCalls() async {
        var current: ReviewSnapshotRequest? = request()
        let scope = current!
        let store = ReviewSnapshotStore(requestProvider: { current }, reader: { request in
            ReviewSnapshot(scope: request.scope, counts: .init(), computedAt: request.now)
        })
        let spy = SyncSpy()
        await store.report(syncer: spy).value
        XCTAssertEqual(spy.calls.map(\.0), ["task_review_stack", "payment_review_stack", "unscheduled_review_stack"])
        XCTAssertEqual(spy.calls.map(\.1), [0, 0, 0])
        let changed = SyncSpy()
        changed.afterCall = { current = nil }
        await store.report(syncer: changed).value
        XCTAssertEqual(changed.calls.count, 1, "Old scope cannot continue reporting after an await")
        XCTAssertEqual(store.snapshot?.scope, scope.scope)
    }
}
