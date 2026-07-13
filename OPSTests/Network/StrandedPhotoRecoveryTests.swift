//
//  StrandedPhotoRecoveryTests.swift
//  OPSTests
//
//  Recovery pipeline for phone-local project photos (Carol Dancer case).
//
//  A ProjectPhoto row with url `local://…` + needsSync = true is a photo whose
//  bytes exist ONLY on the capturing phone — no server backfill can restore
//  them. The recovery contract:
//    1. `enqueueExistingLocalImage` puts an already-saved local file into the
//       restart-surviving pending-upload queue.
//    2. `reconcileStrandedProjectPhotos` sweeps stranded rows into that queue
//       on every drain pass (startup + reconnect), excluding rows owned by the
//       dimensioned-annotation pipeline (which uploads them itself).
//    3. On drain, the server insert carries the row's own identity + metadata
//       and NEVER site_visit_id (iOS visit ids have no server row — the FK
//       would reject the insert), then the local row heals in place
//       (local:// → S3) so the URL-deduped gallery never double-tiles.
//

import XCTest
import SwiftData
@testable import OPS

final class StrandedPhotoRecoveryTests: XCTestCase {

    private var savedLocalIDs: [String] = []
    private var priorPendingUploads: Data?

    override func setUp() {
        super.setUp()
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

    // MARK: - Durable enqueue of pre-existing local files

    @MainActor
    func test_enqueueExistingLocalImage_appendsOnceAndRequiresLocalBytes() {
        let manager = ImageSyncManager(modelContext: nil, connectivity: ConnectivityManager())

        let url = "local://project_images/stranded_recovery_a.jpg"
        saveLocalBytes(for: url)

        manager.enqueueExistingLocalImage(localURL: url, projectId: "p1", companyId: "c1")
        XCTAssertEqual(manager.getPendingUploads().map(\.localURL), [url])
        XCTAssertEqual(manager.getPendingUploads().first?.projectId, "p1")
        XCTAssertEqual(manager.getPendingUploads().first?.companyId, "c1")

        // Re-enqueueing the same file must not double it.
        manager.enqueueExistingLocalImage(localURL: url, projectId: "p1", companyId: "c1")
        XCTAssertEqual(manager.getPendingUploads().count, 1)

        // A file with no bytes on disk can never upload — refuse it.
        manager.enqueueExistingLocalImage(
            localURL: "local://project_images/stranded_recovery_missing.jpg",
            projectId: "p1",
            companyId: "c1"
        )
        XCTAssertEqual(manager.getPendingUploads().count, 1)

        // Remote URLs have nothing to upload.
        manager.enqueueExistingLocalImage(
            localURL: "https://ops-app.s3.amazonaws.com/already-there.jpg",
            projectId: "p1",
            companyId: "c1"
        )
        XCTAssertEqual(manager.getPendingUploads().count, 1)
    }

    // MARK: - Startup / reconnect sweep

    @MainActor
    func test_reconcileStrandedProjectPhotos_enqueuesEligibleRowsOnly() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let eligibleURL = "local://project_images/stranded_sweep_eligible.jpg"
        let claimedURL = "local://project_images/stranded_sweep_dimensioned.heic"
        let missingBytesURL = "local://project_images/stranded_sweep_missing.jpg"
        saveLocalBytes(for: eligibleURL)
        saveLocalBytes(for: claimedURL)

        let eligible = makePhotoRow(url: eligibleURL, projectId: "p1", companyId: "c1")

        // Claimed by a pending dimensioned annotation: that pipeline uploads the
        // HEIC and inserts the project_photos row itself, then heals this row —
        // sweeping it here too would upload the same photo twice.
        let claimed = makePhotoRow(url: claimedURL, projectId: "p1", companyId: "c1")
        let claimingAnnotation = PhotoAnnotation(
            projectId: "p1",
            companyId: "c1",
            photoURL: claimedURL,
            authorId: "user-1"
        )
        claimingAnnotation.needsSync = true

        let remote = makePhotoRow(url: "https://ops-app.s3.amazonaws.com/x.jpg", projectId: "p1", companyId: "c1")
        let missingBytes = makePhotoRow(url: missingBytesURL, projectId: "p1", companyId: "c1")
        let alreadySynced = makePhotoRow(url: "local://project_images/stranded_sweep_synced.jpg", projectId: "p1", companyId: "c1")
        alreadySynced.needsSync = false
        let softDeleted = makePhotoRow(url: eligibleURL + ".deleted.jpg", projectId: "p1", companyId: "c1")
        softDeleted.deletedAt = Date()

        [eligible, claimed, remote, missingBytes, alreadySynced, softDeleted].forEach { context.insert($0) }
        context.insert(claimingAnnotation)
        try context.save()

        let manager = ImageSyncManager(modelContext: context, connectivity: ConnectivityManager())
        manager.reconcileStrandedProjectPhotos()

        XCTAssertEqual(
            manager.getPendingUploads().map(\.localURL),
            [eligibleURL],
            "only stranded local rows with recoverable bytes and no annotation-pipeline claim belong in the upload queue"
        )
        XCTAssertEqual(manager.getPendingUploads().first?.projectId, "p1")

        // Idempotent — a second sweep must not duplicate the queue entry.
        manager.reconcileStrandedProjectPhotos()
        XCTAssertEqual(manager.getPendingUploads().count, 1)
    }

