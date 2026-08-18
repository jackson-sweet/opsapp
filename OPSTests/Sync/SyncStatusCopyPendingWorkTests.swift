//
//  SyncStatusCopyPendingWorkTests.swift
//  OPSTests
//
//  SYNC RECOVERY · T6 — locks every PENDING WORK copy static to its exact,
//  ops-copywriter-approved wording (the plan's FINAL COPY BLOCK) plus the
//  interpolation and tone mapping. The copy chokepoint can't drift without a red.
//

import XCTest
@testable import OPS

final class SyncStatusCopyPendingWorkTests: XCTestCase {

    private typealias Copy = SyncStatusCopy.PendingWork

    // MARK: - Reconnect toast

    func testConnectionRestoredTogglesSingularAndPlural() {
        XCTAssertEqual(
            SyncStatusCopy.connectionRestored(pendingCount: 1),
            "// BACK ONLINE · SAVING 1 CHANGE"
        )
        XCTAssertEqual(
            SyncStatusCopy.connectionRestored(pendingCount: 2),
            "// BACK ONLINE · SAVING 2 CHANGES"
        )
        XCTAssertEqual(SyncStatusCopy.connectionRestoredAction, "VIEW")
    }

    /// The toast used to say "ITEMS" while the panel header said "changes" for
    /// the very same queue. One vocabulary, one count.
    func testConnectionRestoredSharesThePanelsVocabulary() {
        let toast = SyncStatusCopy.connectionRestored(pendingCount: 3)
        let header = SyncStatusCopy.header(pendingCount: 3, failedCount: 0, isSyncing: true)
        XCTAssertTrue(toast.contains("CHANGES"))
        XCTAssertTrue(header.contains("changes"))
        XCTAssertFalse(toast.contains("ITEM"))
    }

    // MARK: - Screen + section headers

    func testScreenAndSectionHeaders() {
        XCTAssertEqual(Copy.screenTitle, "PENDING WORK")
        XCTAssertEqual(Copy.sectionAttention, "// NEEDS ATTENTION")
        XCTAssertEqual(Copy.sectionSending, "// SENDING")
        XCTAssertEqual(Copy.sectionDrafts, "// DRAFTS")
        XCTAssertEqual(Copy.sectionUnlinked, "// NOT LINKED")
    }

    // MARK: - Empty state

    func testEmptyState() {
        XCTAssertEqual(Copy.emptyHero, "—")
        XCTAssertEqual(Copy.emptyLabel, "// NOTHING PENDING · ALL CHANGES SAVED")
    }

    // MARK: - Row status lines

    func testFixedStatusLines() {
        XCTAssertEqual(Copy.parkedRow, "Server said no — held here")
        XCTAssertEqual(Copy.offlineRow, "Waiting for signal")
        XCTAssertEqual(Copy.orphanRow, "Not linked to a job or lead")
        XCTAssertEqual(Copy.draftRow, "Not sent yet — open to finish")
        XCTAssertEqual(Copy.retryingRow, "Retrying…")
        XCTAssertEqual(Copy.retrySucceededRow, "Updated")
        XCTAssertEqual(Copy.retryFailedRow, "Retry failed — still here")
    }

    func testQuarantineRowSpeaksToTheReason() {
        // A parent-deleted packet is not an identity mystery — the office
        // deleted the visit in OPS. Say the event, then the guarantee.
        XCTAssertEqual(
            Copy.quarantineRow(for: .parentDeleted),
            "Deleted in OPS — kept on this phone"
        )
        // Identity-review packets keep the existing custody line.
        XCTAssertEqual(Copy.quarantineRow(for: .foreignCompany), Copy.quarantineRow)
        XCTAssertEqual(Copy.quarantineRow(for: .malformedIdentity), Copy.quarantineRow)
        XCTAssertEqual(Copy.quarantineRow(for: .ambiguousBinding), Copy.quarantineRow)
        XCTAssertEqual(Copy.quarantineRow(for: nil), Copy.quarantineRow)
    }

