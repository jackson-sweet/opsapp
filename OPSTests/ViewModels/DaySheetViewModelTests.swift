//
//  DaySheetViewModelTests.swift
//  OPSTests
//
//  The day sheet is a pure presentation transform over the console's existing
//  triage buckets — no second cadence, no second fetch. These tests lock that
//  transform: the five buckets collapsing into three whose-move-is-it groups,
//  the exact order within each, the defensive row filter (scope, deleted,
//  archived, terminal), the urgency vocabulary, milestone gating on edit
//  permission, and the header counts.
//
//  Every date derives from a FIXED `now` (Monday 2026-07-27 12:00 local) so
//  the day/hour vocabulary asserts exact strings without time-of-day or
//  calendar-date brittleness.
//

import XCTest
@testable import OPS

@MainActor
final class DaySheetViewModelTests: XCTestCase {

    // MARK: - Fixed clock

    private static func at(_ year: Int, _ month: Int, _ day: Int,
                           hour: Int = 12, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        guard let date = Calendar.current.date(from: components) else {
            fatalError("invalid fixture date \(year)-\(month)-\(day)")
        }
        return date
    }

    /// Monday, 2026-07-27 12:00 local. +1d = Tue, +4d = Fri, +8d = Aug 4.
    private static let now = at(2026, 7, 27)

    private func plusDays(_ count: Int) -> Date {
        guard let date = Calendar.current.date(byAdding: .day, value: count, to: Self.now) else {
            fatalError("date math failed")
        }
        return date
    }

    private func minusHours(_ count: Double) -> Date {
        Self.now.addingTimeInterval(-count * 3600)
    }

    // MARK: - Policies

    /// view + edit scoped to the operator's own assignments — the delegate case.
    private func assignedPolicy() -> LeadAccessPolicy {
        LeadAccessPolicy(currentUserId: "u1",
                         permissions: ["pipeline.view": "assigned",
                                       "pipeline.edit": "assigned"],
                         explicitPermissionKeys: [])
    }

    /// Sees everything, edits nothing — `pipeline.edit` explicitly revoked.
    private func viewOnlyPolicy() -> LeadAccessPolicy {
        LeadAccessPolicy(currentUserId: "u1",
                         permissions: ["pipeline.view": "all"],
                         explicitPermissionKeys: ["pipeline.edit"])
    }

    /// Sees and edits everything — the owner case.
    private func allPolicy() -> LeadAccessPolicy {
        LeadAccessPolicy(currentUserId: "u1",
                         permissions: ["pipeline.view": "all",
                                       "pipeline.edit": "all"],
                         explicitPermissionKeys: [])
    }

    // MARK: - Fixtures

    private func lead(_ id: String,
                      stage: PipelineStage = .quoting,
                      assignedTo: String? = "u1",
                      due: Date? = nil,
                      created: Date = DaySheetViewModelTests.now,
                      archived: Bool = false,
                      deleted: Bool = false) -> Opportunity {
        let opportunity = Opportunity(id: id,
                                      companyId: "co-1",
                                      contactName: "Lead \(id)",
                                      stage: stage,
                                      stageEnteredAt: created,
                                      createdAt: created,
                                      updatedAt: created)
        opportunity.assignedTo = assignedTo
        opportunity.nextFollowUpAt = due
        if archived { opportunity.archivedAt = Self.now }
        if deleted { opportunity.deletedAt = Self.now }
        return opportunity
    }

    private func buckets(overdue: [Opportunity] = [],
                         dueToday: [Opportunity] = [],
                         waitingOnYou: [Opportunity] = [],
                         fresh: [Opportunity] = [],
                         waitingOnThem: [Opportunity] = [],
                         unconvertedWon: [Opportunity] = []) -> PipelineViewModel.TriageBuckets {
        PipelineViewModel.TriageBuckets(overdue: overdue,
                                        dueToday: dueToday,
                                        waitingOnYou: waitingOnYou,
                                        fresh: fresh,
                                        waitingOnThem: waitingOnThem,
                                        unconvertedWon: unconvertedWon)
    }

    private func groups(_ buckets: PipelineViewModel.TriageBuckets,
                        policy: LeadAccessPolicy? = nil) -> DaySheetViewModel.Groups {
        DaySheetViewModel.groups(from: buckets,
                                 policy: policy ?? allPolicy(),
                                 now: Self.now)
    }

    // MARK: - Group collapse + ordering

    func test_yourMove_collapsesThreeBuckets_preservingBucketOrder() {
        let result = groups(buckets(
            overdue: [lead("o1", due: plusDays(-4)), lead("o2", due: plusDays(-1))],
            dueToday: [lead("d1", due: Self.now)],
            waitingOnYou: [lead("w1"), lead("w2")]
        ))

        XCTAssertEqual(result.yourMove.map(\.id), ["o1", "o2", "d1", "w1", "w2"])
    }