    // MARK: - Drain: server insert payload contract

    @MainActor
    func test_handoffPhotoInsertPayload_carriesRowMetadataAndNeverSiteVisitId() throws {
        let row = ProjectPhoto(
            id: "9A1B2C3D-4E5F-4A6B-8C7D-0E1F2A3B4C5D",
            projectId: "5f90388c-69af-4bb9-ba26-f8d74487d344",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            url: "local://project_images/site_visit_visit-1_plain.jpg",
            source: "site_visit",
            siteVisitId: "0FA0DB2A-SITE-VISIT-LOCAL-ID",
            uploadedBy: "",
            caption: "Site photo",
            takenAt: Date(timeIntervalSince1970: 1_752_400_000)
        )
        row.needsSync = true

        let remoteURL = "https://ops-app.s3.amazonaws.com/companies/a612edc0/projects/5f90388c/photo.jpg"
        let insert = ImageSyncManager.handoffPhotoInsert(for: row, remoteURL: remoteURL)

        XCTAssertEqual(insert.id, "9a1b2c3d-4e5f-4a6b-8c7d-0e1f2a3b4c5d", "the row id travels lowercased so the server echo merges into the same local row")
        XCTAssertEqual(insert.url, remoteURL)
        XCTAssertEqual(insert.source, "site_visit", "provenance survives the drain — the row must not degrade to 'in_progress'")
        XCTAssertEqual(insert.caption, "Site photo")
        XCTAssertNotNil(insert.takenAt)
        XCTAssertNil(insert.uploadedBy, "an empty uploader must be omitted — project_photos.uploaded_by is a uuid column and an empty string 22P02s the whole insert")

        // THE trap: iOS SiteVisit ids are local-only (UPPERCASE, no server
        // site_visits row). Sending site_visit_id would FK-reject the insert.
        let encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(insert)
        ) as? [String: Any]
        let keys = Set(try XCTUnwrap(encoded).keys)
        XCTAssertFalse(keys.contains("site_visit_id"), "site_visit_id must be structurally impossible in the handoff insert")
        XCTAssertTrue(keys.contains("project_id"))
        XCTAssertTrue(keys.contains("company_id"))
        XCTAssertFalse(keys.contains("uploaded_by"), "nil uploader encodes as an omitted key, not null")

