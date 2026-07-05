//
//  PipelineViewModelDiscardTests.swift
//  OPSTests
//
//  Covers the observable contract of the Discard action: a lead moved to the
//  terminal `.discarded` stage drops off the triage board (every bucket) and is
//  never counted as an open lead. The RPC round-trip is exercised against the
//  live schema separately (move_opportunity_stage accepts 'discarded'); this
//  test pins the LOCAL effect that flipping the stage produces — junk leaves the
//  operator's queue, and it is NOT a lost deal.
//

import XCTest
@testable import OPS

@MainActor
final class PipelineViewModelDiscardTests: XCTestCase {

    private func makeLead(id: String, stage: PipelineStage) -> Opportunity {
        Opportunity(
            id: id,
            companyId: "company-1",
            contactName: "Contact \(id)",
            stage: stage,
            stageEnteredAt: Date(timeIntervalSince1970: 1_000_000),
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    /// A `.discarded` lead is excluded from every triage bucket — the whole
    /// point of Discard: junk leaves the board. An open lead beside it stays.
    func testDiscardedLeadDropsOffTheTriageBoard() {
        let vm = PipelineViewModel()
        vm.allOpportunities = [
            makeLead(id: "open", stage: .quoted),
            makeLead(id: "junk", stage: .discarded),
        ]

        let ids = vm.triageBuckets.all.map(\.id)
        XCTAssertEqual(ids, ["open"], "a discarded lead must leave the triage board; only the open lead remains")
    }

    /// Discard is not Lost: a board of only terminal leads (won/lost/discarded)
    /// shows nothing to triage — discarded never resurfaces as work.
    func testTerminalLeadsIncludingDiscardedShowNoTriage() {
        let vm = PipelineViewModel()
        vm.allOpportunities = [
            makeLead(id: "won", stage: .won),
            makeLead(id: "lost", stage: .lost),
            makeLead(id: "junk", stage: .discarded),
        ]
        XCTAssertTrue(vm.triageBuckets.all.isEmpty, "no terminal lead — won, lost, or discarded — belongs on the triage board")
    }
}
