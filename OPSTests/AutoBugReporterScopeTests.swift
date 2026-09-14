import XCTest
@testable import OPS

@MainActor
final class AutoBugReporterScopeTests: XCTestCase {
    func testCompanySwitchDoesNotSuppressOtherCompanyOrMixCounts() async {
        var identity = AutoBugReportIdentity(companyID: "company-a", userID: "user-a", firebaseUserID: "firebase-A")
        var now = Date(timeIntervalSince1970: 100)
        var sends: [AutoBugReporter.Request] = []
        let reporter = AutoBugReporter(currentIdentity: { identity }, now: { now }, transport: { request in sends.append(request); return true })
        await fire(reporter)
        await fire(reporter) // suppressed for A
        identity = .init(companyID: "company-b", userID: "user-b", firebaseUserID: "firebase-B")
        await fire(reporter)
        XCTAssertEqual(sends.map(\.fireCount), [1, 1])
        XCTAssertEqual(sends.map(\.identity.companyID), ["company-a", "company-b"])
        identity = .init(companyID: "company-a", userID: "user-a", firebaseUserID: "firebase-A")
        now = now.addingTimeInterval(3601)
        await fire(reporter)
        XCTAssertEqual(sends.map(\.fireCount), [1, 1, 2])
    }

    func testScopedSendRejectsReplacementUserEvenWithinSameCompany() async {
        let expected = AutoBugReportIdentity(companyID: "company-a", userID: "user-a", firebaseUserID: "firebase-A")
        var identity = expected
        var sends = 0
        let reporter = AutoBugReporter(currentIdentity: { identity }, transport: { _ in sends += 1; return true })
        identity = .init(companyID: expected.companyID, userID: "user-b", firebaseUserID: "firebase-B")
        await fire(reporter, expectedIdentity: expected)
        XCTAssertEqual(sends, 0)
        await fire(reporter, expectedIdentity: identity)
        XCTAssertEqual(sends, 1, "A rejected old scope cannot poison the new scope's cache")
    }

    func testFirebaseSwitchBeforeLocalAccountChangesRejectsOldReport() async {
        let expected = AutoBugReportIdentity(companyID: "company-a", userID: "user-a", firebaseUserID: "firebase-A")
        let replacement = AutoBugReportIdentity(companyID: expected.companyID, userID: expected.userID, firebaseUserID: "firebase-B")
        var sends = 0
        let reporter = AutoBugReporter(currentIdentity: { replacement }, transport: { _ in sends += 1; return true })
        await fire(reporter, expectedIdentity: expected)
        XCTAssertEqual(sends, 0)
    }

    func testIdentityIsRecheckedImmediatelyBeforeTransport() async {
        let original = AutoBugReportIdentity(companyID: "company-a", userID: "user-a", firebaseUserID: "firebase-A")
        let replacement = AutoBugReportIdentity(companyID: "company-b", userID: "user-b", firebaseUserID: "firebase-B")
        var reads = 0
        var sends = 0
        let reporter = AutoBugReporter(currentIdentity: {
            reads += 1
            return reads == 1 ? original : replacement
        }, transport: { _ in sends += 1; return true })
        await fire(reporter, expectedIdentity: original)
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(reads, 2)
    }

    func testFailedReportCanRetryAndRetainsOccurrenceCount() async {
        let identity = AutoBugReportIdentity(companyID: "company-a", userID: "user-a", firebaseUserID: "firebase-A")
        var counts: [Int] = []
        let reporter = AutoBugReporter(currentIdentity: { identity }, transport: { request in counts.append(request.fireCount); return counts.count > 1 })
        await fire(reporter)
        await fire(reporter)
        await fire(reporter)
        XCTAssertEqual(counts, [1, 2])
    }

    func testOverlappingReportsKeepTheirCountsWithoutOverlappingTransports() async {
        let identity = AutoBugReportIdentity(companyID: "company-a", userID: "user-a", firebaseUserID: "firebase-A")
        let entered = expectation(description: "first transport suspended")
        var release: CheckedContinuation<Void, Never>?
        var now = Date(timeIntervalSince1970: 100)
        var counts: [Int] = []
        let reporter = AutoBugReporter(currentIdentity: { identity }, now: { now }, transport: { request in
            counts.append(request.fireCount)
            if counts.count == 1 {
                await withCheckedContinuation { continuation in
                    release = continuation
                    entered.fulfill()
                }
            }
            return true
        })
        let first = Task { await self.fire(reporter) }
        await fulfillment(of: [entered], timeout: 2)
        await fire(reporter)
        XCTAssertEqual(counts, [1])
        release?.resume()
        await first.value
        now = now.addingTimeInterval(3601)
        await fire(reporter)
        XCTAssertEqual(counts, [1, 2], "The overlapping occurrence survives the first send's acknowledgment")
    }

    private func fire(_ reporter: AutoBugReporter, expectedIdentity: AutoBugReportIdentity? = nil) async {
        await reporter.report(screen: "Sync.projectTask.update", suspectedFile: "SyncBugReporter.swift", errorCode: "PG_42501", summary: "Sync rejected.", expectedIdentity: expectedIdentity)
    }
}
