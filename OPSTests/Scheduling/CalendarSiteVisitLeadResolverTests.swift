import XCTest
@testable import OPS

@MainActor
final class CalendarSiteVisitLeadResolverTests: XCTestCase {
    private let userId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    private let companyId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let opportunityId = "e9618f88-ca6b-49ee-8c35-6d260b31c131"
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRemoteLeadDetailsAreResolvedOnceAndPersistedForOfflineRelaunch() async {
        let cache = CalendarSiteVisitLeadCache(directory: directory)
        let expected = CalendarSiteVisitLeadDetails(
            opportunityId: opportunityId,
            companyId: companyId,
            contactName: "Kim Berelliee",
            title: "Estimate",
            address: "903 Collinson St, Victoria, BC, Canada",
            agentSummary: "Current price: $1,650. Replace the damaged front stair rail.",
            leadDescription: "Customer requested a Thursday visit."
        )
        var requests: [[String]] = []
        let online = CalendarSiteVisitLeadResolver(cache: cache) { receivedCompanyId, ids in
            XCTAssertEqual(receivedCompanyId, self.companyId)
            requests.append(ids)
            return [expected]
        }

        let live = await online.refreshDetails(
            opportunityIds: [opportunityId, opportunityId.uppercased()],
            userId: userId,
            companyId: companyId
        )

        XCTAssertEqual(requests, [[opportunityId]])
        XCTAssertEqual(live[opportunityId], expected)

        enum Offline: Error { case unavailable }
        let offline = CalendarSiteVisitLeadResolver(cache: cache) { _, _ in
            throw Offline.unavailable
        }
        let relaunched = await offline.refreshDetails(
            opportunityIds: [opportunityId],
            userId: userId,
            companyId: companyId
        )

        XCTAssertEqual(relaunched[opportunityId], expected)
    }

    func testCacheNeverCrossesOperatorOrCompanyBoundary() {
        let cache = CalendarSiteVisitLeadCache(directory: directory)
        let details = CalendarSiteVisitLeadDetails(
            opportunityId: opportunityId,
            companyId: companyId,
            contactName: "Kim Berelliee",
            title: nil,
            address: "903 Collinson St",
            agentSummary: nil,
            leadDescription: nil
        )

        XCTAssertTrue(cache.save([details], userId: userId, companyId: companyId))
        XCTAssertEqual(cache.load(userId: userId, companyId: companyId), [details])
        XCTAssertTrue(cache.load(userId: "another-user", companyId: companyId).isEmpty)
        XCTAssertTrue(cache.load(userId: userId, companyId: "another-company").isEmpty)
    }
}
