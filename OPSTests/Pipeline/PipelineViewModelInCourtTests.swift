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
}