    func test_new_reSortsFreshByCreatedAtDescending() {
        let result = groups(buckets(fresh: [
            lead("f-old", stage: .newLead, created: minusHours(50)),
            lead("f-newest", stage: .newLead, created: minusHours(0.5)),
            lead("f-mid", stage: .newLead, created: minusHours(3.5)),
        ]))

        XCTAssertEqual(result.new.map(\.id), ["f-newest", "f-mid", "f-old"])
    }

    func test_waiting_datedComebacksAscending_thenUndatedInBucketOrder() {
        let result = groups(buckets(waitingOnThem: [
            lead("undated-1"),
            lead("far", due: plusDays(8)),
            lead("soon", due: plusDays(1)),
            lead("undated-2"),
            lead("mid", due: plusDays(4)),
        ]))

        XCTAssertEqual(result.waiting.map(\.id),
                       ["soon", "mid", "far", "undated-1", "undated-2"])
    }

    func test_unconvertedWon_neverReachesTheDaySheet() {
        let result = groups(buckets(
            waitingOnYou: [lead("w1")],
            unconvertedWon: [lead("won-1", stage: .won)]
        ))

        XCTAssertEqual(result.yourMove.map(\.id), ["w1"])
        XCTAssertEqual(result.new.count, 0)
        XCTAssertEqual(result.waiting.count, 0)
        XCTAssertEqual(result.total, 1)
    }

    // MARK: - Row filter

    func test_assignedScope_dropsLeadsAssignedElsewhereAndUnassigned() {
        let result = groups(buckets(
            overdue: [lead("mine", assignedTo: "u1", due: plusDays(-2)),
                      lead("theirs", assignedTo: "u2", due: plusDays(-2)),
                      lead("nobody", assignedTo: nil, due: plusDays(-2))],
            fresh: [lead("mine-fresh", stage: .newLead, assignedTo: "u1"),
                    lead("theirs-fresh", stage: .newLead, assignedTo: "u2")],
            waitingOnThem: [lead("theirs-waiting", assignedTo: "u2", due: plusDays(1))]
        ), policy: assignedPolicy())

        XCTAssertEqual(result.yourMove.map(\.id), ["mine"])
        XCTAssertEqual(result.new.map(\.id), ["mine-fresh"])
        XCTAssertEqual(result.waiting.map(\.id), [])
    }

    // The buckets already exclude these; the transform must not depend on that.
    func test_poisonedBuckets_dropTerminalDeletedAndArchivedRows() {
        let result = groups(buckets(
            overdue: [lead("keep-1", due: plusDays(-2)),
                      lead("terminal-won", stage: .won, due: plusDays(-2)),
                      lead("terminal-lost", stage: .lost, due: plusDays(-2)),
                      lead("terminal-discarded", stage: .discarded, due: plusDays(-2))],
            fresh: [lead("deleted", stage: .newLead, deleted: true),
                    lead("keep-2", stage: .newLead)],
            waitingOnThem: [lead("archived", due: plusDays(1), archived: true),
                            lead("keep-3", due: plusDays(1))]
        ))

        XCTAssertEqual(result.yourMove.map(\.id), ["keep-1"])
        XCTAssertEqual(result.new.map(\.id), ["keep-2"])
        XCTAssertEqual(result.waiting.map(\.id), ["keep-3"])
        XCTAssertEqual(result.total, 3)
    }

    // MARK: - Urgency vocabulary

    func test_overdue_reportsWholeDaysLate() {
        let result = groups(buckets(
            overdue: [lead("late", due: Self.at(2026, 7, 25, hour: 9))]
        ))

        XCTAssertEqual(result.yourMove.first?.urgency, .late(days: 2))
    }

    func test_dueToday_andWaitingOnYou_carryTheirBucketUrgency() {
        let result = groups(buckets(
            dueToday: [lead("today", due: Self.at(2026, 7, 27, hour: 16))],
            waitingOnYou: [lead("mine")]
        ))

        XCTAssertEqual(result.yourMove.map(\.urgency), [.today, .yourMove])
    }

    func test_freshLeads_carryAgeVocabulary() {
        let result = groups(buckets(fresh: [
            lead("just-in", stage: .newLead, created: minusHours(0.5)),
            lead("hours", stage: .newLead, created: minusHours(3.5)),
            lead("days", stage: .newLead, created: minusHours(50)),
        ]))

        XCTAssertEqual(result.new.map(\.urgency),
                       [.newLead(age: "NOW"), .newLead(age: "3H AGO"), .newLead(age: "2D AGO")])
    }

