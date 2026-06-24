//
//  CrewAffinityRankerTests.swift
//  OPSTests
//
//  Coverage for the team-member picker's affinity ranking: usual crew for the
//  task type first (by frequency, then recency), everyone else by overall
//  recency, then alphabetical.
//

import XCTest
@testable import OPS

final class CrewAffinityRankerTests: XCTestCase {

    private func d(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

    private func stat(
        _ id: String,
        name: String? = nil,
        typeCount: Int = 0,
        lastForType: TimeInterval = 0,
        lastOverall: TimeInterval = 0
    ) -> CrewAffinityStats {
        CrewAffinityStats(
            memberId: id,
            fullName: name ?? id,
            typeAssignmentCount: typeCount,
            lastAssignedToType: d(lastForType),
            lastAssignedOverall: d(lastOverall)
        )
    }

    // MARK: - Affinity (frequency) dominates

    func testUsualCrewRankedByFrequencyForTheType() {
        // Bob has done vinyl 5×, Ann 2×, Cy 0×. Cy was used most recently overall.
        let ranking = CrewAffinityRanker.rank([
            stat("ann", typeCount: 2, lastForType: 100, lastOverall: 100),
            stat("bob", typeCount: 5, lastForType: 50, lastOverall: 50),
            stat("cy", typeCount: 0, lastForType: 0, lastOverall: 9_000),
        ])
        // Frequency-for-type wins: bob (5) > ann (2) > cy (none), even though
        // cy is the most recent overall.
        XCTAssertEqual(ranking.orderedIds, ["bob", "ann", "cy"])
        XCTAssertEqual(ranking.usualCrewIds, ["ann", "bob"])
    }

    func testUsualCrewTieBrokenByRecencyForType() {
        // Equal frequency → most recent assignment to THIS type wins.
        let ranking = CrewAffinityRanker.rank([
            stat("older", typeCount: 3, lastForType: 100, lastOverall: 100),
            stat("newer", typeCount: 3, lastForType: 500, lastOverall: 500),
        ])
        XCTAssertEqual(ranking.orderedIds, ["newer", "older"])
    }

    func testUsualCrewTieBrokenByNameWhenCountAndRecencyEqual() {
        let ranking = CrewAffinityRanker.rank([
            stat("z", name: "Zoe", typeCount: 1, lastForType: 100, lastOverall: 100),
            stat("a", name: "Amy", typeCount: 1, lastForType: 100, lastOverall: 100),
        ])
        XCTAssertEqual(ranking.orderedIds, ["a", "z"])
    }

    // MARK: - Rest tier: no precedent → recently used → alphabetical

    func testRestTierOrderedByOverallRecencyThenName() {
        let ranking = CrewAffinityRanker.rank([
            stat("stale", name: "Stale", typeCount: 0, lastOverall: 10),
            stat("fresh", name: "Fresh", typeCount: 0, lastOverall: 900),
            stat("never", name: "Never", typeCount: 0, lastOverall: 0),
        ])
        // fresh (most recent overall) → stale → never (no history, alphabetical floor)
        XCTAssertEqual(ranking.orderedIds, ["fresh", "stale", "never"])
        XCTAssertTrue(ranking.usualCrewIds.isEmpty)
    }

    func testNoAffinityFallsBackToRecencyThenAlphabetical() {
        // taskTypeId empty upstream → everyone is rest tier.
        let ranking = CrewAffinityRanker.rank([
            stat("b", name: "Bea", typeCount: 0, lastOverall: 0),
            stat("a", name: "Abe", typeCount: 0, lastOverall: 0),
        ])
        XCTAssertEqual(ranking.orderedIds, ["a", "b"]) // pure alphabetical when no recency
        XCTAssertTrue(ranking.usualCrewIds.isEmpty)
    }

    // MARK: - Tiers don't interleave

    func testUsualCrewAlwaysAboveRestRegardlessOfRecency() {
        // A rest member used today must still sit below a usual-crew member
        // whose last type assignment was long ago.
        let ranking = CrewAffinityRanker.rank([
            stat("usual_old", typeCount: 1, lastForType: 1, lastOverall: 1),
            stat("rest_today", typeCount: 0, lastOverall: 100_000),
        ])
        XCTAssertEqual(ranking.orderedIds, ["usual_old", "rest_today"])
        XCTAssertEqual(ranking.usualCrewIds, ["usual_old"])
    }

    // MARK: - Degenerate

    func testEmptyInput() {
        let ranking = CrewAffinityRanker.rank([])
        XCTAssertTrue(ranking.orderedIds.isEmpty)
        XCTAssertTrue(ranking.usualCrewIds.isEmpty)
    }
}
