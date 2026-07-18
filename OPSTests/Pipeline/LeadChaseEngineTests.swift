//
//  LeadChaseEngineTests.swift
//  OPSTests
//
//  Chase-system semantics (Leads redesign 2026-07, spec §2):
//  YOUR MOVE = last recorded touch was theirs AND the operator has not
//  declared it handled since (handled_at). A newer inbound after a flip
//  re-arms the lead. Date buckets (overdue / due today) stay first-priority.
//

import XCTest
@testable import OPS

@MainActor
final class LeadChaseEngineTests: XCTestCase {
    private func lead(stage: PipelineStage = .quoted,
                      direction: String? = nil,
                      lastInbound: Date? = nil,
                      handled: Date? = nil,
                      followUp: Date? = nil) -> Opportunity {
        let o = Opportunity(id: UUID().uuidString.lowercased(), companyId: "c", contactName: "T", stage: stage)
        o.lastMessageDirection = direction
        o.lastInboundAt = lastInbound
        o.handledAt = handled
        o.nextFollowUpAt = followUp
        return o
    }
    private func vm(_ leads: [Opportunity]) -> PipelineViewModel {
        let m = PipelineViewModel(); m.allOpportunities = leads; return m
    }

    func testInboundUnhandledIsYourMove() {
        let l = lead(direction: "in", lastInbound: .now.addingTimeInterval(-3600))
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnYou)
    }
    func testHandledAfterInboundLeavesYourMove() {
        let l = lead(direction: "in", lastInbound: .now.addingTimeInterval(-7200), handled: .now.addingTimeInterval(-3600))
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnThem)
    }
    func testNewerInboundReflipsToYourMove() {
        let l = lead(direction: "in", lastInbound: .now.addingTimeInterval(-60), handled: .now.addingTimeInterval(-3600))
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnYou)
    }
    func testOverdueOutranksHandledState() {   // date buckets stay first-priority
        let l = lead(direction: "in", lastInbound: .now, followUp: Calendar.current.date(byAdding: .day, value: -2, to: .now))
        XCTAssertEqual(vm([l]).bucketOf(l), .overdue)
    }
    func testVocabulary() {
        XCTAssertEqual(PipelineViewModel.TriageBucket.waitingOnYou.label, "YOUR MOVE")
        XCTAssertEqual(PipelineViewModel.TriageBucket.waitingOnThem.label, "WAITING")
    }
}
