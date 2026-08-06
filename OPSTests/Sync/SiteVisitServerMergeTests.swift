import SwiftData
import XCTest
@testable import OPS

@MainActor
final class SiteVisitServerMergeTests: XCTestCase {
    private let visitId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let companyId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let opportunityId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    private let userId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"

    func testBundleMergeInsertsParentBeforeCanonicalChildrenAndMarksThemSynced() throws {
        let context = try makeContext()
        let bundle = try makeBundle()

        let report = try SiteVisitServerMerge.merge(bundle: bundle, into: context)

        XCTAssertEqual(report.inserted, 4)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SiteVisit>()).first?.id, visitId)
        let artifact = try XCTUnwrap(context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).first)
        XCTAssertEqual(artifact.siteVisitId, visitId)
        XCTAssertEqual(artifact.companyId, companyId)
        XCTAssertFalse(artifact.needsSync)
        let answer = try XCTUnwrap(context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first)
        XCTAssertEqual(answer.answerValue.text, "12 ft")
        XCTAssertFalse(answer.needsSync)
        let identity = try XCTUnwrap(context.fetch(FetchDescriptor<SiteVisitIdentityDraft>()).first)
        XCTAssertEqual(identity.clientName, "Acme Roofing")
        XCTAssertEqual(identity.searchText, "")
        XCTAssertFalse(identity.needsSync)
    }

    func testPendingLocalFieldWinsWhileUnrelatedServerFieldsAndActivityMerge() throws {
        let context = try makeContext()
        let local = SiteVisit(
            id: visitId,
            opportunityId: opportunityId,
            companyId: companyId,
            status: .inProgress,
            scheduledAt: Date(timeIntervalSince1970: 1),
            createdBy: userId
        )
        local.notes = "Local unsent note"
        local.internalNotes = "Old internal"
        local.needsSync = true
        context.insert(local)
        context.insert(
            SyncOperation(
                entityType: "siteVisit",
                entityId: visitId,
                operationType: "update",
                payload: Data(),
                changedFields: ["notes"]
            )
        )
        try context.save()

        var bundle = try makeBundle()
        bundle = SiteVisitBundleDTO(
            visit: bundle.visit.replacing(
                notes: "Stale server note",
                internalNotes: "Fresh remote internal",
                activityId: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
            ),
            artifacts: [],
            checklistAnswers: [],
            identityDrafts: []
        )

        let report = try SiteVisitServerMerge.merge(bundle: bundle, into: context)

        XCTAssertEqual(report.updated, 1)
        XCTAssertEqual(local.notes, "Local unsent note")
        XCTAssertEqual(local.internalNotes, "Fresh remote internal")
        XCTAssertEqual(local.loggedActivityId, "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")
        XCTAssertTrue(local.needsSync)
        XCTAssertNotNil(local.lastSyncedAt)
    }

    func testRemoteTombstoneWinsOverPendingMutableEdit() throws {
        let context = try makeContext()
        let local = SiteVisit(
            id: visitId,
            companyId: companyId,
            status: .inProgress,
            scheduledAt: Date(),
            createdBy: userId
        )
        local.notes = "Local edit"
        context.insert(local)
        context.insert(
            SyncOperation(
                entityType: "siteVisit",
                entityId: visitId,
                operationType: "update",
                payload: Data(),
                changedFields: ["notes"]
            )
        )
        try context.save()

        let base = try makeBundle().visit
        let tombstoned = base.replacing(
            notes: "Remote note",
            deletedAt: Date(timeIntervalSince1970: 500)
        )
        _ = try SiteVisitServerMerge.merge(
            bundle: SiteVisitBundleDTO(
                visit: tombstoned,
                artifacts: [],
                checklistAnswers: [],
                identityDrafts: []
            ),
            into: context
        )

        XCTAssertEqual(local.notes, "Local edit")
        XCTAssertEqual(local.deletedAt, Date(timeIntervalSince1970: 500))
    }

    func testOlderRealtimeEchoCannotOverwriteNewerServerSnapshot() throws {
        let context = try makeContext()
        let bundle = try makeBundle()
        _ = try SiteVisitServerMerge.merge(bundle: bundle, into: context)

        let newer = bundle.visit.replacing(notes: "Newest server note")
        _ = try SiteVisitServerMerge.merge(
            visit: newer,
            companyId: companyId,
            into: context
        )
        let local = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SiteVisit>()).first
        )
        local.updatedAt = Date(timeIntervalSince1970: 2_000_000_000)

        let stale = bundle.visit.replacing(notes: "Delayed old echo")
        _ = try SiteVisitServerMerge.merge(
            visit: stale,
            companyId: companyId,
            into: context
        )

        XCTAssertEqual(local.notes, "Newest server note")
        XCTAssertEqual(local.updatedAt, Date(timeIntervalSince1970: 2_000_000_000))
    }

    func testMalformedDeltaIsRejectedBeforeParentMutation() throws {
        let context = try makeContext()
        let bundle = try makeBundle()
        let orphan: [SiteVisitArtifactDTO] = try JSONDecoder().decode(
            [SiteVisitArtifactDTO].self,
            from: Data("""
            [{
              "id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa09",
              "site_visit_id":"ffffffff-ffff-4fff-8fff-ffffffffffff",
              "company_id":"\(companyId)",
              "kind":"note",
              "source":"keyboard",
              "included_in_project_review":true,
              "captured_at":"2026-07-31T18:12:46Z",
              "created_by":"\(userId)",
              "created_at":"2026-07-31T18:12:46Z",
              "updated_at":"2026-07-31T18:12:46Z"
            }]
            """.utf8)
        )

        XCTAssertThrowsError(
            try SiteVisitServerMerge.merge(
                delta: SiteVisitDeltaBundleDTO(
                    visits: [bundle.visit],
                    artifacts: orphan,
                    checklistAnswers: [],
                    identityDrafts: []
                ),
                companyId: companyId,
                into: context
            )
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisit>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).isEmpty)
        XCTAssertFalse(context.hasChanges)
    }

    /// The row lookups are predicate-scoped now, and `merge(delta:)` checks each
    /// child's parent inside the same transaction that inserted it. If a
    /// predicate fetch could not see a pending insert, every delta pull carrying
    /// a brand-new visit and its children would start throwing `orphanedChild`.
    func testDeltaMergeAcceptsChildrenOfAParentInsertedInTheSameTransaction() throws {
        let context = try makeContext()
        let bundle = try makeBundle()

        let report = try SiteVisitServerMerge.merge(
            delta: SiteVisitDeltaBundleDTO(
                visits: [bundle.visit],
                artifacts: bundle.artifacts,
                checklistAnswers: bundle.checklistAnswers,
                identityDrafts: bundle.identityDrafts
            ),
            companyId: companyId,
            into: context
        )

        XCTAssertEqual(report.inserted, 4)
        XCTAssertEqual(report.updated, 0)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).count,
            1
        )
    }

    /// Realtime echoes the very rows the outbound drain just pushed. A redundant
    /// echo must resolve as `unchanged` — no transaction, no write, and no
    /// movement in `updatedAt`/`lastSyncedAt`.
    func testRedundantEchoResolvesUnchangedAndWritesNothing() throws {
        let context = try makeContext()
        let bundle = try makeBundle()
        _ = try SiteVisitServerMerge.merge(bundle: bundle, into: context)

        // First echo settles any timestamp normalization.
        _ = try SiteVisitServerMerge.merge(
            visit: bundle.visit,
            companyId: companyId,
            into: context
        )
        let local = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SiteVisit>()).first
        )
        let updatedAt = local.updatedAt
        let lastSyncedAt = local.lastSyncedAt
        let needsSync = local.needsSync

        let report = try SiteVisitServerMerge.merge(
            visit: bundle.visit,
            companyId: companyId,
            into: context
        )

        XCTAssertEqual(report.unchanged, 1)
        XCTAssertEqual(report.updated, 0)
        XCTAssertEqual(report.inserted, 0)
        XCTAssertEqual(local.updatedAt, updatedAt)
        XCTAssertEqual(local.lastSyncedAt, lastSyncedAt)
        XCTAssertEqual(local.needsSync, needsSync)
    }

    /// A genuine change still merges — the short-circuit must not swallow work.
    func testChangedEchoStillWrites() throws {
        let context = try makeContext()
        let bundle = try makeBundle()
        _ = try SiteVisitServerMerge.merge(bundle: bundle, into: context)

        let report = try SiteVisitServerMerge.merge(
            visit: bundle.visit.replacing(notes: "Server changed the note"),
            companyId: companyId,
            into: context
        )

        XCTAssertEqual(report.updated, 1)
        XCTAssertEqual(report.unchanged, 0)
        let local = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SiteVisit>()).first
        )
        XCTAssertEqual(local.notes, "Server changed the note")
    }

    func testLogicalChecklistMatchRekeysDirtyRowAndEveryUnresolvedOperationInPlace() throws {
        let context = try makeContext()
        let localId = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
        let serverAnswer = try XCTUnwrap(makeBundle().checklistAnswers.first)
        let visit = makeLocalVisit()
        let local = makeLocalAnswer(id: localId, value: "Local unsent width")
        context.insert(visit)
        context.insert(local)

        let firstDependencyId = UUID()
        let first = try makeChecklistOperation(
            answerId: localId,
            operationType: "create",
            status: "parked",
            changedFields: ["answer_value"],
            dependsOnId: firstDependencyId.uuidString.lowercased()
        )
        first.retryCount = 7
        first.createdAt = Date(timeIntervalSince1970: 10)
        first.lastAttemptedAt = Date(timeIntervalSince1970: 20)
        first.lastError = "23505 active field collision"
        first.previousValues = Data("previous".utf8)

        let second = try makeChecklistOperation(
            answerId: localId,
            operationType: "update",
            status: "failed",
            changedFields: ["answer_value"]
        )
        second.retryCount = 20
        second.createdAt = Date(timeIntervalSince1970: 30)
        second.lastAttemptedAt = Date(timeIntervalSince1970: 40)
        second.lastError = "offline retry budget exhausted"

        let completion = try makeCompletionOperation(
            dependsOnId: first.id.uuidString.lowercased()
        )
        context.insert(first)
        context.insert(second)
        context.insert(completion)
        try context.save()

        let firstSnapshot = OperationSnapshot(first)
        let secondSnapshot = OperationSnapshot(second)
        let completionSnapshot = OperationSnapshot(completion)
        let now = Date(timeIntervalSince1970: 1_000)

        let report = try SiteVisitServerMerge.merge(
            checklistAnswer: serverAnswer,
            companyId: companyId,
            into: context,
            now: now
        )

        XCTAssertEqual(report, SiteVisitMergeReport(inserted: 0, updated: 1, unchanged: 0))
        let answers = try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
        XCTAssertEqual(answers.count, 1)
        XCTAssertTrue(answers[0] === local)
        XCTAssertEqual(local.id, serverAnswer.id)
        XCTAssertEqual(local.answerValue.text, "Local unsent width")
        XCTAssertEqual(local.label, serverAnswer.label)
        XCTAssertTrue(local.needsSync)
        XCTAssertEqual(local.lastSyncedAt, now)

        XCTAssertEqual(OperationSnapshot(first), firstSnapshot.rekeyed(to: serverAnswer.id))
        XCTAssertEqual(OperationSnapshot(second), secondSnapshot.rekeyed(to: serverAnswer.id))
        XCTAssertEqual(OperationSnapshot(completion), completionSnapshot)
        XCTAssertEqual(completion.dependsOnId, first.id.uuidString.lowercased())

        for operation in [first, second] {
            let envelope = try JSONDecoder().decode(
                SiteVisitSyncOperation.Payload.self,
                from: operation.payload
            )
            XCTAssertEqual(envelope.entityId, serverAnswer.id)
            XCTAssertEqual(envelope.siteVisitId, visitId)
            XCTAssertEqual(envelope.companyId, companyId)
        }
    }

    func testRekeyedChecklistRetrySendsServerIdentityAndReleasesPacketCompletion() async throws {
        let context = try makeContext()
        let localId = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
        let serverAnswer = try XCTUnwrap(makeBundle().checklistAnswers.first)
        let visit = makeLocalVisit()
        let local = makeLocalAnswer(id: localId, value: "Local retry value")
        context.insert(visit)
        context.insert(local)

        let operation = try makeChecklistOperation(
            answerId: localId,
            operationType: "create",
            status: "parked",
            changedFields: ["answer_value"]
        )
        let completion = try makeCompletionOperation(
            dependsOnId: operation.id.uuidString.lowercased()
        )
        context.insert(operation)
        context.insert(completion)
        try context.save()

        _ = try SiteVisitServerMerge.merge(
            checklistAnswer: serverAnswer,
            companyId: companyId,
            into: context,
            now: Date(timeIntervalSince1970: 2_000)
        )
        operation.status = "pending"
        operation.retryCount = 0
        operation.lastAttemptedAt = nil
        operation.lastError = nil

        XCTAssertEqual(
            SiteVisitOutboundSync.readyPendingOperationIds(
                in: try context.fetch(FetchDescriptor<SyncOperation>())
            ),
            [operation.id]
        )

        let remote = RecordingChecklistAnswerWriter(response: serverAnswer)
        let sync = SiteVisitOutboundSync(
            repositoryFactory: { _ in remote },
            mediaManager: SiteVisitMediaSyncManager(
                uploader: { _, _, _, _, _ in "" },
                loader: { _ in throw URLError(.fileDoesNotExist) }
            )
        )

        XCTAssertTrue(
            try await sync.executeIfHandled(
                operation: operation,
                context: context,
                activeCompanyId: companyId
            )
        )
        let payload = try XCTUnwrap(remote.checklistPayloads.first)
        XCTAssertEqual(payload.id, serverAnswer.id)
        XCTAssertEqual(payload.answerValue.text, "Local retry value")

        operation.status = "completed"
        operation.completedAt = Date(timeIntervalSince1970: 2_001)
        XCTAssertEqual(
            SiteVisitOutboundSync.readyPendingOperationIds(
                in: try context.fetch(FetchDescriptor<SyncOperation>())
            ),
            [completion.id]
        )
    }

    func testAmbiguousDirtyLogicalChecklistMatchesFailBeforeBundleWrites() throws {
        let context = try makeContext()
        let first = makeLocalAnswer(
            id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
            value: "First unsent value"
        )
        let second = makeLocalAnswer(
            id: "ffffffff-ffff-4fff-8fff-ffffffffffff",
            value: "Second unsent value"
        )
        context.insert(first)
        context.insert(second)
        try context.save()
        let bundle = try makeBundle()
        let answerOnlyBundle = SiteVisitBundleDTO(
            visit: bundle.visit,
            artifacts: [],
            checklistAnswers: bundle.checklistAnswers,
            identityDrafts: []
        )

        XCTAssertThrowsError(
            try SiteVisitServerMerge.merge(bundle: answerOnlyBundle, into: context)
        ) { error in
            XCTAssertTrue(error is SiteVisitMergeError)
        }

        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisit>()).isEmpty)
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).map(\.id)),
            [first.id, second.id]
        )
        XCTAssertFalse(context.hasChanges)
    }

    func testMalformedUnresolvedChecklistEnvelopeFailsBeforeBundleWrites() throws {
        let context = try makeContext()
        let localId = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
        let local = makeLocalAnswer(id: localId, value: "Never discard this")
        let operation = SyncOperation(
            entityType: SyncEntityType.siteVisitChecklistAnswer.rawValue,
            entityId: localId,
            operationType: "create",
            payload: Data("not-json".utf8),
            changedFields: ["answer_value"]
        )
        operation.status = "parked"
        operation.retryCount = 3
        operation.lastError = "Original failure"
        context.insert(local)
        context.insert(operation)
        try context.save()
        let bundle = try makeBundle()
        let answerOnlyBundle = SiteVisitBundleDTO(
            visit: bundle.visit,
            artifacts: [],
            checklistAnswers: bundle.checklistAnswers,
            identityDrafts: []
        )

        XCTAssertThrowsError(
            try SiteVisitServerMerge.merge(bundle: answerOnlyBundle, into: context)
        ) { error in
            XCTAssertTrue(error is SiteVisitMergeError)
        }

        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisit>()).isEmpty)
        XCTAssertEqual(local.id, localId)
        XCTAssertEqual(local.answerValue.text, "Never discard this")
        XCTAssertEqual(operation.entityId, localId)
        XCTAssertEqual(operation.payload, Data("not-json".utf8))
        XCTAssertEqual(operation.status, "parked")
        XCTAssertEqual(operation.retryCount, 3)
        XCTAssertEqual(operation.lastError, "Original failure")
        XCTAssertFalse(context.hasChanges)
    }

    func testMisroutedUnresolvedChecklistEnvelopeFailsBeforeBundleWrites() throws {
        let context = try makeContext()
        let localId = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
        let wrongEntityId = "ffffffff-ffff-4fff-8fff-ffffffffffff"
        let local = makeLocalAnswer(id: localId, value: "Keep this routed value")
        let originalPayload = try JSONEncoder().encode(
            SiteVisitSyncOperation.Payload(
                companyId: companyId,
                siteVisitId: visitId,
                entityId: wrongEntityId
            )
        )
        let operation = SyncOperation(
            entityType: SyncEntityType.siteVisitChecklistAnswer.rawValue,
            entityId: localId,
            operationType: "update",
            payload: originalPayload,
            changedFields: ["answer_value"]
        )
        operation.status = "failed"
        context.insert(local)
        context.insert(operation)
        try context.save()
        let bundle = try makeBundle()
        let answerOnlyBundle = SiteVisitBundleDTO(
            visit: bundle.visit,
            artifacts: [],
            checklistAnswers: bundle.checklistAnswers,
            identityDrafts: []
        )

        XCTAssertThrowsError(
            try SiteVisitServerMerge.merge(bundle: answerOnlyBundle, into: context)
        ) { error in
            XCTAssertTrue(error is SiteVisitMergeError)
        }

        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisit>()).isEmpty)
        XCTAssertEqual(local.id, localId)
        XCTAssertEqual(local.answerValue.text, "Keep this routed value")
        XCTAssertEqual(operation.entityId, localId)
        XCTAssertEqual(operation.payload, originalPayload)
        XCTAssertEqual(operation.status, "failed")
        XCTAssertFalse(context.hasChanges)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
            SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self,
            SyncOperation.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContext(ModelContainer(for: schema, configurations: [configuration]))
    }

    private func makeLocalVisit() -> SiteVisit {
        SiteVisit(
            id: visitId,
            opportunityId: opportunityId,
            companyId: companyId,
            status: .inProgress,
            scheduledAt: Date(timeIntervalSince1970: 1),
            createdBy: userId
        )
    }

    private func makeLocalAnswer(id: String, value: String) -> SiteVisitChecklistAnswer {
        SiteVisitChecklistAnswer(
            id: id,
            siteVisitId: visitId,
            companyId: companyId,
            opportunityId: opportunityId,
            siteVisitTypeId: "estimate",
            fieldId: "width",
            label: "Local width",
            kind: .measurement,
            required: true,
            sortOrder: 10,
            answerValue: SiteVisitChecklistValue(text: value),
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 2)
        )
    }

    private func makeChecklistOperation(
        answerId: String,
        operationType: String,
        status: String,
        changedFields: [String],
        dependsOnId: String? = nil
    ) throws -> SyncOperation {
        let operation = SyncOperation(
            entityType: SyncEntityType.siteVisitChecklistAnswer.rawValue,
            entityId: answerId,
            operationType: operationType,
            payload: try JSONEncoder().encode(
                SiteVisitSyncOperation.Payload(
                    companyId: companyId,
                    siteVisitId: visitId,
                    entityId: answerId
                )
            ),
            changedFields: changedFields,
            dependsOnId: dependsOnId
        )
        operation.status = status
        return operation
    }

    private func makeCompletionOperation(dependsOnId: String) throws -> SyncOperation {
        SyncOperation(
            entityType: SyncEntityType.siteVisit.rawValue,
            entityId: visitId,
            operationType: SiteVisitSyncOperation.completionOperationType,
            payload: try JSONEncoder().encode(
                SiteVisitSyncOperation.Payload(
                    companyId: companyId,
                    siteVisitId: visitId,
                    entityId: visitId,
                    completion: SiteVisitCompletionPayload(notes: "Packet committed")
                )
            ),
            changedFields: ["status"],
            priority: 0,
            dependsOnId: dependsOnId
        )
    }

    private func makeBundle() throws -> SiteVisitBundleDTO {
        let data = Data("""
        {
          "visit": {
            "id":"\(visitId)",
            "company_id":"\(companyId)",
            "opportunity_id":"\(opportunityId)",
            "scheduled_at":"2026-07-31T18:12:45.123456Z",
            "status":"in_progress",
            "notes":"Server note",
            "internal_notes":"Server internal",
            "created_by":"\(userId)",
            "updated_at":"2026-07-31T18:13:00Z"
          },
          "artifacts": [{
            "id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01",
            "site_visit_id":"\(visitId)",
            "company_id":"\(companyId)",
            "opportunity_id":"\(opportunityId)",
            "kind":"note",
            "source":"keyboard",
            "body":"Captured note",
            "included_in_project_review":true,
            "captured_at":"2026-07-31T18:12:46Z",
            "created_by":"\(userId)",
            "created_at":"2026-07-31T18:12:46Z",
            "updated_at":"2026-07-31T18:12:46Z"
          }],
          "checklist_answers": [{
            "id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02",
            "site_visit_id":"\(visitId)",
            "company_id":"\(companyId)",
            "opportunity_id":"\(opportunityId)",
            "field_id":"width",
            "label":"Width",
            "kind":"measurement",
            "required":true,
            "sort_order":10,
            "answer_value":{"text":"12 ft","artifactIds":[]},
            "created_by":"\(userId)",
            "created_at":"2026-07-31T18:12:46Z",
            "updated_at":"2026-07-31T18:12:46Z"
          }],
          "identity_drafts": [{
            "id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa03",
            "site_visit_id":"\(visitId)",
            "company_id":"\(companyId)",
            "opportunity_id":"\(opportunityId)",
            "client_name":"Acme Roofing",
            "contact_name":"Ada",
            "preferred_email":"ada@example.com",
            "additional_emails":[],
            "phone_number":"555-0100",
            "address":"100 Main St",
            "notes":"",
            "created_by":"\(userId)",
            "created_at":"2026-07-31T18:12:46Z",
            "updated_at":"2026-07-31T18:12:46Z"
          }]
        }
        """.utf8)
        return try JSONDecoder().decode(SiteVisitBundleDTO.self, from: data)
    }
}

