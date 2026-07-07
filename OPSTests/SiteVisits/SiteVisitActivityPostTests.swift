//
//  SiteVisitActivityPostTests.swift
//  OPSTests
//
//  A completed site visit posts ONE "Site visit" activity to the timeline —
//  app-side, because SiteVisit is local-only and no DB trigger can fire. These
//  tests prove the decision logic without any live network:
//   - target resolution prefers the bound opportunity (so the row lands on the
//     lead timeline, the only activity timeline that renders today) over a
//     client, and is nil when the visit is fully unbound;
//   - the best-effort post is idempotent — it no-ops when the visit already
//     logged an activity (offline-retry safe) and when the visit is unbound,
//     never touching the network in either case;
//   - the body summary collapses to nil when nothing was captured (the DB
//     trigger still backfills the "Site visit" subject).
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitActivityPostTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([SiteVisit.self, Opportunity.self, Client.self, Project.self, User.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return container.mainContext
    }

    private func makeViewModel(opportunity: Opportunity?, context: ModelContext) -> SiteVisitCaptureViewModel {
        SiteVisitCaptureViewModel(
            opportunity: opportunity,
            companyId: "company-1",
            userId: "user-operator-1",
            modelContext: context
        )
    }

    // MARK: - Target resolution

    func test_activityTarget_prefersBoundOpportunity_evenWhenClientAlsoPresent() throws {
        let context = try makeContext()
        let opp = Opportunity(id: "opp-1", companyId: "company-1", contactName: "Eric Devlin", stage: .quoting)
        opp.clientId = "cli-1"   // a client is also in play, but the lead must win
        let vm = makeViewModel(opportunity: opp, context: context)

        XCTAssertEqual(vm.siteVisitActivityTarget?.parentKey, .opportunity("opp-1"),
                       "the bound lead is preferred so the site visit shows on the lead timeline")
    }

    func test_activityTarget_nilWhenFullyUnbound() throws {
        let context = try makeContext()
        let vm = makeViewModel(opportunity: nil, context: context)

        XCTAssertNil(vm.siteVisitActivityTarget, "no lead and no client → nothing to attach an activity to")
    }

    // MARK: - Idempotency (no network hit on the guarded paths)

    func test_postActivity_skipsWhenAlreadyLogged() async throws {
        let context = try makeContext()
        let opp = Opportunity(id: "opp-1", companyId: "company-1", contactName: "Eric Devlin", stage: .quoting)
        let vm = makeViewModel(opportunity: opp, context: context)

        let visit = SiteVisit(id: "visit-1", opportunityId: "opp-1", companyId: "company-1")
        visit.loggedActivityId = "already-logged"

        await vm.postSiteVisitActivityIfNeeded(for: visit)

        XCTAssertEqual(visit.loggedActivityId, "already-logged",
                       "a visit that already logged an activity must not post a second one")
    }

    func test_postActivity_skipsWhenUnbound() async throws {
        let context = try makeContext()
        let vm = makeViewModel(opportunity: nil, context: context)

        let visit = SiteVisit(id: "visit-unbound", opportunityId: nil, companyId: "company-1")

        await vm.postSiteVisitActivityIfNeeded(for: visit)

        XCTAssertNil(visit.loggedActivityId, "an unbound visit posts nothing and stamps nothing")
    }

    // MARK: - Body summary

    func test_activitySummary_nilWhenNothingCaptured() throws {
        let context = try makeContext()
        let vm = makeViewModel(opportunity: nil, context: context)

        XCTAssertNil(vm.siteVisitActivitySummary,
                     "with no notes and no answered checklist items there is nothing to summarize")
    }
}
