//
//  SiteVisitDrainStressTests.swift
//  OPSTests
//
//  Bug 3eef6ad7 — fatal SwiftData "Duplicate registration attempt for object
//  with id … SiteVisitCaptureArtifact/p13" during the site-visit backlog drain.
//
//  Field repro: launch recovered 310 orphaned site-visit operations, the actor
//  drained them in passes (313 → 294 → 278 pending) while realtime INSERT echoes
//  of the very rows being pushed merged interleaved on the same context. Every
//  site-visit read in that path was a whole-table fetch + in-memory id filter, so
//  each push and each echo materialized every row in the table — hundreds of
//  times — interleaved with unique-id `context.transaction` saves.
//
//  This drives the real drain algorithm (`coalesceOperations` →
//  `readyPendingOperationIds` → `executeIfHandled` → `shouldContinueDrain`) over
//  a seeded backlog with the production operation-chain shape, interleaving a
//  realtime echo for every row as it completes. Deterministic throughout — no
//  wall-clock sleeps.
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitDrainStressTests: XCTestCase {

    private let companyId = "11111111-1111-4111-8111-111111111111"
    private let userId = "22222222-2222-4222-8222-222222222222"
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// Backlog size. The field crash drained ~310 recovered operations; 60
    /// visits × (parent + artifact + answer + draft) plus media follow-ups puts
    /// this in the same order of magnitude while staying a fast unit test.
    private let visitCount = 60

    private var liveContainers: [ModelContainer] = []

    override func tearDown() {
        liveContainers.removeAll()
        super.tearDown()
    }

    // MARK: - The drain

    func test_backlogDrainWithInterleavedEchoesNeverDuplicatesRegistration() async throws {
        let context = try makeContainer().mainContext
        try seedBacklog(in: context)
        try context.save()

        let seededVisits = try count(SiteVisit.self, in: context)
        let seededArtifacts = try count(SiteVisitCaptureArtifact.self, in: context)
        let seededAnswers = try count(SiteVisitChecklistAnswer.self, in: context)
        let seededDrafts = try count(SiteVisitIdentityDraft.self, in: context)
        XCTAssertEqual(seededVisits, visitCount)
        XCTAssertEqual(seededArtifacts, visitCount)

        let sync = makeSync()
        var passes = 0
        var ready = SiteVisitOutboundSync.readyPendingOperationIds(
            in: try allOperations(context)
        )
        XCTAssertFalse(ready.isEmpty, "Seeded backlog released no work")

        // Mirrors OutboundProcessor.processPendingOperations: passes until the
        // live dependency graph stops releasing new work.
        while !ready.isEmpty {
            passes += 1
            XCTAssertLessThan(passes, 40, "Drain failed to converge")

            let operations = try allOperations(context)
            let eligible = operations.filter { ready.contains($0.id) }
            for operation in SiteVisitOutboundSync.coalesceOperations(eligible) {
                guard operation.status == "pending" else { continue }
                // The claim gate the real engines apply before executing.
                operation.status = "inProgress"
                let handled = try await sync.executeIfHandled(
                    operation: operation,
                    context: context,
                    activeCompanyId: companyId
                )
                XCTAssertTrue(handled, "Site-visit op was not routed")
                operation.status = "completed"
                operation.completedAt = Date()

                // The realtime INSERT echo of the row that was just pushed,
                // merging on the same context mid-drain — the interleave that
                // desynced the context's registration map on device.
                try mergeEcho(for: operation, in: context)
            }
            try context.save()

            let readyAfter = SiteVisitOutboundSync.readyPendingOperationIds(
                in: try allOperations(context)
            )
            guard SiteVisitOutboundSync.shouldContinueDrain(
                readyBeforePass: ready,
                readyAfterPass: readyAfter
            ) else { break }
            ready = readyAfter
        }

        // Every operation settled.
        let remaining = try allOperations(context).filter { $0.status != "completed" }
        XCTAssertTrue(
            remaining.isEmpty,
            "Unsettled operations: \(remaining.map { "\($0.entityType)/\($0.operationType)" })"
        )
        XCTAssertGreaterThan(passes, 1, "Chained backlog should need multiple passes")

        // No duplicate rows: the echoes matched the rows the drain pushed.
        XCTAssertEqual(try count(SiteVisit.self, in: context), seededVisits)
        XCTAssertEqual(try count(SiteVisitCaptureArtifact.self, in: context), seededArtifacts)
        XCTAssertEqual(try count(SiteVisitChecklistAnswer.self, in: context), seededAnswers)
        XCTAssertEqual(try count(SiteVisitIdentityDraft.self, in: context), seededDrafts)

        // Everything the drain pushed is marked synced.
        for visit in try fetchAll(SiteVisit.self, in: context) {
            XCTAssertFalse(visit.needsSync, "Visit \(visit.id) still dirty after drain")
            XCTAssertNotNil(visit.lastSyncedAt)
        }
        for artifact in try fetchAll(SiteVisitCaptureArtifact.self, in: context) {
            XCTAssertFalse(artifact.needsSync, "Artifact \(artifact.id) still dirty")
            XCTAssertNotNil(artifact.lastSyncedAt)
        }

        // MARK: Redundant echo waves must not write

        // Wave A normalizes every row to the exact server snapshot.
        let snapshots = try echoSnapshots(in: context)
        let waveA = try applyEchoWave(snapshots, in: context)
        XCTAssertEqual(waveA.inserted, 0, "A settled echo must never insert")

        let beforeSecondWave = try rowFingerprints(in: context)

        // Wave B is byte-identical to wave A: a redundant realtime echo. It must
        // open no transaction and change nothing.
        let waveB = try applyEchoWave(snapshots, in: context)
        XCTAssertEqual(waveB.inserted, 0)
        XCTAssertEqual(waveB.updated, 0, "A redundant echo re-wrote rows")
        XCTAssertEqual(waveB.unchanged, snapshots.count)
        XCTAssertEqual(
            try rowFingerprints(in: context),
            beforeSecondWave,
            "A redundant echo moved updatedAt/lastSyncedAt"
        )
    }

    // MARK: - Echoes

    private struct EchoSnapshot {
        enum Kind {
            case visit(SiteVisitDTO)
            case artifact(SiteVisitArtifactDTO)
            case answer(SiteVisitChecklistAnswerDTO)
            case draft(SiteVisitIdentityDraftDTO)
        }
        let kind: Kind
    }

    private func applyEchoWave(
        _ snapshots: [EchoSnapshot],
        in context: ModelContext
    ) throws -> SiteVisitMergeReport {
        var total = SiteVisitMergeReport()
        for snapshot in snapshots {
            let report: SiteVisitMergeReport
            switch snapshot.kind {
            case .visit(let dto):
                report = try SiteVisitServerMerge.merge(
                    visit: dto, companyId: companyId, into: context
                )
            case .artifact(let dto):
                report = try SiteVisitServerMerge.merge(
                    artifact: dto, companyId: companyId, into: context
                )
            case .answer(let dto):
                report = try SiteVisitServerMerge.merge(
                    checklistAnswer: dto, companyId: companyId, into: context
                )
            case .draft(let dto):
                report = try SiteVisitServerMerge.merge(
                    identityDraft: dto, companyId: companyId, into: context
                )
            }
            total.inserted += report.inserted
            total.updated += report.updated
            total.unchanged += report.unchanged
        }
        return total
    }

    private func echoSnapshots(in context: ModelContext) throws -> [EchoSnapshot] {
        var snapshots: [EchoSnapshot] = []
        for visit in try fetchAll(SiteVisit.self, in: context) {
            snapshots.append(.init(kind: .visit(try visitDTO(from: visit))))
        }
        for artifact in try fetchAll(SiteVisitCaptureArtifact.self, in: context) {
            snapshots.append(.init(kind: .artifact(try artifactDTO(from: artifact))))
        }
        for answer in try fetchAll(SiteVisitChecklistAnswer.self, in: context) {
            snapshots.append(.init(kind: .answer(try answerDTO(from: answer))))
        }
        for draft in try fetchAll(SiteVisitIdentityDraft.self, in: context) {
            snapshots.append(.init(kind: .draft(try draftDTO(from: draft))))
        }
        return snapshots
    }

    /// Echoes the row the just-completed operation pushed.
    private func mergeEcho(for operation: SyncOperation, in context: ModelContext) throws {
        let entityId = operation.entityId.lowercased()
        switch SyncEntityType(rawValue: operation.entityType) {
        case .siteVisit:
            guard let visit = try fetchAll(SiteVisit.self, in: context)
                .first(where: { $0.id.lowercased() == entityId }) else { return }
            _ = try SiteVisitServerMerge.merge(
                visit: try visitDTO(from: visit), companyId: companyId, into: context
            )
        case .siteVisitArtifact:
            guard let artifact = try fetchAll(SiteVisitCaptureArtifact.self, in: context)
                .first(where: { $0.id.lowercased() == entityId }) else { return }
            _ = try SiteVisitServerMerge.merge(
                artifact: try artifactDTO(from: artifact), companyId: companyId, into: context
            )
        case .siteVisitChecklistAnswer:
            guard let answer = try fetchAll(SiteVisitChecklistAnswer.self, in: context)
                .first(where: { $0.id.lowercased() == entityId }) else { return }
            _ = try SiteVisitServerMerge.merge(
                checklistAnswer: try answerDTO(from: answer),
                companyId: companyId,
                into: context
            )
        case .siteVisitIdentityDraft:
            guard let draft = try fetchAll(SiteVisitIdentityDraft.self, in: context)
                .first(where: { $0.id.lowercased() == entityId }) else { return }
            _ = try SiteVisitServerMerge.merge(
                identityDraft: try draftDTO(from: draft), companyId: companyId, into: context
            )
        default:
            return
        }
    }

    // MARK: - Row fingerprints

    private func rowFingerprints(in context: ModelContext) throws -> [String] {
        var lines: [String] = []
        for visit in try fetchAll(SiteVisit.self, in: context).sorted(by: { $0.id < $1.id }) {
            lines.append("v:\(visit.id):\(stampOf(visit.updatedAt)):\(stampOf(visit.lastSyncedAt)):\(visit.needsSync)")
        }
        for a in try fetchAll(SiteVisitCaptureArtifact.self, in: context).sorted(by: { $0.id < $1.id }) {
            lines.append("a:\(a.id):\(stampOf(a.updatedAt)):\(stampOf(a.lastSyncedAt)):\(a.needsSync)")
        }
        for a in try fetchAll(SiteVisitChecklistAnswer.self, in: context).sorted(by: { $0.id < $1.id }) {
            lines.append("c:\(a.id):\(stampOf(a.updatedAt)):\(stampOf(a.lastSyncedAt)):\(a.needsSync)")
        }
        for d in try fetchAll(SiteVisitIdentityDraft.self, in: context).sorted(by: { $0.id < $1.id }) {
            lines.append("d:\(d.id):\(stampOf(d.updatedAt)):\(stampOf(d.lastSyncedAt)):\(d.needsSync)")
        }
        return lines
    }

    private func stampOf(_ date: Date?) -> String {
        guard let date else { return "nil" }
        return String(date.timeIntervalSince1970)
    }

    // MARK: - DTO builders (wire-shaped, so decoding matches production exactly)

    private func visitDTO(from visit: SiteVisit) throws -> SiteVisitDTO {
        try JSONDecoder().decode(SiteVisitDTO.self, from: Data("""
        {
          "id":"\(visit.id)",
          "company_id":"\(visit.companyId)",
          "scheduled_at":"\(iso(visit.scheduledAt ?? visit.createdAt))",
          "duration_minutes":\(visit.durationMinutes),
          "status":"\(visit.status.rawValue)",
          "created_by":"\(visit.createdBy ?? userId)",
          "created_at":"\(iso(visit.createdAt))",
          "updated_at":"\(iso(visit.updatedAt ?? visit.createdAt))"
        }
        """.utf8))
    }

    private func artifactDTO(from artifact: SiteVisitCaptureArtifact) throws -> SiteVisitArtifactDTO {
        try JSONDecoder().decode(SiteVisitArtifactDTO.self, from: Data("""
        {
          "id":"\(artifact.id)",
          "site_visit_id":"\(artifact.siteVisitId)",
          "company_id":"\(artifact.companyId)",
          "kind":"\(artifact.kind.rawValue)",
          "source":"\(artifact.source.rawValue)",
          \(jsonField("body", artifact.body))
          \(jsonField("asset_url", artifact.localAssetURL))
          \(jsonField("rendered_asset_url", artifact.renderedAssetURL))
          \(jsonField("thumbnail_url", artifact.thumbnailURL))
          "included_in_project_review":\(artifact.includedInProjectReview),
          "captured_at":"\(iso(artifact.capturedAt))",
          "created_by":"\(artifact.createdBy ?? userId)",
          "created_at":"\(iso(artifact.createdAt))",
          "updated_at":"\(iso(artifact.updatedAt ?? artifact.createdAt))"
        }
        """.utf8))
    }

    private func answerDTO(from answer: SiteVisitChecklistAnswer) throws -> SiteVisitChecklistAnswerDTO {
        let text = answer.answerValue.text.map { "\"text\":\"\($0)\"," } ?? ""
        return try JSONDecoder().decode(SiteVisitChecklistAnswerDTO.self, from: Data("""
        {
          "id":"\(answer.id)",
          "site_visit_id":"\(answer.siteVisitId)",
          "company_id":"\(answer.companyId)",
          "field_id":"\(answer.fieldId)",
          "label":"\(answer.label)",
          "kind":"\(answer.kind.rawValue)",
          "required":\(answer.required),
          "sort_order":\(answer.sortOrder),
          "answer_value":{\(text)"artifactIds":[]},
          "created_by":"\(answer.createdBy ?? userId)",
          "created_at":"\(iso(answer.createdAt))",
          "updated_at":"\(iso(answer.updatedAt ?? answer.createdAt))"
        }
        """.utf8))
    }

    private func draftDTO(from draft: SiteVisitIdentityDraft) throws -> SiteVisitIdentityDraftDTO {
        try JSONDecoder().decode(SiteVisitIdentityDraftDTO.self, from: Data("""
        {
          "id":"\(draft.id)",
          "site_visit_id":"\(draft.siteVisitId)",
          "company_id":"\(draft.companyId)",
          "client_name":"\(draft.clientName)",
          "contact_name":"\(draft.contactName)",
          "preferred_email":"\(draft.preferredEmail)",
          "additional_emails":[],
          "phone_number":"\(draft.phoneNumber)",
          "address":"\(draft.address)",
          "notes":"\(draft.notes)",
          "created_by":"\(draft.createdBy ?? userId)",
          "created_at":"\(iso(draft.createdAt))",
          "updated_at":"\(iso(draft.updatedAt))"
        }
        """.utf8))
    }

    private func jsonField(_ key: String, _ value: String?) -> String {
        guard let value else { return "" }
        return "\"\(key)\":\"\(value)\","
    }

    private func iso(_ date: Date) -> String { SupabaseDate.format(date) }

    // MARK: - Seeding (mirrors SiteVisitPersistenceCoordinator.queueDirtyGraphs)

    private func seedBacklog(in context: ModelContext) throws {
        for index in 0..<visitCount {
            let visitId = uuid(prefix: "a", index: index)
            let visit = SiteVisit(
                id: visitId,
                companyId: companyId,
                status: .inProgress,
                scheduledAt: epoch.addingTimeInterval(Double(index)),
                assigneeIds: [userId],
                createdBy: userId,
                createdAt: epoch.addingTimeInterval(Double(index))
            )
            visit.needsSync = true
            context.insert(visit)

            // Every fourth capture carries local bytes, so its chain grows the
            // media operation + the follow-up remote-URL upsert.
            let carriesMedia = index % 4 == 0
            let artifact = SiteVisitCaptureArtifact(
                id: uuid(prefix: "b", index: index),
                siteVisitId: visitId,
                companyId: companyId,
                kind: carriesMedia ? .photo : .note,
                source: carriesMedia ? .camera : .keyboard,
                body: carriesMedia ? nil : "Captured note \(index)",
                localAssetURL: carriesMedia ? "local://project_images/photo-\(index).jpg" : nil,
                createdBy: userId,
                createdAt: epoch.addingTimeInterval(Double(index) + 0.1)
            )
            context.insert(artifact)

            let answer = SiteVisitChecklistAnswer(
                id: uuid(prefix: "c", index: index),
                siteVisitId: visitId,
                companyId: companyId,
                opportunityId: nil,
                siteVisitTypeId: nil,
                fieldId: "width",
                label: "Width",
                kind: .measurement,
                required: true,
                sortOrder: 10,
                answerValue: SiteVisitChecklistValue(text: "\(index) ft", artifactIds: []),
                createdBy: userId,
                createdAt: epoch.addingTimeInterval(Double(index) + 0.2)
            )
            context.insert(answer)

            let draft = SiteVisitIdentityDraft(
                id: uuid(prefix: "d", index: index),
                siteVisitId: visitId,
                companyId: companyId,
                clientName: "Client \(index)",
                contactName: "Contact \(index)",
                preferredEmail: "client\(index)@example.com",
                phoneNumber: "555-01\(String(format: "%02d", index % 100))",
                address: "\(index) Main St",
                createdBy: userId,
                createdAt: epoch.addingTimeInterval(Double(index) + 0.3)
            )
            context.insert(draft)

            // Serial chain per visit, exactly as the coordinator records it.
            var tip = try insert(SiteVisitSyncOperation.parent(visit), dependsOn: nil, in: context)
            tip = try insert(SiteVisitSyncOperation.artifact(artifact), dependsOn: tip, in: context)
            tip = try insert(SiteVisitSyncOperation.checklistAnswer(answer), dependsOn: tip, in: context)
            tip = try insert(SiteVisitSyncOperation.identityDraft(draft), dependsOn: tip, in: context)
            if carriesMedia {
                _ = try insert(SiteVisitSyncOperation.media(artifact), dependsOn: tip, in: context)
            }
        }
    }

    private func insert(
        _ specification: SiteVisitSyncOperation.Specification,
        dependsOn dependency: SyncOperation?,
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

    // MARK: - Stubs and helpers

    private func makeSync() -> SiteVisitOutboundSync {
        let writer = StubSiteVisitWriter()
        return SiteVisitOutboundSync(
            repositoryFactory: { _ in writer },
            mediaManager: SiteVisitMediaSyncManager(
                uploader: { _, artifactId, variant, _, _ in
                    "https://cdn.example.com/\(artifactId)/\(variant.rawValue).jpg"
                },
                loader: { _ in (data: Data("bytes".utf8), contentType: "image/jpeg") }
            )
        )
    }

    private func uuid(prefix: String, index: Int) -> String {
        let tail = String(format: "%012d", index)
        return "\(prefix)\(prefix)\(prefix)\(prefix)\(prefix)\(prefix)\(prefix)\(prefix)"
            + "-\(prefix)\(prefix)\(prefix)\(prefix)-4\(prefix)\(prefix)\(prefix)"
            + "-8\(prefix)\(prefix)\(prefix)-\(tail)"
    }

    private func allOperations(_ context: ModelContext) throws -> [SyncOperation] {
        try context.fetch(FetchDescriptor<SyncOperation>())
    }

    private func fetchAll<T: PersistentModel>(
        _ type: T.Type,
        in context: ModelContext
    ) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    private func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
            SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self,
            SyncOperation.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        liveContainers.append(container)
        return container
    }
}

