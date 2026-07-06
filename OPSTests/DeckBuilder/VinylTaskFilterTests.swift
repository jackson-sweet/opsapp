// OPS/OPSTests/DeckBuilder/VinylTaskFilterTests.swift
//
// Bug c6e90385 — Job Board vinyl filter detection logic.

import XCTest
@testable import OPS

final class VinylTaskFilterTests: XCTestCase {

    func testVinylTaskTypeIdsMatchesDisplayNameSubstringCaseInsensitive() {
        let ids = VinylTaskFilter.vinylTaskTypeIds(displaysById: [
            "t1": "Vinyl Install",
            "t2": "vinyl membrane",
            "t3": "Framing",
            "t4": "Railing"
        ])

        XCTAssertEqual(ids, ["t1", "t2"])
    }

    func testVinylTaskTypeIdsEmptyWhenNoVinylType() {
        let ids = VinylTaskFilter.vinylTaskTypeIds(displaysById: [
            "t1": "Framing",
            "t2": "Demo"
        ])

        XCTAssertTrue(ids.isEmpty)
    }

    func testHasVinylTaskTrueWhenAnyTaskIsVinylType() {
        let has = VinylTaskFilter.hasVinylTask(
            taskTypeIds: ["framing-1", "vinyl-1", "railing-1"],
            vinylTaskTypeIds: ["vinyl-1"]
        )
        XCTAssertTrue(has)
    }

    func testHasVinylTaskFalseWhenNoTaskMatches() {
        let has = VinylTaskFilter.hasVinylTask(
            taskTypeIds: ["framing-1", "railing-1"],
            vinylTaskTypeIds: ["vinyl-1"]
        )
        XCTAssertFalse(has)
    }

    func testHasVinylTaskFalseWhenProjectHasNoTasks() {
        let has = VinylTaskFilter.hasVinylTask(
            taskTypeIds: [],
            vinylTaskTypeIds: ["vinyl-1"]
        )
        XCTAssertFalse(has)
    }

    /// A company with no vinyl task type never matches, even if a stray task id
    /// coincidentally overlaps — the vinyl set gates everything.
    func testHasVinylTaskFalseWhenNoVinylTypesDefined() {
        let has = VinylTaskFilter.hasVinylTask(
            taskTypeIds: ["vinyl-1"],
            vinylTaskTypeIds: []
        )
        XCTAssertFalse(has)
    }
}
