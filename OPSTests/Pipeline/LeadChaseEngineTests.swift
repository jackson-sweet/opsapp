//
//  LeadChaseEngineTests.swift
//  OPSTests
//
//  Chase-system semantics (Leads redesign 2026-07, spec §2):
//  ownership follows the newest correspondence or manual signal. Manual
//  corrections resolve exact ties. Date buckets stay first-priority.
//

import XCTest
@testable import OPS

@MainActor
final class LeadChaseEngineTests: XCTestCase {
    private func lead(stage: PipelineStage = .quoted,
                      direction: String? = nil,
                      lastInbound: Date? = nil,
                      lastOutbound: Date? = nil,
                      handled: Date? = nil,
                      operatorActionRequired: Date? = nil,
                      followUp: Date? = nil) -> Opportunity {
        let o = Opportunity(id: UUID().uuidString.lowercased(), companyId: "c", contactName: "T", stage: stage)
        o.lastMessageDirection = direction
        o.lastInboundAt = lastInbound
        o.lastOutboundAt = lastOutbound
        o.handledAt = handled
        o.operatorActionRequiredAt = operatorActionRequired
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
    func testOperatorCorrectionMakesLastOutboundLeadYourMove() {
        let now = Date()
        let l = lead(
            direction: "out",
            lastOutbound: now.addingTimeInterval(-3600),
            operatorActionRequired: now
        )
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnYou)
    }
    func testOperatorCorrectionMakesDirectionlessLeadYourMove() {
        let l = lead(operatorActionRequired: .now)
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnYou)
    }
    func testOperatorCorrectionReversesHandledInboundLead() {
        let now = Date()
        let l = lead(
            direction: "in",
            lastInbound: now.addingTimeInterval(-7200),
            handled: now.addingTimeInterval(-3600),
            operatorActionRequired: now
        )
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnYou)
    }
    func testLaterOutboundSupersedesOperatorCorrection() {
        let now = Date()
        let l = lead(
            direction: "out",
            lastOutbound: now,
            operatorActionRequired: now.addingTimeInterval(-3600)
        )
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnThem)
    }
    func testLaterHandledSupersedesOperatorCorrection() {
        let now = Date()
        let l = lead(
            direction: "in",
            lastInbound: now.addingTimeInterval(-7200),
            handled: now,
            operatorActionRequired: now.addingTimeInterval(-3600)
        )
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnThem)
    }
    func testLaterInboundSupersedesOperatorCorrection() {
        let now = Date()
        let l = lead(
            direction: "in",
            lastInbound: now,
            operatorActionRequired: now.addingTimeInterval(-3600)
        )
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnYou)
    }
    func testOperatorCorrectionWinsExactTieWithHandled() {
        let now = Date()
        let l = lead(
            direction: "in",
            handled: now,
            operatorActionRequired: now
        )
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnYou)
    }
    func testOperatorCorrectionWinsExactTieWithOutboundCorrespondence() {
        let now = Date()
        let l = lead(
            direction: "out",
            lastOutbound: now,
            operatorActionRequired: now
        )
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnYou)
    }
    func testHandledWinsExactTieWithInboundCorrespondence() {
        let now = Date()
        let l = lead(direction: "in", lastInbound: now, handled: now)
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnThem)
    }
    func testLegacyDirectionFallbackStillWorksWithoutTimestamps() {
        let inbound = lead(direction: "in")
        let outbound = lead(direction: "out")
        XCTAssertEqual(vm([inbound]).bucketOf(inbound), .waitingOnYou)
        XCTAssertEqual(vm([outbound]).bucketOf(outbound), .waitingOnThem)
    }
    func testNewerInboundWinsEvenWhenDirectionIsStaleOutbound() {
        let now = Date()
        let l = lead(
            direction: "out",
            lastInbound: now,
            lastOutbound: now.addingTimeInterval(-3600)
        )
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnYou)
    }
    func testNewerOutboundWinsEvenWhenDirectionIsStaleInbound() {
        let now = Date()
        let l = lead(
            direction: "in",
            lastInbound: now.addingTimeInterval(-3600),
            lastOutbound: now
        )
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnThem)
    }
    func testInboundOutboundTieUsesInboundDirection() {
        let now = Date()
        let l = lead(direction: "in", lastInbound: now, lastOutbound: now)
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnYou)
    }
    func testInboundOutboundTieUsesOutboundDirection() {
        let now = Date()
        let l = lead(direction: "out", lastInbound: now, lastOutbound: now)
        XCTAssertEqual(vm([l]).bucketOf(l), .waitingOnThem)
    }
    func testNewLeadIgnoresOperatorCorrection() {
        let l = lead(stage: .newLead, operatorActionRequired: .now)
        XCTAssertEqual(vm([l]).bucketOf(l), .fresh)
    }
    func testDueTodayStillOutranksOperatorCorrection() {
        let l = lead(operatorActionRequired: .now, followUp: .now)
        XCTAssertEqual(vm([l]).bucketOf(l), .dueToday)
    }
    func testOverdueOutranksHandledState() {   // date buckets stay first-priority
        let l = lead(direction: "in", lastInbound: .now, followUp: Calendar.current.date(byAdding: .day, value: -2, to: .now))
        XCTAssertEqual(vm([l]).bucketOf(l), .overdue)
    }
    func testVocabulary() {
        XCTAssertEqual(PipelineViewModel.TriageBucket.waitingOnYou.label, "YOUR MOVE")
        XCTAssertEqual(PipelineViewModel.TriageBucket.waitingOnThem.label, "WAITING")
    }

    func testYourMoveAgeUsesManualCorrectionInsteadOfOldInbound() {
        let now = Date(timeIntervalSince1970: 20_000_000)
        XCTAssertEqual(
            LeadChaseStrip.yourMoveAge(
                lastInboundAt: now.addingTimeInterval(-180 * 86_400),
                operatorActionRequiredAt: now.addingTimeInterval(-30 * 60),
                now: now
            ),
            "NOW"
        )
    }

    func testYourMoveAgeUsesNewestInboundAfterManualCorrection() {
        let now = Date(timeIntervalSince1970: 20_000_000)
        XCTAssertEqual(
            LeadChaseStrip.yourMoveAge(
                lastInboundAt: now.addingTimeInterval(-2 * 3600),
                operatorActionRequiredAt: now.addingTimeInterval(-24 * 3600),
                now: now
            ),
            "2H"
        )
    }

    // MARK: - Comeback rule (spec §2.2)

    func testComebackDefaultsToThreeDays() {
        let d = PipelineViewModel.comebackDate(existing: nil, from: .now)
        XCTAssertEqual(d.timeIntervalSinceNow, 3 * 86_400, accuracy: 5)
    }
    func testSoonerFutureFollowUpKept() {
        let tomorrow = Date().addingTimeInterval(86_400)
        XCTAssertEqual(PipelineViewModel.comebackDate(existing: tomorrow, from: .now), tomorrow)
    }
    func testPastDueFollowUpReplaced() {   // else an overdue lead could never leave OVERDUE
        let yesterday = Date().addingTimeInterval(-86_400)
        let d = PipelineViewModel.comebackDate(existing: yesterday, from: .now)
        XCTAssertEqual(d.timeIntervalSinceNow, 3 * 86_400, accuracy: 5)
    }

    // MARK: - text_message activity type (spec §3 — web parity: pipeline.ts TextMessage)

    func testTextMessageActivityType() {
        XCTAssertEqual(ActivityType.textMessage.rawValue, "text_message")
        XCTAssertFalse(ActivityType.textMessage.isSystemGenerated)
    }

    func testEmailComposeActivityTypePreservesProviderEmailBoundary() {
        XCTAssertEqual(ActivityType.emailCompose.rawValue, "email_compose")
        XCTAssertEqual(ActivityType.emailCompose.icon, "envelope.fill")
        XCTAssertFalse(ActivityType.emailCompose.isSystemGenerated)
    }

    // MARK: - Work-first summary computeds (spec §7)

    func testNeedActionCount() {   // overdue + dueToday + yourMove, never waiting/fresh
        let overdue = lead(followUp: .now.addingTimeInterval(-2 * 86_400))
        let dueToday = lead(followUp: .now)
        let yourMove = lead(direction: "in", lastInbound: .now.addingTimeInterval(-3600))
        let waiting = lead(direction: "out")
        let fresh = lead(stage: .newLead)
        XCTAssertEqual(vm([overdue, dueToday, yourMove, waiting, fresh]).needActionCount, 3)
    }

    func testOpenPipelineValueUnweighted() {
        let a = lead(); a.estimatedValue = 10_000
        let b = lead(); b.estimatedValue = 4_500
        let won = lead(stage: .won); won.estimatedValue = 99_999
        let archived = lead(); archived.estimatedValue = 3_000; archived.archivedAt = .now
        XCTAssertEqual(vm([a, b, won, archived]).openPipelineValue, 14_500)
    }

    func testWonThisMonthValuePrefersActual() {
        let wonNow = lead(stage: .won)
        wonNow.actualCloseDate = .now
        wonNow.actualValue = 12_000
        wonNow.estimatedValue = 10_000
        let wonOld = lead(stage: .won)
        wonOld.actualCloseDate = Calendar.current.date(byAdding: .month, value: -2, to: .now)
        wonOld.estimatedValue = 8_000
        XCTAssertEqual(vm([wonNow, wonOld]).wonThisMonthValue, 12_000)
    }
}