// MARK: - Offline repository stub

private final class StubSiteVisitWriter: SiteVisitRemoteWriting {
    func upsertVisit(_ payload: CreateSiteVisitDTO) async throws -> SiteVisitDTO {
        try JSONDecoder().decode(SiteVisitDTO.self, from: Data("""
        {
          "id":"\(payload.id)",
          "company_id":"\(payload.companyId)",
          "scheduled_at":"\(payload.scheduledAt)",
          "duration_minutes":\(payload.durationMinutes),
          "status":"\(payload.status.rawValue)",
          "created_by":"\(payload.createdBy)",
          "created_at":"\(payload.createdAt)",
          "updated_at":"\(payload.updatedAt ?? payload.createdAt)"
        }
        """.utf8))
    }

    func upsertArtifact(
        _ payload: UpsertSiteVisitArtifactDTO
    ) async throws -> SiteVisitArtifactDTO {
        try JSONDecoder().decode(SiteVisitArtifactDTO.self, from: Data("""
        {
          "id":"\(payload.id)",
          "site_visit_id":"\(payload.siteVisitId)",
          "company_id":"\(payload.companyId)",
          "kind":"\(payload.kind.rawValue)",
          "source":"\(payload.source.rawValue)",
          "included_in_project_review":\(payload.includedInProjectReview),
          "captured_at":"\(payload.capturedAt)",
          "created_by":"\(payload.createdBy)",
          "created_at":"\(payload.createdAt)",
          "updated_at":"\(payload.updatedAt ?? payload.createdAt)"
        }
        """.utf8))
    }

