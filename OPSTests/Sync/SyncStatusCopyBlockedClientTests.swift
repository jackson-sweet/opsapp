//
//  SyncStatusCopyBlockedClientTests.swift
//  OPSTests
//
//  The copy chokepoint's third park cause, and the raw-dump regression.
//
//  A business owner opened PENDING WORK on his own phone and read this:
//
//      PostgrestError(detail: nil, hint: nil, code: Optional("PGRST116"),
//      message: "Cannot coerce the result to a single JSON object")
//
//  `SyncStatusCopy`'s founding rule is that a field user NEVER sees a raw
//  database error. The DETAILS disclosure was printing `String(describing:)` of
//  the stored error verbatim, so the rule held everywhere except the one screen
//  a stuck operator actually opens. These tests lock the sanitizer shut and pin
//  the new "customer never reached OPS" vocabulary.
//

import XCTest
@testable import OPS

final class SyncStatusCopyBlockedClientTests: XCTestCase {

    private typealias Copy = SyncStatusCopy.PendingWork

    /// The exact string the queue stamps when the parent customer was refused.
    private var blockedByClient: String {
        ClientLeadAutocreateError.clientCreateRejectedDetail
    }

    /// The exact dump the founder saw.
    private let rawPostgrestDump = #"PostgrestError(detail: nil, hint: nil, code: Optional("PGRST116"), message: "Cannot coerce the result to a single JSON object")"#

    // MARK: - Wording

    func testClientRejectedCopyIsExact() {
        XCTAssertEqual(Copy.clientRejectedRow, "Customer never reached OPS — held here")
        XCTAssertEqual(Copy.clientRejectedDetailLabel, "SYS :: CUSTOMER NOT SAVED")
        XCTAssertEqual(
            Copy.clientRejectedDetailBody,
            "This lead is waiting on a customer record the server refused. Both are safe on this phone. Retry the customer in this list — the lead follows on its own."
        )
    }

    /// OPS product voice: no exclamation points, and the three park rows share
    /// the "— held here" cadence so they read as one family rather than three
    /// unrelated failures.
    func testCopyKeepsTheOPSRegister() {
        let lines = [
            Copy.clientRejectedRow,
            Copy.clientRejectedDetailLabel,
            Copy.clientRejectedDetailBody,
            Copy.diagnosticUnknown
        ]
        for line in lines {
            XCTAssertFalse(line.contains("!"), "no exclamation points: \(line)")
        }
        XCTAssertTrue(Copy.clientRejectedRow.hasSuffix("— held here"))
        XCTAssertTrue(Copy.parkedRow.hasSuffix("— held here"))
        XCTAssertTrue(Copy.missingRow.hasSuffix("— held here"))
        XCTAssertTrue(Copy.clientRejectedDetailLabel.hasPrefix("SYS :: "))
    }

    // MARK: - Recognition

    func testIsClientRejectedMatchesOnlyTheQueuesOwnMarker() {
        XCTAssertTrue(Copy.isClientRejected(blockedByClient))
        XCTAssertFalse(Copy.isClientRejected(nil))
        XCTAssertFalse(Copy.isClientRejected(""))
        XCTAssertFalse(Copy.isClientRejected(rawPostgrestDump))
        XCTAssertFalse(Copy.isClientRejected("the client rejected our call"))
    }

    // MARK: - Status lines

    /// Three causes, three answers. A refused customer must not be reported as a
    /// deletion, and a deletion must not be reported as a refusal.
    func testParkedStatusLineSplitsThreeWays() {
        XCTAssertEqual(
            Copy.statusLine(statusRaw: "parked", lastError: blockedByClient, secondsUntilRetry: nil).text,
            Copy.clientRejectedRow
        )
        XCTAssertEqual(
            Copy.statusLine(
                statusRaw: "parked",
                lastError: SyncError.serverRowMissing(table: "projects", id: "p1").localizedDescription,
                secondsUntilRetry: nil
            ).text,
            Copy.missingRow
        )
        XCTAssertEqual(
            Copy.statusLine(statusRaw: "parked", lastError: "some other rejection", secondsUntilRetry: nil).text,
            Copy.parkedRow
        )
        XCTAssertEqual(
            Copy.statusLine(statusRaw: "parked", lastError: blockedByClient, secondsUntilRetry: nil).tone,
            .stuck
        )
    }

    func testParkedDetailSplitsThreeWays() {
        let blocked = Copy.parkedDetail(lastError: blockedByClient)
        XCTAssertEqual(blocked.label, Copy.clientRejectedDetailLabel)
        XCTAssertEqual(blocked.body, Copy.clientRejectedDetailBody)

        let missing = Copy.parkedDetail(
            lastError: SyncError.serverRowMissing(table: "projects", id: "p1").localizedDescription
        )
        XCTAssertEqual(missing.label, Copy.missingRowDetailLabel)

        let generic = Copy.parkedDetail(lastError: "some other rejection")
        XCTAssertEqual(generic.label, Copy.parkedDetailLabel)
    }

