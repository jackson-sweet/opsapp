//
//  SiteVisitOutboundSyncTests.swift
//  OPSTests
//
//  Dependency, coalescing, routing, and failure-disposition guarantees for
//  durable phone-authored site-visit operations.
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitOutboundSyncTests: XCTestCase {
    private var liveContainers: [ModelContainer] = []

    private let companyId = "11111111-1111-4111-8111-111111111111"
    private let userId = "22222222-2222-4222-8222-222222222222"
    private let visitId = "33333333-3333-4333-8333-333333333333"
    private let artifactId = "44444444-4444-4444-8444-444444444444"
    private let draftId = "55555555-5555-4555-8555-555555555555"
    private let answerId = "66666666-6666-4666-8666-666666666666"
    private let sessionUserId = "77777777-7777-4777-8777-777777777777"

    override func tearDown() {
        liveContainers.removeAll()
        super.tearDown()
    }

    func test_readySetAdvancesParentChildMediaAndCompletionInOrder() throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        let artifact = makeArtifact(localURL: "local://project_images/photo.jpg")
        context.insert(visit)
        context.insert(artifact)

        let parent = try insert(SiteVisitSyncOperation.parent(visit), in: context)
        let child = try insert(
            SiteVisitSyncOperation.artifact(artifact),
            dependsOn: parent,
            in: context
        )
        let media = try insert(
            SiteVisitSyncOperation.media(artifact),
            dependsOn: child,
            in: context
        )
        let completion = try insert(
            SiteVisitSyncOperation.completion(visit),
            dependsOn: media,
            in: context
        )

        XCTAssertEqual(
            SiteVisitOutboundSync.readyPendingOperationIds(
                in: try allOperations(context)
            ),
            [parent.id]
        )

        parent.status = "completed"
        XCTAssertEqual(
            SiteVisitOutboundSync.readyPendingOperationIds(
                in: try allOperations(context)
            ),
            [child.id]
        )

        child.status = "completed"
        XCTAssertEqual(
            SiteVisitOutboundSync.readyPendingOperationIds(
                in: try allOperations(context)
            ),
            [media.id]
        )

        media.status = "completed"
        XCTAssertEqual(
            SiteVisitOutboundSync.readyPendingOperationIds(
                in: try allOperations(context)
            ),
            [completion.id]
        )
    }

    func test_completionWaitsForChildAddedAfterCompletionWasQueued() throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        let artifact = makeArtifact(localURL: nil)
        context.insert(visit)
        context.insert(artifact)

        let parent = try insert(SiteVisitSyncOperation.parent(visit), in: context)
        parent.status = "completed"
        let completion = try insert(
            SiteVisitSyncOperation.completion(visit),
            dependsOn: parent,
            in: context
        )
        let lateChild = try insert(
            SiteVisitSyncOperation.artifact(artifact),
            in: context
        )

        let before = SiteVisitOutboundSync.readyPendingOperationIds(
            in: try allOperations(context)
        )
        XCTAssertEqual(before, [lateChild.id])
        XCTAssertFalse(before.contains(completion.id))

        lateChild.status = "completed"
        XCTAssertEqual(
            SiteVisitOutboundSync.readyPendingOperationIds(
                in: try allOperations(context)
            ),
            [completion.id]
        )
    }

    func test_completionIgnoresChildrenThatDependOnTheCompletionItself() throws {
        // Device wedge 2026-08-17 (visit 2091c595): children queued after the
        // completion carry dependsOnId → completion, directly or transitively.
        // The barrier counted them as unresolved same-visit work while their
        // dependency check blocked them on the completion — a mutual block in
        // which nothing ever attempted and PENDING WORK read 11 forever. A
        // candidate sequenced AFTER the completion by its own dependency chain
        // can never settle first, so it must not hold the completion's barrier.
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        let artifact = makeArtifact(localURL: nil)
        let draft = makeDraft(author: userId)
        context.insert(visit)
        context.insert(artifact)
        context.insert(draft)

        let completion = try insert(
            SiteVisitSyncOperation.completion(visit),
            in: context
        )
        let child = try insert(
            SiteVisitSyncOperation.artifact(artifact),
            dependsOn: completion,
            in: context
        )
        let grandchild = try insert(
            SiteVisitSyncOperation.identityDraft(draft),
            dependsOn: child,
            in: context
        )

        let ready = SiteVisitOutboundSync.readyPendingOperationIds(
            in: try allOperations(context)
        )
        XCTAssertEqual(ready, [completion.id])
        XCTAssertFalse(ready.contains(child.id))
        XCTAssertFalse(ready.contains(grandchild.id))
    }

    func test_completionStillWaitsForIndependentChildWhenAnotherDependsOnIt() throws {
        // Mixed chain: one child waits on the completion, another is free to
        // run first. The free child still holds the barrier — only the ones
        // sequenced after the completion are excused from it.
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        let artifact = makeArtifact(localURL: nil)
        let answer = makeAnswer(author: userId)
        context.insert(visit)
        context.insert(artifact)
        context.insert(answer)

        let completion = try insert(
            SiteVisitSyncOperation.completion(visit),
            in: context
        )
        _ = try insert(
            SiteVisitSyncOperation.artifact(artifact),
            dependsOn: completion,
            in: context
        )
        let independent = try insert(
            SiteVisitSyncOperation.checklistAnswer(answer),
            in: context
        )

        let ready = SiteVisitOutboundSync.readyPendingOperationIds(
            in: try allOperations(context)
        )
        XCTAssertEqual(ready, [independent.id])
        XCTAssertFalse(ready.contains(completion.id))
    }

    func test_corruptDependencyCycleAmongChildrenTerminates() throws {
        // Two children pointing at each other (corrupt store state) must not
        // hang the transitive walk. Neither reaches the completion, so both
        // still hold the barrier; the assertion here is termination + blocking.
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        let artifact = makeArtifact(localURL: nil)
        let answer = makeAnswer(author: userId)
        context.insert(visit)
        context.insert(artifact)
        context.insert(answer)

        let completion = try insert(
            SiteVisitSyncOperation.completion(visit),
            in: context
        )
        let childA = try insert(
            SiteVisitSyncOperation.artifact(artifact),
            in: context
        )
        let childB = try insert(
            SiteVisitSyncOperation.checklistAnswer(answer),
            dependsOn: childA,
            in: context
        )
        childA.dependsOnId = childB.id.uuidString.lowercased()

        let ready = SiteVisitOutboundSync.readyPendingOperationIds(
            in: try allOperations(context)
        )
        XCTAssertFalse(ready.contains(completion.id))
    }

    func test_transientFailureOrParkedDependencyPreventsDownstreamDrain() throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        let artifact = makeArtifact(localURL: nil)
        context.insert(visit)
        context.insert(artifact)

        let parent = try insert(SiteVisitSyncOperation.parent(visit), in: context)
        let child = try insert(
            SiteVisitSyncOperation.artifact(artifact),
            dependsOn: parent,
            in: context
        )
        parent.status = "failed"
        XCTAssertTrue(
            SiteVisitOutboundSync.readyPendingOperationIds(
                in: try allOperations(context)
            ).isEmpty
        )

        parent.status = "parked"
        XCTAssertTrue(
            SiteVisitOutboundSync.readyPendingOperationIds(
                in: try allOperations(context)
            ).isEmpty
        )
        XCTAssertEqual(child.status, "pending")
    }

    func test_coalescingKeepsCurrentSnapshotWriteMediaAndCompletionSeparate() throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        let artifact = makeArtifact(localURL: "local://project_images/photo.jpg")
        context.insert(visit)
        context.insert(artifact)

        let create = try insert(SiteVisitSyncOperation.parent(visit), in: context)
        visit.lastSyncedAt = Date()
        let update = try insert(SiteVisitSyncOperation.parent(visit), in: context)
        let media = try insert(SiteVisitSyncOperation.media(artifact), in: context)
        let completion = try insert(SiteVisitSyncOperation.completion(visit), in: context)

        let result = SiteVisitOutboundSync.coalesceOperations(
            [create, update, media, completion]
        )

        XCTAssertEqual(Set(result.map(\.id)), [create.id, media.id, completion.id])
        XCTAssertEqual(create.operationType, "create")
        XCTAssertEqual(update.status, "completed")
        XCTAssertEqual(completion.operationType, SiteVisitSyncOperation.completionOperationType)
    }

    func test_parentUpsertUsesCurrentModelSnapshotAndClearsDirtyFlag() async throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        visit.notes = "Newest phone note"
        context.insert(visit)
        let operation = try insert(SiteVisitSyncOperation.parent(visit), in: context)
        operation.status = "inProgress"
        let remote = RecordingSiteVisitWriter(
            visitDTO: try makeVisitDTO(status: .inProgress)
        )
        let sync = SiteVisitOutboundSync(
            repositoryFactory: { _ in remote },
            mediaManager: SiteVisitMediaSyncManager(
                uploader: { _, _, _, _, _ in XCTFail("No media expected"); return "" },
                loader: { _ in throw URLError(.fileDoesNotExist) }
            )
        )

        let handled = try await sync.executeIfHandled(
            operation: operation,
            context: context,
            activeCompanyId: companyId
        )
        XCTAssertTrue(handled)

        XCTAssertEqual(remote.calls, [.upsertVisit(notes: "Newest phone note")])
        XCTAssertFalse(visit.needsSync)
        XCTAssertNotNil(visit.lastSyncedAt)
    }

    func test_completionRetryUsesPersistedPayloadAndStoresActivityId() async throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        visit.notes = "Persisted completion"
        visit.status = .completed
        context.insert(visit)
        let operation = try insert(SiteVisitSyncOperation.completion(visit), in: context)
        operation.status = "inProgress"

        visit.notes = "Edited after queueing"
        let remote = RecordingSiteVisitWriter(
            visitDTO: try makeVisitDTO(status: .completed),
            activityId: artifactId
        )
        let sync = SiteVisitOutboundSync(
            repositoryFactory: { _ in remote },
            mediaManager: SiteVisitMediaSyncManager(
                uploader: { _, _, _, _, _ in "" },
                loader: { _ in throw URLError(.fileDoesNotExist) }
            )
        )

        _ = try await sync.executeIfHandled(
            operation: operation,
            context: context,
            activeCompanyId: companyId
        )

        XCTAssertEqual(remote.calls, [.complete(notes: "Persisted completion")])
        XCTAssertEqual(visit.loggedActivityId, artifactId)
    }

    func test_repositoryErrorsMapToDurableQueueDisposition() {
        XCTAssertEqual(
            SyncErrorClassifier.disposition(
                for: SiteVisitRepositoryError.authorization("RLS denied")
            ),
            .auth
        )
        XCTAssertEqual(
            SyncErrorClassifier.disposition(
                for: SiteVisitRepositoryError.dependency("FK missing")
            ),
            .permanent
        )
        XCTAssertEqual(
            SyncErrorClassifier.disposition(
                for: SiteVisitRepositoryError.schemaCapability("RPC missing")
            ),
            .permanent
        )
        XCTAssertEqual(
            SyncErrorClassifier.disposition(
                for: SiteVisitRepositoryError.transport("offline")
            ),
            .transient
        )
    }

    // MARK: - Legacy authorless rows (bug 70db7ed6)
    //
    // The V19→V20 lightweight migration could only default the new `createdBy` to
    // nil, so every draft/artifact/answer captured by a pre-V20 build is authorless
    // forever. Its payload build throws before any network call, the failure was
    // classified transient, and the launch sweep revived it every single launch —
    // while the unresolved child blocked the visit's completion notes from sending.

    func test_legacyDraftWithoutAuthorHealsFromParentVisitAndSends() async throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        let draft = makeDraft(author: nil)
        context.insert(visit)
        context.insert(draft)
        let operation = try insert(SiteVisitSyncOperation.identityDraft(draft), in: context)
        operation.status = "inProgress"
        let remote = RecordingSiteVisitWriter(visitDTO: try makeVisitDTO(status: .inProgress))

        let handled = try await makeSync(remote).executeIfHandled(
            operation: operation,
            context: context,
            activeCompanyId: companyId
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(remote.calls, [.upsertIdentityDraft(createdBy: userId)])
        XCTAssertEqual(draft.createdBy, userId, "the heal must survive relaunch")
        XCTAssertFalse(draft.needsSync)
    }

    func test_authorlessDraftAndVisitFallBackToTheSessionUser() async throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit(author: nil)
        let draft = makeDraft(author: nil)
        context.insert(visit)
        context.insert(draft)
        let operation = try insert(SiteVisitSyncOperation.identityDraft(draft), in: context)
        operation.status = "inProgress"
        let remote = RecordingSiteVisitWriter(visitDTO: try makeVisitDTO(status: .inProgress))

        _ = try await makeSync(remote, sessionUserId: sessionUserId).executeIfHandled(
            operation: operation,
            context: context,
            activeCompanyId: companyId
        )

        XCTAssertEqual(remote.calls, [.upsertIdentityDraft(createdBy: sessionUserId)])
        XCTAssertEqual(draft.createdBy, sessionUserId)
    }

    /// The V19 `SiteVisit` had no `createdBy` either, so a legacy PARENT wedges the
    /// same way — and a stuck parent blocks every child behind it.
    func test_legacyVisitWithoutAuthorHealsFromTheSessionUser() async throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit(author: nil)
        visit.notes = "Legacy visit"
        context.insert(visit)
        let operation = try insert(SiteVisitSyncOperation.parent(visit), in: context)
        operation.status = "inProgress"
        let remote = RecordingSiteVisitWriter(visitDTO: try makeVisitDTO(status: .inProgress))

        _ = try await makeSync(remote, sessionUserId: sessionUserId).executeIfHandled(
            operation: operation,
            context: context,
            activeCompanyId: companyId
        )

        XCTAssertEqual(remote.calls, [.upsertVisit(notes: "Legacy visit")])
        XCTAssertEqual(visit.createdBy, sessionUserId)
    }

    func test_legacyArtifactWithoutAuthorHealsFromParentVisit() async throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        let artifact = makeArtifact(localURL: nil, author: nil)
        context.insert(visit)
        context.insert(artifact)
        let operation = try insert(SiteVisitSyncOperation.artifact(artifact), in: context)
        operation.status = "inProgress"
        let remote = RecordingSiteVisitWriter(visitDTO: try makeVisitDTO(status: .inProgress))

        _ = try await makeSync(remote).executeIfHandled(
            operation: operation,
            context: context,
            activeCompanyId: companyId
        )

        XCTAssertEqual(remote.calls, [.upsertArtifact(createdBy: userId)])
        XCTAssertEqual(artifact.createdBy, userId)
    }

    func test_legacyChecklistAnswerWithoutAuthorHealsFromParentVisit() async throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        let answer = makeAnswer(author: nil)
        context.insert(visit)
        context.insert(answer)
        let operation = try insert(SiteVisitSyncOperation.checklistAnswer(answer), in: context)
        operation.status = "inProgress"
        let remote = RecordingSiteVisitWriter(visitDTO: try makeVisitDTO(status: .inProgress))

        _ = try await makeSync(remote).executeIfHandled(
            operation: operation,
            context: context,
            activeCompanyId: companyId
        )

        XCTAssertEqual(remote.calls, [.upsertChecklistAnswer(createdBy: userId)])
        XCTAssertEqual(answer.createdBy, userId)
    }

    /// A payload that never reached the server must PARK, not retry: an identical
    /// rebuild fails identically, and `failed` ops are revived on every launch — so
    /// classifying this transient is precisely what made bug 70db7ed6 immortal.
    func test_payloadBuildFailureParksWithoutConsumingTheRetryBudget() throws {
        XCTAssertEqual(
            SyncErrorClassifier.disposition(
                for: SiteVisitPayloadError.missingRequiredField("created_by")
            ),
            .permanent
        )
        XCTAssertEqual(
            SyncErrorClassifier.disposition(
                for: SiteVisitPayloadError.invalidUUID(field: "id", value: "nope")
            ),
            .permanent
        )

        let context = try makeContainer().mainContext
        let visit = makeVisit()
        context.insert(visit)
        let operation = try insert(SiteVisitSyncOperation.parent(visit), in: context)

        let outcome = SyncOperationFailurePolicy.apply(
            SyncErrorClassifier.disposition(
                for: SiteVisitPayloadError.missingRequiredField("created_by")
            ),
            to: operation,
            errorDescription: "payload"
        )

        XCTAssertEqual(outcome, .parked)
        XCTAssertEqual(operation.status, "parked")
        XCTAssertEqual(operation.retryCount, 0)
    }

    func test_draftWithNoResolvableAuthorStillThrowsAndIsLeftUntouched() async throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit(author: nil)
        let draft = makeDraft(author: nil)
        context.insert(visit)
        context.insert(draft)
        let operation = try insert(SiteVisitSyncOperation.identityDraft(draft), in: context)
        operation.status = "inProgress"
        let updatedAt = draft.updatedAt
        let remote = RecordingSiteVisitWriter(visitDTO: try makeVisitDTO(status: .inProgress))

        do {
            _ = try await makeSync(remote).executeIfHandled(
                operation: operation,
                context: context,
                activeCompanyId: companyId
            )
            XCTFail("Expected the payload build to reject an authorless row")
        } catch let error as SiteVisitPayloadError {
            XCTAssertEqual(error, .missingRequiredField("created_by"))
        }

        XCTAssertTrue(remote.calls.isEmpty)
        XCTAssertNil(draft.createdBy)
        XCTAssertEqual(draft.updatedAt, updatedAt)
    }

    /// The heal writes `created_by` and nothing else — re-dirtying an otherwise
    /// clean row would enqueue a spurious write. The remote throws so the success
    /// path never runs: whatever the row carries afterwards is the heal's alone.
    func test_authorHealPersistsWithoutRedirtyingTheRow() async throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        let draft = makeDraft(author: nil)
        draft.needsSync = false
        context.insert(visit)
        context.insert(draft)
        let operation = try insert(SiteVisitSyncOperation.identityDraft(draft), in: context)
        operation.status = "inProgress"
        let updatedAt = draft.updatedAt
        let remote = RecordingSiteVisitWriter(
            visitDTO: try makeVisitDTO(status: .inProgress),
            upsertError: SiteVisitRepositoryError.transport("offline")
        )

        do {
            _ = try await makeSync(remote).executeIfHandled(
                operation: operation,
                context: context,
                activeCompanyId: companyId
            )
            XCTFail("Expected the transport failure to propagate")
        } catch let error as SiteVisitRepositoryError {
            XCTAssertEqual(error, .transport("offline"))
        }

        XCTAssertEqual(draft.createdBy, userId)
        XCTAssertEqual(draft.updatedAt, updatedAt, "the heal must not bump updatedAt")
        XCTAssertFalse(draft.needsSync, "the heal must not re-dirty the row")
        XCTAssertNil(draft.lastSyncedAt)
    }

    func test_healedDraftUnblocksTheVisitCompletionOperation() async throws {
        let context = try makeContainer().mainContext
        let visit = makeVisit()
        let draft = makeDraft(author: nil)
        context.insert(visit)
        context.insert(draft)
        let draftOperation = try insert(
            SiteVisitSyncOperation.identityDraft(draft),
            in: context
        )
        let completion = try insert(SiteVisitSyncOperation.completion(visit), in: context)

        XCTAssertFalse(
            SiteVisitOutboundSync.readyPendingOperationIds(in: try allOperations(context))
                .contains(completion.id),
            "an unresolved child is a live barrier for the completion"
        )

        draftOperation.status = "inProgress"
        let remote = RecordingSiteVisitWriter(visitDTO: try makeVisitDTO(status: .inProgress))
        _ = try await makeSync(remote).executeIfHandled(
            operation: draftOperation,
            context: context,
            activeCompanyId: companyId
        )
        draftOperation.status = "completed"

        XCTAssertTrue(
            SiteVisitOutboundSync.readyPendingOperationIds(in: try allOperations(context))
                .contains(completion.id),
            "the operator's completion notes must send once the draft lands"
        )
    }

    private func makeVisit() -> SiteVisit {
        makeVisit(author: userId)
    }

    private func makeVisit(author: String?) -> SiteVisit {
        SiteVisit(
            id: visitId,
            companyId: companyId,
            status: .inProgress,
            scheduledAt: Date(timeIntervalSince1970: 1_700_000_000),
            assigneeIds: [userId],
            createdBy: author,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeDraft(author: String?) -> SiteVisitIdentityDraft {
        SiteVisitIdentityDraft(
            id: draftId,
            siteVisitId: visitId,
            companyId: companyId,
            clientName: "Ridge Line Exteriors",
            createdBy: author,
            createdAt: Date(timeIntervalSince1970: 1_700_000_002)
        )
    }

    private func makeAnswer(author: String?) -> SiteVisitChecklistAnswer {
        SiteVisitChecklistAnswer(
            id: answerId,
            siteVisitId: visitId,
            companyId: companyId,
            opportunityId: nil,
            siteVisitTypeId: nil,
            fieldId: "gate_code",
            label: "Gate code",
            kind: .shortText,
            required: false,
            sortOrder: 0,
            createdBy: author,
            createdAt: Date(timeIntervalSince1970: 1_700_000_003)
        )
    }

    /// The session user is injected rather than read from `UserDefaults.standard`
    /// so a stale `currentUserId` left in the test host cannot silently satisfy —
    /// or silently break — a fallback assertion.
    private func makeSync(
        _ remote: SiteVisitRemoteWriting,
        sessionUserId: String? = nil
    ) -> SiteVisitOutboundSync {
        SiteVisitOutboundSync(
            repositoryFactory: { _ in remote },
            mediaManager: SiteVisitMediaSyncManager(
                uploader: { _, _, _, _, _ in XCTFail("No media expected"); return "" },
                loader: { _ in throw URLError(.fileDoesNotExist) }
            ),
            sessionUserId: { sessionUserId }
        )
    }

    private func makeArtifact(localURL: String?) -> SiteVisitCaptureArtifact {
        makeArtifact(localURL: localURL, author: userId)
    }

    private func makeArtifact(
        localURL: String?,
        author: String?
    ) -> SiteVisitCaptureArtifact {
        SiteVisitCaptureArtifact(
            id: artifactId,
            siteVisitId: visitId,
            companyId: companyId,
            kind: .photo,
            source: .camera,
            localAssetURL: localURL,
            createdBy: author,
            createdAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
    }

    private func insert(
        _ specification: SiteVisitSyncOperation.Specification,
        dependsOn dependency: SyncOperation? = nil,
        in context: ModelContext
    ) throws -> SyncOperation {
        let operation = SyncOperation(
            entityType: specification.entityType.rawValue,
            entityId: specification.entityId,
            operationType: specification.operationType,
            payload: try JSONEncoder().encode(specification.payload),
            changedFields: specification.changedFields,
            priority: specification.priority,
            dependsOnId: dependency?.id.uuidString.lowercased()
        )
        context.insert(operation)
        return operation
    }

    private func allOperations(_ context: ModelContext) throws -> [SyncOperation] {
        try context.fetch(FetchDescriptor<SyncOperation>())
    }

    private func makeVisitDTO(status: SiteVisitStatus) throws -> SiteVisitDTO {
        try JSONDecoder().decode(
            SiteVisitDTO.self,
            from: Data(
                """
                {
                  "id":"\(visitId)",
                  "company_id":"\(companyId)",
                  "scheduled_at":"2026-07-31T18:12:45Z",
                  "status":"\(status.rawValue)",
                  "created_by":"\(userId)",
                  "updated_at":"2026-07-31T18:13:45Z"
                }
                """.utf8
            )
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
            SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self,
            SyncOperation.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        liveContainers.append(container)
        return container
    }
}

private final class RecordingSiteVisitWriter: SiteVisitRemoteWriting {
    enum Call: Equatable {
        case upsertVisit(notes: String?)
        case upsertArtifact(createdBy: String)
        case upsertChecklistAnswer(createdBy: String)
        case upsertIdentityDraft(createdBy: String)
        case softDelete(SiteVisitRemoteTable, String)
        case complete(notes: String?)
    }

    var calls: [Call] = []
    let visitDTO: SiteVisitDTO
    let activityId: String?
    /// Thrown by every child upsert AFTER the call is recorded, so a test can tell
    /// what the payload-build boundary wrote apart from what the success path wrote.
    let upsertError: Error?

    init(
        visitDTO: SiteVisitDTO,
        activityId: String? = nil,
        upsertError: Error? = nil
    ) {
        self.visitDTO = visitDTO
        self.activityId = activityId
        self.upsertError = upsertError
    }

    func upsertVisit(_ payload: CreateSiteVisitDTO) async throws -> SiteVisitDTO {
        calls.append(.upsertVisit(notes: payload.notes))
        return visitDTO
    }

    func upsertArtifact(
        _ payload: UpsertSiteVisitArtifactDTO
    ) async throws -> SiteVisitArtifactDTO {
        calls.append(.upsertArtifact(createdBy: payload.createdBy))
        if let upsertError { throw upsertError }
        return try Self.decode(
            """
            {
              "id":"\(payload.id)",
              "site_visit_id":"\(payload.siteVisitId)",
              "company_id":"\(payload.companyId)",
              "kind":"\(payload.kind.rawValue)",
              "source":"\(payload.source.rawValue)",
              "captured_at":"2026-07-31T18:12:45Z",
              "created_by":"\(payload.createdBy)",
              "created_at":"2026-07-31T18:12:45Z",
              "updated_at":"2026-07-31T18:13:45Z"
            }
            """
        )
    }

    func upsertChecklistAnswer(
        _ payload: UpsertSiteVisitChecklistAnswerDTO
    ) async throws -> SiteVisitChecklistAnswerDTO {
        calls.append(.upsertChecklistAnswer(createdBy: payload.createdBy))
        if let upsertError { throw upsertError }
        return try Self.decode(
            """
            {
              "id":"\(payload.id)",
              "site_visit_id":"\(payload.siteVisitId)",
              "company_id":"\(payload.companyId)",
              "field_id":"\(payload.fieldId)",
              "label":"\(payload.label)",
              "kind":"\(payload.kind.rawValue)",
              "created_by":"\(payload.createdBy)",
              "created_at":"2026-07-31T18:12:45Z",
              "updated_at":"2026-07-31T18:13:45Z"
            }
            """
        )
    }

    func upsertIdentityDraft(
        _ payload: UpsertSiteVisitIdentityDraftDTO
    ) async throws -> SiteVisitIdentityDraftDTO {
        calls.append(.upsertIdentityDraft(createdBy: payload.createdBy))
        if let upsertError { throw upsertError }
        return try Self.decode(
            """
            {
              "id":"\(payload.id)",
              "site_visit_id":"\(payload.siteVisitId)",
              "company_id":"\(payload.companyId)",
              "client_name":"\(payload.clientName)",
              "created_by":"\(payload.createdBy)",
              "created_at":"2026-07-31T18:12:45Z",
              "updated_at":"2026-07-31T18:13:45Z"
            }
            """
        )
    }

    private static func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func softDelete(
        _ table: SiteVisitRemoteTable,
        id: String,
        at deletedAt: Date
    ) async throws {
        calls.append(.softDelete(table, id))
    }

    func completeSiteVisit(
        _ id: String,
        completion: SiteVisitCompletionPayload
    ) async throws -> SiteVisitCompletionResponseDTO {
        calls.append(.complete(notes: completion.notes))
        return try JSONDecoder().decode(
            SiteVisitCompletionResponseDTO.self,
            from: Data(
                """
                {
                  "visit": {
                    "id":"\(visitDTO.id)",
                    "company_id":"\(visitDTO.companyId)",
                    "scheduled_at":"2026-07-31T18:12:45Z",
                    "status":"completed",
                    "created_by":"\(visitDTO.createdBy)",
                    "updated_at":"2026-07-31T18:13:45Z"
                  },
                  "activity_id":\(activityId.map { "\"\($0)\"" } ?? "null")
                }
                """.utf8
            )
        )
    }
}