    func upsertChecklistAnswer(
        _ payload: UpsertSiteVisitChecklistAnswerDTO
    ) async throws -> SiteVisitChecklistAnswerDTO {
        try JSONDecoder().decode(SiteVisitChecklistAnswerDTO.self, from: Data("""
        {
          "id":"\(payload.id)",
          "site_visit_id":"\(payload.siteVisitId)",
          "company_id":"\(payload.companyId)",
          "field_id":"\(payload.fieldId)",
          "label":"\(payload.label)",
          "kind":"\(payload.kind.rawValue)",
          "required":\(payload.required),
          "sort_order":\(payload.sortOrder),
          "answer_value":{"artifactIds":[]},
          "created_by":"\(payload.createdBy)",
          "created_at":"\(payload.createdAt)",
          "updated_at":"\(payload.updatedAt)"
        }
        """.utf8))
    }

    func upsertIdentityDraft(
        _ payload: UpsertSiteVisitIdentityDraftDTO
    ) async throws -> SiteVisitIdentityDraftDTO {
        try JSONDecoder().decode(SiteVisitIdentityDraftDTO.self, from: Data("""
        {
          "id":"\(payload.id)",
          "site_visit_id":"\(payload.siteVisitId)",
          "company_id":"\(payload.companyId)",
          "client_name":"\(payload.clientName)",
          "contact_name":"\(payload.contactName)",
          "preferred_email":"\(payload.preferredEmail)",
          "additional_emails":[],
          "phone_number":"\(payload.phoneNumber)",
          "address":"\(payload.address)",
          "notes":"\(payload.notes)",
          "created_by":"\(payload.createdBy)",
          "created_at":"\(payload.createdAt)",
          "updated_at":"\(payload.updatedAt)"
        }
        """.utf8))
    }

    func softDelete(
        _ table: SiteVisitRemoteTable,
        id: String,
        at deletedAt: Date
    ) async throws {}

    func completeSiteVisit(
        _ id: String,
        completion: SiteVisitCompletionPayload
    ) async throws -> SiteVisitCompletionResponseDTO {
        throw SiteVisitRepositoryError.transport("No completion in this backlog")
    }
}
