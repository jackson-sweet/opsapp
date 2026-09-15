import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitSingleChoiceTests: XCTestCase {
    private let company = "11111111-1111-4111-8111-111111111111"
    private let actor = "22222222-2222-4222-8222-222222222222"
    private let visit = "33333333-3333-4333-8333-333333333333"

    private func options() -> SiteVisitSingleChoice {
        .init(options: [
            .init(id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", label: "Cedar"),
            .init(id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", label: "Composite")
        ])
    }

    private func template() -> SiteVisitType {
        SiteVisitType(companyId: company, slug: "materials", name: "Materials", fields: [
            .init(id: "material", label: "Material", kind: .shortText, required: true,
                  sortOrder: 10, singleChoice: options())
        ])
    }

    private func answer() throws -> SiteVisitChecklistAnswer {
        try XCTUnwrap(SiteVisitChecklistAnswer.makeAnswers(for: template(), siteVisitId: visit,
            companyId: company, opportunityId: nil, createdBy: actor).first)
    }

    func testValidationNormalizesLabelsAndRejectsAmbiguousOrUnboundedOptions() throws {
        var valid = options()
        valid.options[0].label = "  Cedar \n"
        let normalized = try valid.normalized()
        XCTAssertEqual(normalized.options[0].label, "Cedar")
        XCTAssertEqual(normalized.options.map(\.id), valid.options.map(\.id))
        var invalid: [SiteVisitSingleChoice] = []
        var candidate = options(); candidate.options[1].label = " cedar "; invalid.append(candidate)
        candidate = options(); candidate.options[0].label = "\n "; invalid.append(candidate)
        candidate = options(); candidate.options[0].label = String(repeating: "a", count: 121); invalid.append(candidate)
        candidate = options(); candidate.options[1].id = candidate.options[0].id; invalid.append(candidate)
        candidate = options(); candidate.options[0].id = "not-a-uuid"; invalid.append(candidate)
        candidate = options(); candidate.options[0].id = candidate.options[0].id.uppercased(); invalid.append(candidate)
        candidate = options(); candidate.version = 2; invalid.append(candidate)
        invalid.append(.init(options: [.init(label: "One")]))
        invalid.append(.init(options: (0..<21).map { .init(label: "Option \($0)") }))
        for value in invalid { XCTAssertThrowsError(try value.normalized()) }
        XCTAssertTrue(try SiteVisitSingleChoice(options: (0..<20).map { .init(label: "Option \($0)") }).normalized().isValid)
    }

    func testMatchingRequiresExactSnapshotLabelAndPreservesUnknownText() {
        let snapshot = options()
        XCTAssertEqual(snapshot.option(matching: "Cedar")?.id, snapshot.options[0].id)
        for text in ["cedar", " Cedar", "Cedar ", "Unknown material"] {
            let value = SiteVisitChecklistValue(text: text, choiceSnapshot: snapshot)
            XCTAssertFalse(value.isAnswered)
            XCTAssertTrue(value.hasContent)
            XCTAssertEqual(value.text, text)
        }
        let accented = SiteVisitSingleChoice(options: [.init(label: "Caf\u{e9}"), .init(label: "Other")])
        XCTAssertNil(accented.option(matching: "Cafe\u{301}"))
        XCTAssertFalse(SiteVisitChecklistValue(text: "Cedar", boolValue: true, choiceSnapshot: snapshot).isAnswered)
    }

    func testDuplicateLabelsUseCanonicalEquivalenceAndUnicodeRootLowercase() {
        for labels in [["I", "i"], ["\u{130}", "i\u{307}"], ["Σ", "σ"], ["Caf\u{e9}", "Cafe\u{301}"]] {
            let choice = SiteVisitSingleChoice(options: labels.map { .init(label: $0) })
            XCTAssertThrowsError(try choice.normalized(), labels.joined(separator: "/"))
        }
        for labels in [["I", "ı"], ["Σ", "ς"], ["ß", "SS"]] {
            let choice = SiteVisitSingleChoice(options: labels.map { .init(label: $0) })
            XCTAssertNoThrow(try choice.normalized(), labels.joined(separator: "/"))
        }
    }

    func testTemplateAndAnswerRemainReadableByLegacyEightKindDecoders() throws {
        struct LegacyField: Decodable { let kind: SiteVisitFieldKind; let label: String }
        struct LegacyValue: Decodable { let text: String? }
        let type = template()
        let decoded = try JSONDecoder().decode([LegacyField].self, from: XCTUnwrap(type.fieldsData))
        XCTAssertEqual(decoded.first?.kind, .shortText)
        XCTAssertEqual(SiteVisitFieldKind.allCases.count, 8)
        let value = SiteVisitChecklistValue(text: "Cedar", choiceSnapshot: options())
        XCTAssertEqual(try JSONDecoder().decode(LegacyValue.self, from: JSONEncoder().encode(value)).text, "Cedar")
    }

    func testEditorKindIsSeparateAndValidationRejectsChoiceOnNonTextKind() throws {
        var field = SiteVisitTypeFieldDefinition(label: "Material", kind: .checkbox, sortOrder: 0)
        field.inputType = .singleChoice
        XCTAssertEqual(field.kind, .shortText)
        XCTAssertEqual(field.singleChoice?.options.count, 2)
        XCTAssertThrowsError(try SiteVisitTypeSettingsLogic.normalizedFields([field]))
        field.singleChoice = options()
        XCTAssertNoThrow(try SiteVisitTypeSettingsLogic.normalizedFields([field]))
        field.kind = .yesNoNA
        XCTAssertThrowsError(try SiteVisitTypeSettingsLogic.normalizedFields([field]))
        field.inputType = .standard(.shortText)
        XCTAssertNil(field.singleChoice)
        XCTAssertTrue(SiteVisitTypeSettingsLogic.availableInputTypes(deckBuilderEnabled: false, preserving: .shortText).contains(.singleChoice))
    }

    func testTemplateRenameRemovalAndReorderDoNotChangeExistingVisitSnapshot() throws {
        let type = template()
        let existing = try XCTUnwrap(SiteVisitChecklistAnswer.makeAnswers(for: type, siteVisitId: visit,
            companyId: company, opportunityId: nil, createdBy: actor).first)
        existing.answerValue = .text("Cedar")
        var edited = type.fields
        edited[0].singleChoice?.options[0].label = "Pressure treated"
        edited[0].singleChoice?.options.reverse()
        type.fields = edited
        XCTAssertEqual(existing.answerValue.choiceSnapshot, options())
        XCTAssertEqual(existing.answerValue.selectedOption?.id, options().options[0].id)
        edited[0].inputType = .standard(.shortText); type.fields = edited
        XCTAssertEqual(existing.answerValue.choiceSnapshot, options())
        XCTAssertTrue(existing.isAnswered)
    }

    func testClearKeepsSnapshotButEmitsEmptyWireAndExplicitClearOnlyForEmptyContent() throws {
        let model = try answer()
        XCTAssertFalse(model.isAnswered)
        XCTAssertFalse(model.answerValue.hasContent)
        XCTAssertNil(SiteVisitWriteModels.command(model).rows[0].clearAnswer)
        model.answerValue = .text("Cedar")
        model.writeState = .init(revision: 4)
        model.answerValue = .empty
        var state = model.writeState; state.explicitlyEdited = true; model.writeState = state
        let cleared = SiteVisitWriteModels.command(model)
        XCTAssertEqual(cleared.protocol, SiteVisitWriteCommand.choiceRevision)
        XCTAssertEqual(cleared.rows[0].values["answer_value"], .object([:]))
        XCTAssertEqual(cleared.rows[0].clearAnswer, true)
        XCTAssertNotNil(cleared.rows[0].values["choice_snapshot"])
        XCTAssertEqual(cleared.rows[0].before["answer_value"]?["text"], .string("Cedar"))
        XCTAssertEqual(model.answerValue.choiceSnapshot, options())
        model.answerValue = .text("Legacy free text")
        XCTAssertFalse(model.isAnswered)
        XCTAssertNil(SiteVisitWriteModels.command(model).rows[0].clearAnswer)
        XCTAssertTrue(SiteVisitContentPolicy.hasContent(visit: nil, artifacts: [], answers: [model], drafts: []))
    }

    func testOrdinarySetterCannotReplaceSnapshotAndServerHydrationCan() throws {
        let model = try answer()
        var replacement = options(); replacement.options[0].label = "Oak"
        model.answerValue = .init(text: "Cedar", choiceSnapshot: replacement)
        XCTAssertEqual(model.answerValue.choiceSnapshot, options())
        try model.acceptServerValue(.init(text: "Oak", choiceSnapshot: replacement))
        XCTAssertEqual(model.answerValue.choiceSnapshot, replacement)
        XCTAssertTrue(model.isAnswered)
    }

    func testWireSeparatesSnapshotFromPureAnswerAndInboundHydratesItForLocalStorage() throws {
        let model = try answer(); model.answerValue = .text("Cedar")
        let wire = SiteVisitWriteModels.values(model)
        XCTAssertNotNil(wire["choice_snapshot"])
        XCTAssertNil(wire["answer_value"]?["choiceSnapshot"])
        XCTAssertEqual(wire["answer_value"], .object(["text": .string("Cedar")]))
        let dto = try SiteVisitChecklistAnswerDTO.serverRow(for: model)
        XCTAssertNil(dto.answerValue.choiceSnapshot)
        XCTAssertEqual(dto.hydratedAnswerValue.choiceSnapshot, options())
        XCTAssertEqual(dto.hydratedAnswerValue.selectedOption?.label, "Cedar")
        let roundTrip = try SiteVisitWriteJSON.encode(dto)
        XCTAssertEqual(roundTrip["choice_snapshot"], wire["choice_snapshot"])
        XCTAssertNil(roundTrip["answer_value"]?["choiceSnapshot"])
    }

    func testChoiceProtocolIncludesConversionAwayAndRemoteChoiceWithoutChangingLegacyCommands() throws {
        let type = template(); type.writeState = .init(revision: 7)
        var fields = type.fields; fields[0].inputType = .standard(.shortText); type.fields = fields
        let converted = try SiteVisitWriteModels.command([type])
        XCTAssertEqual(converted.protocol, SiteVisitWriteCommand.choiceRevision)
        XCTAssertTrue(converted.rows[0].before.containsChoiceMetadata)
        XCTAssertFalse(converted.rows[0].values.containsChoiceMetadata)
        let ordinary = SiteVisitType(companyId: company, slug: "ordinary", name: "Ordinary", fields: fields)
        let legacy = try SiteVisitWriteModels.command([ordinary])
        XCTAssertEqual(legacy.protocol, SiteVisitWriteCommand.revision)
        XCTAssertEqual(legacy.applyRPC, "apply_site_visit_write")
        XCTAssertEqual(legacy.reviewRPC, "review_site_visit_write")
        XCTAssertEqual(legacy.resolveRPC, "resolve_site_visit_write")
        var state = ordinary.writeState; state.remoteRow = SiteVisitWriteModels.values(template()); ordinary.writeState = state
        XCTAssertEqual(try SiteVisitWriteModels.command([ordinary]).protocol, SiteVisitWriteCommand.choiceRevision)
        let replay = try JSONDecoder().decode(SiteVisitWriteCommand.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(replay, legacy)
        XCTAssertEqual(replay.protocol, SiteVisitWriteCommand.revision)
        XCTAssertEqual(converted.applyRPC, "apply_site_visit_write_v2")
        XCTAssertEqual(converted.reviewRPC, "review_site_visit_write_v2")
        XCTAssertEqual(converted.resolveRPC, "resolve_site_visit_write_v2")
    }

    func testSnapshotParticipatesInExactReceiptAndConflictDescription() throws {
        let model = try answer(); model.answerValue = .text("Cedar")
        let expected = SiteVisitWriteModels.values(model)
        guard case .object(var changed) = expected else { return XCTFail() }
        changed.removeValue(forKey: "choice_snapshot")
        XCTAssertFalse(SiteVisitWriteJSON.object(changed).matchesRequested(expected))
        var other = options(); other.options.reverse()
        changed["choice_snapshot"] = try SiteVisitWriteJSON.encode(other)
        XCTAssertFalse(SiteVisitWriteJSON.object(changed).matchesRequested(expected))
        let summary = SiteVisitConflictReview.summary(expected)
        XCTAssertTrue(summary.contains("Cedar"))
        XCTAssertTrue(summary.contains("Composite"))
        XCTAssertFalse(summary.contains(options().options[0].id))
    }

    func testSnapshotAndQueuedV2CommandSurviveDiskReopenWithoutSchemaChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = Schema([SiteVisitType.self, SiteVisitChecklistAnswer.self, SyncOperation.self])
        let configuration = ModelConfiguration(schema: schema, url: root.appendingPathComponent("choice.store"))
        let originalCommand: SiteVisitWriteCommand
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(container)
            let model = try answer(); model.answerValue = .text("Cedar")
            model.writeState = .init(revision: 3); model.answerValue = .text("Composite")
            context.insert(model)
            originalCommand = SiteVisitWriteModels.command(model)
            let operation = SyncOperation(entityType: SyncEntityType.siteVisitChecklistAnswer.rawValue, entityId: model.id,
                operationType: "siteVisitWrite", payload: try JSONEncoder().encode(originalCommand), changedFields: ["answer_value"])
            context.insert(operation); try context.save()
        }
        let reopened = try ModelContainer(for: schema, configurations: configuration)
        let verify = ModelContext(reopened)
        let model = try XCTUnwrap(verify.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first)
        XCTAssertEqual(model.answerValue.choiceSnapshot, options())
        XCTAssertEqual(model.answerValue.selectedOption?.label, "Composite")
        XCTAssertEqual(model.writeState.baseRow?["answer_value"]?["text"], .string("Cedar"))
        let operation = try XCTUnwrap(verify.fetch(FetchDescriptor<SyncOperation>()).first)
        XCTAssertEqual(try JSONDecoder().decode(SiteVisitWriteCommand.self, from: operation.payload), originalCommand)
    }

    func testInboundFreshCleanAndPendingReadsPreserveSeparateSnapshotAndLegacyText() throws {
        let schema = Schema(versionedSchema: OPSSchemaCurrent.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let parent = SiteVisit(id: visit, companyId: company, status: .inProgress, createdBy: actor)
        context.insert(parent); try context.save()
        let source = try answer(); source.answerValue = .text("Unrecognized legacy material")
        var dto = try SiteVisitChecklistAnswerDTO.serverRow(for: source, writeRevision: 1)
        _ = try SiteVisitServerMerge.merge(checklistAnswer: dto, companyId: company, into: context)
        let fresh = try XCTUnwrap(context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first)
        XCTAssertEqual(fresh.answerValue.choiceSnapshot, options())
        XCTAssertEqual(fresh.answerValue.text, "Unrecognized legacy material")
        XCTAssertFalse(fresh.isAnswered)
        XCTAssertFalse(fresh.needsSync)
        source.answerValue = .text("Cedar")
        dto = try SiteVisitChecklistAnswerDTO.serverRow(for: source, writeRevision: 2)
        _ = try SiteVisitServerMerge.merge(checklistAnswer: dto, companyId: company, into: context)
        XCTAssertEqual(fresh.answerValue.selectedOption?.label, "Cedar")
        fresh.answerValue = .text("Composite"); try context.save()
        dto.writeRevision = 3
        _ = try SiteVisitServerMerge.merge(checklistAnswer: dto, companyId: company, into: context)
        XCTAssertEqual(fresh.answerValue.selectedOption?.label, "Composite")
        XCTAssertNotNil(fresh.writeState.remoteRow?["choice_snapshot"])
        XCTAssertNil(fresh.writeState.remoteRow?["answer_value"]?["choiceSnapshot"])
    }

    func testCurrentTemplateSelectsV2ForHistoricalNilSnapshotWithoutRewritingQueuedV1() throws {
        let schema = Schema(versionedSchema: OPSSchemaCurrent.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let type = template()
        let historical = SiteVisitChecklistAnswer(siteVisitId: visit, companyId: company, opportunityId: nil,
            siteVisitTypeId: type.id, fieldId: "material", label: "Material", kind: .shortText, required: true,
            sortOrder: 10, answerValue: .text("Cedar"), createdBy: actor)
        let parent = SiteVisit(id: visit, companyId: company, status: .inProgress, createdBy: actor)
        parent.needsSync = false
        context.insert(type); context.insert(parent); context.insert(historical)
        let old = SiteVisitSyncOperation.checklistAnswer(historical)
        let queued = SyncOperation(entityType: old.entityType.rawValue, entityId: historical.id,
            operationType: old.operationType, payload: try JSONEncoder().encode(old.payload), changedFields: old.changedFields)
        queued.siteVisitWriteActorId = SiteVisitAuthorHeal.sessionUserId()?.lowercased()
        context.insert(queued); try context.save()
        let originalBytes = queued.payload
        let originalCommand = try XCTUnwrap(SiteVisitVersionedSync.command(queued))
        XCTAssertEqual(originalCommand.protocol, SiteVisitWriteCommand.revision)
        XCTAssertTrue(try SiteVisitWriteModels.currentTemplateHasChoice(for: historical, context: context))
        XCTAssertTrue(try SiteVisitWriteModels.needsChoiceReview(originalCommand, context: context))
        let coordinator = SiteVisitPersistenceCoordinator(modelContext: context, companyId: company)
        try coordinator.commit { historical.answerValue = .text("Composite") }
        let operations = try context.fetch(FetchDescriptor<SyncOperation>()).filter { $0.entityId == historical.id }
        XCTAssertEqual(operations.count, 2)
        XCTAssertEqual(queued.payload, originalBytes)
        let descendant = try XCTUnwrap(operations.first { $0.id != queued.id })
        let next = try XCTUnwrap(SiteVisitVersionedSync.command(descendant))
        XCTAssertEqual(next.protocol, SiteVisitWriteCommand.choiceRevision)
        XCTAssertNil(next.rows[0].values["choice_snapshot"])
        XCTAssertNil(historical.answerValue.choiceSnapshot)
        XCTAssertEqual(descendant.dependsOnId, queued.id.uuidString.lowercased())
    }

    func testPacketRemainsReadableAsTextForSelectedAndUnrecognizedHistoricalAnswers() throws {
        let model = try answer()
        for text in ["Cedar", "Historic free text"] {
            model.answerValue = .text(text)
            let packet = SiteVisitProjectPayloadBuilder.payload(siteVisitId: visit, opportunityId: actor,
                address: nil, artifacts: [], checklistAnswers: [model])
            XCTAssertEqual(packet.checklistItems.first?.value, text)
            XCTAssertEqual(packet.checklistItems.first?.kind, "short_text")
            XCTAssertTrue(packet.checklistLines.first?.contains(text) == true)
        }
    }
}
