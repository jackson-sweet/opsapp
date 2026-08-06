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
        XCTAssertEqual(Copy.discardConfirmTitle, "DESTRUCTIVE. NO UNDO.")
        XCTAssertEqual(Copy.discardConfirmBody, "Deletes this work from this phone. It was never sent.")
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
