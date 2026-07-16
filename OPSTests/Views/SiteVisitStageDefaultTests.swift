//
//  SiteVisitStageDefaultTests.swift
//  OPSTests
//
//  Bug (site-visit report) — completing a site visit must NOT auto-convert
//  the lead to WON. These lock the default-stage policy: new leads qualify,
//  in-flight leads hold, terminal leads are never touched.
//

import XCTest
@testable import OPS

final class SiteVisitStageDefaultTests: XCTestCase {

    func testNewLeadAdvancesToQualifying() {
        XCTAssertEqual(SiteVisitStageDefault.defaultStage(current: .newLead), .qualifying)
    }

    func testInFlightStagesAreNotRegressed() {
        for stage in [PipelineStage.qualifying, .quoting, .quoted, .followUp, .negotiation] {
            XCTAssertEqual(
                SiteVisitStageDefault.defaultStage(current: stage), stage,
                "\(stage.rawValue) should hold, not regress"
            )
        }
    }

    func testTerminalStagesAreNeverAltered() {
        // The core of the bug: a visit save must never move a lead to (or away
        // from) a terminal stage. WON in particular must never be auto-set.
        for stage in [PipelineStage.won, .lost, .discarded] {
            XCTAssertEqual(
                SiteVisitStageDefault.defaultStage(current: stage), stage,
                "\(stage.rawValue) is terminal and must be left untouched"
            )
        }
    }

    func testDefaultNeverReturnsWonForANonWonLead() {
        // Belt-and-braces: no non-won input should ever yield WON.
        for stage in PipelineStage.allCases where stage != .won {
            XCTAssertNotEqual(
                SiteVisitStageDefault.defaultStage(current: stage), .won,
                "\(stage.rawValue) must not default to WON"
            )
        }
    }

    func testSelectableStagesExcludeTerminalStates() {
        let selectable = Set(SiteVisitStageDefault.selectableStages)
        XCTAssertFalse(selectable.contains(.won))
        XCTAssertFalse(selectable.contains(.lost))
        XCTAssertFalse(selectable.contains(.discarded))
        XCTAssertEqual(
            SiteVisitStageDefault.selectableStages,
            [.newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation]
        )
    }
}
