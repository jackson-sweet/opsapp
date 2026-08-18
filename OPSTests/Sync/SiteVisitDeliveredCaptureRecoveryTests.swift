//
//  SiteVisitDeliveredCaptureRecoveryTests.swift
//  OPSTests
//
//  A delivered capture must stop reading as unsent (bug fe497fb9).
//
//  The report: "there was already a Charles Krusekopf site visit saved, but
//  this one appeared as unsaved also. So tried to save it but now getting this
//  error." Two defects stack behind that sentence, and the server rows for that
//  company show both:
//
//   1. `last_committed_at` was NULL on every identity draft in the company —
//      including drafts bound to a lead whose visit had completed. Only the
//      auto-create-a-new-lead path ever stamped it; picking an EXISTING lead
//      from search bound the draft and stamped nothing. That is fixed at the
//      bind, not here.
//   2. PENDING WORK renders an unbound, uncommitted draft as an abandoned
//      capture — with no regard for whether its VISIT completed and synced. A
//      finished visit that was simply never attached to a lead therefore sat on
//      the recovery screen forever reading "Not sent yet — open to finish",
//      which is exactly the instruction an operator follows into re-running a
//      visit they had already saved.
//
//  Recovery is a SYNC surface: it answers "what has not reached the server". A
//  completed, pushed visit has reached it. An identity that was never bound to
//  a lead is a different gap, on a different screen.
//

import XCTest
@testable import OPS

final class SiteVisitDeliveredCaptureRecoveryTests: XCTestCase {

    private let visitId = "c8db6971-cbdc-4082-b8da-2d734d467a85"
    private let draftId = "2cce3834-267d-4fe9-886e-09f842379155"
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    /// The reported state, reproduced: a completed visit whose identity was
    /// never bound to a lead. Nothing is outstanding, so nothing belongs here.
    func test_build_omitsDraftWhoseVisitIsCompletedAndSynced() {
        let inventory = RecoveryInventory.build(
            ops: [],
            autocreates: [],
            photos: [],
            drafts: [draft()],
            artifacts: [],
            orphans: [],
            visits: [visit(isCompleted: true, needsSync: false)],
            now: now
        )

        XCTAssertTrue(
            inventory.drafts.isEmpty,
            "a finished, delivered capture is not unsent work — telling the operator to 'open to finish' it is what caused the duplicate visit"
        )
        XCTAssertTrue(inventory.isEmpty)
    }

    /// The case the screen exists for is untouched: a capture the operator
    /// walked away from mid-visit is still resumable.
    func test_build_keepsDraftWhoseVisitNeverCompleted() {
        let inventory = RecoveryInventory.build(
            ops: [],
            autocreates: [],
            photos: [],
            drafts: [draft()],
            artifacts: [],
            orphans: [],
            visits: [visit(isCompleted: false, needsSync: true)],
            now: now
        )

        XCTAssertEqual(
            inventory.drafts.map(\.id), [draftId],
            "an unfinished capture is exactly what the drafts section is for"
        )
    }

    /// Completed but still dirty means the push has not happened yet. That is
    /// live work and keeps its place — the guard is delivery, not status alone.
    func test_build_keepsDraftWhoseCompletedVisitStillNeedsSync() {
        let inventory = RecoveryInventory.build(
            ops: [],
            autocreates: [],
            photos: [],
            drafts: [draft()],
            artifacts: [],
            orphans: [],
            visits: [visit(isCompleted: true, needsSync: true)],
            now: now
        )

        XCTAssertEqual(
            inventory.drafts.map(\.id), [draftId],
            "finished on the phone is not the same as arrived on the server"
        )
    }

    /// No visit row for the draft is not evidence of delivery. Absence of proof
    /// keeps the operator's resume path — the screen never hides work on a
    /// guess.
    func test_build_keepsDraftWhenNoVisitRowIsKnown() {
        let inventory = RecoveryInventory.build(
            ops: [],
            autocreates: [],
            photos: [],
            drafts: [draft()],
            artifacts: [],
            orphans: [],
            visits: [],
            now: now
        )

        XCTAssertEqual(inventory.drafts.map(\.id), [draftId])
    }

    /// A committed draft was already omitted and stays omitted — this is the
    /// state the bind-time stamp now produces for every lead, not just
    /// auto-created ones.
    func test_build_omitsDraftCommittedToALead() {
        let committed = DraftSnapshot(
            id: draftId,
            siteVisitId: visitId,
            clientId: "ee02e44a-4d73-4afb-9645-786ceb9a4b14",
            opportunityId: "a53a50b5-6e87-44b3-bfd4-18d047211428",
            displayName: "Charles Krusekopf",
            createdAt: now.addingTimeInterval(-3600),
            lastCommittedAt: now.addingTimeInterval(-1800)
        )

        let inventory = RecoveryInventory.build(
            ops: [],
            autocreates: [],
            photos: [],
            drafts: [committed],
            artifacts: [],
            orphans: [],
            visits: [visit(isCompleted: false, needsSync: false)],
            now: now
        )

        XCTAssertTrue(inventory.isEmpty)
    }

    /// Ids arrive from both sides of the wire, so casing varies. A snapshot
    /// built from an uppercase id must still match its draft.
    func test_visitDeliverySnapshot_normalizesIdCasing() {
        let inventory = RecoveryInventory.build(
            ops: [],
            autocreates: [],
            photos: [],
            drafts: [draft()],
            artifacts: [],
            orphans: [],
            visits: [
                VisitDeliverySnapshot(
                    id: visitId.uppercased(),
                    isCompleted: true,
                    needsSync: false
                )
            ],
            now: now
        )

        XCTAssertTrue(
            inventory.drafts.isEmpty,
            "casing is a storage detail — the uppercase id is the same visit"
        )
    }

    // MARK: - Helpers

    private func draft() -> DraftSnapshot {
        DraftSnapshot(
            id: draftId,
            siteVisitId: visitId,
            clientId: nil,
            opportunityId: nil,
            displayName: "Charles Krusekopf",
            createdAt: now.addingTimeInterval(-3600),
            lastCommittedAt: nil
        )
    }

    private func visit(isCompleted: Bool, needsSync: Bool) -> VisitDeliverySnapshot {
        VisitDeliverySnapshot(
            id: visitId,
            isCompleted: isCompleted,
            needsSync: needsSync
        )
    }
}