    /// The notifications panel and PENDING WORK must never disagree about what
    /// happened to the same change.
    func testPanelAgreesWithPendingWorkOnAllThreeCauses() {
        for raw in [
            blockedByClient,
            SyncError.serverRowMissing(table: "projects", id: "p1").localizedDescription,
            "some other rejection"
        ] {
            XCTAssertEqual(
                SyncStatusCopy.status(status: "parked", retryCount: 0, canRetry: false, rawError: raw).text,
                Copy.statusLine(statusRaw: "parked", lastError: raw, secondsUntilRetry: nil).text,
                "panel and PENDING WORK disagree for: \(raw)"
            )
        }
    }

    // MARK: - THE regression: the DETAILS disclosure

    /// The one that must never go red again. Whatever the sanitizer returns, it
    /// cannot contain the Swift struct dump, the PostgREST code, or the
    /// coercion message — the three fragments the founder actually read.
    func testDiagnosticNeverEchoesTheRawDump() {
        let line = Copy.diagnostic(rawPostgrestDump)
        XCTAssertNotNil(line)
        for leak in ["PostgrestError", "PGRST116", "Optional(", "coerce", "detail:", "hint:"] {
            XCTAssertFalse(
                line!.localizedCaseInsensitiveContains(leak),
                "DETAILS leaked \(leak): \(line!)"
            )
        }
    }

    /// Nothing a repository can throw may reach the screen verbatim — including
    /// causes this app has never seen.
    func testEveryStoredErrorIsTranslatedNeverEchoed() {
        let stored = [
            rawPostgrestDump,
            #"new row violates row-level security policy "role_scope_read" for table "clients""#,
            "duplicate key value violates unique constraint",
            "PostgrestError(code: \"PGRST301\", message: \"JWT expired\")",
            "The Internet connection appears to be offline.",
            "some cause nobody has written a rule for yet — 0xDEADBEEF"
        ]
        for raw in stored {
            guard let line = Copy.diagnostic(raw) else {
                return XCTFail("a non-empty error still owes the operator a sentence: \(raw)")
            }
            XCTAssertNotEqual(line, raw)
            XCTAssertFalse(line.contains(raw), "echoed the raw text: \(line)")
        }
    }

    func testDiagnosticNamesEachKnownBlocker() {
        XCTAssertEqual(
            Copy.diagnostic(blockedByClient),
            "The customer record this lead belongs to was refused by the server."
        )
        XCTAssertEqual(
            Copy.diagnostic(SyncError.serverRowMissing(table: "projects", id: "p1").localizedDescription),
            "The record this change belongs to is no longer in OPS."
        )
        XCTAssertEqual(
            Copy.diagnostic(#"new row violates row-level security policy "role_scope_read" for table "clients""#),
            "The server would not let this account save that record."
        )
        XCTAssertEqual(
            Copy.diagnostic(rawPostgrestDump),
            "The server had no matching record to return."
        )
        XCTAssertEqual(
            Copy.diagnostic("duplicate key value violates unique constraint"),
            "A matching record already exists in OPS."
        )
        XCTAssertEqual(
            Copy.diagnostic("The Internet connection appears to be offline."),
            "There was no connection the last time this was tried."
        )
    }

    /// A blocked customer outranks the PGRST116 the same request also carries —
    /// naming the blocker the operator can act on is the whole point.
    func testTheActionableCauseWinsOverTheTransportOne() {
        XCTAssertEqual(
            Copy.diagnostic("\(blockedByClient) — PGRST116 no rows"),
            "The customer record this lead belongs to was refused by the server."
        )
    }

    func testUnknownCausesPointAtExportRatherThanSpillingText() {
        XCTAssertEqual(Copy.diagnostic("something entirely new"), Copy.diagnosticUnknown)
        XCTAssertTrue(Copy.diagnosticUnknown.localizedCaseInsensitiveContains("export"))
    }

    func testEmptyAndNilErrorsProduceNoLine() {
        XCTAssertNil(Copy.diagnostic(nil))
        XCTAssertNil(Copy.diagnostic(""))
        XCTAssertNil(Copy.diagnostic("   \n "))
    }

    /// Two members blocked by the same thing must not say it twice.
    func testDiagnosticsDedupeByMeaningNotByRawText() {
        let lines = Copy.diagnostics([
            rawPostgrestDump,
            "PostgrestError(code: Optional(\"PGRST116\"), message: \"Cannot coerce the result\")",
            blockedByClient
        ])
        XCTAssertEqual(lines, [
            "The server had no matching record to return.",
            "The customer record this lead belongs to was refused by the server."
        ])
    }

    func testDiagnosticsSkipsEmptyEntries() {
        XCTAssertEqual(Copy.diagnostics([]), [])
        XCTAssertEqual(Copy.diagnostics(["", "  "]), [])
    }
}
