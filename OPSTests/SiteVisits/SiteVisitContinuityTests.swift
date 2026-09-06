import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitContinuityTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private let company = "11111111-1111-1111-1111-111111111111"
    private let actor = "22222222-2222-2222-2222-222222222222"
    private let lead = "33333333-3333-3333-3333-333333333333"

    override func tearDown() { containers.removeAll(); super.tearDown() }

    func test_initialAndReassignedLeadSnapshotsPreserveConversionAndSummaryFields() throws {
        let (vm, context) = try makeVisit(prepareShared: { context in
            let initial = try XCTUnwrap(context.fetch(FetchDescriptor<Opportunity>()).first)
            self.fillLeadSnapshotFields(initial, version: 7)
            try context.save()
        })
        assertSnapshotFields(try XCTUnwrap(vm.currentOpportunity), version: 7)
        let reassigned = Opportunity(id: UUID().uuidString.lowercased(), companyId: company, contactName: "Reassigned")
        fillLeadSnapshotFields(reassigned, version: 11)
        context.insert(reassigned); try context.save()
        vm.reassignVisit(to: reassigned)
        assertSnapshotFields(try XCTUnwrap(vm.currentOpportunity), version: 11)
        XCTAssertNil(vm.currentOpportunity?.modelContext)
    }

    func test_actualDeckHostSaveKeepsCallerWIPPendingAndRetainsFailedDrawingForRetry() throws {
        var other: SiteVisit!
        let (vm, context) = try makeVisit(prepareShared: { context in
            other = SiteVisit(companyId: self.company, createdBy: self.actor)
            other.notes = "Stored other visit"
            context.insert(other); try context.save()
            other.notes = "Unfinished other visit"
        })
        let design = DeckDesign(companyId: company, opportunityId: lead, title: "Synthetic deck")
        design.drawingDataJSON = "{\"synthetic_geometry\":true}"
        vm.validateDeckSave = { throw URLError(.cannotWriteToFile) }
        XCTAssertNil(vm.saveDeckForCapture(design))
        XCTAssertEqual(vm.pendingDeckCreation?.drawingDataJSON, design.drawingDataJSON)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(try ModelContext(context.container).fetch(FetchDescriptor<DeckDesign>()).isEmpty)
        vm.validateDeckSave = {}
        let saved = try XCTUnwrap(vm.saveDeckForCapture(try XCTUnwrap(vm.pendingDeckCreation)))
        XCTAssertTrue(saved.modelContext === vm.modelContext)
        XCTAssertNil(vm.pendingDeckCreation)
        XCTAssertEqual(other.notes, "Unfinished other visit")
        XCTAssertTrue(context.hasChanges)
        let fresh = ModelContext(context.container)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<SiteVisit>()).first { $0.id == other.id }?.notes, "Stored other visit")
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<DeckDesign>()).first?.drawingDataJSON, design.drawingDataJSON)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<DeckDesign>()).first?.needsSync, true)
        XCTAssertTrue(try fresh.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).contains { $0.deckDesignId == saved.id })
    }

    private func fillLeadSnapshotFields(_ opportunity: Opportunity, version: Int64) {
        opportunity.assignmentVersion = version
        opportunity.aiSummary = "Synthetic summary"
        opportunity.aiSummaryUpdatedAt = Date(timeIntervalSince1970: 123)
        opportunity.images = ["local://project_images/synthetic.jpg"]
        opportunity.latitude = 48.4; opportunity.longitude = -123.3
        opportunity.handledAt = Date(timeIntervalSince1970: 124)
        opportunity.operatorActionRequiredAt = Date(timeIntervalSince1970: 125)
    }

    private func assertSnapshotFields(_ opportunity: Opportunity, version: Int64) {
        XCTAssertEqual(opportunity.assignmentVersion, version)
        XCTAssertEqual(opportunity.aiSummary, "Synthetic summary")
        XCTAssertEqual(opportunity.aiSummaryUpdatedAt, Date(timeIntervalSince1970: 123))
        XCTAssertEqual(opportunity.images, ["local://project_images/synthetic.jpg"])
        XCTAssertEqual(opportunity.latitude, 48.4); XCTAssertEqual(opportunity.longitude, -123.3)
        XCTAssertEqual(opportunity.handledAt, Date(timeIntervalSince1970: 124))
        XCTAssertEqual(opportunity.operatorActionRequiredAt, Date(timeIntervalSince1970: 125))
    }

    func test_captureSessionDoesNotSaveOrRollbackCallerPendingVisitGraph() throws {
        for shouldFail in [false, true] {
            let gate = FailureGate()
            var other: SiteVisit!
            var answer: SiteVisitChecklistAnswer!
            var draft: SiteVisitIdentityDraft!
            let (vm, context) = try makeVisit(gate: gate, prepareShared: { context in
                other = SiteVisit(companyId: self.company, createdBy: self.actor)
                other.notes = "Stored B"
                answer = SiteVisitChecklistAnswer(siteVisitId: other.id, companyId: self.company,
                    opportunityId: nil, siteVisitTypeId: nil, fieldId: "b", label: "B",
                    kind: .shortText, required: false, sortOrder: 0, answerValue: .text("Stored B answer"))
                context.insert(other); context.insert(answer); try context.save()
                other.notes = "Pending B"
                answer.answerValue = .text("Pending B answer")
                draft = SiteVisitIdentityDraft(siteVisitId: other.id, companyId: self.company, notes: "Pending B draft")
                context.insert(draft)
            })
            gate.fail = shouldFail
            vm.noteDraft = "Owned A note"
            XCTAssertEqual(vm.preserveDraft(), !shouldFail)
            XCTAssertEqual(other.notes, "Pending B")
            XCTAssertEqual(answer.answerValue.text, "Pending B answer")
            XCTAssertEqual(draft.notes, "Pending B draft")
            XCTAssertTrue(context.insertedModelsArray.contains { ObjectIdentifier($0) == ObjectIdentifier(draft!) })
            XCTAssertTrue(context.hasChanges)
            let fresh = ModelContext(context.container)
            XCTAssertEqual(try fresh.fetch(FetchDescriptor<SiteVisit>()).first { $0.id == other.id }?.notes, "Stored B")
            XCTAssertEqual(try fresh.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first { $0.id == answer.id }?.answerValue.text,
                "Stored B answer")
            XCTAssertFalse(try fresh.fetch(FetchDescriptor<SiteVisitIdentityDraft>()).contains { $0.id == draft.id })
            let visitId = try XCTUnwrap(vm.siteVisit?.id)
            let captures = try fresh.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).filter { $0.siteVisitId == visitId }
            XCTAssertEqual(captures.contains { $0.body == "Owned A note" }, !shouldFail)
            XCTAssertNil(vm.currentOpportunity?.modelContext, "A lead passed from another context is a detached display snapshot")
        }
    }

    func test_incompleteChecklistSavesDraftWithoutCompletionOrStageCommand() async throws {
        let (vm, context) = try makeVisit()
        let required = try XCTUnwrap(vm.missingRequiredChecklistAnswers.first)
        vm.noteDraft = "Synthetic partial work"
        let result = await vm.saveVisit(movingLeadTo: .qualifying)
        XCTAssertEqual(result, .draftSaved)
        XCTAssertFalse(required.isAnswered)
        XCTAssertNil(vm.siteVisit?.completedAt)
        XCTAssertTrue(vm.artifacts.contains { $0.body == "Synthetic partial work" })
        XCTAssertFalse(try context.fetch(FetchDescriptor<SyncOperation>()).contains {
            [SiteVisitSyncOperation.completionOperationType, SiteVisitSyncOperation.stageOperationType].contains($0.operationType)
        })
        let completion = await vm.completeVisit()
        XCTAssertEqual(completion, .notCommitted(.requiredAnswers))
    }

    func test_bufferedChecklistFlushIsAtomicAndRetainsFailedEditsForRetry() throws {
        let gate = FailureGate()
        let (vm, context) = try makeVisit(gate: gate)
        let answer = try XCTUnwrap(vm.checklistAnswers.first { $0.kind == .longText })
        vm.bufferChecklistAnswer(answer, value: .text("First"))
        vm.bufferChecklistAnswer(answer, value: .text("Newest"))
        XCTAssertFalse(answer.isAnswered)
        gate.fail = true
        XCTAssertFalse(vm.flushChecklistEdits())
        XCTAssertEqual(vm.pendingChecklistValues[answer.id]?.text, "Newest")
        XCTAssertFalse(answer.isAnswered, "held reference must reflect rollback")
        gate.fail = false
        XCTAssertTrue(vm.flushChecklistEdits())
        XCTAssertTrue(vm.pendingChecklistValues.isEmpty)
        let freshContext = ModelContext(try XCTUnwrap(containers.last))
        let saved = try XCTUnwrap(freshContext.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first { $0.id == answer.id })
        XCTAssertEqual(saved.answerValue.text, "Newest")
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).contains { $0.entityId == answer.id })
    }

    func test_unchangedIdentityAndAnswerNeverRestartStoppedWork() throws {
        let (vm, context) = try makeVisit()
        vm.updateIdentityDraft(searchText: "", clientName: "", contactName: "Synthetic customer",
            preferredEmail: "", additionalEmailsText: "", phoneNumber: "", address: "", notes: "")
        let draft = try XCTUnwrap(vm.identityDraft)
        let operation = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first { $0.entityId == draft.id })
        operation.status = "parked"; operation.retryCount = 8
        try context.save()
        vm.updateIdentityDraft(searchText: "", clientName: "", contactName: "Synthetic customer",
            preferredEmail: "", additionalEmailsText: "", phoneNumber: "", address: "", notes: "")
        XCTAssertEqual(operation.status, "parked")
        XCTAssertEqual(operation.retryCount, 8)
    }

    func test_stageSaveCommitsDurableCommandWithoutRemoteDelivery() async throws {
        let (vm, context) = try makeVisit()
        for answer in vm.missingRequiredChecklistAnswers { vm.updateChecklistAnswer(answer, value: .text("Scope")) }
        vm.readStageSnapshot = { [self] _ in snapshot() }
        await vm.prepareStageSnapshot()
        let result = await vm.saveVisit(movingLeadTo: .qualifying)
        XCTAssertEqual(result, .committedStageUpdatePending)
        XCTAssertEqual(vm.currentOpportunity?.stage, .newLead)
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let stage = try XCTUnwrap(operations.first { $0.operationType == SiteVisitSyncOperation.stageOperationType })
        let completion = try XCTUnwrap(operations.first { $0.operationType == SiteVisitSyncOperation.completionOperationType })
        XCTAssertEqual(stage.dependsOnId, completion.id.uuidString.lowercased())
        let reopened = ModelContext(try XCTUnwrap(containers.last))
        let saved = try XCTUnwrap(reopened.fetch(FetchDescriptor<SyncOperation>()).first { $0.id == stage.id })
        let envelope = try JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: saved.payload)
        XCTAssertEqual(envelope.stageCommand?.snapshot?.stageRevision, "opaque-fixture-revision")
        XCTAssertEqual(envelope.stageCommand?.actorId, actor)
        XCTAssertEqual(envelope.stageCommand?.companyId, company)
        XCTAssertFalse(SiteVisitOutboundSync.isReady(stage, in: operations))
        for op in operations where op.id != stage.id { op.status = "completed" }
        XCTAssertTrue(SiteVisitOutboundSync.isReady(stage, in: operations))
    }

    func test_offlineSnapshotFailureStillSavesVisitAndParksOriginalStageIntent() async throws {
        let (vm, context) = try makeVisit()
        for answer in vm.missingRequiredChecklistAnswers { vm.updateChecklistAnswer(answer, value: .text("Scope")) }
        vm.readStageSnapshot = { _ in throw URLError(.notConnectedToInternet) }
        await vm.prepareStageSnapshot()
        let result = await vm.saveVisit(movingLeadTo: .qualifying)
        XCTAssertEqual(result, .committedStageUpdateFailed)
        XCTAssertEqual(vm.siteVisit?.status, .completed)
        XCTAssertEqual(vm.currentOpportunity?.stage, .newLead)
        let stage = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first { $0.operationType == SiteVisitSyncOperation.stageOperationType })
        XCTAssertEqual(stage.status, "parked")
        let envelope = try JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: stage.payload)
        XCTAssertNil(envelope.stageCommand?.snapshot)
    }

    func test_freshQuotedSnapshotDefaultsToQuotedDespiteStaleLocalNewLead() async throws {
        let (vm, context) = try makeVisit()
        for answer in vm.missingRequiredChecklistAnswers { vm.updateChecklistAnswer(answer, value: .text("Scope")) }
        vm.readStageSnapshot = { [self] _ in snapshot(stage: "quoted") }
        await vm.prepareStageSnapshot()
        let decision = try XCTUnwrap(vm.makeStageDecision())
        XCTAssertEqual(decision.currentStage, .quoted)
        XCTAssertEqual(decision.targetStage, .quoted)
        let result = await vm.saveVisit(stageDecision: decision)
        XCTAssertEqual(result, .committed)
        XCTAssertEqual(vm.currentOpportunity?.stage, .newLead, "Review does not mutate cached lead state")
        XCTAssertFalse(try context.fetch(FetchDescriptor<SyncOperation>()).contains {
            $0.operationType == SiteVisitSyncOperation.stageOperationType
        })
    }

    func test_explicitTargetEqualToStaleLocalStageStillQueuesAgainstFreshSnapshot() async throws {
        let (vm, context) = try makeVisit()
        vm.currentOpportunity?.stage = .qualifying
        for answer in vm.missingRequiredChecklistAnswers { vm.updateChecklistAnswer(answer, value: .text("Scope")) }
        vm.readStageSnapshot = { [self] _ in snapshot(stage: "quoted") }
        await vm.prepareStageSnapshot()
        var decision = try XCTUnwrap(vm.makeStageDecision())
        decision.targetStage = .qualifying
        let result = await vm.saveVisit(stageDecision: decision)
        XCTAssertEqual(result, .committedStageUpdatePending)
        let command = try stageCommand(in: context)
        XCTAssertEqual(command.targetStage, "qualifying")
        XCTAssertEqual(command.snapshot?.stage, "quoted")
    }

    func test_lateSnapshotDoesNotAuthorizeSelectionMadeWithoutToken() async throws {
        let (vm, context) = try makeVisit()
        for answer in vm.missingRequiredChecklistAnswers { vm.updateChecklistAnswer(answer, value: .text("Scope")) }
        let decision = try XCTUnwrap(vm.makeStageDecision())
        XCTAssertNil(decision.snapshot)
        vm.readStageSnapshot = { [self] _ in snapshot(stage: "quoted") }
        await vm.prepareStageSnapshot()
        XCTAssertEqual(vm.makeStageDecision()?.targetStage, .quoted)
        let result = await vm.saveVisit(stageDecision: decision)
        XCTAssertEqual(result, .committedStageUpdateFailed)
        let command = try stageCommand(in: context)
        XCTAssertEqual(command.targetStage, "qualifying")
        XCTAssertNil(command.snapshot, "Late response must not silently authorize an older selection")
    }

    func test_laterSnapshotDoesNotRebaseExistingReviewDecision() async throws {
        let (vm, context) = try makeVisit()
        for answer in vm.missingRequiredChecklistAnswers { vm.updateChecklistAnswer(answer, value: .text("Scope")) }
        vm.readStageSnapshot = { [self] _ in snapshot(stage: "new_lead", revision: "original") }
        await vm.prepareStageSnapshot()
        let decision = try XCTUnwrap(vm.makeStageDecision())
        vm.readStageSnapshot = { [self] _ in snapshot(stage: "quoted", revision: "later") }
        await vm.prepareStageSnapshot()
        let result = await vm.saveVisit(stageDecision: decision)
        XCTAssertEqual(result, .committedStageUpdatePending)
        let command = try stageCommand(in: context)
        XCTAssertEqual(command.snapshot?.stageRevision, "original")
        XCTAssertEqual(command.snapshot?.stage, "new_lead")
        XCTAssertEqual(command.targetStage, "qualifying")
    }

    func test_stageCommandEncodingFailureRollsBackCompletion() async throws {
        let (vm, context) = try makeVisit(rejectStageEncoding: true)
        for answer in vm.missingRequiredChecklistAnswers { vm.updateChecklistAnswer(answer, value: .text("Scope")) }
        vm.readStageSnapshot = { [self] _ in snapshot() }
        await vm.prepareStageSnapshot()
        let result = await vm.saveVisit(movingLeadTo: .qualifying)
        XCTAssertEqual(result, .notCommitted(.persistence))
        XCTAssertNil(vm.siteVisit?.completedAt)
        XCTAssertFalse(try context.fetch(FetchDescriptor<SyncOperation>()).contains {
            [SiteVisitSyncOperation.stageOperationType, SiteVisitSyncOperation.completionOperationType].contains($0.operationType)
        })
    }

    func test_stagedPhotoReplayUsesStableArtifactIdentityAndRejectsForeignOwner() throws {
        let (vm, context) = try makeVisit()
        let owner = try XCTUnwrap(vm.captureOwner)
        let item = StagedCaptureItem(id: "44444444-4444-4444-4444-444444444444",
            localURL: "local://project_images/synthetic.jpg", originalLocalURL: "local://project_images/synthetic.original",
            capturedAt: Date(timeIntervalSince1970: 100), pixelWidth: 40, pixelHeight: 20)
        let batch = StagedCaptureBatch(id: "55555555-5555-5555-5555-555555555555", owner: owner, items: [item])
        XCTAssertTrue(vm.attachStagedPhotos(batch))
        XCTAssertTrue(vm.attachStagedPhotos(batch), "reopen between commit and journal acknowledgement must not duplicate")
        XCTAssertEqual(try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).filter { $0.id == item.id }.count, 1)
        let foreign = StagedCaptureBatch(id: batch.id,
            owner: StagedCaptureOwner(companyID: company, userID: "different-user", contextID: owner.contextID), items: [item])
        XCTAssertFalse(vm.attachStagedPhotos(foreign))
    }

    func test_failedStagedPhotoSaveKeepsBatchReplayable() throws {
        let gate = FailureGate()
        let (vm, context) = try makeVisit(gate: gate)
        let item = StagedCaptureItem(id: UUID().uuidString.lowercased(), localURL: "local://project_images/synthetic.jpg",
            originalLocalURL: "local://project_images/synthetic.original", capturedAt: Date(), pixelWidth: 1, pixelHeight: 1)
        let batch = StagedCaptureBatch(id: UUID().uuidString.lowercased(), owner: try XCTUnwrap(vm.captureOwner), items: [item])
        gate.fail = true
        XCTAssertFalse(vm.attachStagedPhotos(batch))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).isEmpty)
        gate.fail = false
        XCTAssertTrue(vm.attachStagedPhotos(batch))
    }

    func test_explicitMarkupSaveAtSameURLRevivesOnlyThatMediaRevision() throws {
        let (vm, context) = try makeVisit()
        let url = "local://project_images/synthetic-markup.jpg"
        let item = StagedCaptureItem(id: UUID().uuidString.lowercased(), localURL: url,
            originalLocalURL: url, capturedAt: Date(), pixelWidth: 1, pixelHeight: 1)
        let batch = StagedCaptureBatch(id: UUID().uuidString.lowercased(), owner: try XCTUnwrap(vm.captureOwner), items: [item])
        XCTAssertTrue(vm.attachStagedPhotos(batch))
        let artifact = try XCTUnwrap(vm.artifacts.first { $0.id == item.id })
        XCTAssertTrue(vm.saveMarkup(artifact, renderedAssetURL: url))
        let media = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first {
            $0.entityId == artifact.id && $0.operationType == SiteVisitSyncOperation.mediaOperationType
        })
        media.status = "declined"; media.retryCount = 5; try context.save()
        XCTAssertTrue(vm.saveMarkup(artifact, renderedAssetURL: url))
        let fresh = ModelContext(context.container)
        let mediaId = media.id
        let persisted = try XCTUnwrap(fresh.fetch(FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.id == mediaId })).first)
        XCTAssertEqual(persisted.status, "pending")
        XCTAssertEqual(persisted.retryCount, 0)
    }

    private func stageCommand(in context: ModelContext) throws -> SiteVisitStageCommand {
        let stage = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first {
            $0.operationType == SiteVisitSyncOperation.stageOperationType
        })
        return try XCTUnwrap(JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: stage.payload).stageCommand)
    }

    private func snapshot(stage: String = "new_lead", revision: String = "opaque-fixture-revision") -> SiteVisitStageSnapshot {
        SiteVisitStageSnapshot(contractVersion: 1, capability: "site_visit_stage_command_v1", actorId: actor,
            companyId: company, opportunityId: lead, stage: stage, stageRevision: revision,
            stageEnteredAt: "2026-09-06T12:34:56.123456Z", canMove: true)
    }

    private final class FailureGate { var fail = false }
    private func makeVisit(gate: FailureGate = FailureGate(), rejectStageEncoding: Bool = false,
                           prepareShared: (ModelContext) throws -> Void = { _ in }) throws -> (SiteVisitCaptureViewModel, ModelContext) {
        let schema = Schema([SiteVisit.self, SiteVisitType.self, SiteVisitCaptureArtifact.self, SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self, SyncOperation.self, Opportunity.self, Client.self, SubClient.self, DeckDesign.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        containers.append(container)
        let context = container.mainContext
        let opportunity = Opportunity(id: lead, companyId: company, contactName: "Synthetic customer", stage: .newLead)
        context.insert(opportunity); try context.save()
        try prepareShared(context)
        let coordinator = SiteVisitPersistenceCoordinator(modelContext: context, companyId: company,
            encodeOperation: { payload in
                if rejectStageEncoding && payload.stageCommand != nil { throw URLError(.cannotWriteToFile) }
                return try JSONEncoder().encode(payload)
            }, validateCommit: { if gate.fail { throw URLError(.cannotWriteToFile) } })
        let vm = SiteVisitCaptureViewModel(opportunity: opportunity, companyId: company, userId: actor,
            modelContext: context, persistenceCoordinator: coordinator)
        vm.loadOrCreateVisit()
        return (vm, context)
    }
}
