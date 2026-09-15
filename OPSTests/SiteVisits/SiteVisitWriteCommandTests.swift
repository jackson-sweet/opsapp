import XCTest
@testable import OPS

final class SiteVisitWriteCommandTests: XCTestCase {
    func testRestartPreservesOriginalBaseAndExplicitFalse() throws {
        let row = SiteVisitWriteCommand.Row(id: "field", baseRevision: 3,
            before: .object(["answer_value": .object([:])]),
            values: .object(["answer_value": .object(["boolValue": .bool(false)])]))
        let command = SiteVisitWriteCommand(companyId: "company", entity: "answer", rows: [row])
        XCTAssertEqual(try JSONDecoder().decode(SiteVisitWriteCommand.self, from: JSONEncoder().encode(command)), command)
    }
    func testOnlyExactSavedPredecessorCanAdvanceBase() {
        var command = SiteVisitWriteCommand(companyId: "company", entity: "answer", rows: [
            .init(id: "field", baseRevision: 3, before: .null, values: .object(["text": .string("next edit")]))
        ])
        let saved: SiteVisitWriteJSON = .object(["id": .string("field"), "company_id": .string("company"), "write_revision": .number(4)])
        command.acknowledgePredecessor(.init(commandId: UUID(), entity: "answer", outcome: "conflict", reason: "stale", rows: [saved]))
        XCTAssertEqual(command.rows[0].baseRevision, 3)
        command.acknowledgePredecessor(.init(commandId: UUID(), entity: "template", outcome: "saved", reason: nil, rows: [saved]))
        XCTAssertEqual(command.rows[0].baseRevision, 3)
        command.acknowledgePredecessor(.init(commandId: UUID(), entity: "answer", outcome: "saved", reason: nil, rows: [saved]))
        XCTAssertEqual(command.rows[0].baseRevision, 4)
        XCTAssertEqual(command.rows[0].values["text"], .string("next edit"))
    }
    /// The capture screen freezes a base at the first keystroke and writes it
    /// back when the buffer flushes. If the phone's own save landed in between,
    /// the persisted (newer) revision wins — restoring the captured base would
    /// re-create the stale_edit self-conflict of bug 0e110106.
    func testCapturedKeystrokeBaseYieldsToARevisionSavedMeanwhile() {
        var captured = SiteVisitWriteState(revision: 1)
        captured.begin(.string("original"))
        captured.explicitlyEdited = true
        var persisted = SiteVisitWriteState(revision: 2)
        persisted.baseRevision = 2
        persisted.baseRow = .string("saved")
        let merged = persisted.restoringCapturedBase(captured)
        XCTAssertEqual(merged.revision, 2)
        XCTAssertEqual(merged.baseRevision, 2)
        XCTAssertEqual(merged.baseRow, .string("saved"))
        XCTAssertEqual(merged.explicitlyEdited, true)
        let unchanged = SiteVisitWriteState(revision: 1).restoringCapturedBase(captured)
        XCTAssertEqual(unchanged, captured)
    }
    func testFirstKeystrokeBaseSurvivesLaterIncomingRevision() {
        var state = SiteVisitWriteState(revision: 2)
        state.begin(.string("original"))
        state.revision = 3
        state.remoteRow = .string("other phone")
        state.begin(.string("other phone"))
        XCTAssertEqual(state.baseRevision, 2)
        XCTAssertEqual(state.baseRow, .string("original"))
        XCTAssertEqual(state.remoteRow, .string("other phone"))
    }
    func testDeletionReceiptAcceptsEquivalentTimestampAndRejectsDifferentInstant() {
        let expected: SiteVisitWriteJSON = .object(["deleted_at": .string("2026-09-10T20:00:00.123Z")])
        XCTAssertTrue(SiteVisitWriteJSON.object(["deleted_at": .string("2026-09-10T20:00:00.123000+00:00")]).matchesRequested(expected))
        XCTAssertFalse(SiteVisitWriteJSON.object(["deleted_at": .string("2026-09-10T20:00:00.124Z")]).matchesRequested(expected))
        XCTAssertFalse(SiteVisitWriteJSON.object(["deleted_at": .null]).matchesRequested(expected))
    }
    func testNoOpEmptyMediaWireEncodingDoesNotChangeAnswerMeaning() {
        let expected: SiteVisitWriteJSON = .object(["answer_value": .object(["text": .string("0")])])
        XCTAssertTrue(SiteVisitWriteJSON.object(["answer_value": .object(["text": .string("0"), "artifactIds": .array([])])]).matchesRequested(expected))
        XCTAssertFalse(SiteVisitWriteJSON.object(["answer_value": .object(["text": .string("")])]).matchesRequested(expected))
        XCTAssertFalse(SiteVisitWriteJSON.object(["answer_value": .object(["boolValue": .bool(false)])]).matchesRequested(expected))
    }
    func testResolutionRestartKeepsExactIdentityChoiceAndReviewedAuthority() throws {
        let resolution = SiteVisitWriteResolution(id: UUID(), choice: "current", current: [
            .object(["id": .string("row"), "write_revision": .number(8), "answer_value": .object(["text": .string("server")])])
        ])
        let encoded = try JSONEncoder().encode(resolution)
        XCTAssertEqual(try JSONDecoder().decode(SiteVisitWriteResolution.self, from: encoded), resolution)
    }
    func testSupersessionAndCurrentResolutionCannotRebaseDirtyDescendant() {
        var command = SiteVisitWriteCommand(companyId: "company", entity: "answer", rows: [
            .init(id: "field", baseRevision: 3, before: .string("original"), values: .string("pending"))
        ])
        for outcome in ["superseded", "resolved", "conflict"] {
            command.acknowledgePredecessor(.init(commandId: UUID(), entity: "answer", outcome: outcome, reason: nil, rows: [
                .object(["id": .string("field"), "company_id": .string("company"), "write_revision": .number(99)])
            ]))
            XCTAssertEqual(command.rows[0].baseRevision, 3)
            XCTAssertEqual(command.rows[0].before, .string("original"))
        }
    }

}
