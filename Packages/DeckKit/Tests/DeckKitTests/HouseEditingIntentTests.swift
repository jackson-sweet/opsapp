import CoreGraphics
import XCTest
@testable import DeckKit

@MainActor
final class HouseEditingIntentTests: XCTestCase {
    func test_addOpening_appendsValidatedOpeningAndPersists() {
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: houseEdgeData(),
            capabilities: .full,
            onPersist: { persisted.append($0) }
        )

        let result = model.addOpening(
            .patioDoor,
            onEdge: "house-edge",
            widthInches: 72,
            heightInches: 80,
            sillHeightInches: 0,
            offsetAlongEdgeInches: 24
        )

        guard case let .ok(opening) = result else {
            XCTFail("Expected ok result, got \(result)")
            return
        }
        XCTAssertEqual(opening.kind, .patioDoor)
        XCTAssertEqual(opening.edgeId, "house-edge")
        XCTAssertEqual(opening.offsetAlongEdgeInches, 24)
        XCTAssertEqual(model.drawingData.house?.openings, [opening])
        XCTAssertEqual(persisted.last?.house?.openings, [opening])
    }

    func test_addOpening_clampsOverflowingOffsetAndPersistsAdjustedOpening() {
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: houseEdgeData(),
            capabilities: .full,
            onPersist: { persisted.append($0) }
        )

        let result = model.addOpening(
            .window,
            onEdge: "house-edge",
            widthInches: 48,
            heightInches: 48,
            sillHeightInches: 36,
            offsetAlongEdgeInches: 90
        )

        guard case let .clampedToWall(opening) = result else {
            XCTFail("Expected clamped result, got \(result)")
            return
        }
        XCTAssertEqual(opening.offsetAlongEdgeInches, 72)
        XCTAssertEqual(model.drawingData.house?.openings, [opening])
        XCTAssertEqual(persisted.last?.house?.openings, [opening])
    }

    func test_updateOpening_rejectsOverlapAndDoesNotPersist() {
        var data = houseEdgeData()
        let first = WallOpening(
            id: "first",
            edgeId: "house-edge",
            kind: .window,
            widthInches: 36,
            heightInches: 48,
            sillHeightInches: 36,
            offsetAlongEdgeInches: 24
        )
        let second = WallOpening(
            id: "second",
            edgeId: "house-edge",
            kind: .window,
            widthInches: 30,
            heightInches: 48,
            sillHeightInches: 36,
            offsetAlongEdgeInches: 72
        )
        data.house = HouseModel(storyHeights: [8], openings: [first, second])
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: data,
            capabilities: .full,
            onPersist: { persisted.append($0) }
        )

        var updated = second
        updated.offsetAlongEdgeInches = 40
        let result = model.updateOpening(updated)

        XCTAssertEqual(result, .overlapsOpening(otherId: "first"))
        XCTAssertEqual(model.drawingData.house?.openings, [first, second])
        XCTAssertTrue(persisted.isEmpty)
    }

    func test_resolveLedger_brickReturnsFreestandingAndPersistsDetail() {
        var data = houseEdgeData()
        data.edges[0].houseEdgeMaterial = .brick
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: data,
            capabilities: .full,
            onPersist: { persisted.append($0) }
        )

        let strategy = model.resolveLedger(
            forEdge: "house-edge",
            houseSideBeamSpanInches: 144
        )

        guard case let .freestanding(detail, fallback)? = strategy else {
            XCTFail("Expected freestanding strategy, got \(String(describing: strategy))")
            return
        }
        XCTAssertEqual(detail.cladding, .brick)
        XCTAssertFalse(detail.attachmentAllowed)
        XCTAssertEqual(model.drawingData.house?.ledger, detail)
        XCTAssertEqual(persisted.last?.house?.ledger, detail)
        XCTAssertFalse(fallback.beamMembers.isEmpty)
        XCTAssertFalse(fallback.footingAnchors.isEmpty)
    }

    func test_setLedgerDetail_persistsFastenerScheduleAndLateralConnectors() {
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: houseEdgeData(),
            capabilities: .full,
            onPersist: { persisted.append($0) }
        )
        let detail = LedgerDetail(
            cladding: .stucco,
            attachmentAllowed: true,
            fastenerSchedule: "1/2\" through-bolts @ 16\" o.c.",
            lateralConnectors: 2
        )

        XCTAssertTrue(model.setLedgerDetail(detail))

        XCTAssertEqual(model.drawingData.house?.ledger, detail)
        XCTAssertEqual(persisted.last?.house?.ledger, detail)
    }

    func test_setStoryHeightsAndFloorLine_persistAndRoundTrip() throws {
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: houseEdgeData(),
            capabilities: .full,
            onPersist: { persisted.append($0) }
        )

        XCTAssertTrue(model.setFloorLine(feet: 1.5))
        XCTAssertTrue(model.setStoryHeights([9, 8.5]))

        XCTAssertEqual(model.drawingData.house?.floorLineFeet, 1.5)
        XCTAssertEqual(model.drawingData.house?.storyHeights, [9, 8.5])
        XCTAssertEqual(persisted.last?.house?.storyHeights, [9, 8.5])

        let roundTripped = try XCTUnwrap(DeckDrawingData.fromJSON(model.drawingData.toJSON()))
        XCTAssertEqual(roundTripped.house?.floorLineFeet, 1.5)
        XCTAssertEqual(roundTripped.house?.storyHeights, [9, 8.5])
    }

    func test_intentsNoopWhenUnavailableInLightSurface() {
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: houseEdgeData(includeHouse: false),
            capabilities: .light,
            onPersist: { persisted.append($0) }
        )

        let addResult = model.addOpening(
            .window,
            onEdge: "house-edge",
            widthInches: 48,
            heightInches: 48,
            sillHeightInches: 36,
            offsetAlongEdgeInches: 24
        )

        XCTAssertEqual(addResult, .unavailable)
        XCTAssertFalse(model.setFloorLine(feet: 1.5))
        XCTAssertFalse(model.setStoryHeights([9]))
        XCTAssertFalse(model.setLedgerDetail(LedgerDetail()))
        XCTAssertNil(model.resolveLedger(forEdge: "house-edge", houseSideBeamSpanInches: 144))
        XCTAssertNil(model.drawingData.house)
        XCTAssertTrue(persisted.isEmpty)
    }

    private func houseEdgeData(includeHouse: Bool = true) -> DeckDrawingData {
        let v1 = DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(id: "v2", position: CGPoint(x: 240, y: 0))
        let v3 = DeckVertex(id: "v3", position: CGPoint(x: 240, y: 120))
        let v4 = DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120))
        let house = DeckEdge(
            id: "house-edge",
            startVertexId: "v1",
            endVertexId: "v2",
            edgeType: .houseEdge
        )
        let side = DeckEdge(id: "side-edge", startVertexId: "v2", endVertexId: "v3")
        let front = DeckEdge(id: "front-edge", startVertexId: "v3", endVertexId: "v4")
        let returnEdge = DeckEdge(id: "return-edge", startVertexId: "v4", endVertexId: "v1")

        var data = DeckDrawingData()
        data.vertices = [v1, v2, v3, v4]
        data.edges = [house, side, front, returnEdge]
        data.scaleFactor = 2
        if includeHouse {
            data.house = HouseModel(storyHeights: [8])
        }
        return data
    }
}