    func testBackoffRowInterpolationAndFloor() {
        XCTAssertEqual(Copy.backoffRow(seconds: 40), "Retrying — next in 40s")
        XCTAssertEqual(Copy.backoffRow(seconds: 1), "Retrying — next in 1s")
        // Floored to 1 — the operator never sees "next in 0s" or a negative.
        XCTAssertEqual(Copy.backoffRow(seconds: 0), "Retrying — next in 1s")
        XCTAssertEqual(Copy.backoffRow(seconds: -5), "Retrying — next in 1s")
    }

    // MARK: - Detail sheet

    func testParkedDetailBlock() {
        XCTAssertEqual(Copy.parkedDetailLabel, "SYS :: REJECTED BY SERVER")
        XCTAssertEqual(Copy.parkedDetailBody, "Your copy is safe on this phone. Retry now or export it.")
    }

    // MARK: - Actions / labels / confirms

    func testActionAndConfirmCopy() {
        XCTAssertEqual(Copy.linkAction, "LINK")
        XCTAssertEqual(Copy.linkPickerTitle, "LINK TO")
        XCTAssertEqual(Copy.exportAction, "EXPORT")
        XCTAssertEqual(Copy.deleteAction, "DELETE")
        XCTAssertEqual(Copy.stopSendingAction, "STOP SENDING")
        XCTAssertEqual(Copy.discardConfirmTitle, "DESTRUCTIVE. NO UNDO.")
        XCTAssertEqual(Copy.stopSendingConfirmTitle, "STOP SENDING?")
        XCTAssertEqual(Copy.discardConfirmBody, "Deletes this work from this phone. It was never sent.")
        XCTAssertEqual(Copy.staleReviewTag, "STALE · 30D")
        XCTAssertEqual(Copy.discardFailure, "COULD NOT DELETE · WORK IS STILL HERE")
    }

    // MARK: - Discard confirmation bodies (one per scope)

    /// A stopped send names what stays, not what dies — the visit and everything
    /// captured on it are untouched, here and in OPS.
    func testQueuedSendsConfirmationPromisesNothingIsDeleted() {
        XCTAssertEqual(
            Copy.discardConfirmationBody(for: .queuedSends(count: 1)),
            "Stops 1 queued send. The visit and everything captured on it stay — nothing is deleted here or in OPS."
        )
        XCTAssertEqual(
            Copy.discardConfirmationBody(for: .queuedSends(count: 4)),
            "Stops 4 queued sends. The visit and everything captured on it stay — nothing is deleted here or in OPS."
        )
    }

    func testLocalPhotosConfirmationSaysThereIsNoOtherCopy() {
        XCTAssertEqual(
            Copy.discardConfirmationBody(for: .localPhotos(count: 1)),
            "Deletes 1 unsent photo from this phone. They never reached OPS — there is no other copy."
        )
        XCTAssertEqual(
            Copy.discardConfirmationBody(for: .localPhotos(count: 2)),
            "Deletes 2 unsent photos from this phone. They never reached OPS — there is no other copy."
        )
    }

    func testQuarantinedVisitConfirmationNamesWhatWillBeDeleted() {
        XCTAssertEqual(
            Copy.discardConfirmationBody(for: .quarantinedVisit(capturedItemCount: 1)),
            "Deletes the protected recovery packet — 1 captured item — from this phone. There is no other copy."
        )
        XCTAssertEqual(
            Copy.discardConfirmationBody(for: .quarantinedVisit(capturedItemCount: 7)),
            "Deletes the protected recovery packet — 7 captured items — from this phone. There is no other copy."
        )
    }

    func testLeadDeliveryConfirmationIsUnchanged() {
        XCTAssertEqual(
            Copy.discardConfirmationBody(for: .leadDeliveryRequest),
            "Cancels this pending lead creation. The client stays on this phone."
        )
    }

    // MARK: - Scope-driven title + action label