        // A real uploader id is carried through.
        let attributed = ProjectPhoto(
            projectId: "p1",
            companyId: "c1",
            url: "local://project_images/x.jpg",
            source: "site_visit",
            uploadedBy: "9f4ca7fb-f4fc-4942-96f0-02723d1ff99f"
        )
        XCTAssertEqual(
            ImageSyncManager.handoffPhotoInsert(for: attributed, remoteURL: remoteURL).uploadedBy,
            "9f4ca7fb-f4fc-4942-96f0-02723d1ff99f"
        )
    }

    // MARK: - Drain: local row heals in place

    @MainActor
    func test_healHandoffPhotoRow_swapsURLInPlaceAndClearsNeedsSync() {
        let localURL = "local://project_images/site_visit_visit-1_markup.rendered.jpg"
        let row = ProjectPhoto(
            id: "9A1B2C3D-4E5F-4A6B-8C7D-0E1F2A3B4C5D",
            projectId: "p1",
            companyId: "c1",
            url: localURL,
            renderedURL: localURL,
            source: "site_visit",
            uploadedBy: "user-1"
        )
        row.needsSync = true

        let remoteURL = "https://ops-app.s3.amazonaws.com/photo.jpg"
        ImageSyncManager.healHandoffPhotoRow(row, remoteURL: remoteURL)

        XCTAssertEqual(row.url, remoteURL, "the row must heal IN PLACE — the gallery dedupes by URL, so replacing the row instead of its url would double-tile")
        XCTAssertEqual(row.renderedURL, remoteURL, "a rendered URL pointing at the same local file follows the swap")
        XCTAssertFalse(row.needsSync)
        XCTAssertNotNil(row.lastSyncedAt)
        XCTAssertEqual(row.id, "9a1b2c3d-4e5f-4a6b-8c7d-0e1f2a3b4c5d", "the id lowercases with the heal so the server echo matches this row")

        // A row with no rendered variant stays that way.
        let plain = ProjectPhoto(projectId: "p1", companyId: "c1", url: localURL, uploadedBy: "user-1")
        plain.needsSync = true
        ImageSyncManager.healHandoffPhotoRow(plain, remoteURL: remoteURL)
        XCTAssertNil(plain.renderedURL)
        XCTAssertFalse(plain.needsSync)
    }

    // MARK: - Dimensioned pipeline heals its own handoff rows

    @MainActor
    func test_healHandoffPhotoRows_dimensionedSyncSuccessHealsMatchingRow() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let localURL = "local://project_images/site_visit_dimensioned_ABC.heic"
        let matching = makePhotoRow(url: localURL, projectId: "p1", companyId: "c1")
        let unrelated = makePhotoRow(url: "local://project_images/other.jpg", projectId: "p1", companyId: "c1")
        context.insert(matching)
        context.insert(unrelated)
        try context.save()

        DimensionedPhotoSyncManager.healHandoffPhotoRows(
            matching: localURL,
            heicURL: "https://ops-app.s3.amazonaws.com/measurements/c1/p1/ABC.heic",
            renderedURL: "https://ops-app.s3.amazonaws.com/measurements/c1/p1/ABC.rendered.png",
            in: context
        )

        XCTAssertEqual(matching.url, "https://ops-app.s3.amazonaws.com/measurements/c1/p1/ABC.heic")
        XCTAssertEqual(matching.renderedURL, "https://ops-app.s3.amazonaws.com/measurements/c1/p1/ABC.rendered.png")
        XCTAssertFalse(matching.needsSync)
        XCTAssertEqual(unrelated.url, "local://project_images/other.jpg")
        XCTAssertTrue(unrelated.needsSync)

        // Guard: a non-local match target is a programming error — no-op.
        DimensionedPhotoSyncManager.healHandoffPhotoRows(
            matching: "https://ops-app.s3.amazonaws.com/measurements/c1/p1/ABC.heic",
            heicURL: "https://elsewhere.example/x.heic",
            renderedURL: nil,
            in: context
        )
        XCTAssertEqual(matching.url, "https://ops-app.s3.amazonaws.com/measurements/c1/p1/ABC.heic")
    }

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ProjectPhoto.self, PhotoAnnotation.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makePhotoRow(url: String, projectId: String, companyId: String) -> ProjectPhoto {
        let row = ProjectPhoto(
            id: UUID().uuidString.lowercased(),
            projectId: projectId,
            companyId: companyId,
            url: url,
            source: "site_visit",
            uploadedBy: "user-1"
        )
        row.needsSync = true
        return row
    }
}