private struct OperationSnapshot: Equatable {
    let id: UUID
    let entityId: String
    let operationType: String
    let changedFields: String
    let createdAt: Date
    let retryCount: Int
    let lastAttemptedAt: Date?
    let status: String
    let lastError: String?
    let previousValues: Data?
    let priority: Int
    let requiresWiFi: Bool
    let dependsOnId: String?
    let completedAt: Date?
    let serverConfirmedAt: Date?

    init(_ operation: SyncOperation) {
        id = operation.id
        entityId = operation.entityId
        operationType = operation.operationType
        changedFields = operation.changedFields
        createdAt = operation.createdAt
        retryCount = operation.retryCount
        lastAttemptedAt = operation.lastAttemptedAt
        status = operation.status
        lastError = operation.lastError
        previousValues = operation.previousValues
        priority = operation.priority
        requiresWiFi = operation.requiresWiFi
        dependsOnId = operation.dependsOnId
        completedAt = operation.completedAt
        serverConfirmedAt = operation.serverConfirmedAt
    }

    private init(copying source: OperationSnapshot, entityId: String) {
        id = source.id
        self.entityId = entityId
        operationType = source.operationType
        changedFields = source.changedFields
        createdAt = source.createdAt
        retryCount = source.retryCount
        lastAttemptedAt = source.lastAttemptedAt
        status = source.status
        lastError = source.lastError
        previousValues = source.previousValues
        priority = source.priority
        requiresWiFi = source.requiresWiFi
        dependsOnId = source.dependsOnId
        completedAt = source.completedAt
        serverConfirmedAt = source.serverConfirmedAt
    }

