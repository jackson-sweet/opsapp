//
//  LeadNotificationRouteParserTests.swift
//  OPSTests
//
//  Covers the pure-string resolution that decides where a lead/opportunity
//  notification tap lands. Cases mirror the real production payload shapes
//  verified against prod `notifications` (257 leads_waiting rows):
//   • /pipeline?opportunityId=<uuid>            → opportunity id in url
//   • lead_lifecycle:...:<opp-uuid> dedupe key  → opportunity id in dedupe key
//   • /inbox/<thread-uuid>                       → email thread (resolve later)
//   • destructive-candidate / settings rows      → nil (Job Board fallback)
//

import XCTest
@testable import OPS

final class LeadNotificationRouteParserTests: XCTestCase {

    private let oppId = "1fe62667-53dd-43aa-a956-1b3f7066931a"
    private let threadId = "ce7031fb-0be3-4f80-8ac0-1d0ef1737b20"

    // MARK: - isLeadNotification

    func testDominantLeadRowDetectedByTypeWhenDeepLinkNull() {
        // The 257-row production reality: type=leads_waiting, deep_link_type=NULL.
        XCTAssertTrue(
            LeadNotificationRouteParser.isLeadNotification(type: "leads_waiting", deepLinkType: nil)
        )
    }

    func testDetectedByDeepLinkType() {
        XCTAssertTrue(LeadNotificationRouteParser.isLeadNotification(type: "something", deepLinkType: "lead"))
        XCTAssertTrue(LeadNotificationRouteParser.isLeadNotification(type: "x", deepLinkType: "opportunities"))
    }

    func testLifecycleTypesDetected() {
        for t in ["lead_created", "lead_updated", "lead_follow_up_due",
                  "opportunity_created", "opportunity_updated", "opportunity_follow_up_due",
                  "pipeline_complete"] {
            XCTAssertTrue(
                LeadNotificationRouteParser.isLeadNotification(type: t, deepLinkType: nil),
                "expected \(t) to be a lead notification"
            )
        }
    }

    func testNonLeadNotificationNotDetected() {
        XCTAssertFalse(LeadNotificationRouteParser.isLeadNotification(type: "expense_submitted", deepLinkType: nil))
        XCTAssertFalse(LeadNotificationRouteParser.isLeadNotification(type: nil, deepLinkType: nil))
        XCTAssertFalse(LeadNotificationRouteParser.isLeadNotification(type: "invoice_overdue", deepLinkType: "invoice"))
    }

    // MARK: - opportunityId(fromActionUrl:)

    func testOpportunityIdFromPipelineQueryParam() {
        let url = "/pipeline?opportunityId=\(oppId)"
        XCTAssertEqual(LeadNotificationRouteParser.opportunityId(fromActionUrl: url), oppId)
    }

    func testOpportunityIdFromLeadIdQueryParam() {
        XCTAssertEqual(
            LeadNotificationRouteParser.opportunityId(fromActionUrl: "/pipeline?leadId=\(oppId)"),
            oppId
        )
    }

    func testOpportunityIdFromGenericIdQueryParam() {
        XCTAssertEqual(
            LeadNotificationRouteParser.opportunityId(fromActionUrl: "ops://leads?id=\(oppId)"),
            oppId
        )
    }

    func testOpportunityIdFromOpsLeadsPath() {
        XCTAssertEqual(
            LeadNotificationRouteParser.opportunityId(fromActionUrl: "ops://leads/\(oppId)"),
            oppId
        )
    }

    func testOpportunityIdFromOpsOpportunitiesPath() {
        XCTAssertEqual(
            LeadNotificationRouteParser.opportunityId(fromActionUrl: "ops://opportunities/\(oppId)"),
            oppId
        )
    }

    func testOpportunityIdNilForInboxUrl() {
        // Documents WHY thread resolution is needed: the /inbox/<uuid> tail is a
        // thread id, never an opportunity id.
        XCTAssertNil(LeadNotificationRouteParser.opportunityId(fromActionUrl: "/inbox/\(threadId)"))
    }