    func test_waitingLeads_carryComebackVocabulary() {
        let result = groups(buckets(waitingOnThem: [
            lead("tmrw", due: plusDays(1)),
            lead("friday", due: plusDays(4)),
            lead("august", due: plusDays(8)),
            lead("undated"),
        ]))

        XCTAssertEqual(result.waiting.map(\.urgency), [
            .waiting(back: "BACK TMRW"),
            .waiting(back: "BACK FRI"),
            .waiting(back: "BACK AUG 4"),
            .waiting(back: nil),
        ])
    }

    // Defensive: a same-day comeback should never land in WAITING, but if it
    // does the row must still read as a date, not as a negative day count.
    func test_waitingToday_readsBackToday() {
        let result = groups(buckets(waitingOnThem: [
            lead("today", due: Self.at(2026, 7, 27, hour: 18))
        ]))

        XCTAssertEqual(result.waiting.first?.urgency, .waiting(back: "BACK TODAY"))
    }

    // MARK: - Milestone gating

    func test_milestone_comesFromTheStageMap_whenEditIsGranted() {
        let result = groups(buckets(
            waitingOnYou: [lead("new", stage: .newLead),
                           lead("qualifying", stage: .qualifying),
                           lead("quoting", stage: .quoting)]
        ), policy: assignedPolicy())

        XCTAssertEqual(result.yourMove.map(\.milestone),
                       [.contacted, .siteVisited, .quoteSent])
    }

    func test_milestone_isWonForEveryLateFunnelStage() {
        let result = groups(buckets(
            waitingOnYou: [lead("quoted", stage: .quoted),
                           lead("follow", stage: .followUp),
                           lead("negotiation", stage: .negotiation)]
        ))

        XCTAssertEqual(result.yourMove.map(\.milestone), [.won, .won, .won])
    }

    func test_milestone_isNilWithoutEditPermission() {
        let result = groups(buckets(
            waitingOnYou: [lead("new", stage: .newLead)],
            fresh: [lead("fresh", stage: .newLead)]
        ), policy: viewOnlyPolicy())

        XCTAssertNil(result.yourMove.first?.milestone)
        XCTAssertNil(result.new.first?.milestone)
    }

    func test_milestone_isNilForLeadsTheOperatorCannotEdit() {
        // view: all, edit: assigned — a colleague's lead is visible, not editable.
        let policy = LeadAccessPolicy(currentUserId: "u1",
                                      permissions: ["pipeline.view": "all",
                                                    "pipeline.edit": "assigned"],
                                      explicitPermissionKeys: [])
        let result = groups(buckets(
            waitingOnYou: [lead("mine", stage: .quoting, assignedTo: "u1"),
                           lead("theirs", stage: .quoting, assignedTo: "u2")]
        ), policy: policy)

        XCTAssertEqual(result.yourMove.map(\.id), ["mine", "theirs"])
        XCTAssertEqual(result.yourMove.first?.milestone, .quoteSent)
        XCTAssertNil(result.yourMove.last?.milestone)
    }

    // MARK: - Header counts

    func test_counts_tallyEveryVisibleRow_andYourMoveSeparately() {
        let result = groups(buckets(
            overdue: [lead("o1", due: plusDays(-2))],
            dueToday: [lead("d1", due: Self.now)],
            waitingOnYou: [lead("w1"), lead("w2")],
            fresh: [lead("f1", stage: .newLead)],
            waitingOnThem: [lead("t1", due: plusDays(3)), lead("t2")],
            unconvertedWon: [lead("won", stage: .won)]
        ))

        XCTAssertEqual(result.yourMoveCount, 4)
        XCTAssertEqual(result.new.count, 1)
        XCTAssertEqual(result.waiting.count, 2)
        XCTAssertEqual(result.total, 7)
    }

    func test_emptyBuckets_produceEmptyGroups() {
        let result = groups(buckets())

        XCTAssertEqual(result.total, 0)
        XCTAssertEqual(result.yourMoveCount, 0)
        XCTAssertTrue(result.yourMove.isEmpty)
        XCTAssertTrue(result.new.isEmpty)
        XCTAssertTrue(result.waiting.isEmpty)
    }

    // MARK: - Row identity

    func test_rowIdentity_isTheLeadId_andRowsCompareByValue() {
        let result = groups(buckets(waitingOnYou: [lead("w1", stage: .quoting)]))
        let same = groups(buckets(waitingOnYou: [lead("w1", stage: .quoting)]))
        let different = groups(buckets(waitingOnYou: [lead("w2", stage: .quoting)]))

        XCTAssertEqual(result.yourMove.first?.id, "w1")
        XCTAssertEqual(result.yourMove, same.yourMove)
        XCTAssertNotEqual(result.yourMove, different.yourMove)
    }
}
