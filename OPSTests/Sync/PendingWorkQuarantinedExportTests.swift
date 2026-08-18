//
//  PendingWorkQuarantinedExportTests.swift
//  OPSTests
//
//  A quarantined site-visit packet's EXPORT is the operator's explicit recovery
//  path for work the server will never accept again (deleted-parent custody).
//  The share payload must carry the captured media bytes that exist only on
//  this phone — a summary alone would export everything except the thing that
//  matters — plus the visit's own notes. The row copy must also say WHY the
//  packet is held, not just that it is.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class PendingWorkQuarantinedExportTests: XCTestCase {
    private var liveContainers: [ModelContainer] = []

    private let userId = "d2222222-2222-4222-8222-222222222222"
    private let companyId = "d1111111-1111-4111-8111-111111111111"
    private let visitId = "d3333333-3333-4333-8333-333333333333"

    override func tearDown() {
        liveContainers.removeAll()
        super.tearDown()
    }

    func test_quarantinedVisitExportCarriesLocalMediaFilesAndVisitNotes() throws {
        let context = try makeContainer().mainContext
        let mediaRoot = try makeTemporaryDirectory()

        let markupURL = mediaRoot.appendingPathComponent("site_visit_markup.jpg")
        try Data("rendered-markup-bytes".utf8).write(to: markupURL)
        let missingURL = mediaRoot.appendingPathComponent("gone.jpg")

        let visit = SiteVisit(
            id: visitId,
            companyId: companyId,
            status: .completed,
            scheduledAt: Date(timeIntervalSince1970: 1_700_000_000),
            createdBy: userId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        visit.notes = "Deck measurements confirmed with Charles on site"
        context.insert(visit)

        let artifact = SiteVisitCaptureArtifact(
            siteVisitId: visitId,
            companyId: companyId,
            kind: .photo,
            source: .camera,
            localAssetURL: "https://cdn.example.com/original.jpg",
            createdBy: userId
        )
        artifact.renderedAssetURL = markupURL.path
        artifact.thumbnailURL = missingURL.path
        context.insert(artifact)

        let snapshot = QuarantinedSiteVisitSnapshot(
            id: "site-visit-quarantine:parent_deleted:\(companyId):\(visitId)",
            userId: userId,
            companyId: companyId,
            siteVisitId: visitId,
            reason: .parentDeleted,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            capturedItemCount: 1
        )

        let payload = PendingWorkExport.build(
            item: .quarantinedVisit(snapshot),
            modelContext: context,
            now: Date(timeIntervalSince1970: 1_700_100_000)
        )

        let exportedURLs = payload.activityItems.compactMap { $0 as? URL }
        XCTAssertTrue(
            exportedURLs.contains { $0.path == markupURL.path },
            "The rendered markup — the only copy anywhere — must ship with the export"
        )
        XCTAssertFalse(
            exportedURLs.contains { $0.path == missingURL.path },
            "A pointer whose file is gone must not become a dead share item"
        )
        XCTAssertFalse(
            exportedURLs.contains { $0.absoluteString.contains("cdn.example.com") },
            "Remote URLs are already durable in OPS — not part of the phone-only export"
        )

        let summary = try XCTUnwrap(payload.activityItems.first as? String)
        XCTAssertTrue(
            summary.contains("Deck measurements confirmed with Charles on site"),
            "The visit's own notes belong in the export summary"
        )
    }

    func test_quarantinedRowStatusLineNamesTheDeletedParentReason() {
        let parentDeleted = QuarantinedSiteVisitSnapshot(
            id: "site-visit-quarantine:parent_deleted:\(companyId):\(visitId)",
            userId: userId,
            companyId: companyId,
            siteVisitId: visitId,
            reason: .parentDeleted,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            capturedItemCount: 1
        )
        let line = PendingWorkVisuals.statusLine(
            for: .quarantinedVisit(parentDeleted),
            now: Date(timeIntervalSince1970: 1_700_100_000)
        )
        XCTAssertEqual(line.text, "Deleted in OPS — kept on this phone")
        XCTAssertEqual(line.tone, .stuck)

        let identityReview = QuarantinedSiteVisitSnapshot(
            id: "site-visit-quarantine:foreign_company:\(companyId):\(visitId)",
            userId: userId,
            companyId: companyId,
            siteVisitId: visitId,
            reason: .foreignCompany,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            capturedItemCount: 1
        )
        let genericLine = PendingWorkVisuals.statusLine(
            for: .quarantinedVisit(identityReview),
            now: Date(timeIntervalSince1970: 1_700_100_000)
        )
        XCTAssertEqual(genericLine.text, SyncStatusCopy.PendingWork.quarantineRow)
    }

    // MARK: - Harness

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        liveContainers.append(container)
        return container
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
