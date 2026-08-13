//
//  SiteVisitAuthorBackfillTests.swift
//  OPSTests
//
//  Launch-time heal for site-visit rows the V19→V20 lightweight migration left
//  authorless. The outbound boundary heals a row when its turn comes; this sweep
//  clears the whole backlog up front so a wedged child never blocks its visit's
//  completion in the first place.
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitAuthorBackfillTests: XCTestCase {
    private var liveContainers: [ModelContainer] = []

    private let companyId = "11111111-1111-4111-8111-111111111111"
    private let visitAuthor = "22222222-2222-4222-8222-222222222222"
    private let sessionUser = "77777777-7777-4777-8777-777777777777"
    private let visitId = "33333333-3333-4333-8333-333333333333"
    private let orphanVisitId = "88888888-8888-4888-8888-888888888888"

    override func tearDown() {
        liveContainers.removeAll()
        super.tearDown()
    }

    func test_authorlessRowsHealFromTheirParentVisit() throws {
        let context = try makeContainer().mainContext
        context.insert(makeVisit(author: visitAuthor))
        let draft = makeDraft(author: nil)
        let artifact = makeArtifact(author: nil)
        let answer = makeAnswer(author: nil)
        context.insert(draft)
        context.insert(artifact)
        context.insert(answer)

        let result = try SiteVisitAuthorHeal.backfillAuthors(
            in: context,
            sessionUserId: sessionUser
        )

        XCTAssertEqual(result.healedIds, [artifact.id, answer.id, draft.id].sorted())
        XCTAssertTrue(result.unresolvedIds.isEmpty)
        XCTAssertEqual(draft.createdBy, visitAuthor)
        XCTAssertEqual(artifact.createdBy, visitAuthor)
        XCTAssertEqual(answer.createdBy, visitAuthor)
    }

    /// The V19 `SiteVisit` had no `createdBy` either, so the parent is a candidate
    /// in its own right — and a wedged parent blocks every child behind it.
    func test_authorlessParentVisitAndChildBothFallBackToSessionUser() throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit(author: nil)
        let draft = makeDraft(author: nil)
        context.insert(visit)
        context.insert(draft)

        let result = try SiteVisitAuthorHeal.backfillAuthors(
            in: context,
            sessionUserId: sessionUser
        )

        XCTAssertEqual(result.healedIds, [draft.id, visit.id].sorted())
        XCTAssertEqual(visit.createdBy, sessionUser)
        XCTAssertEqual(draft.createdBy, sessionUser)
    }

    /// A visit whose parent row never made it to this device (orphaned child) still
    /// heals off the session user — the operator on this phone is the only author
    /// this row can honestly claim.
    func test_rowWithoutAnyParentVisitFallsBackToSessionUser() throws {
        let context = try makeContainer().mainContext
        let draft = makeDraft(author: nil, siteVisitId: orphanVisitId)
        context.insert(draft)

        let result = try SiteVisitAuthorHeal.backfillAuthors(
            in: context,
            sessionUserId: sessionUser
        )

        XCTAssertEqual(result.healedIds, [draft.id])
        XCTAssertEqual(draft.createdBy, sessionUser)
    }

    /// Signed out at launch: nothing resolves, nothing is written, and the row is
    /// reported unresolved so the caller leaves its one-time flag unset and retries.
    func test_noSessionUserLeavesRowsUntouchedAndReportsThemUnresolved() throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit(author: nil)
        let draft = makeDraft(author: nil)
        context.insert(visit)
        context.insert(draft)
        let updatedAt = draft.updatedAt

        let result = try SiteVisitAuthorHeal.backfillAuthors(
            in: context,
            sessionUserId: nil
        )

        XCTAssertTrue(result.healedIds.isEmpty)
        XCTAssertEqual(result.unresolvedIds, [draft.id, visit.id].sorted())
        XCTAssertFalse(result.isClean, "an unresolved row must keep the sweep armed")
        XCTAssertNil(draft.createdBy)
        XCTAssertNil(visit.createdBy)
        XCTAssertEqual(draft.updatedAt, updatedAt)
    }

    func test_rowsThatAlreadyHaveAnAuthorAreLeftCompletelyAlone() throws {
        let context = try makeContainer().mainContext
        context.insert(makeVisit(author: visitAuthor))
        let draft = makeDraft(author: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")
        draft.needsSync = false
        context.insert(draft)
        let updatedAt = draft.updatedAt

        let result = try SiteVisitAuthorHeal.backfillAuthors(
            in: context,
            sessionUserId: sessionUser
        )

        XCTAssertTrue(result.healedIds.isEmpty)
        XCTAssertTrue(result.unresolvedIds.isEmpty)
        XCTAssertEqual(draft.createdBy, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        XCTAssertEqual(draft.updatedAt, updatedAt)
        XCTAssertFalse(draft.needsSync)
    }

    /// Soft-deleted rows sync as a delete, which carries no author — healing them
    /// would be busywork, and counting them unresolved would pin the one-time flag
    /// open forever.
    func test_softDeletedRowsAreSkippedEntirely() throws {
        let context = try makeContainer().mainContext
        context.insert(makeVisit(author: visitAuthor))
        let draft = makeDraft(author: nil)
        draft.deletedAt = Date(timeIntervalSince1970: 1_700_000_100)
        context.insert(draft)

        let result = try SiteVisitAuthorHeal.backfillAuthors(
            in: context,
            sessionUserId: nil
        )

        XCTAssertTrue(result.healedIds.isEmpty)
        XCTAssertTrue(result.unresolvedIds.isEmpty)
        XCTAssertNil(draft.createdBy)
    }

    /// The heal writes `created_by` only. Flipping `needsSync` would enqueue a
    /// write for every legacy row on the device at once.
    func test_backfillDoesNotDirtyOrTouchAnyOtherField() throws {
        let context = try makeContainer().mainContext
        context.insert(makeVisit(author: visitAuthor))
        let draft = makeDraft(author: nil)
        draft.needsSync = false
        draft.lastSyncedAt = nil
        context.insert(draft)
        let updatedAt = draft.updatedAt

        _ = try SiteVisitAuthorHeal.backfillAuthors(
            in: context,
            sessionUserId: sessionUser
        )

        XCTAssertEqual(draft.createdBy, visitAuthor)
        XCTAssertFalse(draft.needsSync)
        XCTAssertNil(draft.lastSyncedAt)
        XCTAssertEqual(draft.updatedAt, updatedAt)
    }

    func test_emptyStoreIsCleanSoTheCallerCanRetireTheSweep() throws {
        let context = try makeContainer().mainContext

        let result = try SiteVisitAuthorHeal.backfillAuthors(
            in: context,
            sessionUserId: sessionUser
        )

        XCTAssertTrue(result.healedIds.isEmpty)
        XCTAssertTrue(result.unresolvedIds.isEmpty)
    }

    // MARK: - Fixtures

    private func makeVisit(author: String?) -> SiteVisit {
        SiteVisit(
            id: visitId,
            companyId: companyId,
            status: .inProgress,
            scheduledAt: Date(timeIntervalSince1970: 1_700_000_000),
            createdBy: author,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeDraft(
        author: String?,
        siteVisitId: String? = nil
    ) -> SiteVisitIdentityDraft {
        SiteVisitIdentityDraft(
            id: "55555555-5555-4555-8555-555555555555",
            siteVisitId: siteVisitId ?? visitId,
            companyId: companyId,
            clientName: "Ridge Line Exteriors",
            createdBy: author,
            createdAt: Date(timeIntervalSince1970: 1_700_000_002)
        )
    }

    private func makeArtifact(author: String?) -> SiteVisitCaptureArtifact {
        SiteVisitCaptureArtifact(
            id: "44444444-4444-4444-8444-444444444444",
            siteVisitId: visitId,
            companyId: companyId,
            kind: .photo,
            source: .camera,
            localAssetURL: nil,
            createdBy: author,
            createdAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
    }

    private func makeAnswer(author: String?) -> SiteVisitChecklistAnswer {
        SiteVisitChecklistAnswer(
            id: "66666666-6666-4666-8666-666666666666",
            siteVisitId: visitId,
            companyId: companyId,
            opportunityId: nil,
            siteVisitTypeId: nil,
            fieldId: "gate_code",
            label: "Gate code",
            kind: .shortText,
            required: false,
            sortOrder: 0,
            createdBy: author,
            createdAt: Date(timeIntervalSince1970: 1_700_000_003)
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
            SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self,
            SyncOperation.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        liveContainers.append(container)
        return container
    }
}