    /// Only a scope that really erases the only copy is allowed to shout
    /// "DESTRUCTIVE. NO UNDO." — a stopped send must not pretend to be one.
    func testConfirmationTitleWarnsOnlyForDestructiveScopes() {
        XCTAssertEqual(
            Copy.discardConfirmationTitle(for: .localPhotos(count: 2)),
            "DESTRUCTIVE. NO UNDO."
        )
        XCTAssertEqual(
            Copy.discardConfirmationTitle(for: .quarantinedVisit(capturedItemCount: 2)),
            "DESTRUCTIVE. NO UNDO."
        )
        XCTAssertEqual(
            Copy.discardConfirmationTitle(for: .queuedSends(count: 2)),
            "STOP SENDING?"
        )
        XCTAssertEqual(
            Copy.discardConfirmationTitle(for: .leadDeliveryRequest),
            "STOP SENDING?"
        )
    }

    func testActionLabelMatchesWhatTheScopeActuallyDoes() {
        XCTAssertEqual(Copy.discardActionLabel(for: .localPhotos(count: 2)), "DELETE")
        XCTAssertEqual(
            Copy.discardActionLabel(for: .quarantinedVisit(capturedItemCount: 2)),
            "DELETE"
        )
        XCTAssertEqual(Copy.discardActionLabel(for: .queuedSends(count: 2)), "STOP SENDING")
        XCTAssertEqual(Copy.discardActionLabel(for: .leadDeliveryRequest), "STOP SENDING")
    }

    func testExportTitleInterpolation() {
        XCTAssertEqual(Copy.exportTitle(name: "Charles"), "OPS EXPORT — Charles")
        XCTAssertEqual(Copy.exportTitle(name: "Lyall St"), "OPS EXPORT — Lyall St")
    }

    func testRetryAllButtonInterpolation() {
        XCTAssertEqual(Copy.retryAllButton(count: 2), "RETRY ALL (2)")
        XCTAssertEqual(Copy.retryAllButton(count: 0), "RETRY ALL (0)")
        XCTAssertEqual(Copy.retryAllButton(count: 12), "RETRY ALL (12)")
    }

    func testPillBadgeInterpolation() {
        XCTAssertEqual(Copy.pillBadge(count: 3), "3 NEED A LOOK")
        XCTAssertEqual(Copy.pillBadge(count: 1), "1 NEED A LOOK")
    }

    // MARK: - Member labels

    func testMemberLabels() {
        XCTAssertEqual(Copy.memberLabel(.client), "CLIENT")
        XCTAssertEqual(Copy.memberLabel(.lead), "LEAD")
        XCTAssertEqual(Copy.memberLabel(.deck), "DECK")
        XCTAssertEqual(Copy.memberLabel(.photos), "PHOTOS")
        XCTAssertEqual(Copy.memberLabel(.other("notes")), "NOTES")
    }

    // MARK: - Row titles

    func testLeadTitle() {
        XCTAssertEqual(Copy.leadTitle(name: "Amber Chen"), "Lead · Amber Chen")
        XCTAssertEqual(Copy.leadTitle(name: "  "), "New lead")
        XCTAssertEqual(Copy.leadTitle(name: ""), "New lead")
    }

    func testPhotosTitlePluralisation() {
        XCTAssertEqual(Copy.photosTitle(count: 1), "1 photo")
        XCTAssertEqual(Copy.photosTitle(count: 2), "2 photos")
        XCTAssertEqual(Copy.photosTitle(count: 0), "0 photos")
    }

    func testDraftTitleFallback() {
        XCTAssertEqual(Copy.draftTitle(displayName: "Charles"), "Charles")
        XCTAssertEqual(Copy.draftTitle(displayName: "   "), "Site visit")
        XCTAssertEqual(Copy.draftTitle(displayName: ""), "Site visit")
    }

    func testSiteVisitPacketSummary() {
        XCTAssertEqual(
            Copy.siteVisitPacketSummary(capturedItemCount: 3, blockedStage: .visit),
            "3 CAPTURED · VISIT"
        )
        XCTAssertEqual(
            Copy.siteVisitPacketSummary(capturedItemCount: 1, blockedStage: .media),
            "1 CAPTURED · MEDIA"
        )
        XCTAssertEqual(
            Copy.siteVisitPacketSummary(capturedItemCount: 0, blockedStage: .completion),
            "0 CAPTURED · COMPLETION"
        )
    }

    func testOrphanTitleFallback() {
        XCTAssertEqual(Copy.orphanTitle(title: "Site visit deck"), "Site visit deck")
        XCTAssertEqual(Copy.orphanTitle(title: ""), "Deck design")
    }

