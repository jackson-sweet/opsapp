import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitChoiceResolutionTests: XCTestCase {
    private let company = "11111111-1111-4111-8111-111111111111"
    private let actor = "22222222-2222-4222-8222-222222222222"
    private let visit = "33333333-3333-4333-8333-333333333333"
    private let canonicalID = "44444444-4444-4444-8444-444444444444"

    private struct Fixture {
        // Retain the container across the fresh-context receipt verification.
        let container: ModelContainer
        let context: ModelContext
        let answer: SiteVisitChecklistAnswer
        let operation: SyncOperation
        let command: SiteVisitWriteCommand
        let payload: Data
        let answerData: Data?
    }

    private func snapshot(secondLabel: String = "Composite") -> SiteVisitSingleChoice {
        .init(options: [
            .init(id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", label: "Cedar"),
            .init(id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", label: secondLabel)
        ])
    }

    private func fixture(choice: SiteVisitSingleChoice?, revision: Int64 = 0) throws -> Fixture {
        let schema = Schema([SiteVisitType.self, SiteVisitChecklistAnswer.self, SyncOperation.self])
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let answer = SiteVisitChecklistAnswer(siteVisitId: visit, companyId: company, opportunityId: nil,
            siteVisitTypeId: nil, fieldId: "material", label: "Material", kind: .shortText,
            required: true, sortOrder: 10, answerValue: .init(text: "Cedar", choiceSnapshot: choice), createdBy: actor)
        answer.writeState = .init(revision: revision)
        context.insert(answer)
        let command = SiteVisitWriteModels.command(answer)
        let payload = try JSONEncoder().encode(SiteVisitSyncOperation.Payload(
            companyId: company, siteVisitId: visit, entityId: answer.id, writeCommand: command))
        let operation = SyncOperation(entityType: SyncEntityType.siteVisitChecklistAnswer.rawValue,
            entityId: answer.id, operationType: "siteVisitWrite", payload: payload, changedFields: ["answer_value"])
        operation.siteVisitWriteActorId = actor
        operation.siteVisitWriteAttemptedAt = Date()
        context.insert(operation)
        try context.save()
        return Fixture(container: container, context: context, answer: answer, operation: operation,
            command: command, payload: payload, answerData: answer.answerValueData)
    }

    private func serverRow(_ fixture: Fixture, id: String, choice: SiteVisitSingleChoice?,
                           revision: Int = 8) throws -> SiteVisitWriteJSON {
        guard case .object(var values) = fixture.command.rows[0].values else {
            throw SiteVisitWriteError.invalidReceipt
        }
        values["id"] = .string(id)
        values["choice_snapshot"] = try choice.map { try SiteVisitWriteJSON.encode($0) } ?? .null
        values["write_revision"] = .number(Double(revision))
        values["answer_state"] = .string("answered")
        values["created_by"] = .string(actor)
        values["created_at"] = .string("2026-09-11T12:00:00Z")
        values["updated_at"] = .string("2026-09-11T13:00:00Z")
        return .object(values)
    }

    private func resolve(_ fixture: Fixture, reviewed: [SiteVisitWriteJSON], saved: SiteVisitWriteJSON) throws -> SiteVisitWriteReceipt {
        let resolution = SiteVisitWriteResolution(id: UUID(), choice: "pending", current: reviewed)
        let data = try JSONEncoder().encode(resolution)
        fixture.operation.siteVisitWriteResolutionData = data
        try fixture.context.save()
        let receipt = SiteVisitWriteReceipt(commandId: resolution.id, entity: "answer", outcome: "saved", reason: nil, rows: [saved])
        try SiteVisitVersionedSync.applyReceipt(receipt, to: fixture.operation, command: fixture.command,
            resolutionData: data, context: fixture.context, companyId: company, actorId: actor)
        return receipt
    }

    private func assertAccepted(_ fixture: Fixture, receipt: SiteVisitWriteReceipt, id: String,
                                choice: SiteVisitSingleChoice, file: StaticString = #filePath, line: UInt = #line) throws {
        let context = ModelContext(fixture.container)
        let answers = try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
        XCTAssertEqual(answers.count, 1, file: file, line: line)
        let answer = try XCTUnwrap(answers.first, file: file, line: line)
        XCTAssertEqual(answer.id, id, file: file, line: line)
        XCTAssertEqual(answer.answerValue.choiceSnapshot, choice, file: file, line: line)
        XCTAssertEqual(answer.answerValue.text, "Cedar", file: file, line: line)
        XCTAssertTrue(answer.isAnswered, file: file, line: line)
        XCTAssertFalse(answer.needsSync, file: file, line: line)
        XCTAssertEqual(answer.writeState.revision, 8, file: file, line: line)
        let operation = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first, file: file, line: line)
        XCTAssertEqual(operation.payload, fixture.payload, file: file, line: line)
        XCTAssertEqual(SiteVisitVersionedSync.command(operation), fixture.command, file: file, line: line)
        let storedReceipt = try JSONDecoder().decode(SiteVisitWriteReceipt.self,
            from: XCTUnwrap(operation.siteVisitWriteReceiptData, file: file, line: line))
        XCTAssertEqual(storedReceipt, receipt, file: file, line: line)
    }

    private func assertRejected(_ fixture: Fixture, reviewed: [SiteVisitWriteJSON], saved: SiteVisitWriteJSON,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertThrowsError(try resolve(fixture, reviewed: reviewed, saved: saved), file: file, line: line) { error in
            guard case SiteVisitWriteError.invalidReceipt = error else {
                return XCTFail("Unexpected rejection: \(error)", file: file, line: line)
            }
        }
        try assertUnchanged(fixture, file: file, line: line)
    }

    private func assertUnchanged(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) throws {
        let context = ModelContext(fixture.container)
        let answer = try XCTUnwrap(context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first, file: file, line: line)
        XCTAssertEqual(answer.id, fixture.command.rows[0].id, file: file, line: line)
        XCTAssertEqual(answer.answerValueData, fixture.answerData, file: file, line: line)
        XCTAssertTrue(answer.needsSync, file: file, line: line)
        let operation = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first, file: file, line: line)
        XCTAssertEqual(operation.payload, fixture.payload, file: file, line: line)
        XCTAssertEqual(SiteVisitVersionedSync.command(operation), fixture.command, file: file, line: line)
        XCTAssertNil(operation.siteVisitWriteReceiptData, file: file, line: line)
    }

    func testV2LogicalCollisionAcceptsOnlyReviewedCanonicalSnapshotAndPreservesCommand() throws {
        let fixture = try fixture(choice: snapshot())
        let canonical = snapshot(secondLabel: "Pressure treated")
        XCTAssertEqual(fixture.command.protocol, SiteVisitWriteCommand.choiceRevision)
        XCTAssertNotEqual(snapshot(), canonical)
        XCTAssertNotNil(snapshot().option(matching: "Cedar"))
        XCTAssertNotNil(canonical.option(matching: "Cedar"))
        let reviewed = try serverRow(fixture, id: canonicalID, choice: canonical, revision: 7)
        let saved = try serverRow(fixture, id: canonicalID, choice: canonical)
        let receipt = try resolve(fixture, reviewed: [reviewed], saved: saved)
        try assertAccepted(fixture, receipt: receipt, id: canonicalID, choice: canonical)
    }

    func testOriginalV1SameIDRecoveryHydratesReviewedSnapshotWithoutRewritingCommand() throws {
        let fixture = try fixture(choice: nil, revision: 4)
        let canonical = snapshot(secondLabel: "Pressure treated")
        XCTAssertEqual(fixture.command.protocol, SiteVisitWriteCommand.revision)
        XCTAssertNil(fixture.command.rows[0].values["choice_snapshot"])
        let reviewed = try serverRow(fixture, id: fixture.answer.id, choice: canonical, revision: 7)
        let saved = try serverRow(fixture, id: fixture.answer.id, choice: canonical)
        let receipt = try resolve(fixture, reviewed: [reviewed], saved: saved)
        try assertAccepted(fixture, receipt: receipt, id: fixture.answer.id, choice: canonical)
    }

    func testLogicalCollisionRejectsProposedSnapshotWhenReviewedSnapshotDiffers() throws {
        let fixture = try fixture(choice: snapshot())
        let reviewed = try serverRow(fixture, id: canonicalID, choice: snapshot(secondLabel: "Pressure treated"), revision: 7)
        let saved = try serverRow(fixture, id: canonicalID, choice: snapshot())
        try assertRejected(fixture, reviewed: [reviewed], saved: saved)
    }

    func testOriginalV1SameIDRecoveryRejectsSnapshotDifferentFromReview() throws {
        let fixture = try fixture(choice: nil, revision: 4)
        let reviewed = try serverRow(fixture, id: fixture.answer.id, choice: snapshot(secondLabel: "Pressure treated"), revision: 7)
        let saved = try serverRow(fixture, id: fixture.answer.id, choice: snapshot())
        try assertRejected(fixture, reviewed: [reviewed], saved: saved)
    }

    func testSameIDV2ResolutionCannotReplaceOriginalSnapshotWithReviewedGeneration() throws {
        let fixture = try fixture(choice: snapshot(), revision: 4)
        let canonical = snapshot(secondLabel: "Pressure treated")
        let reviewed = try serverRow(fixture, id: fixture.answer.id, choice: canonical, revision: 7)
        let saved = try serverRow(fixture, id: fixture.answer.id, choice: canonical)
        try assertRejected(fixture, reviewed: [reviewed], saved: saved)
        let unreviewed = try serverRow(fixture, id: fixture.answer.id, choice: snapshot())
        try assertRejected(fixture, reviewed: [reviewed], saved: unreviewed)
    }

    func testOrdinaryV2SaveStillRejectsDifferentSnapshot() throws {
        let fixture = try fixture(choice: snapshot(), revision: 4)
        let saved = try serverRow(fixture, id: fixture.answer.id, choice: snapshot(secondLabel: "Pressure treated"))
        let receipt = SiteVisitWriteReceipt(commandId: fixture.operation.id, entity: "answer", outcome: "saved", reason: nil, rows: [saved])
        XCTAssertThrowsError(try SiteVisitVersionedSync.applyReceipt(receipt, to: fixture.operation,
            command: fixture.command, resolutionData: nil, context: fixture.context, companyId: company, actorId: actor)) { error in
            guard case SiteVisitWriteError.invalidReceipt = error else { return XCTFail("Unexpected rejection: \(error)") }
        }
        try assertUnchanged(fixture)
    }

    func testLogicalCollisionCannotAdoptAnUnreviewedCanonicalID() throws {
        let fixture = try fixture(choice: snapshot())
        let reviewed = try serverRow(fixture, id: canonicalID, choice: snapshot(), revision: 7)
        let saved = try serverRow(fixture, id: UUID().uuidString.lowercased(), choice: snapshot())
        try assertRejected(fixture, reviewed: [reviewed], saved: saved)
        try assertRejected(fixture, reviewed: [], saved: saved)
    }
}
