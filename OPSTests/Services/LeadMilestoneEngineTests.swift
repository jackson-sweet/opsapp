//
//  LeadMilestoneEngineTests.swift
//  OPSTests
//
//  The milestone map is the day sheet's single answer to "what is the next
//  real-world event worth stamping on this lead?" — spec §4. It is a pure
//  stage → verb table, so it is locked here exactly: all nine pipeline
//  stages (including the three terminals, which offer no milestone), the
//  button label, the post-stamp confirmation label, and the stage each
//  stamp writes.
//

import XCTest
@testable import OPS

final class LeadMilestoneEngineTests: XCTestCase {

    // MARK: - Stage → milestone (spec §4 table)

    func test_openStages_mapToTheirNextRealWorldEvent() {
        XCTAssertEqual(LeadMilestone.milestone(for: .newLead), .contacted)
        XCTAssertEqual(LeadMilestone.milestone(for: .qualifying), .siteVisited)
        XCTAssertEqual(LeadMilestone.milestone(for: .quoting), .quoteSent)
        XCTAssertEqual(LeadMilestone.milestone(for: .quoted), .won)
        XCTAssertEqual(LeadMilestone.milestone(for: .followUp), .won)
        XCTAssertEqual(LeadMilestone.milestone(for: .negotiation), .won)
    }

    func test_terminalStages_haveNoMilestone() {
        XCTAssertNil(LeadMilestone.milestone(for: .won))
        XCTAssertNil(LeadMilestone.milestone(for: .lost))
        XCTAssertNil(LeadMilestone.milestone(for: .discarded))
    }

    // Guards the table against a new stage landing without a decision.
    func test_everyStageIsCovered_andOnlyTerminalsAreNil() {
        for stage in PipelineStage.allCases {
            let milestone = LeadMilestone.milestone(for: stage)
            XCTAssertEqual(milestone == nil, stage.isTerminal,
                           "stage \(stage.rawValue) milestone/terminal disagreement")
        }
        XCTAssertEqual(PipelineStage.allCases.count, 9)
    }

    // MARK: - Copy (locked — spec §8)

    func test_labels_areExact() {
        XCTAssertEqual(LeadMilestone.contacted.label, "CONTACTED")
        XCTAssertEqual(LeadMilestone.siteVisited.label, "SITE VISITED")
        XCTAssertEqual(LeadMilestone.quoteSent.label, "QUOTE SENT")
        XCTAssertEqual(LeadMilestone.won.label, "WON")
    }

    func test_confirmationLabels_areExact() {
        XCTAssertEqual(LeadMilestone.contacted.confirmationLabel, "CONTACTED ✓")
        XCTAssertEqual(LeadMilestone.siteVisited.confirmationLabel, "VISITED ✓")
        XCTAssertEqual(LeadMilestone.quoteSent.confirmationLabel, "QUOTED ✓")
        XCTAssertEqual(LeadMilestone.won.confirmationLabel, "WON")
    }

    // MARK: - Stage written on stamp

    func test_targetStages_areExact() {
        XCTAssertEqual(LeadMilestone.contacted.targetStage, .qualifying)
        XCTAssertEqual(LeadMilestone.siteVisited.targetStage, .quoting)
        XCTAssertEqual(LeadMilestone.quoteSent.targetStage, .quoted)
    }

    // WON is not a direct stage write — it routes to the won flow.
    func test_wonMilestone_hasNoDirectTargetStage() {
        XCTAssertNil(LeadMilestone.won.targetStage)
    }

    // A stamp always advances the lead; it never writes the stage it came from.
    func test_eachStamp_advancesOffItsSourceStage() {
        for stage in PipelineStage.allCases {
            guard let target = LeadMilestone.milestone(for: stage)?.targetStage else { continue }
            XCTAssertNotEqual(target, stage, "stamp on \(stage.rawValue) did not advance")
            XCTAssertEqual(target, stage.next, "stamp on \(stage.rawValue) left the funnel order")
        }
    }
}
