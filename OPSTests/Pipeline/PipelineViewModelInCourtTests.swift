//
//  PipelineViewModelInCourtTests.swift
//  OPSTests
//
//  Coverage for PipelineViewModel stat-card computeds.
//  The in-court bar was replaced by the triage chip filter (design-intent §24 J2),
//  removing inCourtCount / inCourtBuckets / inCourtTotalValue / inCourtOpportunityIds
//  / oldestStaleDescription / staleLeadsTotalValue. Those tests are dropped.
//  closeRate(periodDays:) is retained for the BOOKS tab.
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

    // MARK: - closeRate

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