    func rekeyed(to entityId: String) -> OperationSnapshot {
        OperationSnapshot(copying: self, entityId: entityId)
    }
}

private final class RecordingChecklistAnswerWriter: SiteVisitRemoteWriting {
    let response: SiteVisitChecklistAnswerDTO
    var checklistPayloads: [UpsertSiteVisitChecklistAnswerDTO] = []

    init(response: SiteVisitChecklistAnswerDTO) {
        self.response = response
    }

    func upsertVisit(_ payload: CreateSiteVisitDTO) async throws -> SiteVisitDTO {
        throw SiteVisitRepositoryError.transport("Unexpected visit upsert")
    }

    func upsertArtifact(
        _ payload: UpsertSiteVisitArtifactDTO
    ) async throws -> SiteVisitArtifactDTO {
        throw SiteVisitRepositoryError.transport("Unexpected artifact upsert")
    }

    func upsertChecklistAnswer(
        _ payload: UpsertSiteVisitChecklistAnswerDTO
    ) async throws -> SiteVisitChecklistAnswerDTO {
        checklistPayloads.append(payload)
        return response
    }

    func upsertIdentityDraft(
        _ payload: UpsertSiteVisitIdentityDraftDTO
    ) async throws -> SiteVisitIdentityDraftDTO {
        throw SiteVisitRepositoryError.transport("Unexpected identity upsert")
    }

    func softDelete(
        _ table: SiteVisitRemoteTable,
        id: String,
        at deletedAt: Date
    ) async throws {
        throw SiteVisitRepositoryError.transport("Unexpected soft delete")
    }

    func completeSiteVisit(
        _ id: String,
        completion: SiteVisitCompletionPayload
    ) async throws -> SiteVisitCompletionResponseDTO {
        throw SiteVisitRepositoryError.transport("Unexpected completion")
    }
}
