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

    private func makeVisit() -> SiteVisit {
        SiteVisit(
            id: visitId,
            companyId: companyId,
            status: .inProgress,
            scheduledAt: Date(timeIntervalSince1970: 1_700_000_000),
            assigneeIds: [userId],
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeArtifact(localURL: String?) -> SiteVisitCaptureArtifact {
        SiteVisitCaptureArtifact(
            id: artifactId,
            siteVisitId: visitId,
            companyId: companyId,
            kind: .photo,
            source: .camera,
            localAssetURL: localURL,
            createdBy: userId,
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
        case upsertArtifact
        case upsertChecklistAnswer
        case upsertIdentityDraft
        case softDelete(SiteVisitRemoteTable, String)
        case complete(notes: String?)
    }

    var calls: [Call] = []
    let visitDTO: SiteVisitDTO
    let activityId: String?

    init(visitDTO: SiteVisitDTO, activityId: String? = nil) {
        self.visitDTO = visitDTO
        self.activityId = activityId
    }

    func upsertVisit(_ payload: CreateSiteVisitDTO) async throws -> SiteVisitDTO {
        calls.append(.upsertVisit(notes: payload.notes))
        return visitDTO
    }

    func upsertArtifact(
        _ payload: UpsertSiteVisitArtifactDTO
    ) async throws -> SiteVisitArtifactDTO {
        calls.append(.upsertArtifact)
        throw SiteVisitRepositoryError.transport("Unused fixture")
    }

    func upsertChecklistAnswer(
        _ payload: UpsertSiteVisitChecklistAnswerDTO
    ) async throws -> SiteVisitChecklistAnswerDTO {
        calls.append(.upsertChecklistAnswer)
        throw SiteVisitRepositoryError.transport("Unused fixture")
    }

    func upsertIdentityDraft(
        _ payload: UpsertSiteVisitIdentityDraftDTO
    ) async throws -> SiteVisitIdentityDraftDTO {
        calls.append(.upsertIdentityDraft)
        throw SiteVisitRepositoryError.transport("Unused fixture")
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