    func testOpportunityIdNilForNilOrEmpty() {
        XCTAssertNil(LeadNotificationRouteParser.opportunityId(fromActionUrl: nil))
        XCTAssertNil(LeadNotificationRouteParser.opportunityId(fromActionUrl: "  "))
    }

    // MARK: - opportunityId(fromDedupeKey:)

    func testOpportunityIdFromTrailingLifecycleKey() {
        // 138 of 257 prod rows.
        let key = "lead_lifecycle:operator_follow_up_miss:\(oppId)"
        XCTAssertEqual(LeadNotificationRouteParser.opportunityId(fromDedupeKey: key), oppId)
    }

    func testOpportunityIdFromInteriorLifecycleKey() {
        // destructive_candidate keys carry the uuid mid-string, not trailing.
        let key = "lead_lifecycle:destructive_candidate:\(oppId):archive_no_meaningful_correspondence"
        XCTAssertEqual(LeadNotificationRouteParser.opportunityId(fromDedupeKey: key), oppId)
    }

    func testOpportunityIdNilForNonLeadDedupeKey() {
        XCTAssertNil(LeadNotificationRouteParser.opportunityId(fromDedupeKey: "expense_batch_review:\(oppId)"))
        XCTAssertNil(LeadNotificationRouteParser.opportunityId(fromDedupeKey: nil))
        XCTAssertNil(LeadNotificationRouteParser.opportunityId(fromDedupeKey: "lead_lifecycle:no_uuid_here"))
    }

    // MARK: - emailThreadId(fromActionUrl:)

    func testEmailThreadIdFromInboxPath() {
        XCTAssertEqual(
            LeadNotificationRouteParser.emailThreadId(fromActionUrl: "/inbox/\(threadId)"),
            threadId
        )
    }

    func testEmailThreadIdFromInboxQueryParam() {
        XCTAssertEqual(
            LeadNotificationRouteParser.emailThreadId(fromActionUrl: "/inbox?thread=\(threadId)"),
            threadId
        )
    }

    func testEmailThreadIdNilForNonInboxUrl() {
        XCTAssertNil(LeadNotificationRouteParser.emailThreadId(fromActionUrl: "/pipeline?opportunityId=\(oppId)"))
        XCTAssertNil(LeadNotificationRouteParser.emailThreadId(fromActionUrl: "/settings?tab=integrations"))
    }

    // MARK: - route() priority

    func testRoutePrefersUrlOpportunityIdOverDedupeKey() {
        let other = "00000000-0000-0000-0000-000000000001"
        let route = LeadNotificationRouteParser.route(
            actionUrl: "/pipeline?opportunityId=\(oppId)",
            dedupeKey: "lead_lifecycle:operator_follow_up_miss:\(other)"
        )
        XCTAssertEqual(route, .opportunity(oppId))
    }

    func testRouteFallsToDedupeKeyWhenUrlIsInboxThread() {
        // The dominant 138-row shape: inbox url + lifecycle dedupe key.
        let route = LeadNotificationRouteParser.route(
            actionUrl: "/inbox/\(threadId)",
            dedupeKey: "lead_lifecycle:operator_follow_up_miss:\(oppId)"
        )
        XCTAssertEqual(route, .opportunity(oppId))
    }

    func testRouteFallsToEmailThreadWhenOnlyInboxUrl() {
        // The 135-row shape with no resolvable dedupe key — thread must resolve.
        let route = LeadNotificationRouteParser.route(
            actionUrl: "/inbox/\(threadId)",
            dedupeKey: nil
        )
        XCTAssertEqual(route, .emailThread(threadId))
    }

    func testRouteNilWhenNothingResolvable() {
        // destructive-candidate row with no live opportunity / settings row.
        let route = LeadNotificationRouteParser.route(
            actionUrl: "/settings?tab=integrations",
            dedupeKey: nil
        )
        XCTAssertNil(route)
    }
}
