import XCTest
import SwiftData
@testable import OPS

final class SiteVisitVersionedSyncTests: XCTestCase {
    @MainActor
    func testAcknowledgementPreservesEditCommittedByAnotherContext() throws {
        let schema = Schema([SiteVisitType.self, SiteVisitChecklistAnswer.self, SyncOperation.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let outbound = ModelContext(container)
        let type = SiteVisitType(companyId: "company", slug: "scope", name: "Sent name")
        type.id = type.id.uppercased() // A persisted template created by an older client.
        type.writeState = .init(revision: 4)
        outbound.insert(type)
        let command = try SiteVisitWriteModels.command([type])
        let operation = SyncOperation(entityType: SyncEntityType.siteVisitType.rawValue, entityId: type.id,
            operationType: "siteVisitWrite", payload: try JSONEncoder().encode(command), changedFields: ["name"])
        operation.siteVisitWriteActorId = "actor"
        operation.siteVisitWriteAttemptedAt = Date()
        outbound.insert(operation); try outbound.save()
        let editor = ModelContext(container)
        let edited = try XCTUnwrap(editor.fetch(FetchDescriptor<SiteVisitType>()).first)
        edited.name = "Newer edit while request was in flight"
        edited.needsSync = true
        try editor.save()
        guard case .object(var values) = command.rows[0].values else { return XCTFail("Expected object") }
        values["write_revision"] = .number(5)
        let receipt = SiteVisitWriteReceipt(commandId: operation.id, entity: "template", outcome: "saved", reason: nil, rows: [.object(values)])
        try SiteVisitVersionedSync.applyReceipt(receipt, to: operation, command: command, resolutionData: nil,
            context: outbound, companyId: "company", actorId: "actor")
        try outbound.save()
        let verifier = ModelContext(container)
        let preserved = try XCTUnwrap(verifier.fetch(FetchDescriptor<SiteVisitType>()).first)
        XCTAssertEqual(preserved.name, "Newer edit while request was in flight")
        XCTAssertTrue(preserved.needsSync)
        // The save that just landed is this phone's own. The newer edit builds
        // on it, so the next command must ship base 5 — a base of 4 is exactly
        // the stale_edit self-conflict of bug 0e110106.
        XCTAssertEqual(preserved.writeState.revision, 5)
        XCTAssertEqual(preserved.writeState.baseRevision, 5)
        XCTAssertEqual(preserved.writeState.remoteRow?["write_revision"], .number(5))
        XCTAssertNotNil(try verifier.fetch(FetchDescriptor<SyncOperation>()).first(where: { $0.id == operation.id })?.siteVisitWriteReceiptData)
    }

    @MainActor
    func testExactAcknowledgementUpdatesRegisteredUnattemptedDescendant() throws {
        let schema = Schema([SiteVisitType.self, SiteVisitChecklistAnswer.self, SyncOperation.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let outbound = ModelContext(container)
        let type = SiteVisitType(companyId: "company", slug: "scope", name: "Sent name")
        type.writeState = .init(revision: 4)
        outbound.insert(type)
        let command = try SiteVisitWriteModels.command([type])
        let operation = SyncOperation(entityType: SyncEntityType.siteVisitType.rawValue, entityId: type.id,
            operationType: "siteVisitWrite", payload: try JSONEncoder().encode(command), changedFields: ["name"])
        operation.siteVisitWriteActorId = "actor"
        operation.siteVisitWriteAttemptedAt = Date()
        outbound.insert(operation); try outbound.save()
        let descendant = SyncOperation(entityType: SyncEntityType.siteVisitType.rawValue, entityId: type.id,
            operationType: "siteVisitWrite", payload: try JSONEncoder().encode(command), changedFields: ["name"],
            dependsOnId: operation.id.uuidString.lowercased())
        descendant.siteVisitWriteActorId = "actor"
        outbound.insert(descendant); try outbound.save()
        let editor = ModelContext(container)
        let edited = try XCTUnwrap(editor.fetch(FetchDescriptor<SiteVisitType>()).first)
        edited.name = "Newer edit while request was in flight"
        edited.needsSync = true
        try editor.save()
        guard case .object(var values) = command.rows[0].values else { return XCTFail("Expected object") }
        values["write_revision"] = .number(5)
        let receipt = SiteVisitWriteReceipt(commandId: operation.id, entity: "template", outcome: "saved", reason: nil, rows: [.object(values)])
        try SiteVisitVersionedSync.applyReceipt(receipt, to: operation, command: command, resolutionData: nil,
            context: outbound, companyId: "company", actorId: "actor")
        try outbound.save()
        let verifier = ModelContext(container)
        let preserved = try XCTUnwrap(verifier.fetch(FetchDescriptor<SiteVisitType>()).first)
        XCTAssertEqual(preserved.name, "Newer edit while request was in flight")
        XCTAssertTrue(preserved.needsSync)
        XCTAssertEqual(preserved.writeState.baseRevision, 5)
        XCTAssertEqual(SiteVisitVersionedSync.command(descendant)?.rows[0].baseRevision, 5)
        XCTAssertNil(descendant.siteVisitWriteAttemptedAt)
        XCTAssertEqual(preserved.writeState.remoteRow?["write_revision"], .number(5))
        XCTAssertNotNil(try verifier.fetch(FetchDescriptor<SyncOperation>()).first(where: { $0.id == operation.id })?.siteVisitWriteReceiptData)
    }

    @MainActor
    func testInboundLowercaseReceiptFindsLegacyTemplateWithoutDuplicateOrOverwrite() throws {
        let schema = Schema([SiteVisitType.self, SiteVisitChecklistAnswer.self, SyncOperation.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let type = SiteVisitType(companyId: "company", slug: "scope", name: "My pending version")
        type.id = type.id.uppercased()
        type.writeState = .init(revision: 4)
        context.insert(type)
        type.beginVersionedEdit()
        try context.save()
        var dto = SiteVisitTypeDTO(id: type.id.lowercased(), companyId: "company", slug: "scope", name: "Server version",
            descriptionText: nil, isSystemTemplate: false, isDefault: false, sortOrder: 0, fields: [],
            createdAt: nil, updatedAt: nil, deletedAt: nil)
        dto.writeRevision = 5
        XCTAssertTrue(try SiteVisitTypeServerMerge.merge(dto: dto, accepting: SiteVisitTypeServerMerge.mutableFields,
            hasPendingLocalOperation: false, context: context))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<SiteVisitType>()).count, 1)
        XCTAssertEqual(type.name, "My pending version")
        XCTAssertEqual(type.writeState.baseRevision, 4)
        XCTAssertEqual(type.writeState.remoteRow?["write_revision"], .number(5))
    }

    @MainActor
    func testOldResponseCannotCrossNewResolutionOrActorBinding() throws {
        let schema = Schema([SiteVisitType.self, SiteVisitChecklistAnswer.self, SyncOperation.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let outbound = ModelContext(container)
        let type = SiteVisitType(companyId: "company", slug: "scope", name: "Sent name")
        outbound.insert(type)
        let command = try SiteVisitWriteModels.command([type])
        let operation = SyncOperation(entityType: SyncEntityType.siteVisitType.rawValue, entityId: type.id,
            operationType: "siteVisitWrite", payload: try JSONEncoder().encode(command), changedFields: ["name"])
        operation.siteVisitWriteActorId = "actor"
        outbound.insert(operation); try outbound.save()
        let editor = ModelContext(container)
        let latest = try XCTUnwrap(editor.fetch(FetchDescriptor<SyncOperation>()).first)
        let choice = try JSONEncoder().encode(SiteVisitWriteResolution(id: UUID(), choice: "current", current: []))
        latest.siteVisitWriteResolutionData = choice
        try editor.save()
        let receipt = SiteVisitWriteReceipt(commandId: operation.id, entity: "template", outcome: "conflict", reason: "stale", rows: [])
        XCTAssertThrowsError(try SiteVisitVersionedSync.applyReceipt(receipt, to: operation, command: command, resolutionData: nil,
            context: outbound, companyId: "company", actorId: "actor"))
        latest.siteVisitWriteResolutionData = nil
        latest.siteVisitWriteActorId = "different-actor"
        try editor.save()
        XCTAssertThrowsError(try SiteVisitVersionedSync.applyReceipt(receipt, to: operation, command: command, resolutionData: nil,
            context: outbound, companyId: "company", actorId: "actor"))
        XCTAssertNil(latest.siteVisitWriteReceiptData)
    }

    // MARK: - Self-conflict (bug 0e110106)
    //
    // Device evidence 2026-09-15, visit 96090555: the phone saved "…enclosed s"
    // as revision 2 while the operator kept typing; every later command shipped
    // base 1 → stale_edit → parked as "changed on another device", and RETRY
    // re-sent the same frozen command forever.

    /// The operator kept typing after a save left the phone. The saved
    /// revision is the phone's own; the next command must build on it even
    /// though no dependsOn successor exists yet.
    @MainActor
    func testSavedReceiptAdvancesBaseWhenTheOperatorKeptTypingWithNoSuccessorQueued() throws {
        let fixture = try makeAnswerFixture(localRevision: 1, sentText: "Client would like to rebuild enclosed s")
        fixture.operation.siteVisitWriteAttemptedAt = Date()
        try fixture.outbound.save()
        let editor = ModelContext(fixture.container)
        let edited = try XCTUnwrap(editor.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first)
        edited.answerValue = .text("Client would like to rebuild enclosed storage if it needs to be demoed.")
        edited.needsSync = true
        try editor.save()
        let receipt = SiteVisitWriteReceipt(commandId: fixture.operation.id, entity: "answer", outcome: "saved", reason: nil,
            rows: [Self.row(fixture.command, revision: 2)])
        try SiteVisitVersionedSync.applyReceipt(receipt, to: fixture.operation, command: fixture.command, resolutionData: nil,
            context: fixture.outbound, companyId: "company", actorId: "actor")
        try fixture.outbound.save()
        let verifier = ModelContext(fixture.container)
        let preserved = try XCTUnwrap(verifier.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first)
        XCTAssertEqual(preserved.answerValue.text, "Client would like to rebuild enclosed storage if it needs to be demoed.")
        XCTAssertTrue(preserved.needsSync)
        XCTAssertEqual(preserved.writeState.revision, 2)
        XCTAssertEqual(preserved.writeState.baseRevision, 2)
        XCTAssertEqual(preserved.writeState.baseRow?["write_revision"], .number(2))
        XCTAssertEqual(SiteVisitWriteModels.command(preserved).rows[0].baseRevision, 2)
    }

    /// A successor queued from a stale in-memory write state (the Deck Layout
    /// case: base 0 while this phone's own create had landed as revision 1) must
    /// still ship on the newest revision the phone has already saved for the row.
    @MainActor
    func testUnattemptedCommandIsRebasedOntoThePhonesOwnLatestSavedRevisionBeforeSending() async throws {
        let fixture = try makeAnswerFixture(localRevision: 1, sentText: "Client would like to rebuild enclosed storage if it needs to be demoed.")
        let earlierCommand = Self.command(like: fixture.command, text: "Client would like to rebuild enclosed s", baseRevision: 1)
        let predecessor = try Self.makeOperation(answer: fixture.answer, command: earlierCommand)
        predecessor.status = "completed"
        predecessor.completedAt = Date(timeIntervalSinceNow: -60)
        predecessor.siteVisitWriteAttemptedAt = Date(timeIntervalSinceNow: -61)
        predecessor.siteVisitWriteReceiptData = try JSONEncoder().encode(SiteVisitWriteReceipt(
            commandId: predecessor.id, entity: "answer", outcome: "saved", reason: nil, rows: [Self.row(earlierCommand, revision: 2)]))
        fixture.outbound.insert(predecessor)
        try fixture.outbound.save()

        let recorder = DeliveryRecorder()
        try await SiteVisitVersionedSync.execute(operation: fixture.operation, context: fixture.outbound, companyId: "company",
            actorId: "actor", isCurrent: { true },
            deliverWrite: { id, command, _ in
                recorder.delivered.append(command)
                return SiteVisitWriteReceipt(commandId: id, entity: "answer", outcome: "saved", reason: nil, rows: [Self.row(command, revision: 3)])
            })
        XCTAssertEqual(recorder.delivered.count, 1)
        XCTAssertEqual(recorder.delivered.first?.rows[0].baseRevision, 2)
        XCTAssertEqual(recorder.delivered.first?.rows[0].before["write_revision"], .number(2))
        XCTAssertEqual(recorder.delivered.first?.rows[0].values["answer_value"]?["text"],
            .string("Client would like to rebuild enclosed storage if it needs to be demoed."))
        XCTAssertEqual(SiteVisitVersionedSync.command(fixture.operation)?.rows[0].baseRevision, 2)
        let verifier = ModelContext(fixture.container)
        let preserved = try XCTUnwrap(verifier.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first)
        XCTAssertEqual(preserved.writeState.revision, 3)
        XCTAssertFalse(preserved.needsSync)
    }

    /// A stale-edit rejection whose current row is the phone's own earlier save
    /// is settled as USE PENDING on the spot — never parked for review, never
    /// blamed on another device.
    @MainActor
    func testStaleEditAgainstThePhonesOwnSavedRowResolvesAsPendingWithoutParking() async throws {
        let fixture = try makeAnswerFixture(localRevision: 1, sentText: "Client would like to rebuild enclosed storage if it needs")
        let earlierCommand = Self.command(like: fixture.command, text: "Client would like to rebuild enclosed s", baseRevision: 1)
        let ours = Self.row(earlierCommand, revision: 2)
        let predecessor = try Self.makeOperation(answer: fixture.answer, command: earlierCommand)
        predecessor.status = "completed"
        predecessor.completedAt = Date(timeIntervalSinceNow: -60)
        predecessor.siteVisitWriteAttemptedAt = Date(timeIntervalSinceNow: -61)
        predecessor.siteVisitWriteReceiptData = try JSONEncoder().encode(SiteVisitWriteReceipt(
            commandId: predecessor.id, entity: "answer", outcome: "saved", reason: nil, rows: [ours]))
        fixture.outbound.insert(predecessor)
        // Frozen like every already-attempted command on a shipped phone: no
        // rebase can touch it, so the server answers stale_edit on replay.
        fixture.operation.siteVisitWriteAttemptedAt = Date(timeIntervalSinceNow: -30)
        try fixture.outbound.save()
        let editor = ModelContext(fixture.container)
        let edited = try XCTUnwrap(editor.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first)
        edited.answerValue = .text("Client would like to rebuild enclosed storage if it needs to be demoed.")
        edited.needsSync = true
        try editor.save()

        let recorder = DeliveryRecorder()
        try await SiteVisitVersionedSync.execute(operation: fixture.operation, context: fixture.outbound, companyId: "company",
            actorId: "actor", isCurrent: { true },
            deliverWrite: { id, _, _ in
                SiteVisitWriteReceipt(commandId: id, entity: "answer", outcome: "conflict", reason: "stale_edit", rows: [ours])
            },
            deliverResolution: { originalId, command, resolution, actor, _ in
                recorder.resolutions.append(DeliveryRecorder.Resolution(originalId: originalId, resolution: resolution, actor: actor))
                return SiteVisitWriteReceipt(commandId: resolution.id, entity: "answer", outcome: "saved", reason: nil,
                    rows: [Self.row(command, revision: 3)])
            })
        XCTAssertEqual(recorder.resolutions.count, 1)
        XCTAssertEqual(recorder.resolutions.first?.originalId, fixture.operation.id)
        XCTAssertEqual(recorder.resolutions.first?.resolution.choice, "pending")
        XCTAssertEqual(recorder.resolutions.first?.resolution.current, [ours])
        XCTAssertEqual(recorder.resolutions.first?.actor, "actor")
        let persistedResolution = try XCTUnwrap(fixture.operation.siteVisitWriteResolutionData
            .map { try JSONDecoder().decode(SiteVisitWriteResolution.self, from: $0) })
        XCTAssertEqual(persistedResolution.id, recorder.resolutions.first?.resolution.id)
        let receipt = try XCTUnwrap(fixture.operation.siteVisitWriteReceiptData
            .map { try JSONDecoder().decode(SiteVisitWriteReceipt.self, from: $0) })
        XCTAssertEqual(receipt.outcome, "saved")
        let verifier = ModelContext(fixture.container)
        let preserved = try XCTUnwrap(verifier.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first)
        XCTAssertEqual(preserved.answerValue.text, "Client would like to rebuild enclosed storage if it needs to be demoed.")
        XCTAssertTrue(preserved.needsSync)
        XCTAssertEqual(preserved.writeState.revision, 3)
        XCTAssertEqual(preserved.writeState.baseRevision, 3)
    }

    /// A stale-edit rejection carrying a row this phone never saved is a real
    /// conflict: it still parks for review and no resolution is sent.
    @MainActor
    func testStaleEditAgainstAnotherWritersRowStillParksForReview() async throws {
        let fixture = try makeAnswerFixture(localRevision: 1, sentText: "Client would like to rebuild enclosed storage if it needs")
        let earlierCommand = Self.command(like: fixture.command, text: "Client would like to rebuild enclosed s", baseRevision: 1)
        let predecessor = try Self.makeOperation(answer: fixture.answer, command: earlierCommand)
        predecessor.status = "completed"
        predecessor.completedAt = Date(timeIntervalSinceNow: -60)
        predecessor.siteVisitWriteAttemptedAt = Date(timeIntervalSinceNow: -61)
        predecessor.siteVisitWriteReceiptData = try JSONEncoder().encode(SiteVisitWriteReceipt(
            commandId: predecessor.id, entity: "answer", outcome: "saved", reason: nil, rows: [Self.row(earlierCommand, revision: 2)]))
        fixture.outbound.insert(predecessor)
        fixture.operation.siteVisitWriteAttemptedAt = Date(timeIntervalSinceNow: -30)
        try fixture.outbound.save()
        // Same revision number, different content: another writer replaced the row.
        let foreign = Self.replacingText(Self.row(earlierCommand, revision: 2), with: "Homeowner wants composite instead")

        let recorder = DeliveryRecorder()
        do {
            try await SiteVisitVersionedSync.execute(operation: fixture.operation, context: fixture.outbound, companyId: "company",
                actorId: "actor", isCurrent: { true },
                deliverWrite: { id, _, _ in
                    SiteVisitWriteReceipt(commandId: id, entity: "answer", outcome: "conflict", reason: "stale_edit", rows: [foreign])
                },
                deliverResolution: { originalId, _, resolution, actor, _ in
                    recorder.resolutions.append(DeliveryRecorder.Resolution(originalId: originalId, resolution: resolution, actor: actor))
                    return SiteVisitWriteReceipt(commandId: resolution.id, entity: "answer", outcome: "saved", reason: nil, rows: [])
                })
            XCTFail("A foreign write must still surface as a conflict")
        } catch SiteVisitWriteError.conflict {}
        XCTAssertTrue(recorder.resolutions.isEmpty)
        XCTAssertNil(fixture.operation.siteVisitWriteResolutionData)
        let receipt = try XCTUnwrap(fixture.operation.siteVisitWriteReceiptData
            .map { try JSONDecoder().decode(SiteVisitWriteReceipt.self, from: $0) })
        XCTAssertEqual(receipt.outcome, "conflict")
        XCTAssertEqual(receipt.reason, "stale_edit")
    }

    // MARK: - Fixtures

    private struct AnswerFixture {
        let container: ModelContainer
        let outbound: ModelContext
        let answer: SiteVisitChecklistAnswer
        let command: SiteVisitWriteCommand
        let operation: SyncOperation
    }

    private final class DeliveryRecorder {
        struct Resolution {
            let originalId: UUID
            let resolution: SiteVisitWriteResolution
            let actor: String
        }
        var delivered: [SiteVisitWriteCommand] = []
        var resolutions: [Resolution] = []
    }

    /// One answer whose local write state sits at `localRevision`, plus the
    /// queued, unattempted command that carries `sentText` on that base.
    @MainActor
    private func makeAnswerFixture(localRevision: Int64, sentText: String) throws -> AnswerFixture {
        let schema = Schema([SiteVisitType.self, SiteVisitChecklistAnswer.self, SyncOperation.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let outbound = ModelContext(container)
        let answer = SiteVisitChecklistAnswer(id: "9e21c3db-f5b0-4fab-b7be-fc552ff73f68",
            siteVisitId: "96090555-b4d0-4a34-9800-3587a80653a5", companyId: "company", opportunityId: nil, siteVisitTypeId: nil,
            fieldId: "739d9f85-6e6c-4b6d-bb33-a52dd443d893", label: "General Notes", kind: .longText, required: false,
            sortOrder: 40, answerValue: .text(sentText))
        answer.writeState = .init(revision: localRevision)
        outbound.insert(answer)
        let command = SiteVisitWriteModels.command(answer)
        let operation = try Self.makeOperation(answer: answer, command: command)
        outbound.insert(operation)
        try outbound.save()
        return AnswerFixture(container: container, outbound: outbound, answer: answer, command: command, operation: operation)
    }

    private static func makeOperation(answer: SiteVisitChecklistAnswer, command: SiteVisitWriteCommand) throws -> SyncOperation {
        let operation = SyncOperation(entityType: SyncEntityType.siteVisitChecklistAnswer.rawValue, entityId: answer.id,
            operationType: "siteVisitWrite",
            payload: try JSONEncoder().encode(SiteVisitSyncOperation.Payload(
                companyId: answer.companyId, siteVisitId: answer.siteVisitId, entityId: answer.id, writeCommand: command)),
            changedFields: ["answer_value"])
        operation.siteVisitWriteActorId = "actor"
        return operation
    }

    /// The same row as `command`, carrying `text` on `baseRevision`.
    private static func command(like command: SiteVisitWriteCommand, text: String, baseRevision: Int64) -> SiteVisitWriteCommand {
        SiteVisitWriteCommand(companyId: command.companyId, entity: command.entity, rows: [
            .init(id: command.rows[0].id, baseRevision: baseRevision, before: command.rows[0].before,
                  values: replacingText(command.rows[0].values, with: text))
        ])
    }

    /// A server row exactly as `apply_site_visit_rows` echoes it: the requested
    /// values plus the revision the server assigned.
    private static func row(_ command: SiteVisitWriteCommand, revision: Int64) -> SiteVisitWriteJSON {
        guard case .object(var values) = command.rows[0].values else { return .null }
        values["write_revision"] = .number(Double(revision))
        return .object(values)
    }

    private static func replacingText(_ values: SiteVisitWriteJSON, with text: String) -> SiteVisitWriteJSON {
        guard case .object(var object) = values else { return values }
        object["answer_value"] = .object(["text": .string(text)])
        return .object(object)
    }
}
