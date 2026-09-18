//
//  SiteVisitPushRouteTests.swift
//  OPSTests
//
//  CREW SITE VISITS · P1 — site-visit prompts carry `siteVisitId` beside
//  `leadId` from every entry (push tap, cold-launch drain, notification rail)
//  so an assignee without the Leads tab lands on the exact visit. Invented ids.
//

import XCTest
@testable import OPS

final class SiteVisitPushRouteTests: XCTestCase {
    private let leadId = "90909090-1111-4111-8111-909090909090"
    private let visitId = "91919191-2222-4222-8222-919191919191"
    private let userId = "92929292-3333-4333-8333-929292929292"

    func testDeepLinkTypeDecidesTheKindAndABareReminderIsAHeadsUp() {
        XCTAssertEqual(SiteVisitPushRoute.kind(deepLinkType: "site_visit_start", type: "site_visit_reminder"), .start)
        XCTAssertEqual(SiteVisitPushRoute.kind(deepLinkType: " SITE_VISIT_HEADS_UP ", type: nil), .headsUp)
        XCTAssertEqual(SiteVisitPushRoute.kind(deepLinkType: nil, type: "site_visit_reminder"), .headsUp)
        XCTAssertEqual(SiteVisitPushRoute.kind(deepLinkType: nil, type: "site_visit_start"), .start)
        XCTAssertNil(SiteVisitPushRoute.kind(deepLinkType: "leads", type: "lead_assigned"))
        XCTAssertNil(SiteVisitPushRoute.kind(deepLinkType: nil, type: nil))
    }

    func testTheVisitIdIsThePrimaryKeyAndTheLeadRidesAlong() {
        XCTAssertEqual(
            SiteVisitPushRoute.coordinatorLink(kind: .start, leadId: leadId, siteVisitId: visitId),
            .init(entity: "site-visit-start-visit", id: visitId, extraUserInfo: ["leadId": leadId])
        )
        XCTAssertEqual(
            SiteVisitPushRoute.coordinatorLink(kind: .headsUp, leadId: nil, siteVisitId: visitId),
            .init(entity: "site-visit-heads-up-visit", id: visitId, extraUserInfo: [:])
        )
    }

    func testAPushWithoutAVisitIdKeepsTheLeadKeyedRoute() {
        XCTAssertEqual(
            SiteVisitPushRoute.coordinatorLink(kind: .start, leadId: leadId, siteVisitId: "  "),
            .init(entity: "site-visit-start", id: leadId, extraUserInfo: [:])
        )
        XCTAssertEqual(
            SiteVisitPushRoute.coordinatorLink(kind: .headsUp, leadId: leadId, siteVisitId: nil),
            .init(entity: "site-visit-heads-up", id: leadId, extraUserInfo: [:])
        )
        XCTAssertNil(SiteVisitPushRoute.coordinatorLink(kind: .start, leadId: nil, siteVisitId: nil))
    }

    func testRelayUserInfoCarriesOnlyTheIdsThatExist() {
        let both = SiteVisitPushRoute.userInfo(leadId: leadId, siteVisitId: visitId)
        XCTAssertEqual(both["leadId"] as? String, leadId)
        XCTAssertEqual(both["siteVisitId"] as? String, visitId)
        let leadless = SiteVisitPushRoute.userInfo(leadId: nil, siteVisitId: visitId)
        XCTAssertNil(leadless["leadId"])
        XCTAssertEqual(leadless["siteVisitId"] as? String, visitId)
    }

    func testRailDedupeKeyYieldsTheVisitId() {
        XCTAssertEqual(
            LeadNotificationRouteParser.siteVisitId(
                fromDedupeKey: "site_visit:\(visitId.uppercased()):heads_up:\(userId):1790000000"),
            visitId
        )
        XCTAssertEqual(
            LeadNotificationRouteParser.siteVisitId(fromDedupeKey: "site_visit:\(visitId):start:\(userId):1790000000"),
            visitId
        )
        XCTAssertNil(LeadNotificationRouteParser.siteVisitId(fromDedupeKey: "lead_lifecycle:follow_up:\(leadId)"))
        XCTAssertNil(LeadNotificationRouteParser.siteVisitId(fromDedupeKey: "site_visit:not-a-uuid:start"))
        XCTAssertNil(LeadNotificationRouteParser.siteVisitId(fromDedupeKey: nil))
    }

    @MainActor
    func testCoordinatorPostsTheVisitKeyedStartWithTheLeadBesideIt() {
        let center = NotificationCenter()
        let coordinator = DeepLinkCoordinator(notificationCenter: center)
        let link = SiteVisitPushRoute.coordinatorLink(kind: .start, leadId: leadId, siteVisitId: visitId)!

        let dispatched = expectation(
            forNotification: SiteVisitPushRoute.startRelayName,
            object: nil,
            notificationCenter: center
        ) { notification in
            XCTAssertEqual(notification.userInfo?["siteVisitId"] as? String, self.visitId)
            XCTAssertEqual(notification.userInfo?["leadId"] as? String, self.leadId)
            XCTAssertNotNil(notification.userInfo?[DeepLinkCoordinator.deepLinkIdUserInfoKey] as? String)
            return true
        }

        coordinator.receive(entity: link.entity, id: link.id, scheme: "push", extraUserInfo: link.extraUserInfo)

        wait(for: [dispatched], timeout: 1.0)
        XCTAssertEqual(coordinator.pendingLink?.extraUserInfo, ["leadId": leadId],
                       "the stash keeps the lead for a cold-launch drain")
    }

    @MainActor
    func testCoordinatorPostsTheHeadsUpToTheReminderRelay() {
        let center = NotificationCenter()
        let coordinator = DeepLinkCoordinator(notificationCenter: center)

        let dispatched = expectation(
            forNotification: SiteVisitPushRoute.reminderRelayName,
            object: nil,
            notificationCenter: center
        ) { notification in
            XCTAssertEqual(notification.userInfo?["leadId"] as? String, self.leadId)
            return true
        }

        coordinator.receive(entity: "site-visit-heads-up", id: leadId, scheme: "push")

        wait(for: [dispatched], timeout: 1.0)
    }
}
