//
//  LeadPhotoOptimisticDisplayTests.swift
//  OPSTests
//
//  Regression coverage for bug 9764f289-f118-4f5d-ad3d-2234af0a64a4:
//  picker reservations must become durable local thumbnails before upload,
//  without changing position or losing photos queued during a drain.
//

import XCTest
import UIKit
@testable import OPS

final class LeadPhotoOptimisticDisplayTests: XCTestCase {

    @MainActor
    func test_stageImagesPublishesAndPersistsWholeBatchInSelectionOrder() {
        let suiteName = "LeadPhotoOptimisticDisplayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = LeadImageService(
            defaults: defaults,
            backgroundWorkEnabled: false
        )
        let reservationIDs = ["reservation-first", "reservation-second"]

        let result = service.stageImages(
            [fixtureImage(color: .red), fixtureImage(color: .blue)],
            opportunityId: "lead-1",
            companyId: "company-1",
            reservationIDs: reservationIDs
        )

        let queued = service.queuedUploads(for: "lead-1")
        defer {
            for upload in queued where upload.localURL.hasPrefix("local://") {
                _ = ImageFileManager.shared.deleteImage(localID: upload.localURL)
            }
        }

        XCTAssertEqual(result.queuedCount, 2)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(queued.map(\.id), reservationIDs)
        XCTAssertEqual(queued.map(\.batchIndex), [0, 1])
        XCTAssertTrue(queued.allSatisfy { service.queuedImage(for: $0) != nil })

        let persistedData = defaults.data(forKey: "pendingLeadImageUploads")
        let persisted = try? persistedData.flatMap {
            try JSONDecoder().decode([PendingLeadImageUpload].self, from: $0)
        }
        XCTAssertEqual(persisted?.map(\.id), reservationIDs)
    }

    func test_stripPresentationReplacesMatchingReservationWithoutMovingItsPosition() {
        let stagedFirst = PendingLeadImageUpload(
            localURL: "local://project_images/lead_lead-1_first.jpg",
            opportunityId: "lead-1",
            companyId: "company-1",
            timestamp: Date(timeIntervalSince1970: 100),
            displayID: "reservation-first",
            batchIndex: 0
        )

        let items = LeadPhotoStripPresentation.items(
            reservationIDs: ["reservation-first", "reservation-second"],
            queued: [stagedFirst],
            remoteURLs: ["https://example.test/existing.jpg"]
        )

        XCTAssertEqual(
            items.map(\.id),
            ["reservation-first", "reservation-second", "https://example.test/existing.jpg"]
        )
        XCTAssertEqual(items[0], .photo(.queued(stagedFirst)))
        XCTAssertEqual(items[1], .importing("reservation-second"))
    }

    func test_storedEmailPhotosFollowManualPhotosAndCannotBeDeleted() {
        let attachment = LeadAttachment(
            id: "attachment-1",
            filename: "site.jpg",
            mimeType: "image/jpeg",
            sourceUrl: nil,
            fromEmail: "client@example.com",
            ingestStatus: "stored",
            occurredAt: "2026-08-07T12:00:00Z",
            createdAt: "2026-08-07T12:00:00Z"
        )

        let items = LeadPhotoStripPresentation.items(
            reservationIDs: [],
            queued: [],
            remoteURLs: [
                "  https://example.test/manual.jpg  ",
                "  https://example.test/manual.jpg  ",
                "   "
            ],
            emailPhotoAttachments: [attachment]
        )

        XCTAssertEqual(
            items.map(\.id),
            ["https://example.test/manual.jpg", "email:attachment-1"]
        )
        XCTAssertFalse(LeadPhotoItem.emailAttachment(attachment).canDeleteFromLead)
        guard case .photo(.remote(let remotePhoto)) = items[0] else {
            return XCTFail("Expected normalized manual photo first")
        }
        XCTAssertEqual(remotePhoto.displayURL, "https://example.test/manual.jpg")
        XCTAssertEqual(remotePhoto.storedURL, "  https://example.test/manual.jpg  ")
        XCTAssertTrue(LeadPhotoItem.remote(remotePhoto).canDeleteFromLead)
    }

    func test_drainReconciliationPreservesPhotoQueuedAfterSnapshot() {
        let snapshotItem = pending(localURL: "local://project_images/snapshot.jpg")
        let failedSnapshotItem = pending(localURL: "local://project_images/failed.jpg")
        let newlyQueuedItem = pending(localURL: "local://project_images/new.jpg")

        let reconciled = LeadImagePendingQueue.reconciling(
            current: [snapshotItem, newlyQueuedItem],
            drainedSnapshot: [snapshotItem],
            stillPendingFromSnapshot: [failedSnapshotItem]
        )

        XCTAssertEqual(reconciled, [failedSnapshotItem, newlyQueuedItem])
    }

    @MainActor
    private func fixtureImage(color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
    }

    private func pending(localURL: String) -> PendingLeadImageUpload {
        PendingLeadImageUpload(
            localURL: localURL,
            opportunityId: "lead-1",
            companyId: "company-1",
            timestamp: Date(timeIntervalSince1970: 100)
        )
    }
}
