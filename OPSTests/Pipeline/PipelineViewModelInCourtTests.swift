//
//  PipelineViewModelInCourtTests.swift
//  OPSTests
//
//  Coverage for ball-in-court derivations on PipelineViewModel.
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

    // MARK: - In-court derivations

    func test_inCourtCount_isZeroWhenCurrentUserIdNil() {
        let vm = PipelineViewModel()
        vm.allOpportunities = [makeOpp()]
        XCTAssertNil(vm.currentUserId)
        XCTAssertEqual(vm.inCourtCount, 0)
    }

    func test_inCourtCount_excludesTerminalStages() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let won = makeOpp(stage: .won)
        let lost = makeOpp(stage: .lost)
        vm.allOpportunities = [won, lost]
        XCTAssertEqual(vm.inCourtCount, 0)
    }

    func test_inCourtCount_excludesUnassignedAndOthers() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let untouched = makeOpp(stage: .newLead, assignedTo: "me")
        let other = makeOpp(stage: .newLead, assignedTo: "other-user")
        let unassigned = makeOpp(stage: .newLead, assignedTo: nil)
        vm.allOpportunities = [untouched, other, unassigned]
        XCTAssertEqual(vm.inCourtCount, 1)
    }

    func test_inCourtCount_excludesDeletedAndArchived() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let active = makeOpp(stage: .newLead)
        let deleted = makeOpp(stage: .newLead, deletedAt: Date())
        let archived = makeOpp(stage: .newLead, archivedAt: Date())
        vm.allOpportunities = [active, deleted, archived]
        XCTAssertEqual(vm.inCourtCount, 1)
    }

    func test_inCourtBuckets_overdueTrumpsStale() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let both = makeOpp(stage: .quoting, nextFollowUpAt: yesterday, stageEnteredAt: tenDaysAgo)
        vm.allOpportunities = [both]
        XCTAssertEqual(vm.inCourtBuckets.overdue, 1)
        XCTAssertEqual(vm.inCourtBuckets.stale, 0)
        XCTAssertEqual(vm.inCourtBuckets.untouched, 0)
    }

    func test_inCourtBuckets_staleFallsThroughOverdue() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let staleOnly = makeOpp(stage: .quoting, nextFollowUpAt: nil, stageEnteredAt: tenDaysAgo)
        vm.allOpportunities = [staleOnly]
        XCTAssertEqual(vm.inCourtBuckets.overdue, 0)
        XCTAssertEqual(vm.inCourtBuckets.stale, 1)
        XCTAssertEqual(vm.inCourtBuckets.untouched, 0)
    }

    func test_inCourtBuckets_untouchedRequiresNewLeadAndNoActivity() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let untouchedNew = makeOpp(stage: .newLead, lastActivityAt: nil, stageEnteredAt: Date())
        let touchedNew = makeOpp(stage: .newLead, lastActivityAt: Date(), stageEnteredAt: Date())
        vm.allOpportunities = [untouchedNew, touchedNew]
        XCTAssertEqual(vm.inCourtBuckets.untouched, 1)
        XCTAssertEqual(vm.inCourtCount, 1)
    }

    func test_inCourtBuckets_followUpStageRollsIntoStale() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let inFollowUpStage = makeOpp(stage: .followUp, nextFollowUpAt: nil, stageEnteredAt: Date())
        vm.allOpportunities = [inFollowUpStage]
        XCTAssertEqual(vm.inCourtBuckets.overdue, 0)
        XCTAssertEqual(vm.inCourtBuckets.stale, 1)
        XCTAssertEqual(vm.inCourtBuckets.untouched, 0)
    }

    func test_inCourtTotalValue_sumsEstimatedValues() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let a = makeOpp(stage: .quoting, nextFollowUpAt: yesterday, estimatedValue: 10_000)
        let b = makeOpp(stage: .quoting, nextFollowUpAt: yesterday, estimatedValue: 32_300)
        let c = makeOpp(stage: .quoting, nextFollowUpAt: yesterday, estimatedValue: nil)
        vm.allOpportunities = [a, b, c]
        XCTAssertEqual(vm.inCourtTotalValue, 42_300, accuracy: 0.01)
    }

    func test_inCourtOpportunityIds_returnsExactSet() {
        let vm = PipelineViewModel()
        vm.currentUserId = "me"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let a = makeOpp(id: "a", stage: .quoting, nextFollowUpAt: yesterday)
        let b = makeOpp(id: "b", stage: .quoting, nextFollowUpAt: nil)
        vm.allOpportunities = [a, b]
        XCTAssertEqual(vm.inCourtOpportunityIds, Set(["a"]))
    }

    // MARK: - Stat-card computeds

    func test_staleLeadsTotalValue_sumsStaleEstimates() {
        let vm = PipelineViewModel()
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let stale1 = makeOpp(stage: .quoting, stageEnteredAt: tenDaysAgo, estimatedValue: 5_000)
        let stale2 = makeOpp(stage: .quoting, stageEnteredAt: tenDaysAgo, estimatedValue: 13_400)
        let fresh = makeOpp(stage: .quoting, stageEnteredAt: Date(), estimatedValue: 1_000_000)
        vm.allOpportunities = [stale1, stale2, fresh]
        XCTAssertEqual(vm.staleLeadsTotalValue, 18_400, accuracy: 0.01)
    }

    func test_oldestStaleDescription_returnsOldestStaleSummary() {
        let vm = PipelineViewModel()
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        let twelveDaysAgo = Calendar.current.date(byAdding: .day, value: -12, to: Date())!
        let older = makeOpp(stage: .quoting, stageEnteredAt: twelveDaysAgo)
        let newer = makeOpp(stage: .qualifying, stageEnteredAt: fiveDaysAgo)
        vm.allOpportunities = [newer, older]
        XCTAssertEqual(vm.oldestStaleDescription, "12D IN QUOTING")
    }

    func test_oldestStaleDescription_nilWhenNoStale() {
        let vm = PipelineViewModel()
        vm.allOpportunities = [makeOpp(stage: .quoting, stageEnteredAt: Date())]
        XCTAssertNil(vm.oldestStaleDescription)
    }

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
