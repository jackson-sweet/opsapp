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
