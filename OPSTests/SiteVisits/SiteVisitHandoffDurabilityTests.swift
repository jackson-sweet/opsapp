//
//  SiteVisitHandoffDurabilityTests.swift
//  OPSTests
//
//  Site-visit → project conversion durability (Carol Dancer case, 2026-07-13).
//
//  Two data-loss bugs shared one root cause: SiteVisitProjectHandoff wrote
//  needsSync-only mutations with no durable operation behind them.
//    Bug A — photos: local ProjectPhoto rows (url local://…) were created with
//            needsSync = true, but the sync engine treats ProjectPhoto as
//            read-only and the upload queue was only fed by ImageSyncManager's
//            own saveImageLocally — so the rows stayed phone-local forever.
//    Bug B — decks: attachDeckDesigns set projectId + markForSync() but never
//            recorded a SyncOperation, and the deck UPDATE payload omitted
//            project_id, so the link could never reach the server.
//  Additionally the staging store bridging review → conversion is in-memory,
//  so an app kill between the two silently dropped the whole packet.
//

import XCTest
import SwiftData
@testable import OPS

final class SiteVisitHandoffDurabilityTests: XCTestCase {

    private var savedLocalIDs: [String] = []
    private var priorPendingUploads: Data?

    override func setUp() {
        super.setUp()
        // The pending-upload queue persists in UserDefaults. Snapshot + clear so
        // tests see only their own entries and the developer's real queue (test
        // host = the OPS app) survives the run untouched.
        priorPendingUploads = UserDefaults.standard.data(forKey: "pendingImageUploads")
        UserDefaults.standard.removeObject(forKey: "pendingImageUploads")
    }

    override func tearDown() {
        for localID in savedLocalIDs {
            _ = ImageFileManager.shared.deleteImage(localID: localID)
        }
        savedLocalIDs = []
        if let priorPendingUploads {
            UserDefaults.standard.set(priorPendingUploads, forKey: "pendingImageUploads")
        } else {
            UserDefaults.standard.removeObject(forKey: "pendingImageUploads")
        }
        priorPendingUploads = nil
        super.tearDown()
    }

    private func saveLocalBytes(for localID: String) {
        XCTAssertTrue(
            ImageFileManager.shared.saveImage(data: Data([0xFF, 0xD8, 0xFF, 0xD9]), localID: localID),
            "test fixture bytes must save"
        )
        savedLocalIDs.append(localID)
    }

    // MARK: - Bug A: photos enter the durable upload pipeline

    @MainActor
    func test_handoffEnqueuesPhotoArtifactsIntoDurableUploadQueue() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let plainURL = "local://project_images/site_visit_visit-1_plain.jpg"
        let renderedURL = "local://project_images/site_visit_visit-1_markup.rendered.jpg"
        saveLocalBytes(for: plainURL)
        saveLocalBytes(for: renderedURL)

        let photo = SiteVisitCaptureArtifact.durabilityFixture(kind: .photo, capturedAt: Date(timeIntervalSince1970: 1))
        photo.localAssetURL = plainURL
        let annotated = SiteVisitCaptureArtifact.durabilityFixture(kind: .annotatedPhoto, capturedAt: Date(timeIntervalSince1970: 2))
        annotated.localAssetURL = "local://project_images/site_visit_visit-1_original.jpg"
        annotated.renderedAssetURL = renderedURL

        let payload = SiteVisitProjectPayloadBuilder.payload(
            siteVisitId: "visit-1",
            opportunityId: "lead-1",
            address: nil,
            artifacts: [photo, annotated]
        )

        let imageSync = ImageSyncManager(modelContext: nil, connectivity: ConnectivityManager())

        SiteVisitProjectHandoff.apply(
            payload: payload,
            artifacts: [photo, annotated],
            projectId: "project-1",
            companyId: "company-1",
            userId: "user-1",
            modelContext: context,
            imageSync: imageSync
        )

