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
    func packet(synced: Bool = false) throws -> (ModelContainer, SiteVisitCaptureViewModel) {
        let schema = Schema(versionedSchema: OPSSchemaCurrent.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        containers.append(container)
        let context = ModelContext(container)
        let visit = SiteVisit(companyId: company, status: .inProgress, createdBy: actor)
        let type = SiteVisitType(companyId: company, slug: "photo-check", name: "Photo check", fields: [
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

    func testDiscardRejectsBookedVisitBeforeLocalTombstones() throws {
        let (_,vm)=try packet();vm.siteVisit?.bookedAt=Date()
        vm.discardVisit();XCTAssertNotNil(vm.errorMessage);XCTAssertNil(vm.siteVisit?.deletedAt);XCTAssertFalse(vm.artifacts.isEmpty)
    }
}
private func throwawayWriter() -> SiteVisitRemoteWriting { fatalError("Discard must not request a row writer") }
