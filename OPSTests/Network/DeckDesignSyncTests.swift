//
//  DeckDesignSyncTests.swift
//  OPSTests
//
//  Regression coverage for repaired deck_designs rows whose project_id was
//  restored server-side after an iOS device had already cached them as
//  standalone sketches.
//

import SwiftData
import XCTest
@testable import OPS

final class DeckDesignSyncTests: XCTestCase {

    func test_DeckDesignInitializer_canonicalizesUUIDIdentifiersForSupabaseEchoes() throws {
        let design = DeckDesign(
            id: "C0509774-2748-479F-92E7-EE7D5DCFF14E",
            companyId: "A612EDC0-5C18-4C4D-AF97-55B9410DD077",
            projectId: "1AD4822D-2A9F-4E0A-A9C1-2CCFA7B142D1",
            title: "Untitled Deck"
        )

        XCTAssertEqual(design.id, "c0509774-2748-479f-92e7-ee7d5dcff14e")
        XCTAssertEqual(design.companyId, "a612edc0-5c18-4c4d-af97-55b9410dd077")
        XCTAssertEqual(design.projectId, "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1")

        let nonUUID = DeckDesign(
            id: "DEMO-DECK-ID",
            companyId: "test-company-001",
            projectId: "DEMO_PROJECT_1",
            title: "Tutorial Deck"
        )

        XCTAssertEqual(nonUUID.id, "DEMO-DECK-ID")
        XCTAssertEqual(nonUUID.companyId, "test-company-001")
        XCTAssertEqual(nonUUID.projectId, "DEMO_PROJECT_1")
    }

