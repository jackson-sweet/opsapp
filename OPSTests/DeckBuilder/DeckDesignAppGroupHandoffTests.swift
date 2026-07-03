//
//  DeckDesignAppGroupHandoffTests.swift
//  OPSTests
//
//  Verifies that the main OPS app can consume Deckset's App Group handoff
//  records without pulling the standalone designer into OPS.
//

import SwiftData
import XCTest
@testable import OPS

final class DeckDesignAppGroupHandoffTests: XCTestCase {
    private let companyId = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let projectId = "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1"
    private let deckId = "c0509774-2748-479f-92e7-ee7d5dcff14e"

    func testRecordDecodesDecksetSnakeCaseContract() throws {
        let payload = """
        {
          "format_version": 1,
          "deck_id": "\(deckId)",
          "company_id": "\(companyId.uppercased())",
          "project_id": "\(projectId.uppercased())",
          "title": "Deckset field capture",
          "drawing_data": {
            "vertices": [
              { "id": "v1", "position": [0, 0], "elevationSource": "manual" },
              { "id": "v2", "position": [120, 0], "elevationSource": "manual" },
              { "id": "v3", "position": [120, 120], "elevationSource": "manual" },
              { "id": "v4", "position": [0, 120], "elevationSource": "manual" }
            ],
            "edges": [
              { "id": "e1", "startVertexId": "v1", "endVertexId": "v2", "edgeType": "deck_edge", "dimensionSource": "manual", "assignedItems": [], "dimensionStale": false },
              { "id": "e2", "startVertexId": "v2", "endVertexId": "v3", "edgeType": "deck_edge", "dimensionSource": "manual", "assignedItems": [], "dimensionStale": false },
              { "id": "e3", "startVertexId": "v3", "endVertexId": "v4", "edgeType": "deck_edge", "dimensionSource": "manual", "assignedItems": [], "dimensionStale": false },
              { "id": "e4", "startVertexId": "v4", "endVertexId": "v1", "edgeType": "deck_edge", "dimensionSource": "manual", "assignedItems": [], "dimensionStale": false }
            ],
            "footprint": { "assignedItems": [], "isClosed": true },
            "config": {
              "measurementSystem": "imperial",
              "angleSnapIncrement": 15,
              "lengthSnapIncrement": 6,
              "snappingEnabled": true,
              "endpointSnapRadius": 20,
              "gridVisible": true
            },
            "levels": [],
            "levelConnections": [],
            "scaleFactor": 1
          },
          "deck_schema_version": 7,
          "source_app": "deckset",
          "created_at": "2026-07-02T10:15:30Z",
          "updated_at": "2026-07-02T10:20:30Z"
        }
        """

        let record = try DeckDesignHandoffRecord.decoder.decode(
            DeckDesignHandoffRecord.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(record.formatVersion, 1)
        XCTAssertEqual(record.deckId, deckId)
        XCTAssertEqual(record.companyId, companyId.uppercased())
        XCTAssertEqual(record.projectId, projectId.uppercased())
        XCTAssertEqual(record.sourceApp, .deckset)
        XCTAssertEqual(record.deckSchemaVersion, 7)
        XCTAssertEqual(record.drawingData?.vertices.count, 4)
        XCTAssertEqual(record.drawingData?.edges.count, 4)
        XCTAssertFalse(record.isDeleted)
    }

    func testImporterCreatesDeckDesignForCurrentCompanyOnly() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let store = try DeckDesignAppGroupHandoffStore(directory: temporaryDirectory())

        var drawing = squareDrawing()
        drawing.scaleFactor = 2

        try store.upsert(
            DeckDesignHandoffRecord(
                deckId: deckId,
                companyId: companyId.uppercased(),
                projectId: projectId.uppercased(),
                title: "Deckset import",
                drawingData: drawing,
                deckSchemaVersion: 7,
                sourceApp: .deckset,
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200),
                deletedAt: nil
            )
        )
        try store.upsert(
            DeckDesignHandoffRecord(
                deckId: "11111111-1111-4111-8111-111111111111",
                companyId: "22222222-2222-4222-8222-222222222222",
                projectId: nil,
                title: "Wrong company",
                drawingData: drawing,
                deckSchemaVersion: 7,
                sourceApp: .deckset,
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200),
                deletedAt: nil
            )
        )

        let summary = try DeckDesignAppGroupImporter(store: store)
            .importDecks(into: context, companyId: companyId)

        XCTAssertEqual(summary.created, 1)
        XCTAssertEqual(summary.updated, 0)
        XCTAssertEqual(summary.skippedCompanyMismatch, 1)

        let designs = try context.fetch(FetchDescriptor<DeckDesign>())
        XCTAssertEqual(designs.count, 1)
        let imported = try XCTUnwrap(designs.first)
        XCTAssertEqual(imported.id, deckId)
        XCTAssertEqual(imported.companyId, companyId)
        XCTAssertEqual(imported.projectId, projectId)
        XCTAssertEqual(imported.title, "Deckset import")
        XCTAssertEqual(imported.drawingData.vertices.count, 4)
        XCTAssertEqual(imported.drawingData.scaleFactor, 2)
        XCTAssertEqual(imported.updatedAt, Date(timeIntervalSince1970: 200))
        XCTAssertTrue(imported.needsSync, "Deckset handoff imports should queue for OPS sync once network is available.")
    }

    func testImporterAppliesTombstoneToExistingDeck() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let store = try DeckDesignAppGroupHandoffStore(directory: temporaryDirectory())

        let existing = DeckDesign(
            id: deckId,
            companyId: companyId,
            projectId: projectId,
            title: "Existing",
            drawingDataJSON: squareDrawing().toJSON()
        )
        existing.updatedAt = Date(timeIntervalSince1970: 200)
        existing.needsSync = false
        context.insert(existing)
        try context.save()

        let deletedAt = Date(timeIntervalSince1970: 300)
        try store.upsert(
            DeckDesignHandoffRecord(
                deckId: deckId,
                companyId: companyId,
                projectId: projectId,
                title: "Existing",
                drawingData: nil,
                deckSchemaVersion: 7,
                sourceApp: .deckset,
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200),
                deletedAt: deletedAt
            )
        )

        let summary = try DeckDesignAppGroupImporter(store: store)
            .importDecks(into: context, companyId: companyId)

        XCTAssertEqual(summary.deleted, 1)
        XCTAssertEqual(existing.deletedAt, deletedAt)
        XCTAssertTrue(existing.needsSync)
    }

    func testImporterDoesNotOverwriteNewerLocalDeck() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let store = try DeckDesignAppGroupHandoffStore(directory: temporaryDirectory())

        let existing = DeckDesign(
            id: deckId,
            companyId: companyId,
            projectId: projectId,
            title: "Newer local edit",
            drawingDataJSON: squareDrawing().toJSON()
        )
        existing.updatedAt = Date(timeIntervalSince1970: 500)
        existing.needsSync = true
        context.insert(existing)
        try context.save()

        try store.upsert(
            DeckDesignHandoffRecord(
                deckId: deckId,
                companyId: companyId,
                projectId: projectId,
                title: "Older Deckset edit",
                drawingData: DeckDrawingData(),
                deckSchemaVersion: 7,
                sourceApp: .deckset,
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200),
                deletedAt: nil
            )
        )

        let summary = try DeckDesignAppGroupImporter(store: store)
            .importDecks(into: context, companyId: companyId)

        XCTAssertEqual(summary.skippedOlderRecord, 1)
        XCTAssertEqual(existing.title, "Newer local edit")
        XCTAssertEqual(existing.drawingData.vertices.count, 4)
        XCTAssertTrue(existing.needsSync)
    }

    private func squareDrawing() -> DeckDrawingData {
        var drawing = DeckDrawingData()
        drawing.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120))
        ]
        drawing.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1")
        ]
        drawing.scaleFactor = 1
        return drawing
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([DeckDesign.self, SyncOperation.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
