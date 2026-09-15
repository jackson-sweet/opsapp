import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitFieldWorkflowTests: XCTestCase {
    let company = "11111111-1111-4111-8111-111111111111"
    let actor = "22222222-2222-4222-8222-222222222222"
    var containers: [ModelContainer] = []
    var originalActor: String?
    override func setUp() { originalActor = UserDefaults.standard.string(forKey: "currentUserId"); UserDefaults.standard.set(actor, forKey: "currentUserId") }
    override func tearDown() {
        if let originalActor { UserDefaults.standard.set(originalActor, forKey: "currentUserId") } else { UserDefaults.standard.removeObject(forKey: "currentUserId") }
        containers.removeAll()
    }
    func testCustomChoiceSelectionClearAndRequiredStateSurviveReopenWithOriginalOptions() throws {
        let choices = SiteVisitSingleChoice(options: [.init(label: "Cedar"), .init(label: "Composite")])
        let (container, vm) = try packet(fields: [
            .init(id: "material", label: "Material", kind: .shortText, required: true, sortOrder: 0, singleChoice: choices)
        ])
        let answer = try XCTUnwrap(vm.checklistAnswers.first)
        XCTAssertFalse(vm.canComplete)
        vm.bufferChecklistAnswer(answer, value: .text("Cedar"))
        XCTAssertTrue(vm.flushChecklistEdits())
        XCTAssertEqual(answer.answerValue.selectedOption?.id, choices.options[0].id)
        XCTAssertTrue(vm.canComplete)
        vm.updateChecklistAnswer(answer, value: .text("Unknown legacy material"))
        XCTAssertFalse(vm.canComplete)
        XCTAssertTrue(vm.hasCapturedAnything)
        XCTAssertEqual(answer.answerValue.text, "Unknown legacy material")
        vm.updateChecklistAnswer(answer, value: .empty)
        XCTAssertEqual(answer.answerValue.choiceSnapshot, choices)
        XCTAssertFalse(answer.answerValue.hasContent)
        XCTAssertEqual(SiteVisitWriteModels.command(answer).rows[0].clearAnswer, true)
        let reopened = SiteVisitCaptureViewModel(opportunity: nil, companyId: company, userId: actor,
            modelContext: ModelContext(container), entryIntent: .resume(visitId: try XCTUnwrap(vm.siteVisit).id))
        reopened.loadOrCreateVisit()
        let restored = try XCTUnwrap(reopened.checklistAnswers.first)
        XCTAssertEqual(restored.answerValue.choiceSnapshot, choices)
        XCTAssertFalse(restored.isAnswered)
        XCTAssertFalse(reopened.canComplete)
        reopened.updateChecklistAnswer(restored, value: .text("Composite"))
        XCTAssertTrue(reopened.canComplete)
        XCTAssertEqual(restored.answerValue.selectedOption?.id, choices.options[1].id)
    }
    func packet(synced: Bool = false, fields: [SiteVisitTypeFieldDefinition]? = nil) throws -> (ModelContainer, SiteVisitCaptureViewModel) {
        let schema = Schema(versionedSchema: OPSSchemaCurrent.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        containers.append(container)
        let context = ModelContext(container)
        let visit = SiteVisit(companyId: company, status: .inProgress, createdBy: actor)
        let type = SiteVisitType(companyId: company, slug: "photo-check", name: "Photo check", fields: fields ?? [
            .init(id: "photo", label: "Photo", kind: .photo, sortOrder: 0),
            .init(id: "markup", label: "Marked dimensions", kind: .photoMarkup, sortOrder: 1)])
        context.insert(type); try context.save()
        let coordinator = SiteVisitPersistenceCoordinator(modelContext: context, companyId: company)
        try coordinator.commit {
            context.insert(visit)
            if synced { visit.lastSyncedAt = Date() }
            for kind in [SiteVisitCaptureArtifactKind.photo, .annotatedPhoto, .dimensionedPhoto] {
                let artifact = SiteVisitCaptureArtifact(siteVisitId: visit.id, companyId: company, kind: kind, source: .camera,
                    localAssetURL: synced ? "https://example.invalid/\(kind.rawValue).jpg" : "local://project_images/\(kind.rawValue).jpg", createdBy: actor)
                context.insert(artifact)
            }
            for answer in SiteVisitChecklistAnswer.makeAnswers(for: type, siteVisitId: visit.id, companyId: company, opportunityId: nil, createdBy: actor) { context.insert(answer) }
        }
        let vm = SiteVisitCaptureViewModel(opportunity: nil, companyId: company, userId: actor,
            modelContext: ModelContext(container), entryIntent: .resume(visitId: visit.id))
        vm.loadOrCreateVisit()
        return (container,vm)
    }
    func testHydrationSelectsOnlyRealMarkupAndPreservesExplicitClearingAcrossReopen() throws {
        let (container,vm) = try packet()
        let photo = try XCTUnwrap(vm.checklistAnswers.first { $0.kind == .photo })
        let markup = try XCTUnwrap(vm.checklistAnswers.first { $0.kind == .photoMarkup })
        XCTAssertEqual(photo.answerValue.artifactIds.count, 3)
        XCTAssertEqual(markup.answerValue.artifactIds.count, 2)
        let kinds = vm.artifacts.filter { markup.answerValue.artifactIds.contains($0.id) }.map(\.kind)
        XCTAssertEqual(Set(kinds), Set([.annotatedPhoto,.dimensionedPhoto]))
        vm.updateChecklistAnswer(markup, value: .empty)
        XCTAssertEqual(SiteVisitWriteModels.command(markup).rows.first?.clearAnswer, true)
        vm.loadOrCreateVisit()
        XCTAssertEqual(markup.answerValue, .empty)
        let resumed = SiteVisitCaptureViewModel(opportunity: nil, companyId: company, userId: actor,
            modelContext: ModelContext(container), entryIntent: .resume(visitId: try XCTUnwrap(vm.siteVisit).id))
        resumed.loadOrCreateVisit()
        XCTAssertEqual(resumed.checklistAnswers.first { $0.kind == .photoMarkup }?.answerValue, .empty)
        XCTAssertEqual(resumed.checklistAnswers.first { $0.kind == .photoMarkup }?.writeState.explicitlyEdited, true)
    }
    func testDiscardUIClosesUnsentAndSyncedPacketsWithoutUploadingChildren() async throws {
        for synced in [false,true] {
            let (container,vm) = try packet(synced: synced)
            let visitId = try XCTUnwrap(vm.siteVisit).id
            vm.discardVisit()
            XCTAssertNil(vm.errorMessage)
            XCTAssertNotNil(vm.siteVisit?.deletedAt)
            XCTAssertTrue(vm.artifacts.isEmpty)
            let drain = ModelContext(container)
            var operations = try drain.fetch(FetchDescriptor<SyncOperation>())
            let discard = try XCTUnwrap(operations.first { $0.operationType == SiteVisitSyncOperation.discardOperationType })
            let intent = try XCTUnwrap(JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: discard.payload).discard)
            let originalBytes = Dictionary(uniqueKeysWithValues: operations.filter { intent.supersededOperationIds.contains($0.id) }.map { ($0.id,$0.payload) })
            XCTAssertTrue(SiteVisitOutboundSync.isReady(discard, in: operations))
            XCTAssertTrue(operations.filter { intent.supersededOperationIds.contains($0.id) }.allSatisfy { !SiteVisitOutboundSync.isReady($0,in:operations) })
            _ = try SiteVisitPersistenceCoordinator(modelContext: drain,companyId:company).recoverOrphanedWrites(siteVisitIds:[visitId])
            XCTAssertEqual(try drain.fetch(FetchDescriptor<SyncOperation>()).count,operations.count)
            var deliveries = 0
            let sync = SiteVisitOutboundSync(repositoryFactory: { _ in XCTFail("Discard must not upload child rows"); return throwawayWriter() },sessionUserId:{self.actor},deliverDiscard:{id,submitted,actor in
                deliveries += 1; XCTAssertEqual(submitted,intent);XCTAssertEqual(actor,self.actor)
                return SiteVisitDiscardReceipt(commandId:id,companyId:self.company,siteVisitId:visitId,discardedAt:intent.discardedAt,outcome:"discarded")
            })
            let handled = try await sync.executeIfHandled(operation:discard,context:drain,activeCompanyId:company)
            XCTAssertTrue(handled)
            discard.status="completed";try drain.save()
            let verify=ModelContext(container);operations=try verify.fetch(FetchDescriptor<SyncOperation>())
            for old in operations where originalBytes[old.id] != nil { XCTAssertEqual(old.payload,originalBytes[old.id]);XCTAssertEqual(old.status,"completed") }
            XCTAssertTrue(try verify.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).allSatisfy { $0.siteVisitId != visitId || ($0.deletedAt != nil && !$0.needsSync) })
            XCTAssertTrue(try verify.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).allSatisfy { $0.siteVisitId != visitId || ($0.deletedAt != nil && !$0.needsSync) })
            XCTAssertEqual(deliveries,1)
        }
    }
    func testInboundClearAndUnknownSurviveFreshAndCleanMergeWhileUntouchedHydrates() throws {
        for fresh in [false, true] {
            for state in ["cleared", "unknown", "untouched"] {
                let (container, vm) = try packet(synced: true)
                let context = ModelContext(container)
                let answer = try XCTUnwrap(context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first { $0.kind == .photoMarkup })
                let answerId = answer.id, visitId = answer.siteVisitId
                guard case .object(var row) = SiteVisitWriteModels.values(answer) else { return XCTFail() }
                row["answer_value"] = .object([:]); row["answer_state"] = state == "untouched" ? .null : .string(state)
                row["write_revision"] = .number(7); row["created_by"] = .string(actor)
                row["created_at"] = .string(SupabaseDate.format(Date()))
                row["updated_at"] = .string(SupabaseDate.format(Date().addingTimeInterval(10)))
                for operation in try context.fetch(FetchDescriptor<SyncOperation>()) { context.delete(operation) }
                if fresh { context.delete(answer) } else { answer.needsSync = false; answer.writeState = .init(); answer.lastSyncedAt = Date() }
                try context.save()
                let dto = try JSONDecoder().decode(SiteVisitChecklistAnswerDTO.self, from: JSONEncoder().encode(SiteVisitWriteJSON.object(row)))
                _ = try SiteVisitServerMerge.merge(checklistAnswer: dto, companyId: company, into: context)
                let reopened = SiteVisitCaptureViewModel(opportunity: nil, companyId: company, userId: actor,
                    modelContext: ModelContext(container), entryIntent: .resume(visitId: visitId))
                reopened.loadOrCreateVisit()
                let result = try XCTUnwrap(reopened.checklistAnswers.first { $0.id == answerId })
                XCTAssertEqual(result.writeState.answerState, state == "untouched" ? nil : state)
                XCTAssertEqual(result.answerValue.artifactIds.count, state == "untouched" ? 2 : 0)
                if state != "untouched" { XCTAssertFalse(result.needsSync) }
                _ = vm
            }
        }
    }

    func testAcceptCurrentUnknownRemainsEmptyWhenCaptureReopens() throws {
        let (container, vm) = try packet(synced: true)
        let context = ModelContext(container)
        let answer = try XCTUnwrap(context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first { $0.kind == .photoMarkup })
        let command = SiteVisitWriteModels.command(answer)
        for old in try context.fetch(FetchDescriptor<SyncOperation>()) { old.status = "completed" }
        let operation = SyncOperation(entityType: SyncEntityType.siteVisitChecklistAnswer.rawValue, entityId: answer.id,
            operationType: "siteVisitWrite", payload: try JSONEncoder().encode(SiteVisitSyncOperation.Payload(
                companyId: company, siteVisitId: answer.siteVisitId, entityId: answer.id, writeCommand: command)), changedFields: ["answer_value"])
        operation.siteVisitWriteActorId = actor; context.insert(operation)
        guard case .object(var row) = command.rows[0].values else { return XCTFail() }
        row["answer_value"] = .object([:]); row["answer_state"] = .string("unknown"); row["write_revision"] = .number(8)
        row["created_by"] = .string(actor); row["created_at"] = .string(SupabaseDate.format(Date()))
        row["updated_at"] = .string(SupabaseDate.format(Date()))
        let current: [SiteVisitWriteJSON] = [.object(row)]
        let resolution = SiteVisitWriteResolution(id: UUID(), choice: "current", current: current)
        let data = try JSONEncoder().encode(resolution); operation.siteVisitWriteResolutionData = data; try context.save()
        let receipt = SiteVisitWriteReceipt(commandId: resolution.id, entity: "answer", outcome: "resolved", reason: nil, rows: current)
        try SiteVisitVersionedSync.applyReceipt(receipt, to: operation, command: command, resolutionData: data,
            context: context, companyId: company, actorId: actor)
        operation.status = "completed"; try context.save()
        let reopened = SiteVisitCaptureViewModel(opportunity: nil, companyId: company, userId: actor,
            modelContext: ModelContext(container), entryIntent: .resume(visitId: try XCTUnwrap(vm.siteVisit).id))
        reopened.loadOrCreateVisit()
        let accepted = try XCTUnwrap(reopened.checklistAnswers.first { $0.id == answer.id })
        XCTAssertEqual(accepted.answerValue, .empty); XCTAssertEqual(accepted.writeState.answerState, "unknown")
        XCTAssertFalse(accepted.needsSync)
    }

    func testBufferedBlankTextClearHasEmptyWireValueAndPreservesAttemptedAudit() throws {
        for kind in [SiteVisitFieldKind.shortText, .measurement] {
            for blank in ["", " \n "] {
                let (container, _) = try packet(fields: [.init(id: "scope", label: "Scope", kind: kind, sortOrder: 0)])
                let context = ModelContext(container)
                let answer = try XCTUnwrap(context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first)
                answer.answerValue = .text("18 in"); answer.writeState = .init(revision: 3)
                answer.needsSync = false; answer.lastSyncedAt = Date()
                let old = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first { $0.entityId == answer.id })
                old.siteVisitWriteAttemptedAt = Date(); let bytes = old.payload; try context.save()
                let vm = SiteVisitCaptureViewModel(opportunity: nil, companyId: company, userId: actor,
                    modelContext: ModelContext(container), entryIntent: .resume(visitId: answer.siteVisitId))
                vm.loadOrCreateVisit()
                let edited = try XCTUnwrap(vm.checklistAnswers.first { $0.id == answer.id })
                vm.bufferChecklistAnswer(edited, value: .text(blank))
                XCTAssertTrue(vm.flushChecklistEdits()); XCTAssertNil(vm.errorMessage)
                XCTAssertTrue(vm.saveDraft()) // typing stays local; saving the visit queues the clear
                let verify = ModelContext(container)
                let operations = try verify.fetch(FetchDescriptor<SyncOperation>())
                let sent = try XCTUnwrap(operations.first { $0.id == old.id })
                XCTAssertEqual(sent.payload, bytes)
                let next = try XCTUnwrap(operations.first { $0.entityId == answer.id && $0.id != old.id })
                let command = try XCTUnwrap(SiteVisitVersionedSync.command(next))
                XCTAssertEqual(command.rows[0].values["answer_value"], .object([:]))
                XCTAssertEqual(command.rows[0].before["answer_value"]?["text"], .string("18 in"))
                XCTAssertEqual(command.rows[0].clearAnswer, true)
                guard case .object(var values) = command.rows[0].values else { return XCTFail() }
                values["write_revision"] = .number(4); values["answer_state"] = .string("cleared")
                sent.status = "completed"; try verify.save()
                let receipt = SiteVisitWriteReceipt(commandId: next.id, entity: "answer", outcome: "saved", reason: nil, rows: [.object(values)])
                try SiteVisitVersionedSync.applyReceipt(receipt, to: next, command: command, resolutionData: nil,
                    context: verify, companyId: company, actorId: actor)
                let acknowledged = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first)
                XCTAssertFalse(acknowledged.needsSync); XCTAssertEqual(acknowledged.writeState.answerState, "cleared")
                XCTAssertEqual(SiteVisitWriteModels.values(acknowledged)["answer_value"], .object([:]))
                for value in [SiteVisitChecklistValue.text("0"), .text("18 in"), .bool(false)] {
                    acknowledged.answerValue = value
                    XCTAssertNotEqual(SiteVisitWriteModels.values(acknowledged)["answer_value"], .object([:]))
                    XCTAssertNil(SiteVisitWriteModels.command(acknowledged).rows.first?.clearAnswer)
                }
            }
        }
    }

    // MARK: - Local until save (2026-09-15)

    /// Typing stays on the phone. Going to the background stays on the phone.
    /// Saving the visit queues what was typed and starts the upload.
    func testTypingSavesLocallyAndUploadsOnlyWhenTheVisitIsSaved() throws {
        let (container, vm) = try packet(fields: [
            .init(id: "notes", label: "General Notes", kind: .longText, sortOrder: 0)
        ])
        vm.checklistFlushDelayNanoseconds = 0
        let queue = ModelContext(container)
        for operation in try queue.fetch(FetchDescriptor<SyncOperation>()) {
            operation.status = "completed"
            operation.completedAt = Date()
        }
        try queue.save()
        let answer = try XCTUnwrap(vm.checklistAnswers.first)
        var uploadsStarted = 0
        vm.onWorkQueued = { uploadsStarted += 1 }

        vm.bufferChecklistAnswer(answer, value: .text("Client would like"))
        vm.bufferChecklistAnswer(answer, value: .text("Client would like to rebuild"))
        XCTAssertTrue(vm.flushChecklistEdits())
        XCTAssertEqual(answer.answerValue.text, "Client would like to rebuild")
        XCTAssertTrue(answer.needsSync)
        XCTAssertTrue(try pendingOperations(in: container).isEmpty, "Typing must not queue an upload")
        XCTAssertEqual(uploadsStarted, 0)

        XCTAssertTrue(vm.preserveDraft())
        XCTAssertTrue(try pendingOperations(in: container).isEmpty, "Backgrounding keeps the draft on the phone")
        XCTAssertEqual(uploadsStarted, 0)

        XCTAssertTrue(vm.saveDraft())
        let write = try XCTUnwrap(pendingOperations(in: container).first { $0.entityId == answer.id })
        XCTAssertEqual(
            SiteVisitVersionedSync.command(write)?.rows[0].values["answer_value"]?["text"],
            .string("Client would like to rebuild")
        )
        XCTAssertEqual(uploadsStarted, 1)
    }

    /// A keystroke shows on screen at once and reaches the store only after the
    /// operator pauses — one transaction per pause, not one per character.
    func testKeystrokesWaitBeforeTouchingTheStore() async throws {
        let (container, vm) = try packet(fields: [
            .init(id: "notes", label: "General Notes", kind: .longText, sortOrder: 0)
        ])
        vm.checklistFlushDelayNanoseconds = 40_000_000
        let answer = try XCTUnwrap(vm.checklistAnswers.first)
        vm.bufferChecklistAnswer(answer, value: .text("C"))
        XCTAssertEqual(vm.checklistValue(for: answer).text, "C")
        XCTAssertNil(answer.answerValue.text, "The store is not touched on the keystroke itself")
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(answer.answerValue.text, "C")
        withExtendedLifetime(container) {}
    }

    private func pendingOperations(in container: ModelContainer) throws -> [SyncOperation] {
        try ModelContext(container).fetch(FetchDescriptor<SyncOperation>()).filter { $0.status != "completed" }
    }

    func testDiscardRejectsBookedVisitBeforeLocalTombstones() throws {
        let (_,vm)=try packet();vm.siteVisit?.bookedAt=Date()
        vm.discardVisit();XCTAssertNotNil(vm.errorMessage);XCTAssertNil(vm.siteVisit?.deletedAt);XCTAssertFalse(vm.artifacts.isEmpty)
    }
}
private func throwawayWriter() -> SiteVisitRemoteWriting { fatalError("Discard must not request a row writer") }
