//
//  SiteVisitInboundSyncTests.swift
//  OPSTests
//
//  Pull and realtime recovery guarantees for cloud-backed site-visit packets.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class SiteVisitInboundSyncTests: XCTestCase {
    private let visitId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let companyId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let opportunityId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    private let userId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"

    func test_fullAndDeltaOrdersIncludeSiteVisitsAfterTheirReferencedParents() throws {
        for order in [InboundProcessor.syncOrder, DataActor.syncOrder] {
            let client = try XCTUnwrap(order.firstIndex(of: .client))
            let project = try XCTUnwrap(order.firstIndex(of: .project))
            let siteVisit = try XCTUnwrap(order.firstIndex(of: .siteVisit))

            XCTAssertLessThan(client, siteVisit)
            XCTAssertLessThan(project, siteVisit)
            XCTAssertEqual(order.filter { $0 == .siteVisit }.count, 1)
        }
    }

    func test_realtimeBindingsCoverEveryPublishedSiteVisitTable() {
        let tables = Set(RealtimeProcessor.companyFilteredTables)
        XCTAssertTrue(tables.isSuperset(of: [
            "site_visits",
            "site_visit_artifacts",
            "site_visit_checklist_answers",
            "site_visit_identity_drafts",
        ]))
    }

    func test_dataActorRealtimeReconstructsCanonicalParentAndChildren() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()
        let bundle = try makeBundle()

        await actor.handleRealtimeUpdate(.siteVisit(bundle.visit))
        for draft in bundle.identityDrafts {
            await actor.handleRealtimeUpdate(.siteVisitIdentityDraft(draft))
        }
        for answer in bundle.checklistAnswers {
            await actor.handleRealtimeUpdate(.siteVisitChecklistAnswer(answer))
        }
        for artifact in bundle.artifacts {
            await actor.handleRealtimeUpdate(.siteVisitArtifact(artifact))
        }

        let context = ModelContext(container)
        let visit = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SiteVisit>()).first
        )
        XCTAssertEqual(visit.id, visitId)
        XCTAssertEqual(visit.companyId, companyId)
        XCTAssertFalse(visit.needsSync)

        let artifact = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).first
        )
        XCTAssertEqual(artifact.siteVisitId, visitId)
        XCTAssertEqual(artifact.localAssetURL, "https://cdn.ops.test/photo.jpg")
        XCTAssertFalse(artifact.needsSync)

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).count,
            1
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<SiteVisitIdentityDraft>()).count,
            1
        )
    }

    func test_dataActorRealtimeDeleteTombstonesSiteVisitRows() async throws {
        let container = try makeContainer()
        let actor = DataActor(modelContainer: container)
        await actor.configure()
        let bundle = try makeBundle()
        await actor.handleRealtimeUpdate(.siteVisit(bundle.visit))
        await actor.handleRealtimeUpdate(.siteVisitArtifact(bundle.artifacts[0]))

        await actor.softDeleteFromRealtime(
            table: "site_visit_artifacts",
            id: bundle.artifacts[0].id
        )
        await actor.softDeleteFromRealtime(table: "site_visits", id: visitId)

        let context = ModelContext(container)
        XCTAssertNotNil(
            try context.fetch(FetchDescriptor<SiteVisit>()).first?.deletedAt
        )
        XCTAssertNotNil(
            try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).first?.deletedAt
        )
    }

    func test_realtimeEntityNamesCoverWholePacket() throws {
        let bundle = try makeBundle()
        XCTAssertEqual(RealtimeUpdate.siteVisit(bundle.visit).mergedEntityName, "SiteVisit")
        XCTAssertEqual(
            RealtimeUpdate.siteVisitArtifact(bundle.artifacts[0]).mergedEntityName,
            "SiteVisitCaptureArtifact"
        )
        XCTAssertEqual(
            RealtimeUpdate.siteVisitChecklistAnswer(bundle.checklistAnswers[0]).mergedEntityName,
            "SiteVisitChecklistAnswer"
        )
        XCTAssertEqual(
            RealtimeUpdate.siteVisitIdentityDraft(bundle.identityDrafts[0]).mergedEntityName,
            "SiteVisitIdentityDraft"
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
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeBundle() throws -> SiteVisitBundleDTO {
        let json = """
        {
          "visit": {
            "id":"\(visitId)",
            "company_id":"\(companyId)",
            "opportunity_id":"\(opportunityId)",
            "scheduled_at":"2026-07-31T18:12:45.123456Z",
            "status":"in_progress",
            "notes":"Server note",
            "created_by":"\(userId)",
            "updated_at":"2026-07-31T18:13:00Z"
          },
          "artifacts": [{
            "id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01",
            "site_visit_id":"\(visitId)",
            "company_id":"\(companyId)",
            "opportunity_id":"\(opportunityId)",
            "kind":"photo",
            "source":"camera",
            "asset_url":"https://cdn.ops.test/photo.jpg",
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
            "created_by":"\(userId)",
            "created_at":"2026-07-31T18:12:46Z",
            "updated_at":"2026-07-31T18:12:46Z"
          }]
        }
        """
        return try JSONDecoder().decode(SiteVisitBundleDTO.self, from: Data(json.utf8))
    }
}
