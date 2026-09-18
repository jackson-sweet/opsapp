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

// MARK: - CREW SITE VISITS P1 · visit-keyed briefs

/// `read_site_visit_briefs` replaces the opportunities read for Schedule: an
/// assignee holds no opportunities grant, and the phone never prunes visits
/// that fell out of reach, so one visit-keyed answer supplies both the lead
/// details and the still-readable visit set. Invented names and ids only.
extension CalendarSiteVisitLeadResolverTests {
    private var visitA: String { "a1a1a1a1-0000-4000-8000-a1a1a1a1a1a1" }
    private var visitB: String { "b2b2b2b2-0000-4000-8000-b2b2b2b2b2b2" }
    private var visitC: String { "c3c3c3c3-0000-4000-8000-c3c3c3c3c3c3" }
    private var otherLeadId: String { "d4d4d4d4-0000-4000-8000-d4d4d4d4d4d4" }

    private func brief(_ visitId: String, lead: String?, name: String? = "Avery Sample") -> SiteVisitBriefDTO {
        SiteVisitBriefDTO(
            siteVisitId: visitId,
            opportunityId: lead,
            contactName: lead == nil ? nil : name,
            title: lead == nil ? nil : "Deck rebuild",
            address: lead == nil ? nil : "8 Placeholder Ave",
            aiSummary: lead == nil ? nil : "Replace the rear stairs.",
            description: lead == nil ? nil : "Asked for a morning visit."
        )
    }

    func testBriefsResolveLeadDetailsByLeadAndTheReadableVisitSet() async {
        let cache = CalendarSiteVisitLeadCache(directory: directory)
        var requests: [[String]] = []
        let resolver = CalendarSiteVisitLeadResolver(cache: cache) { ids in
            requests.append(ids)
            return [self.brief(self.visitA, lead: self.opportunityId), self.brief(self.visitC, lead: nil)]
        }

        let result = await resolver.refreshBriefs(
            visits: [
                CalendarSiteVisitBriefRequest(siteVisitId: visitA.uppercased(), opportunityId: opportunityId),
                CalendarSiteVisitBriefRequest(siteVisitId: visitB, opportunityId: otherLeadId),
                CalendarSiteVisitBriefRequest(siteVisitId: visitC, opportunityId: nil),
            ],
            userId: userId,
            companyId: companyId
        )

        XCTAssertEqual(requests, [[visitA, visitB, visitC].sorted()], "one call, canonical ids")
        XCTAssertEqual(result.readableSiteVisitIds, [visitA, visitC])
        let details = result.detailsByOpportunityId[opportunityId]
        XCTAssertEqual(details?.contactName, "Avery Sample")
        XCTAssertEqual(details?.companyId, companyId)
        XCTAssertEqual(details?.agentSummary, "Replace the rear stairs.")
        XCTAssertEqual(details?.leadDescription, "Asked for a morning visit.")
        XCTAssertNil(result.detailsByOpportunityId[otherLeadId], "an unreadable visit's lead resolves nothing")
    }

    func testASuccessfulBriefIsAuthoritativeForEveryLeadItTouches() async {
        let cache = CalendarSiteVisitLeadCache(directory: directory)
        let stale = CalendarSiteVisitLeadDetails(
            opportunityId: otherLeadId, companyId: companyId, contactName: "Old Name",
            title: nil, address: nil, agentSummary: nil, leadDescription: nil
        )
        XCTAssertTrue(cache.save([stale], userId: userId, companyId: companyId))
        let resolver = CalendarSiteVisitLeadResolver(cache: cache) { _ in [] }

        let result = await resolver.refreshBriefs(
            visits: [CalendarSiteVisitBriefRequest(siteVisitId: visitB, opportunityId: otherLeadId)],
            userId: userId,
            companyId: companyId
        )

        XCTAssertEqual(result.readableSiteVisitIds, [])
        XCTAssertTrue(result.detailsByOpportunityId.isEmpty)
        XCTAssertTrue(cache.load(userId: userId, companyId: companyId).isEmpty,
                      "a lead the answer omits leaves the offline cache too")
    }