    // MARK: - Stale-overwrite guard (deck-revert data loss)

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// A locally-edited deck (renamed level + fresh geometry, not yet converged)
    /// must NOT be reverted by an inbound snapshot that is older than the local
    /// row — the exact LUPIN data-loss path where a replica-lagged delta re-pull
    /// overwrote a just-saved deck.
    func test_applyServerSnapshot_ignoresStaleOlderServerSnapshot() throws {
        // Closed square (4 verts + 4 edges) so the geometry survives the JSON
        // round-trip — orphan (edgeless) vertices are pruned on decode.
        var localDrawing = DeckDrawingData()
        localDrawing.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120))
        ]
        localDrawing.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1")
        ]
        localDrawing.scaleFactor = 1
        let local = DeckDesign(
            id: "deck-stale",
            companyId: "c1",
            projectId: "p1",
            title: "Renamed Level",
            drawingDataJSON: localDrawing.toJSON(),
            createdBy: nil
        )
        local.updatedAt = Date()          // saved "now"
        local.needsSync = true            // push not yet converged

        // Server snapshot is 10 minutes OLDER, with the reverted (empty) geometry.
        let staleDTO = SupabaseDeckDesignDTO(
            id: "deck-stale", companyId: "c1", projectId: "p1", title: "Untitled Deck",
            drawingData: DeckDrawingData(), thumbnailUrl: nil, version: 1, createdBy: nil,
            createdAt: "2026-06-19T19:00:00Z",
            updatedAt: iso(Date().addingTimeInterval(-600)),
            deletedAt: nil
        )

        local.applyServerSnapshot(staleDTO, accepting: Set(DeckDesign.serverMergeFields))

        XCTAssertEqual(local.title, "Renamed Level", "stale snapshot must not revert the title")
        XCTAssertEqual(local.drawingData.vertices.count, 4, "stale snapshot must not discard local geometry")
    }

    /// A genuinely NEWER server edit must still apply normally — the guard only
    /// blocks stale/echoed snapshots, never legitimate remote updates.
    func test_applyServerSnapshot_appliesGenuinelyNewerServerSnapshot() throws {
        let local = DeckDesign(
            id: "deck-newer",
            companyId: "c1",
            projectId: "p1",
            title: "Old Title",
            drawingDataJSON: DeckDrawingData().toJSON(),
            createdBy: nil
        )
        local.updatedAt = Date().addingTimeInterval(-600)   // local is older
        local.needsSync = false

        // Closed triangle (3 verts + 3 edges) so it survives the round-trip.
        var newerDrawing = DeckDrawingData()
        newerDrawing.vertices = [
            DeckVertex(id: "a", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "b", position: CGPoint(x: 100, y: 0)),
            DeckVertex(id: "c", position: CGPoint(x: 0, y: 100))
        ]
        newerDrawing.edges = [
            DeckEdge(id: "ea", startVertexId: "a", endVertexId: "b"),
            DeckEdge(id: "eb", startVertexId: "b", endVertexId: "c"),
            DeckEdge(id: "ec", startVertexId: "c", endVertexId: "a")
        ]
        newerDrawing.scaleFactor = 1
        let newerDTO = SupabaseDeckDesignDTO(
            id: "deck-newer", companyId: "c1", projectId: "p1", title: "New Title",
            drawingData: newerDrawing, thumbnailUrl: nil, version: 2, createdBy: nil,
            createdAt: "2026-06-19T19:00:00Z",
            updatedAt: iso(Date()),
            deletedAt: nil
        )

        local.applyServerSnapshot(newerDTO, accepting: Set(DeckDesign.serverMergeFields))

        XCTAssertEqual(local.title, "New Title", "a newer server edit must still apply")
        XCTAssertEqual(local.drawingData.vertices.count, 3)
    }

    func test_DataActorRealtimeDeckDesignMerge_attachesExistingStandaloneDesignToServerProject() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let designId = "c0509774-2748-479f-92e7-ee7d5dcff14e"
        let companyId = "a612edc0-5c18-4c4d-af97-55b9410dd077"
        let projectId = "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1"

        let standalone = DeckDesign(
            id: designId,
            companyId: companyId,
            projectId: nil,
            title: "Untitled Deck",
            drawingDataJSON: DeckDrawingData().toJSON(),
            createdBy: nil
        )
        standalone.needsSync = false
        context.insert(standalone)
        try context.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()

        var drawing = DeckDrawingData()
        let v1 = DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0))
        let v3 = DeckVertex(id: "v3", position: CGPoint(x: 120, y: 120))
        let v4 = DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120))
        drawing.vertices = [v1, v2, v3, v4]
        drawing.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1")
        ]
        drawing.scaleFactor = 1

        let dto = SupabaseDeckDesignDTO(
            id: designId,
            companyId: companyId,
            projectId: projectId,
            title: "Untitled Deck",
            drawingData: drawing,
            thumbnailUrl: nil,
            version: 2,
            createdBy: "9f4ca7fb-f4fc-4942-96f0-02723d1ff99f",
            createdAt: "2026-05-06T20:57:35Z",
            updatedAt: "2026-05-13T00:16:41Z",
            deletedAt: nil
        )

        await actor.handleRealtimeUpdate(.deckDesign(dto))

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<DeckDesign>(
            predicate: #Predicate { $0.id == designId }
        )
        let merged = try XCTUnwrap(try verificationContext.fetch(descriptor).first)
        XCTAssertEqual(merged.projectId, projectId)
        XCTAssertEqual(merged.companyId, companyId)
        XCTAssertEqual(merged.version, 2)
        XCTAssertEqual(merged.drawingData.vertices.count, 4)
        XCTAssertNil(merged.deletedAt)
        XCTAssertFalse(merged.needsSync)
    }

    func test_DisplayCandidate_prefersGeometryDesignOverNewerEmptyPlaceholderAndMatchesProjectIdCaseInsensitively() throws {
        let projectId = "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1"
        let uppercasedProjectId = projectId.uppercased()

        let emptyPlaceholder = DeckDesign(
            id: "11111111-1111-4111-8111-111111111111",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: uppercasedProjectId,
            title: "Placeholder",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        emptyPlaceholder.updatedAt = Date(timeIntervalSince1970: 2_000)

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

        let restoredServerDesign = DeckDesign(
            id: "c0509774-2748-479f-92e7-ee7d5dcff14e",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: projectId,
            title: "Untitled Deck",
            drawingDataJSON: drawing.toJSON()
        )
        restoredServerDesign.updatedAt = Date(timeIntervalSince1970: 1_000)

        let selected = DeckDesign.displayCandidate(
            in: [emptyPlaceholder, restoredServerDesign],
            forProjectId: uppercasedProjectId
        )

        XCTAssertTrue(restoredServerDesign.hasRenderableGeometry)
        XCTAssertEqual(selected?.id, restoredServerDesign.id)
        XCTAssertTrue(restoredServerDesign.isAttached(toProjectId: uppercasedProjectId))
    }

    func test_SupabaseDeckDesignDTO_decodesLegacyDrawingDataMissingSurfaces() throws {
        let payload = """
        {
          "id": "ad67d5c4-ab64-4c29-b01f-2e426dc53992",
          "company_id": "a612edc0-5c18-4c4d-af97-55b9410dd077",
          "project_id": "fd7a25b0-3349-4c8c-8f83-92fc59985420",
          "title": "L3 Deck",
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
            "footprint": { "assignedItems": [], "isClosed": 1 },
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
          "thumbnail_url": null,
          "version": 1,
          "created_by": null,
          "created_at": "2026-05-04T21:27:13Z",
          "updated_at": "2026-05-13T00:16:41.407879Z",
          "deleted_at": null
        }
        """

        let dto = try JSONDecoder().decode(SupabaseDeckDesignDTO.self, from: Data(payload.utf8))

        XCTAssertEqual(dto.id, "ad67d5c4-ab64-4c29-b01f-2e426dc53992")
        XCTAssertEqual(dto.drawingData.vertices.count, 4)
        XCTAssertEqual(dto.drawingData.edges.count, 4)
        XCTAssertTrue(dto.drawingData.footprint.isClosed)
        XCTAssertEqual(dto.drawingData.surfaces.count, 0)
        XCTAssertFalse(dto.drawingData.vertices.isEmpty)
    }

    func test_DeckFootprint_decodesLegacyNumericClosedState() throws {
        let openPayload = #"{"assignedItems":[],"isClosed":0}"#
        let closedPayload = #"{"assignedItems":[],"isClosed":1}"#

        let open = try JSONDecoder().decode(DeckFootprint.self, from: Data(openPayload.utf8))
        let closed = try JSONDecoder().decode(DeckFootprint.self, from: Data(closedPayload.utf8))

        XCTAssertFalse(open.isClosed)
        XCTAssertTrue(closed.isClosed)
    }

    func test_DeckNestedModels_decodeLegacyNumericBooleans() throws {
        let stairPayload = #"{"width":48,"flipDirection":1}"#
        let itemPayload = #"{"id":"item-1","name":"Gate","unitType":"each","isGate":1}"#

        let stair = try JSONDecoder().decode(StairConfig.self, from: Data(stairPayload.utf8))
        let item = try JSONDecoder().decode(AssignedItem.self, from: Data(itemPayload.utf8))

        XCTAssertTrue(stair.flipDirection)
        XCTAssertTrue(item.isGate)
    }

    func test_decodeResilient_skipsACorruptRowAndKeepsTheValidOnes() throws {
        // Two genuinely-valid rows (round-tripped through the codec) bracketing a
        // row whose drawing_data is the wrong shape — the exact failure that, when
        // it fails the WHOLE [SupabaseDeckDesignDTO] decode, blacks out every deck.
        func valid(_ id: String) -> SupabaseDeckDesignDTO {
            SupabaseDeckDesignDTO(
                id: id,
                companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
                projectId: nil,
                title: "Deck \(id)",
                drawingData: DeckDrawingData(),
                thumbnailUrl: nil,
                version: 1,
                createdBy: nil,
                createdAt: "2026-05-04T21:27:13Z",
                updatedAt: nil,
                deletedAt: nil
            )
        }
        let encoder = JSONEncoder()
        let v1 = String(data: try encoder.encode(valid("aaa")), encoding: .utf8)!
        let v2 = String(data: try encoder.encode(valid("bbb")), encoding: .utf8)!
        let corrupt = #"{"id":"corrupt","company_id":"c","title":"Bad","drawing_data":"not-an-object","version":1,"created_at":"2026-05-04T21:27:13Z"}"#
        let arrayJSON = "[\(v1),\(corrupt),\(v2)]"

        let decoded = DeckDesignRepository.decodeResilient(Data(arrayJSON.utf8))

        XCTAssertEqual(decoded.count, 2, "the corrupt row is skipped, the valid rows survive")
        XCTAssertEqual(Set(decoded.map(\.id)), ["aaa", "bbb"])
    }

    func test_decodeResilient_returnsEmptyForANonArrayPayload() {
        XCTAssertTrue(DeckDesignRepository.decodeResilient(Data(#"{"not":"an array"}"#.utf8)).isEmpty)
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
}
