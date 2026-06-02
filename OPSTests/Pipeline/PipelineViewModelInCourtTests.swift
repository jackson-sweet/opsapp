//
//  PipelineViewModelInCourtTests.swift
//  OPSTests
//
//  Coverage for PipelineViewModel.closeRate(periodDays:).
//
//  NOTE (leads review 3, 2026-05-31): the in-court / stale-total / oldest-stale
//  tests that used to live here were removed because the LEADS rebuild removed
//  the view-model members they exercised — `inCourtCount`, `inCourtBuckets`,
//  `inCourtTotalValue`, `inCourtOpportunityIds`, `oldestStaleDescription`, and
//  `staleLeadsTotalValue`. The "ball in your court" bar those derivations fed
//  was replaced by the triage chip filter in the rebuild (design-intent §23/§24
//  J2). Those tests referenced symbols that no longer exist, which silently
//  broke the entire OPSTests target's compilation. Triage-bucket behavior is now
//  covered by the live `triageBuckets` logic + `LeadsConformanceTests`. The
//  surviving `closeRate(periodDays:)` member (kept for the BOOKS tab) is covered
//  below, unchanged.
//

import XCTest
@testable import OPS

@MainActor
final class PipelineViewModelInCourtTests: XCTestCase {

    func makeOpp(
        id: String = UUID().uuidString,
        stage: PipelineStage = .newLead,
        assignedTo: String? = "me",
        nextFollowUpAt: Date? = nil,
        lastActivityAt: Date? = nil,
        stageEnteredAt: Date = Date(),
        estimatedValue: Double? = nil,
        deletedAt: Date? = nil,
        archivedAt: Date? = nil
    ) -> Opportunity {
        let opp = Opportunity(
            id: id,
            companyId: "co",
            contactName: "Test",
            stage: stage,
            stageEnteredAt: stageEnteredAt
        )
        opp.assignedTo = assignedTo
        opp.nextFollowUpAt = nextFollowUpAt
        opp.lastActivityAt = lastActivityAt
        opp.estimatedValue = estimatedValue
        opp.deletedAt = deletedAt
        opp.archivedAt = archivedAt
        return opp
    }

    // MARK: - Close rate (kept for BOOKS)

    func test_closeRate_returnsNilWhenInsufficientData() {
        let vm = PipelineViewModel()
        let recently = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let won = makeOpp(stage: .won)
        won.actualCloseDate = recently
        let lost = makeOpp(stage: .lost)
        lost.actualCloseDate = recently
        let lost2 = makeOpp(stage: .lost)
        lost2.actualCloseDate = recently
        vm.allOpportunities = [won, lost, lost2]
        XCTAssertNil(vm.closeRate(periodDays: 90))
    }

    func test_closeRate_computesAcrossPeriod() {
        let vm = PipelineViewModel()
        let recently = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        var opps: [Opportunity] = []
        for _ in 0..<3 {
            let o = makeOpp(stage: .won); o.actualCloseDate = recently; opps.append(o)
        }
        for _ in 0..<5 {
            let o = makeOpp(stage: .lost); o.actualCloseDate = recently; opps.append(o)
        }
        vm.allOpportunities = opps
        XCTAssertEqual(vm.closeRate(periodDays: 90) ?? 0, 0.375, accuracy: 0.001)
    }

    func test_closeRate_excludesClosesOutsidePeriod() {
        let vm = PipelineViewModel()
        let oldClose = Calendar.current.date(byAdding: .day, value: -120, to: Date())!
        let recentClose = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        var opps: [Opportunity] = []
        for _ in 0..<3 { let o = makeOpp(stage: .won); o.actualCloseDate = recentClose; opps.append(o) }
        for _ in 0..<2 { let o = makeOpp(stage: .lost); o.actualCloseDate = recentClose; opps.append(o) }
        for _ in 0..<5 { let o = makeOpp(stage: .won); o.actualCloseDate = oldClose; opps.append(o) }
        vm.allOpportunities = opps
        XCTAssertEqual(vm.closeRate(periodDays: 90) ?? 0, 0.6, accuracy: 0.001)
    }
}
