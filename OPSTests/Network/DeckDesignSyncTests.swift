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