    // MARK: - Status-line resolver (text + tone precedence)

    func testStatusLineParked() {
        let result = Copy.statusLine(statusRaw: "parked", lastError: "22023 unsupported field", secondsUntilRetry: nil)
        XCTAssertEqual(result.text, "Server said no — held here")
        XCTAssertEqual(toneName(result.tone), "stuck")
    }

    func testStatusLineInProgress() {
        let result = Copy.statusLine(statusRaw: "inProgress", lastError: nil, secondsUntilRetry: nil)
        XCTAssertEqual(result.text, "Saving…")
        XCTAssertEqual(toneName(result.tone), "syncing")
    }

    func testStatusLineOfflineBeatsBackoff() {
        // A network error reads as waiting-for-signal even while a backoff window
        // is counting — the countdown can't fire offline, so signal wins.
        let result = Copy.statusLine(
            statusRaw: "pending",
            lastError: "The network connection was lost.",
            secondsUntilRetry: 40
        )
        XCTAssertEqual(result.text, "Waiting for signal")
        XCTAssertEqual(toneName(result.tone), "waiting")
    }

    func testStatusLineBackoffCountdown() {
        let result = Copy.statusLine(statusRaw: "pending", lastError: nil, secondsUntilRetry: 40)
        XCTAssertEqual(result.text, "Retrying — next in 40s")
        XCTAssertEqual(toneName(result.tone), "waiting")
    }

    func testStatusLineFailed() {
        let result = Copy.statusLine(statusRaw: "failed", lastError: "23514 conflict", secondsUntilRetry: nil)
        XCTAssertEqual(result.text, "Couldn't save yet")
        XCTAssertEqual(toneName(result.tone), "attention")
    }

    func testStatusLinePendingQueued() {
        let result = Copy.statusLine(statusRaw: "pending", lastError: nil, secondsUntilRetry: nil)
        XCTAssertEqual(result.text, "Waiting to sync")
        XCTAssertEqual(toneName(result.tone), "waiting")
    }

    func testStatusLineLocalPhotoQueued() {
        let result = Copy.statusLine(statusRaw: "local", lastError: nil, secondsUntilRetry: nil)
        XCTAssertEqual(result.text, "Waiting to sync")
        XCTAssertEqual(toneName(result.tone), "waiting")
    }

    // MARK: - Failure copy names the action that actually failed

    /// A failed stop must never report a deletion. "WORK NOT DELETED" after a
    /// stopped send implies the app tried to erase something — the exact
    /// over-promise that made bug f7431c17 read as catastrophic in the field.
    func testFailureCopyMatchesTheActionTheOperatorTook() {
        XCTAssertEqual(
            Copy.failureTitle(for: .queuedSends(count: 3)),
            "SEND NOT STOPPED"
        )
        XCTAssertEqual(
            Copy.failureMessage(for: .queuedSends(count: 3)),
            "COULD NOT STOP THIS SEND · IT IS STILL QUEUED"
        )
        XCTAssertEqual(
            Copy.failureTitle(for: .leadDeliveryRequest),
            "SEND NOT STOPPED"
        )

        // Scopes that really do erase the last copy keep the deletion language.
        XCTAssertEqual(
            Copy.failureTitle(for: .localPhotos(count: 2)),
            "WORK NOT DELETED"
        )
        XCTAssertEqual(
            Copy.failureMessage(for: .localPhotos(count: 2)),
            "COULD NOT DELETE · WORK IS STILL HERE"
        )
        XCTAssertEqual(
            Copy.failureTitle(for: .quarantinedVisit(capturedItemCount: 2)),
            "WORK NOT DELETED"
        )
    }

    // MARK: - Helpers

    /// `SyncStatusTone` is a plain enum used via pattern-match, not `==`; name it
    /// so assertions stay readable without depending on Equatable synthesis.
    private func toneName(_ tone: SyncStatusTone) -> String {
        switch tone {
        case .syncing:   return "syncing"
        case .waiting:   return "waiting"
        case .attention: return "attention"
        case .stuck:     return "stuck"
        }
    }
}
