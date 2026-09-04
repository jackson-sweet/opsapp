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
            id: "deck-stale", companyId: "c1", projectId: "p1", opportunityId: nil, title: "Untitled Deck",
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
            id: "deck-newer", companyId: "c1", projectId: "p1", opportunityId: nil, title: "New Title",
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
            opportunityId: nil,
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

    func test_SupabaseDeckDesignDTO_roundTripPreservesFramingAndFutureDrawingBlock() throws {
        let payload = """
        {
          "id": "ad67d5c4-ab64-4c29-b01f-2e426dc53992",
          "company_id": "a612edc0-5c18-4c4d-af97-55b9410dd077",
          "project_id": "fd7a25b0-3349-4c8c-8f83-92fc59985420",
          "opportunity_id": null,
          "title": "Framed deck",
          "drawing_data": {
            "schemaVersion": 2,
            "vertices": [],
            "edges": [],
            "framing": {
              "members": [
                {
                  "levelId": "",
                  "members": [
                    {
                      "id": "beam-1",
                      "role": "beam",
                      "start": [0, 120],
                      "end": [144, 120],
                      "nominalSize": "2x10",
                      "plyCount": 2,
                      "spacingInchesOC": 24,
                      "species": "spf",
                      "grade": "no2",
                      "sizing": {"outcome":"pass","utilization":0.75},
                      "locked": true
                    }
                  ]
                }
              ],
              "loadPreset": {
                "liveLoadPSF": 40,
                "deadLoadPSF": 10,
                "snowLoadPSF": 25,
                "species": "spf",
                "grade": "no2"
              },
              "generationSource": "manual",
              "generatedAtSchemaVersion": 2
            },
            "futureDisplay": {
              "enabled": true,
              "mode": "inspection",
              "threshold": 0.25
            }
          },
          "thumbnail_url": null,
          "version": 4,
          "created_by": null,
          "created_at": "2026-07-17T12:00:00Z",
          "updated_at": "2026-07-17T12:30:00Z",
          "deleted_at": null
        }
        """

        let inboundObject = try DeckJSONValue.parseObject(from: payload)
        guard case .object(let inboundDrawing)? = inboundObject["drawing_data"] else {
            return XCTFail("Fixture drawing_data must be an object")
        }

        let inboundDTO = try JSONDecoder().decode(SupabaseDeckDesignDTO.self, from: Data(payload.utf8))
        let localModel = inboundDTO.toModel()
        let outboundDTO = SupabaseDeckDesignDTO.fromModel(localModel)
        let outboundData = try JSONEncoder().encode(outboundDTO)
        let outboundJSON = try XCTUnwrap(String(data: outboundData, encoding: .utf8))
        let outboundObject = try DeckJSONValue.parseObject(from: outboundJSON)
        guard case .object(let outboundDrawing)? = outboundObject["drawing_data"] else {
            return XCTFail("Encoded drawing_data must be an object")
        }

        XCTAssertEqual(outboundDrawing["framing"], inboundDrawing["framing"])
        XCTAssertEqual(outboundDrawing["futureDisplay"], inboundDrawing["futureDisplay"])
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
                opportunityId: nil,
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

    // MARK: - Deck→project link durability (site-visit conversion stranding)

    /// Bug B (Carol Dancer case): the deck UPDATE op payload structurally
    /// omitted `project_id`, so a deck created during a site visit (project_id
    /// nil at create time) could NEVER deliver its project link to the server —
    /// every later builder save pushed title/drawing/version but not the link.
    /// The update payload must carry `project_id` whenever the local design has
    /// one.
    @MainActor
    func test_deckDesignUpdateOperationPayloadCarriesProjectId() throws {
        let container = try makeSyncOperationContainer()
        let context = container.mainContext

        let projectId = "5f90388c-69af-4bb9-ba26-f8d74487d344"
        let design = DeckDesign(
            id: "bff17fb7-af08-457b-9062-822d25270e9a",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: projectId,
            title: "Visit deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        // Simulate a design whose create op already synced — the next save must
        // emit an UPDATE op.
        design.lastSyncedAt = Date()
        context.insert(design)
        try context.save()

        let syncEngine = SyncEngine()
        syncEngine.configure(
            modelContext: context,
            connectivity: ConnectivityManager()
        )

        let viewModel = DeckBuilderViewModel(
            deckDesign: design,
            modelContext: context,
            syncEngine: syncEngine
        )
        viewModel.flushBeforeExit()

        let ops = try context.fetch(FetchDescriptor<SyncOperation>())
            .filter { $0.entityType == SyncEntityType.deckDesign.rawValue }
        XCTAssertEqual(ops.count, 1)
        let op = try XCTUnwrap(ops.first)
        XCTAssertEqual(op.operationType, "update")

        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: op.payload) as? [String: Any]
        )
        XCTAssertEqual(
            payload["project_id"] as? String,
            projectId,
            "the deck update op must carry the project link — omitting it strands site-visit decks with project_id NULL on the server"
        )
        XCTAssertNotNil(payload["updated_at"])
    }

    /// A deck with NO local project link must keep omitting `project_id` from
    /// its update payload — sending an explicit null from a device whose local
    /// row is stale-nil would UNLINK a deck another device just attached.
    @MainActor
    func test_deckDesignUpdateOperationOmitsProjectIdWhenUnlinked() throws {
        let container = try makeSyncOperationContainer()
        let context = container.mainContext

        let design = DeckDesign(
            id: "0e1d44a1-9c2b-4f6e-8a35-6d1f0b9a7c21",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: nil,
            title: "Standalone deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        design.lastSyncedAt = Date()
        context.insert(design)
        try context.save()

        let syncEngine = SyncEngine()
        syncEngine.configure(
            modelContext: context,
            connectivity: ConnectivityManager()
        )

        let viewModel = DeckBuilderViewModel(
            deckDesign: design,
            modelContext: context,
            syncEngine: syncEngine
        )
        viewModel.flushBeforeExit()

        let ops = try context.fetch(FetchDescriptor<SyncOperation>())
            .filter { $0.entityType == SyncEntityType.deckDesign.rawValue }
        let op = try XCTUnwrap(ops.first)
        XCTAssertEqual(op.operationType, "update")

        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: op.payload) as? [String: Any]
        )
        XCTAssertNil(
            payload["project_id"],
            "an unlinked deck must not push project_id at all — an explicit null could unlink a project attachment made on another device"
        )
    }

    /// Recovery sweep for decks stranded with work the server never received.
    /// It used to require a projectId — skipping every lead deck and standalone
    /// sketch, the two kinds most likely to be stranded — and pushed the link
    /// alone, bumping the server updated_at without delivering a single vertex.
    @MainActor
    func test_enqueueStrandedDeckDesigns_recordsAFullRevisionForEveryStrandedDeck() throws {
        let container = try makeSyncOperationContainer()
        let context = container.mainContext

        let stranded = DeckDesign(
            id: "bff17fb7-af08-457b-9062-822d25270e9a",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: "5f90388c-69af-4bb9-ba26-f8d74487d344",
            title: "Carol Dancer deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        stranded.markForSync()

        // Dirty and unlinked — a lead deck or standalone sketch. This is the
        // case the old sweep skipped outright, stranding the drawing forever.
        let unlinkedDirty = DeckDesign(
            id: "11111111-1111-4111-8111-111111111111",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: nil,
            title: "Sketch",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        unlinkedDirty.markForSync()

        // Linked and clean — already converged, must not be touched.
        let clean = DeckDesign(
            id: "22222222-2222-4222-8222-222222222222",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: "5f90388c-69af-4bb9-ba26-f8d74487d344",
            title: "Synced deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        clean.needsSync = false

        [stranded, unlinkedDirty, clean].forEach { context.insert($0) }
        try context.save()

        let syncEngine = SyncEngine()
        syncEngine.configure(
            modelContext: context,
            connectivity: ConnectivityManager()
        )

        syncEngine.enqueueStrandedDeckDesigns()

        let ops = try context.fetch(FetchDescriptor<SyncOperation>())
            .filter { $0.entityType == SyncEntityType.deckDesign.rawValue }
        XCTAssertEqual(
            ops.count, 2,
            "both stranded decks get a recovery op — the converged one does not"
        )
        XCTAssertEqual(
            Set(ops.map(\.entityId)), Set([stranded.id, unlinkedDirty.id]),
            "an unlinked deck holding unpushed work must be swept, not skipped"
        )

        let linkedOp = try XCTUnwrap(ops.first { $0.entityId == stranded.id })
        XCTAssertEqual(linkedOp.operationType, "update")
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: linkedOp.payload) as? [String: Any]
        )
        XCTAssertEqual(payload["project_id"] as? String, "5f90388c-69af-4bb9-ba26-f8d74487d344")
        XCTAssertNotNil(payload["updated_at"])
        XCTAssertNotNil(
            payload["drawing_data"],
            "the sweep must deliver the drawing, not just bump the server timestamp"
        )

        let unlinkedOp = try XCTUnwrap(ops.first { $0.entityId == unlinkedDirty.id })
        let unlinkedPayload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: unlinkedOp.payload) as? [String: Any]
        )
        XCTAssertNil(
            unlinkedPayload["project_id"],
            "an unlinked deck must not push an explicit null project link"
        )
        XCTAssertNotNil(unlinkedPayload["drawing_data"])

        // A pending op suppresses re-recording — the sweep runs every push
        // cycle and must not stack duplicate ops.
        syncEngine.enqueueStrandedDeckDesigns()
        let opsAfterSecondSweep = try context.fetch(FetchDescriptor<SyncOperation>())
            .filter { $0.entityType == SyncEntityType.deckDesign.rawValue }
        XCTAssertEqual(opsAfterSecondSweep.count, 2)
    }

    /// A deck whose op just completed is mid-convergence (needsSync clears on
    /// the next inbound merge) — the sweep must not spam link updates for it.
    @MainActor
    func test_enqueueStrandedDeckDesigns_skipsDecksWithRecentOperations() throws {
        let container = try makeSyncOperationContainer()
        let context = container.mainContext

        let converging = DeckDesign(
            id: "33333333-3333-4333-8333-333333333333",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: "5f90388c-69af-4bb9-ba26-f8d74487d344",
            title: "Just pushed deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        converging.markForSync()
        context.insert(converging)

        let completedOp = SyncOperation(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: converging.id,
            operationType: "update",
            payload: Data("{}".utf8),
            changedFields: ["title"]
        )
        completedOp.status = "completed"
        completedOp.completedAt = Date()
        context.insert(completedOp)
        try context.save()

        let syncEngine = SyncEngine()
        syncEngine.configure(
            modelContext: context,
            connectivity: ConnectivityManager()
        )

        syncEngine.enqueueStrandedDeckDesigns()

        let pendingOps = try context.fetch(FetchDescriptor<SyncOperation>())
            .filter { $0.entityType == SyncEntityType.deckDesign.rawValue && $0.status == "pending" }
        XCTAssertTrue(
            pendingOps.isEmpty,
            "a deck with recent op lifecycle is converging through the normal pipeline — no recovery op"
        )
    }

    // MARK: - Content-based conflict resolution (bug 9f4aeaf8)

    /// THE BUG. The server row is stamped by a Postgres BEFORE UPDATE trigger
    /// (`NEW.updated_at = now()`), the local row by the device clock before the
    /// push — so the server ALWAYS looks newer than the local row that produced
    /// it. On the old code that made `serverIsNewer` true, which skipped the
    /// protective subtract, which let a delta re-pull write pre-session server
    /// geometry over the session's autosaved work. Bug 9f4aeaf8.
    func test_applyServerSnapshot_keepsUnpushedLocalGeometryWhenServerClockIsAhead() throws {
        var localDrawing = DeckDrawingData()
        localDrawing.scaleFactor = 1
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

        // The merge base: what the server confirmed at the END of the LAST session.
        let serverConfirmed = DeckDrawingData().toJSON()

        let local = DeckDesign(
            id: "deck-clock-skew",
            companyId: "c1",
            projectId: "p1",
            title: "This session's work",
            drawingDataJSON: localDrawing.toJSON()
        )
        local.syncedDrawingJSON = serverConfirmed      // server agreed on the EMPTY drawing
        local.updatedAt = Date()                       // device clock, at save time
        local.needsSync = false                        // a prior merge already cleared it

        // Server snapshot: the pre-session (empty) geometry, stamped LATER by
        // the server trigger — exactly what the trigger guarantees.
        let dto = SupabaseDeckDesignDTO(
            id: "deck-clock-skew",
            companyId: "c1",
            projectId: "p1",
            opportunityId: nil,
            title: "Untitled Deck",
            drawingData: DeckDrawingData(),
            thumbnailUrl: nil,
            version: 1,
            createdBy: nil,
            createdAt: iso(Date().addingTimeInterval(-3600)),
            updatedAt: iso(Date().addingTimeInterval(30)),   // server clock, AHEAD
            deletedAt: nil
        )

        local.applyServerSnapshot(dto, accepting: Set(DeckDesign.serverMergeFields))

        let survived = DeckDrawingData.fromJSON(local.drawingDataJSON)
        XCTAssertEqual(
            survived?.vertices.count, 4,
            "unpushed local geometry must survive a server snapshot that is only newer by wall clock"
        )
        XCTAssertEqual(local.title, "This session's work")
        XCTAssertTrue(local.needsSync, "the row still holds unpushed content and must be re-flagged")
    }

    /// A genuinely newer remote edit — one the server confirmed AFTER our merge
    /// base — must still be applied. The fix must not freeze the row.
    func test_applyServerSnapshot_appliesAGenuineRemoteEditWhenLocalIsClean() throws {
        var remote = DeckDrawingData()
        remote.scaleFactor = 1
        remote.vertices = [
            DeckVertex(id: "r1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "r2", position: CGPoint(x: 60, y: 0))
        ]
        remote.edges = [DeckEdge(id: "re1", startVertexId: "r1", endVertexId: "r2")]

        let baseline = DeckDrawingData().toJSON()
        let local = DeckDesign(
            id: "deck-remote-edit",
            companyId: "c1",
            projectId: "p1",
            title: "Old",
            drawingDataJSON: baseline
        )
        local.syncedDrawingJSON = baseline    // local holds nothing unpushed
        local.updatedAt = Date().addingTimeInterval(-600)
        local.needsSync = false

        let dto = SupabaseDeckDesignDTO(
            id: "deck-remote-edit", companyId: "c1", projectId: "p1", opportunityId: nil,
            title: "Edited on another device", drawingData: remote, thumbnailUrl: nil,
            version: 2, createdBy: nil,
            createdAt: iso(Date().addingTimeInterval(-3600)), updatedAt: iso(Date()),
            deletedAt: nil
        )

        local.applyServerSnapshot(dto, accepting: Set(DeckDesign.serverMergeFields))

        XCTAssertEqual(DeckDrawingData.fromJSON(local.drawingDataJSON)?.vertices.count, 2)
        XCTAssertEqual(local.title, "Edited on another device")
        XCTAssertEqual(local.syncedDrawingJSON, local.drawingDataJSON,
                       "accepting a server snapshot moves the merge base")
    }

    /// A row with no recorded base and no local write is a row the inbound merge
    /// itself produced — it holds the server's own content, so it must keep
    /// accepting server updates. Failing safe here instead would freeze every
    /// pre-existing deck on every device the moment this shipped.
    func test_applyServerSnapshot_appliesToALegacyRowThatHoldsNoLocalWork() throws {
        var remote = DeckDrawingData()
        remote.scaleFactor = 1
        remote.vertices = [
            DeckVertex(id: "r1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "r2", position: CGPoint(x: 60, y: 0))
        ]
        remote.edges = [DeckEdge(id: "re1", startVertexId: "r1", endVertexId: "r2")]

        let local = DeckDesign(
            id: "deck-legacy-clean",
            companyId: "c1",
            title: "Old",
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        XCTAssertNil(local.syncedDrawingJSON, "the shape every row upgraded from an older build has")
        local.needsSync = false
        local.updatedAt = Date().addingTimeInterval(-600)

        let dto = SupabaseDeckDesignDTO(
            id: "deck-legacy-clean", companyId: "c1", projectId: nil, opportunityId: nil,
            title: "Edited on another device", drawingData: remote, thumbnailUrl: nil,
            version: 2, createdBy: nil,
            createdAt: iso(Date().addingTimeInterval(-3600)), updatedAt: iso(Date()),
            deletedAt: nil
        )

        local.applyServerSnapshot(dto, accepting: Set(DeckDesign.serverMergeFields))

        XCTAssertEqual(DeckDrawingData.fromJSON(local.drawingDataJSON)?.vertices.count, 2)
        XCTAssertEqual(local.title, "Edited on another device")
    }

    /// The same legacy row, but flagged for push: it holds local work with no
    /// baseline to prove it against, so the local copy wins until its own push
    /// confirms and records one.
    func test_applyServerSnapshot_protectsALegacyRowThatIsStillFlaggedForPush() throws {
        var localDrawing = DeckDrawingData()
        localDrawing.scaleFactor = 1
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

        let local = DeckDesign(
            id: "deck-legacy-dirty",
            companyId: "c1",
            title: "Local work",
            drawingDataJSON: localDrawing.toJSON()
        )
        local.needsSync = true
        local.updatedAt = Date()

        let dto = SupabaseDeckDesignDTO(
            id: "deck-legacy-dirty", companyId: "c1", projectId: nil, opportunityId: nil,
            title: "Untitled Deck", drawingData: DeckDrawingData(), thumbnailUrl: nil,
            version: 1, createdBy: nil,
            createdAt: iso(Date().addingTimeInterval(-3600)),
            updatedAt: iso(Date().addingTimeInterval(30)),
            deletedAt: nil
        )

        local.applyServerSnapshot(dto, accepting: Set(DeckDesign.serverMergeFields))

        XCTAssertEqual(DeckDrawingData.fromJSON(local.drawingDataJSON)?.vertices.count, 4)
        XCTAssertEqual(local.title, "Local work")
        XCTAssertTrue(local.needsSync)
    }

    /// Guard (a) must never be permanently disabled by a null server timestamp.
    func test_applyServerSnapshot_neverNilsTheLocalUpdatedAt() throws {
        let baseline = DeckDrawingData().toJSON()
        let local = DeckDesign(id: "deck-null-ts", companyId: "c1", title: "T", drawingDataJSON: baseline)
        local.syncedDrawingJSON = baseline
        let stamped = Date().addingTimeInterval(-120)
        local.updatedAt = stamped

        let dto = SupabaseDeckDesignDTO(
            id: "deck-null-ts", companyId: "c1", projectId: nil, opportunityId: nil,
            title: "T", drawingData: DeckDrawingData(), thumbnailUrl: nil, version: 1,
            createdBy: nil, createdAt: iso(Date()), updatedAt: nil, deletedAt: nil
        )

        local.applyServerSnapshot(dto, accepting: Set(DeckDesign.serverMergeFields))

        XCTAssertEqual(local.updatedAt, stamped,
                       "a null server timestamp must not erase the local one — that disables the stale guard forever")
    }

    // MARK: - Confirmed push moves the merge base (bug 9f4aeaf8)

    @MainActor
    func test_recordConfirmedPush_movesTheMergeBaseToThePushedPayload() throws {
        let container = try makeSyncOperationContainer()
        let context = container.mainContext

        let pushed = closedSquare()
        let design = DeckDesign(
            id: "3c9d5f31-6d0e-4a1b-8f2c-5b7a1d0e4f88",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            title: "Pushed deck",
            drawingDataJSON: pushed.toJSON()
        )
        context.insert(design)

        let operation = SyncOperation(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: design.id,
            operationType: "update",
            payload: try payloadData(carrying: pushed),
            changedFields: ["drawing_data"]
        )
        context.insert(operation)
        try context.save()

        try DeckDesignServerMerge.recordConfirmedPush(for: operation, in: context)

        XCTAssertEqual(design.syncedDrawingJSON, design.drawingDataJSON)
        XCTAssertFalse(design.hasUnsyncedDrawing)
    }

    /// If the user edited again while the push was in flight, the server has not
    /// seen that edit — the base must stay where it was.
    @MainActor
    func test_recordConfirmedPush_leavesTheBaseWhenTheDesignMovedOnAfterThePush() throws {
        let container = try makeSyncOperationContainer()
        let context = container.mainContext

        let pushed = closedSquare()
        let design = DeckDesign(
            id: "5a0b1c2d-3e4f-4506-8718-29a3b4c5d6e7",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            title: "Edited again mid-flight",
            drawingDataJSON: pushed.toJSON()
        )
        context.insert(design)

        let operation = SyncOperation(
            entityType: SyncEntityType.deckDesign.rawValue,
            entityId: design.id,
            operationType: "update",
            payload: try payloadData(carrying: pushed),
            changedFields: ["drawing_data"]
        )
        context.insert(operation)

        var edited = closedSquare()
        edited.config.gridVisible = false
        design.storeDrawingData(edited, json: edited.toJSON())
        try context.save()

        try DeckDesignServerMerge.recordConfirmedPush(for: operation, in: context)

        XCTAssertNotEqual(
            design.syncedDrawingJSON, design.drawingDataJSON,
            "the base must not advance past an edit the server has not seen"
        )
        XCTAssertTrue(design.hasUnsyncedDrawing)
    }

    /// Builds the queue payload shape `enqueueDeckDesignSync` produces — the
    /// drawing as a re-parsed JSON object, not as a string.
    private func payloadData(carrying drawing: DeckDrawingData) throws -> Data {
        let drawingObject = try JSONSerialization.jsonObject(with: Data(drawing.toJSON().utf8))
        return try JSONSerialization.data(withJSONObject: [
            "title": "any",
            "drawing_data": drawingObject,
            "version": 2
        ])
    }

    // MARK: - Mid-session durability (bug 9f4aeaf8)

    /// Since 88edd771 the only path that put a deck edit on the wire was a
    /// clean editor exit. A crash, an OOM kill or a force-quit therefore lost
    /// the whole session server-side even though the 2-minute tick had written
    /// it to disk — there was no SyncOperation for the session at all.
    @MainActor
    func test_autosaveTick_recordsDeferredSyncOperation() throws {
        let container = try makeSyncOperationContainer()
        let context = container.mainContext
        let syncEngine = SyncEngine()
        syncEngine.configure(modelContext: context, connectivity: ConnectivityManager())

        let design = DeckDesign(
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1",
            title: "Mid-session deck",
            drawingDataJSON: closedSquare().toJSON()
        )
        context.insert(design)
        try context.save()

        let viewModel = DeckBuilderViewModel(
            deckDesign: design,
            modelContext: context,
            syncEngine: syncEngine
        )
        viewModel.drawingData.config.gridVisible = false
        viewModel.performAutosaveTickForTesting()

        let ops = try context.fetch(FetchDescriptor<SyncOperation>())
            .filter { $0.entityType == SyncEntityType.deckDesign.rawValue }
        XCTAssertFalse(
            ops.isEmpty,
            "the 2-minute tick must record a durable queue entry — exit is not the only cloud boundary"
        )
        XCTAssertTrue(
            ops.contains { $0.getChangedFields().contains("drawing_data") },
            "the queued revision must carry the drawing, not just a link"
        )
    }

    /// Backgrounding used to record nothing at all — `flushLocallyForInterruption`
    /// wrote to disk and stopped there, which is the worst possible moment to
    /// stop: a suspended app is what the OS kills.
    @MainActor
    func test_backgrounding_recordsDeferredSyncOperation() throws {
        let container = try makeSyncOperationContainer()
        let context = container.mainContext
        let syncEngine = SyncEngine()
        syncEngine.configure(modelContext: context, connectivity: ConnectivityManager())

        let design = DeckDesign(
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1",
            title: "Interrupted deck",
            drawingDataJSON: closedSquare().toJSON()
        )
        context.insert(design)
        try context.save()

        let viewModel = DeckBuilderViewModel(
            deckDesign: design,
            modelContext: context,
            syncEngine: syncEngine
        )
        viewModel.drawingData.config.gridVisible = false
        viewModel.flushLocallyForInterruption()

        let ops = try context.fetch(FetchDescriptor<SyncOperation>())
            .filter { $0.entityType == SyncEntityType.deckDesign.rawValue }
        XCTAssertFalse(
            ops.isEmpty,
            "backgrounding is where the OS kills a suspended app — it must leave a durable queue record"
        )
    }

    /// The revision counter was inert: every production row read version 1
    /// because nothing ever incremented it. Each enqueued revision must move it.
    @MainActor
    func test_enqueuedRevisionIncrementsTheVersionColumn() throws {
        let container = try makeSyncOperationContainer()
        let context = container.mainContext
        let syncEngine = SyncEngine()
        syncEngine.configure(modelContext: context, connectivity: ConnectivityManager())

        let design = DeckDesign(
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1",
            title: "Versioned deck",
            drawingDataJSON: closedSquare().toJSON()
        )
        design.lastSyncedAt = Date()
        context.insert(design)
        try context.save()
        let startingVersion = design.version

        let viewModel = DeckBuilderViewModel(
            deckDesign: design,
            modelContext: context,
            syncEngine: syncEngine
        )
        viewModel.drawingData.config.gridVisible = false
        viewModel.performAutosaveTickForTesting()

        XCTAssertEqual(design.version, startingVersion + 1)

        let op = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SyncOperation>())
                .first { $0.entityType == SyncEntityType.deckDesign.rawValue }
        )
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: op.payload) as? [String: Any]
        )
        XCTAssertEqual(payload["version"] as? Int, startingVersion + 1)
    }

    /// An editor left open on an unchanged design must enqueue nothing, or the
    /// tick becomes a request storm — the failure 88edd771 was written to stop.
    @MainActor
    func test_repeatedTicksOnAnUnchangedDesignEnqueueOnlyOnce() throws {
        let container = try makeSyncOperationContainer()
        let context = container.mainContext
        let syncEngine = SyncEngine()
        syncEngine.configure(modelContext: context, connectivity: ConnectivityManager())

        let design = DeckDesign(
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1",
            title: "Idle deck",
            drawingDataJSON: closedSquare().toJSON()
        )
        design.lastSyncedAt = Date()
        context.insert(design)
        try context.save()

        let viewModel = DeckBuilderViewModel(
            deckDesign: design,
            modelContext: context,
            syncEngine: syncEngine
        )
        viewModel.drawingData.config.gridVisible = false
        viewModel.performAutosaveTickForTesting()
        viewModel.performAutosaveTickForTesting()
        viewModel.performAutosaveTickForTesting()

        let ops = try context.fetch(FetchDescriptor<SyncOperation>())
            .filter { $0.entityType == SyncEntityType.deckDesign.rawValue }
        XCTAssertEqual(
            ops.count, 1,
            "an idle editor must not stack a queue record on every tick"
        )
    }

    /// Closed square (4 verts + 4 edges) so the geometry survives the JSON
    /// round-trip — orphan (edgeless) vertices are pruned on decode.
    private func closedSquare() -> DeckDrawingData {
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

    /// The stranding case the old sweep could never reach: a deck drawn on a
    /// LEAD, so `projectId` is nil until conversion. The sweep skipped it, and
    /// nothing else ever retried it — the drawing lived on one phone forever.
    @MainActor
    func test_strandedSweep_recoversALeadDeckWithItsGeometry() throws {
        let container = try makeSyncOperationContainer()
        let context = container.mainContext
        let syncEngine = SyncEngine()
        syncEngine.configure(modelContext: context, connectivity: ConnectivityManager())

        let design = DeckDesign(
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: nil,                                   // lead deck — no project
            opportunityId: "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1",
            title: "Stranded lead deck",
            drawingDataJSON: closedSquare().toJSON()
        )
        design.needsSync = true
        design.syncedDrawingJSON = nil                        // never confirmed
        design.updatedAt = Date().addingTimeInterval(-3600)
        context.insert(design)
        try context.save()

        syncEngine.enqueueStrandedDeckDesigns()

        let ops = try context.fetch(FetchDescriptor<SyncOperation>())
            .filter { $0.entityType == SyncEntityType.deckDesign.rawValue }
        XCTAssertTrue(
            ops.contains { $0.getChangedFields().contains("drawing_data") },
            "the recovery sweep must carry the user's geometry, not just a link"
        )

        let op = try XCTUnwrap(ops.first { $0.entityId == design.id })
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: op.payload) as? [String: Any]
        )
        let drawing = try XCTUnwrap(payload["drawing_data"] as? [String: Any])
        let vertices = try XCTUnwrap(drawing["vertices"] as? [[String: Any]])
        XCTAssertEqual(vertices.count, 4, "the swept payload carries the real drawing")
    }

    /// A deck whose content the server has already confirmed must not be swept —
    /// re-pushing it would bump the server timestamp for nothing, which is the
    /// pattern that arms the inbound clobber.
    @MainActor
    func test_strandedSweep_ignoresADeckWhoseContentIsAlreadyConfirmed() throws {
        let container = try makeSyncOperationContainer()
        let context = container.mainContext
        let syncEngine = SyncEngine()
        syncEngine.configure(modelContext: context, connectivity: ConnectivityManager())

        let design = DeckDesign(
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            projectId: nil,
            opportunityId: "1ad4822d-2a9f-4e0a-a9c1-2ccfa7b142d1",
            title: "Converged lead deck",
            drawingDataJSON: closedSquare().toJSON()
        )
        design.needsSync = false
        design.markDrawingSynced()
        context.insert(design)
        try context.save()

        syncEngine.enqueueStrandedDeckDesigns()

        let ops = try context.fetch(FetchDescriptor<SyncOperation>())
            .filter { $0.entityType == SyncEntityType.deckDesign.rawValue }
        XCTAssertTrue(ops.isEmpty, "a converged deck must not be re-pushed")
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

    /// Container for tests that drive SyncEngine.recordOperation —
    /// PhotoAnnotation is included because refreshPendingCount counts pending
    /// dimensioned annotations alongside SyncOperation rows.
    private func makeSyncOperationContainer() throws -> ModelContainer {
        let schema = Schema([DeckDesign.self, SyncOperation.self, PhotoAnnotation.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