    func testAFailedBriefFallsBackToCachedDetailsAndIsNotAuthoritative() async {
        let cache = CalendarSiteVisitLeadCache(directory: directory)
        let online = CalendarSiteVisitLeadResolver(cache: cache) { _ in
            [self.brief(self.visitA, lead: self.opportunityId)]
        }
        let request = [CalendarSiteVisitBriefRequest(siteVisitId: visitA, opportunityId: opportunityId)]
        let live = await online.refreshBriefs(visits: request, userId: userId, companyId: companyId)

        enum Offline: Error { case unavailable }
        let offline = CalendarSiteVisitLeadResolver(cache: cache) { _ in throw Offline.unavailable }
        let relaunched = await offline.refreshBriefs(visits: request, userId: userId, companyId: companyId)

        XCTAssertNil(relaunched.readableSiteVisitIds, "offline says nothing about access")
        XCTAssertEqual(relaunched.detailsByOpportunityId, live.detailsByOpportunityId)
    }

    func testBriefsBatchAtTheServerCapAndFailWholeOnAnyBatchError() async {
        let cache = CalendarSiteVisitLeadCache(directory: directory)
        let visits = (0..<250).map { index in
            CalendarSiteVisitBriefRequest(
                siteVisitId: String(format: "00000000-0000-4000-8000-%012d", index),
                opportunityId: nil
            )
        }
        var batchSizes: [Int] = []
        let resolver = CalendarSiteVisitLeadResolver(cache: cache) { ids in
            batchSizes.append(ids.count)
            return ids.map { self.brief($0, lead: nil) }
        }
        let result = await resolver.refreshBriefs(visits: visits, userId: userId, companyId: companyId)
        XCTAssertEqual(batchSizes, [200, 50])
        XCTAssertEqual(result.readableSiteVisitIds?.count, 250)

        enum Flaky: Error { case dropped }
        var calls = 0
        let flaky = CalendarSiteVisitLeadResolver(cache: cache) { ids in
            calls += 1
            if calls == 2 { throw Flaky.dropped }
            return ids.map { self.brief($0, lead: nil) }
        }
        let partial = await flaky.refreshBriefs(visits: visits, userId: userId, companyId: companyId)
        XCTAssertNil(partial.readableSiteVisitIds, "half an answer is not an authoritative answer")
    }

    func testRowsForVisitsThatWereNotRequestedAreIgnored() async {
        let cache = CalendarSiteVisitLeadCache(directory: directory)
        let resolver = CalendarSiteVisitLeadResolver(cache: cache) { _ in
            [self.brief(self.visitA, lead: self.opportunityId), self.brief(self.visitB, lead: self.otherLeadId)]
        }
        let result = await resolver.refreshBriefs(
            visits: [CalendarSiteVisitBriefRequest(siteVisitId: visitA, opportunityId: opportunityId)],
            userId: userId,
            companyId: companyId
        )
        XCTAssertEqual(result.readableSiteVisitIds, [visitA])
        XCTAssertNil(result.detailsByOpportunityId[otherLeadId])
    }

    func testScheduleReadabilityHidesOnlyWhatASuccessfulAnswerExcluded() {
        var readability = CalendarSiteVisitReadability()
        XCTAssertTrue(readability.isVisible(siteVisitId: visitA), "before any answer, everything shows")

        readability.record(readableSiteVisitIds: [visitA.uppercased()], requestedSiteVisitIds: [visitA, visitB])
        XCTAssertTrue(readability.isVisible(siteVisitId: visitA))
        XCTAssertFalse(readability.isVisible(siteVisitId: visitB.uppercased()))
        XCTAssertTrue(readability.isVisible(siteVisitId: visitC), "never asked about, still shows")

        readability.record(readableSiteVisitIds: nil, requestedSiteVisitIds: [visitA, visitB])
        XCTAssertFalse(readability.isVisible(siteVisitId: visitB), "offline, the last answer stands")

        readability.record(readableSiteVisitIds: [visitA, visitB], requestedSiteVisitIds: [visitA, visitB])
        XCTAssertTrue(readability.isVisible(siteVisitId: visitB), "access restored, the visit returns")

        XCTAssertEqual(
            readability.visible([visitA, visitB, visitC], siteVisitId: { $0 }),
            [visitA, visitB, visitC]
        )
        readability.record(readableSiteVisitIds: [], requestedSiteVisitIds: [visitC])
        XCTAssertEqual(readability.visible([visitA, visitB, visitC], siteVisitId: { $0 }), [visitA, visitB])

        readability.reset()
        XCTAssertTrue(readability.isVisible(siteVisitId: visitC))
    }
}