        // The gallery row is optimistic AND the upload is durably queued — the
        // queue survives restarts (UserDefaults) and drains on connectivity.
        let queued = imageSync.getPendingUploads()
        XCTAssertEqual(
            Set(queued.map(\.localURL)),
            [plainURL, renderedURL],
            "each photo artifact's gallery URL must enter the restart-surviving upload queue (annotated photos upload their rendered markup, which is what the gallery row shows)"
        )
        XCTAssertTrue(queued.allSatisfy { $0.projectId == "project-1" && $0.companyId == "company-1" })

        let rows = try context.fetch(FetchDescriptor<ProjectPhoto>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy(\.needsSync))
        XCTAssertTrue(
            rows.allSatisfy { $0.id == $0.id.lowercased() },
            "row ids must be lowercase so the server insert echo merges back into the same row (Postgres uuids are lowercase)"
        )
    }

    @MainActor
    func test_handoffDoesNotEnqueueDimensionedPhotosIntoImageUploadQueue() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let heicURL = "local://project_images/site_visit_dimensioned_ABC.heic"
        saveLocalBytes(for: heicURL)

        let dimensioned = SiteVisitCaptureArtifact.durabilityFixture(kind: .dimensionedPhoto, capturedAt: Date(timeIntervalSince1970: 1))
        dimensioned.localAssetURL = heicURL
        dimensioned.dimensionsJSON = try fixtureDimensionsJSON()

        let payload = SiteVisitProjectPayloadBuilder.payload(
            siteVisitId: "visit-1",
            opportunityId: "lead-1",
            address: nil,
            artifacts: [dimensioned]
        )

        let imageSync = ImageSyncManager(modelContext: nil, connectivity: ConnectivityManager())

        SiteVisitProjectHandoff.apply(
            payload: payload,
            artifacts: [dimensioned],
            projectId: "project-1",
            companyId: "company-1",
            userId: "user-1",
            modelContext: context,
            imageSync: imageSync
        )

        // Dimensioned captures already sync durably through the PhotoAnnotation
        // pending sweep, which uploads the HEIC + rendered deliverable AND
        // inserts the project_photos row itself. Queueing them here too would
        // upload the same photo twice and double-tile every teammate's gallery.
        XCTAssertTrue(
            imageSync.getPendingUploads().isEmpty,
            "dimensioned photos are owned by the annotation sync pipeline — the image queue must not double-upload them"
        )

        let rows = try context.fetch(FetchDescriptor<ProjectPhoto>())
        XCTAssertEqual(rows.count, 1, "the optimistic gallery row still appears immediately")
        XCTAssertTrue(rows.allSatisfy(\.needsSync))
    }

    @MainActor
    func test_handoffWithoutImageSyncStillCreatesRowsForSweepRecovery() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let plainURL = "local://project_images/site_visit_visit-1_offline.jpg"
        saveLocalBytes(for: plainURL)

        let photo = SiteVisitCaptureArtifact.durabilityFixture(kind: .photo, capturedAt: Date(timeIntervalSince1970: 1))
        photo.localAssetURL = plainURL

        let payload = SiteVisitProjectPayloadBuilder.payload(
            siteVisitId: "visit-1",
            opportunityId: "lead-1",
            address: nil,
            artifacts: [photo]
        )

        SiteVisitProjectHandoff.apply(
            payload: payload,
            artifacts: [photo],
            projectId: "project-1",
            companyId: "company-1",
            userId: "user-1",
            modelContext: context
        )

        let rows = try context.fetch(FetchDescriptor<ProjectPhoto>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.url, plainURL)
        XCTAssertTrue(
            rows.first?.needsSync == true,
            "without a live upload manager the row must stay flagged so the stranded-photo sweep can enqueue it on the next launch"
        )
    }

    // MARK: - Bug B: deck link records a durable operation

    @MainActor
    func test_handoffRecordsDurableDeckDesignLinkOperation() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let deck = DeckDesign(
            id: "bff17fb7-af08-457b-9062-822d25270e9a",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: nil,
            title: "Visit deck",
            createdBy: "user-1"
        )
        context.insert(deck)
        try context.save()

        let syncEngine = SyncEngine()
        syncEngine.configure(
            modelContext: context,
            connectivity: ConnectivityManager()
        )

        let projectId = "5f90388c-69af-4bb9-ba26-f8d74487d344"
        let deckArtifact = SiteVisitCaptureArtifact.durabilityFixture(
            kind: .deckDesign,
            deckDesignId: deck.id,
            capturedAt: Date(timeIntervalSince1970: 1)
        )
        let payload = SiteVisitProjectPayloadBuilder.payload(
            siteVisitId: "visit-1",
            opportunityId: "lead-1",
            address: nil,
            artifacts: [deckArtifact]
        )

        SiteVisitProjectHandoff.apply(
            payload: payload,
            artifacts: [deckArtifact],
            projectId: projectId,
            companyId: "company-1",
            userId: "user-1",
            modelContext: context,
            syncEngine: syncEngine
        )

        XCTAssertEqual(deck.projectId, projectId)

        // The old code stopped at markForSync() — a flag no sweep ever read, so
        // the link never left the phone. A durable SyncOperation must exist.
        let ops = try context.fetch(FetchDescriptor<SyncOperation>())
            .filter { $0.entityType == SyncEntityType.deckDesign.rawValue }
        XCTAssertEqual(ops.count, 1, "attaching a deck at conversion must record a durable outbound operation")
        let op = try XCTUnwrap(ops.first)
        XCTAssertEqual(op.operationType, "update")
        XCTAssertEqual(op.entityId, deck.id)

        let opPayload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: op.payload) as? [String: Any]
        )
        XCTAssertEqual(opPayload["project_id"] as? String, projectId)
        XCTAssertNotNil(opPayload["updated_at"])
    }

    // MARK: - Staging-store loss: payload derives from persisted rows

    @MainActor
    func test_derivePayloadRebuildsPacketFromArtifactRowsWhenStoreLost() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let visit = SiteVisit(id: "visit-1", opportunityId: "lead-1", companyId: "company-1")
        context.insert(visit)

        let photo = SiteVisitCaptureArtifact.durabilityFixture(id: "photo-1", kind: .photo, capturedAt: Date(timeIntervalSince1970: 1))
        // Captured BEFORE the visit was bound to the lead — carries no
        // opportunityId of its own, and must still ride along via the visit.
        let preBindPhoto = SiteVisitCaptureArtifact.durabilityFixture(id: "photo-0", kind: .photo, opportunityId: nil, capturedAt: Date(timeIntervalSince1970: 2))
        let deckArtifact = SiteVisitCaptureArtifact.durabilityFixture(id: "deck-artifact-1", kind: .deckDesign, deckDesignId: "deck-9", capturedAt: Date(timeIntervalSince1970: 3))
        let excluded = SiteVisitCaptureArtifact.durabilityFixture(id: "photo-excluded", kind: .photo, capturedAt: Date(timeIntervalSince1970: 4))
        excluded.includedInProjectReview = false
        let deleted = SiteVisitCaptureArtifact.durabilityFixture(id: "photo-deleted", kind: .photo, capturedAt: Date(timeIntervalSince1970: 5))
        deleted.deletedAt = Date()
        [photo, preBindPhoto, deckArtifact, excluded, deleted].forEach { context.insert($0) }

        let answer = SiteVisitChecklistAnswer(
            id: "answer-1",
            siteVisitId: "visit-1",
            companyId: "company-1",
            opportunityId: "lead-1",
            siteVisitTypeId: "type-1",
            fieldId: "gate",
            label: "Gate code",
            kind: .shortText,
            required: false,
            sortOrder: 10,
            answerValue: .text("4812"),
            createdBy: "user-1"
        )
        context.insert(answer)
        try context.save()

        let derived = try XCTUnwrap(
            SiteVisitProjectHandoff.derivePayload(
                opportunityId: "lead-1",
                opportunityAddress: "972 Lyall St, Esquimalt",
                modelContext: context
            ),
            "with persisted site-visit evidence the payload must be derivable without the in-memory staging store"
        )

        XCTAssertEqual(derived.payload.siteVisitId, "visit-1")
        XCTAssertEqual(derived.payload.opportunityId, "lead-1")
        XCTAssertEqual(derived.payload.address, "972 Lyall St, Esquimalt")
        XCTAssertEqual(
            derived.payload.photoArtifactIds,
            ["photo-1", "photo-0"],
            "included photos ride in capture order; pre-bind captures on the bound visit are recovered too"
        )
        XCTAssertEqual(derived.payload.deckDesignIds, ["deck-9"])
        XCTAssertTrue(derived.payload.checklistLines.contains("CHECKLIST :: Gate code: 4812"))
        XCTAssertTrue(
            derived.artifacts.contains { $0.id == "photo-0" },
            "the artifact set handed to apply() must include visit-linked artifacts that never got the opportunity binding"
        )
    }

    @MainActor
    func test_derivePayloadFindsVisitViaArtifactBindingWhenVisitRowUnlinked() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // The visit row itself lost (or never had) the opportunity link, but
        // the artifacts carry it — derivation must still find the packet.
        let visit = SiteVisit(id: "visit-2", opportunityId: nil, companyId: "company-1")
        context.insert(visit)

        let photo = SiteVisitCaptureArtifact(
            id: "photo-2",
            siteVisitId: "visit-2",
            companyId: "company-1",
            opportunityId: "lead-2",
            kind: .photo,
            source: .camera,
            capturedAt: Date(timeIntervalSince1970: 1)
        )
        context.insert(photo)
        try context.save()

        let derived = try XCTUnwrap(
            SiteVisitProjectHandoff.derivePayload(
                opportunityId: "lead-2",
                opportunityAddress: nil,
                modelContext: context
            )
        )
        XCTAssertEqual(derived.payload.siteVisitId, "visit-2")
        XCTAssertEqual(derived.payload.photoArtifactIds, ["photo-2"])
    }

    @MainActor
    func test_derivePayloadReturnsNilWithoutSiteVisitEvidence() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // A visit with zero artifacts and zero answered checklist rows is not
        // evidence — conversion must not synthesize an empty packet.
        let visit = SiteVisit(id: "visit-3", opportunityId: "lead-3", companyId: "company-1")
        context.insert(visit)
        try context.save()

        XCTAssertNil(
            SiteVisitProjectHandoff.derivePayload(
                opportunityId: "lead-3",
                opportunityAddress: nil,
                modelContext: context
            )
        )
        XCTAssertNil(
            SiteVisitProjectHandoff.derivePayload(
                opportunityId: "lead-never-visited",
                opportunityAddress: nil,
                modelContext: context
            )
        )
    }

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
            SiteVisitChecklistAnswer.self,
            ProjectPhoto.self,
            ProjectNote.self,
            PhotoAnnotation.self,
            DeckDesign.self,
            SyncOperation.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func fixtureDimensionsJSON() throws -> String {
        var dimensions = DimensionsData(
            captureMode: .lidar,
            calibration: .init(method: .lidar, estimatedAccuracyMeters: 0.025),
            intrinsics: .init(fx: 1000, fy: 1000, cx: 500, cy: 500, imageWidth: 1000, imageHeight: 1000),
            measurements: []
        )
        dimensions.sidecarMetadataUrl = "file:///tmp/handoff-durability.metadata.json"
        let data = try DimensionsData.jsonEncoder.encode(dimensions)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}

private extension SiteVisitCaptureArtifact {
    static func durabilityFixture(
        id: String = UUID().uuidString,
        kind: SiteVisitCaptureArtifactKind,
        opportunityId: String? = "lead-1",
        deckDesignId: String? = nil,
        capturedAt: Date
    ) -> SiteVisitCaptureArtifact {
        SiteVisitCaptureArtifact(
            id: id,
            siteVisitId: "visit-1",
            companyId: "company-1",
            opportunityId: opportunityId,
            kind: kind,
            source: kind == .dimensionedPhoto ? .lidar : .camera,
            title: kind.rawValue,
            deckDesignId: deckDesignId,
            capturedAt: capturedAt,
            createdBy: "user-1"
        )
    }
}
