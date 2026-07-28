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
        for t in ["lead_created", "lead_updated", "lead_follow_up_due", "lead_follow_up_sent",
                  "opportunity_created", "opportunity_updated", "opportunity_follow_up_due",
                  "pipeline_complete"] {
            XCTAssertTrue(
                LeadNotificationRouteParser.isLeadNotification(type: t, deepLinkType: nil),
                "expected \(t) to be a lead notification"
            )
        }
    }

    func testAssignmentTypesDetectedWithoutDeepLinkType() {
        // The live assignment worker stamps deep_link_type='lead', so routing
        // already works. These assertions are the belt: if the server ever drops
        // deep_link_type, `type` alone must still carry the row to the lead.
        for t in ["lead_assigned", "lead_assignment_required"] {
            XCTAssertTrue(
                LeadNotificationRouteParser.isLeadNotification(type: t, deepLinkType: nil),
                "expected \(t) to be a lead notification on type alone"
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

    func testRouteResolvesShippedAssignmentPayload() {
        // Exactly what the live assignment worker writes: the opportunity id in
        // the url and a `lead-assignment-delivery:` dedupe key keyed on the
        // DELIVERY id, not the lead. The url must win — a delivery id resolved
        // as a lead id would open the wrong record (the dedupe scanner only
        // accepts `lead_lifecycle:` keys, which is what keeps that from happening).
        let deliveryId = "6b2f2b7a-9d8d-4a1f-9f2a-2f1c0d3e4a5b"
        let route = LeadNotificationRouteParser.route(
            actionUrl: "/pipeline?opportunityId=\(oppId)",
            dedupeKey: "lead-assignment-delivery:\(deliveryId)"
        )
        XCTAssertEqual(route, .opportunity(oppId))
    }

    func testRouteNilWhenNothingResolvable() {
        // destructive-candidate row with no live opportunity / settings row.
        let route = LeadNotificationRouteParser.route(
            actionUrl: "/settings?tab=integrations",
            dedupeKey: nil
        )
        XCTAssertNil(route)
    }

    // MARK: - AI provider quota push routing

    func testNotificationsScreenTargetsNotificationRail() {
        XCTAssertTrue(
            NotificationRailPushRoute.shouldOpen(
                screen: "notifications",
                type: nil
            )
        )
    }

    func testAIProviderQuotaTypeTargetsNotificationRailWithoutScreen() {
        XCTAssertTrue(
            NotificationRailPushRoute.shouldOpen(
                screen: nil,
                type: "ai_provider_quota"
            )
        )
    }

    func testPlatformHealthDoesNotTargetNotificationRail() {
        XCTAssertFalse(
            NotificationRailPushRoute.shouldOpen(
                screen: "platform_health",
                type: "platform_health"
            )
        )
    }

    func testAIProviderQuotaDeliveryWaitsForUserTap() {
        XCTAssertFalse(
            NotificationRailPushRoute.shouldNavigateFromDelivery(
                screen: "notifications",
                type: "ai_provider_quota"
            )
        )
    }

    func testNotificationRailPresentationWaitsForPINUnlock() {
        XCTAssertFalse(
            NotificationRailPushRoute.canPresent(
                sessionAuthenticated: true,
                requiresPIN: true,
                pinAuthenticated: false
            )
        )
        XCTAssertTrue(
            NotificationRailPushRoute.canPresent(
                sessionAuthenticated: true,
                requiresPIN: true,
                pinAuthenticated: true
            )
        )
        XCTAssertFalse(
            NotificationRailPushRoute.canPresent(
                sessionAuthenticated: false,
                requiresPIN: false,
                pinAuthenticated: true
            )
        )
    }

    func testPersistentNotificationsStayUnreadUntilConditionResolution() {
        XCTAssertFalse(NotificationReadPolicy.shouldMarkRead(persistent: true))
        XCTAssertTrue(NotificationReadPolicy.shouldMarkRead(persistent: false))
        XCTAssertTrue(NotificationReadPolicy.shouldMarkRead(persistent: nil))
        XCTAssertEqual(
            NotificationReadPolicy.nonPersistentPostgrestFilter,
            "persistent.is.null,persistent.eq.false"
        )
    }

    @MainActor
    func testNotificationRailCoordinatorDispatchesOpenNotifications() {
        let coordinator = DeepLinkCoordinator.shared
        coordinator.clear()
        defer { coordinator.clear() }

        let dispatched = expectation(
            forNotification: Notification.Name("OpenNotifications"),
            object: nil
        ) { notification in
            XCTAssertEqual(notification.userInfo?["notificationRail"] as? String, "rail")
            XCTAssertNotNil(
                notification.userInfo?[DeepLinkCoordinator.deepLinkIdUserInfoKey] as? String
            )
            return true
        }

        coordinator.receive(entity: "notifications", id: "rail", scheme: "push")

        wait(for: [dispatched], timeout: 1.0)
    }
}
