//
//  PipelineViewModelTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

@MainActor
final class PipelineViewModelTests: XCTestCase {

    func makeOpportunity(
        id: String = UUID().uuidString,
        stage: PipelineStage = .newLead,
        stageEnteredAt: Date = Date(),
        lastActivityAt: Date? = nil,
        deletedAt: Date? = nil,
        archivedAt: Date? = nil,
        estimatedValue: Double? = nil
    ) -> Opportunity {
        let opp = Opportunity(
            id: id,
            companyId: "co",
            contactName: "Test",
            stage: stage,
            stageEnteredAt: stageEnteredAt
        )
        opp.lastActivityAt = lastActivityAt
        opp.deletedAt = deletedAt
        opp.archivedAt = archivedAt
        opp.estimatedValue = estimatedValue
        return opp
    }

    // MARK: - Filtering

    func test_opportunitiesInStage_excludesDeletedAndArchived() {
        let vm = PipelineViewModel()
        let active = makeOpportunity(stage: .newLead)
        let deleted = makeOpportunity(stage: .newLead, deletedAt: Date())
        let archived = makeOpportunity(stage: .newLead, archivedAt: Date())
        vm.allOpportunities = [active, deleted, archived]

        let result = vm.opportunities(in: .newLead)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, active.id)
    }

    // MARK: - Sorting

    func test_opportunitiesInStage_staleSortsFirst() {
        let vm = PipelineViewModel()
        let nowMinus10d = Calendar.current.date(byAdding: .day, value: -10, to: Date())!  // stale (newLead threshold = 3d)
        let now = Date()
        let stale = makeOpportunity(id: "stale", stage: .newLead, stageEnteredAt: nowMinus10d)
        let fresh = makeOpportunity(id: "fresh", stage: .newLead, stageEnteredAt: now)
        vm.allOpportunities = [fresh, stale]

        let result = vm.opportunities(in: .newLead)
        XCTAssertEqual(result.first?.id, "stale")
        XCTAssertEqual(result.last?.id, "fresh")
    }

    func test_opportunitiesInStage_recentActivitySortsBeforeOlder() {
        let vm = PipelineViewModel()
        let recent = Date()
        let old = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let oppRecent = makeOpportunity(id: "recent", stage: .quoting, stageEnteredAt: recent, lastActivityAt: recent)
        let oppOld = makeOpportunity(id: "old", stage: .quoting, stageEnteredAt: recent, lastActivityAt: old)
        vm.allOpportunities = [oppOld, oppRecent]

        let result = vm.opportunities(in: .quoting)
        XCTAssertEqual(result.first?.id, "recent")
    }

    // MARK: - Aggregates

    func test_activeLeadCount_excludesTerminalStages() {
        let vm = PipelineViewModel()
        vm.allOpportunities = [
            makeOpportunity(stage: .newLead),
            makeOpportunity(stage: .quoting),
            makeOpportunity(stage: .won),
            makeOpportunity(stage: .lost)
        ]
        XCTAssertEqual(vm.activeLeadCount, 2)
    }

    func test_weightedForecastValue_appliesStageProbability() {
        let vm = PipelineViewModel()
        // newLead = 10%, quoting = 40%
        vm.allOpportunities = [
            makeOpportunity(stage: .newLead, estimatedValue: 1000),    // 100
            makeOpportunity(stage: .quoting, estimatedValue: 5000),    // 2000
            makeOpportunity(stage: .won, estimatedValue: 10000)        // excluded (terminal)
        ]
        XCTAssertEqual(vm.weightedForecastValue, 100 + 2000, accuracy: 0.01)
    }

    func test_staleLeadsCount_respectsPerStageThreshold() {
        let vm = PipelineViewModel()
        let nowMinus10d = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        // newLead threshold = 3d, quoting threshold = 5d
        vm.allOpportunities = [
            makeOpportunity(stage: .newLead, stageEnteredAt: nowMinus10d),  // stale
            makeOpportunity(stage: .quoting, stageEnteredAt: nowMinus10d),  // stale
            makeOpportunity(stage: .negotiation, stageEnteredAt: Date())    // fresh
        ]
        XCTAssertEqual(vm.staleLeadsCount, 2)
    }

    func test_isPipelineEmpty_whenAllDeletedOrArchived() {
        let vm = PipelineViewModel()
        vm.allOpportunities = [
            makeOpportunity(stage: .newLead, deletedAt: Date()),
            makeOpportunity(stage: .quoting, archivedAt: Date())
        ]
        XCTAssertTrue(vm.isPipelineEmpty)
    }

    func test_currentUserId_canBeSetAfterSetup() {
        let vm = PipelineViewModel()
        vm.setup(companyId: "co", currentUserId: "user-123")
        XCTAssertEqual(vm.currentUserId, "user-123")
    }
}
