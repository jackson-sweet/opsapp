//
//  SyncStatusCopyTests.swift
//  OPSTests
//
//  Locks the plain-language rules for the notifications sync panel (bug
//  dbada8f5): honest counts, human titles, calm status lines, and — critically
//  — that a raw column name or raw Postgres error can never reach the user.
//

import XCTest
@testable import OPS

final class SyncStatusCopyTests: XCTestCase {

    // MARK: - Header count (the "1 vs 3" bug)

    func testHeaderCountsPendingPlusFailed() {
        // 1 pending + 2 failed must read as 3, never 1.
        XCTAssertEqual(
            SyncStatusCopy.header(pendingCount: 1, failedCount: 2, isSyncing: false),
            "3 changes need a look"
        )
    }

    func testHeaderSingularGrammar() {
        XCTAssertEqual(
            SyncStatusCopy.header(pendingCount: 1, failedCount: 0, isSyncing: false),
            "1 change waiting to sync"
        )
    }

    func testHeaderSyncingWhenNoFailures() {
        XCTAssertEqual(
            SyncStatusCopy.header(pendingCount: 2, failedCount: 0, isSyncing: true),
            "Saving 2 changes…"
        )
    }

    func testHeaderFailuresOutrankSyncing() {
        // Any failure surfaces (singular grammar) even mid-sync.
        XCTAssertEqual(
            SyncStatusCopy.header(pendingCount: 0, failedCount: 1, isSyncing: true),
            "1 change needs a look"
        )
    }

    // MARK: - Titles (no raw columns)

    func testVinylChangeGetsSemanticTitle() {
        XCTAssertEqual(
            SyncStatusCopy.title(entityType: "project", operationType: "update",
                                 changedFields: ["vinyl_ordered_by", "vinyl_order_status"]),
            "Vinyl order"
        )
    }

    func testGenericProjectUpdateTitle() {
        XCTAssertEqual(
            SyncStatusCopy.title(entityType: "project", operationType: "update",
                                 changedFields: ["title", "status"]),
            "Project update"
        )
    }

    func testCreateAndDeleteTitles() {
        XCTAssertEqual(SyncStatusCopy.title(entityType: "projectTask", operationType: "create", changedFields: []), "New task")
        XCTAssertEqual(SyncStatusCopy.title(entityType: "expense", operationType: "delete", changedFields: []), "Expense removed")
    }

    func testTitleNeverContainsRawColumnNames() {
        let title = SyncStatusCopy.title(entityType: "project", operationType: "update",
                                         changedFields: ["vinyl_ordered_by", "vinyl_order_status", "vinyl_order_id"])
        XCTAssertFalse(title.contains("_"), "titles must never leak snake_case column names")
    }

    // MARK: - Status lines

    func testPendingAndSyncingStatuses() {
        XCTAssertEqual(SyncStatusCopy.status(status: "pending", retryCount: 0, canRetry: true, rawError: nil).tone, .waiting)
        XCTAssertEqual(SyncStatusCopy.status(status: "inProgress", retryCount: 0, canRetry: true, rawError: nil).tone, .syncing)
    }

    func testFailedRetryableIsReassuring() {
        let s = SyncStatusCopy.status(status: "failed", retryCount: 2, canRetry: true,
                                      rawError: "Unexpected sync error: insert or update violates foreign key")
        XCTAssertEqual(s.tone, .attention)
        XCTAssertEqual(s.text, "Couldn't save — retrying")
        XCTAssertFalse(s.text.lowercased().contains("insert"), "raw Postgres text must never surface")
    }

    func testFailedOutOfRetriesAsksTheUser() {
        let s = SyncStatusCopy.status(status: "failed", retryCount: 20, canRetry: false, rawError: "boom")
        XCTAssertEqual(s.tone, .stuck)
        XCTAssertEqual(s.text, "Still can't save — retry or dismiss")
    }

    func testNetworkErrorReadsAsSignal() {
        let s = SyncStatusCopy.status(status: "failed", retryCount: 1, canRetry: true,
                                      rawError: "The Internet connection appears to be offline.")
        XCTAssertEqual(s.text, "Waiting for signal")
        XCTAssertEqual(s.tone, .waiting)
    }

    func testAuthErrorIsActionable() {
        let s = SyncStatusCopy.status(status: "failed", retryCount: 1, canRetry: true,
                                      rawError: "PGRST301 JWT expired (401)")
        XCTAssertEqual(s.text, "Sign in again to save")
    }

    func testDuplicateKeyReadsAsAlreadySaved() {
        let s = SyncStatusCopy.status(status: "failed", retryCount: 1, canRetry: true,
                                      rawError: "duplicate key value violates unique constraint projects_pkey")
        XCTAssertEqual(s.text, "Already saved")
    }

    // MARK: - Entity names

    func testEntityNameMapping() {
        XCTAssertEqual(SyncStatusCopy.entityName("projectTask"), "Task")
        XCTAssertEqual(SyncStatusCopy.entityName("subClient"), "Sub-Client")
        XCTAssertEqual(SyncStatusCopy.entityName("mysteryThing"), "Mysterything")
    }

    func testSemanticLabelReturnsNilForNonVinyl() {
        XCTAssertNil(SyncStatusCopy.semanticLabel(entityType: "project", changedFields: ["title"]))
        XCTAssertNil(SyncStatusCopy.semanticLabel(entityType: "expense", changedFields: ["vinyl_ordered_by"]))
    }
}
