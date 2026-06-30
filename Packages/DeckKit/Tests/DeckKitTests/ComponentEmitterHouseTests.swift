import CoreGraphics
import XCTest
@testable import DeckKit

final class ComponentEmitterHouseTests: XCTestCase {
    func test_emitsDoorAndWindowRows() throws {
        var data = DeckDrawingData()
        data.house = HouseModel(
            openings: [
                WallOpening(
                    id: "door-1",
                    edgeId: "house-edge",
                    kind: .sliderDoor,
                    widthInches: 72,
                    heightInches: 80,
                    sillHeightInches: 0,
                    offsetAlongEdgeInches: 24
                ),
                WallOpening(
                    id: "window-1",
                    edgeId: "house-edge",
                    kind: .window,
                    widthInches: 48,
                    heightInches: 36,
                    sillHeightInches: 36,
                    offsetAlongEdgeInches: 132
                ),
            ]
        )

        let rows = ComponentEmitter.emit(data)
        let door = try XCTUnwrap(rows.singleComponent("door"))
        let window = try XCTUnwrap(rows.singleComponent("window"))

        XCTAssertEqual(door.metadata["kind"], AnyCodable("sliderDoor"))
        XCTAssertEqual(door.metadata["widthInches"], AnyCodable(72.0))
        XCTAssertEqual(door.metadata["heightInches"], AnyCodable(80.0))
        XCTAssertEqual(door.metadata["edgeId"], AnyCodable("house-edge"))
        XCTAssertEqual(door.metadata["calloutTag"], AnyCodable("D1"))

        XCTAssertEqual(window.metadata["kind"], AnyCodable("window"))
        XCTAssertEqual(window.metadata["widthInches"], AnyCodable(48.0))
        XCTAssertEqual(window.metadata["heightInches"], AnyCodable(36.0))
        XCTAssertEqual(window.metadata["sillHeightInches"], AnyCodable(36.0))
        XCTAssertEqual(window.metadata["edgeId"], AnyCodable("house-edge"))
        XCTAssertEqual(window.metadata["calloutTag"], AnyCodable("W1"))
    }

    func test_emitsLedgerRow() throws {
        var data = DeckDrawingData()
        data.house = HouseModel(
            ledger: LedgerDetail(
                cladding: .brick,
                attachmentAllowed: false,
                lateralConnectors: 4
            )
        )

        let ledger = try XCTUnwrap(ComponentEmitter.emit(data).singleComponent("ledger"))

        XCTAssertEqual(ledger.metadata["cladding"], AnyCodable("brick"))
        XCTAssertEqual(ledger.metadata["attachmentAllowed"], AnyCodable(false))
        XCTAssertEqual(ledger.metadata["lateralConnectors"], AnyCodable(4))
    }

    func test_emitsBeamLineRowOnlyWhenFreestanding() throws {
        var freestanding = Self.houseEdgeDrawing()
        freestanding.house = HouseModel(
            ledger: LedgerDetail(cladding: .brick, attachmentAllowed: false)
        )

        let beamLine = try XCTUnwrap(
            ComponentEmitter.emit(freestanding).singleComponent("freestanding_beam_line")
        )
        XCTAssertEqual(beamLine.metadata["spanInches"], AnyCodable(144.0))
        XCTAssertEqual(beamLine.metadata["footingCount"], AnyCodable(3))
        XCTAssertEqual(beamLine.metadata["edgeId"], AnyCodable("house-edge"))

        var attached = freestanding
        attached.house?.ledger = LedgerDetail(cladding: .stucco, attachmentAllowed: true)

        XCTAssertNil(ComponentEmitter.emit(attached).singleComponent("freestanding_beam_line"))
    }

    func test_nilHouseEmitsNoHouseRows() {
        let data = Self.deckVocabularyDrawing()
        let rows = ComponentEmitter.emit(data)
        let types = Set(rows.map(\.componentType))

        XCTAssertFalse(types.contains("door"))
        XCTAssertFalse(types.contains("window"))
        XCTAssertFalse(types.contains("ledger"))
        XCTAssertFalse(types.contains("freestanding_beam_line"))
    }

    func test_doesNotRenameExistingComponentTypes() {
        let rows = ComponentEmitter.emit(Self.deckVocabularyDrawing())
        let types = Set(rows.map(\.componentType))

        XCTAssertTrue(types.contains("railing"))
        XCTAssertTrue(types.contains("deck_board"))
        XCTAssertTrue(types.contains("stair_set"))
        XCTAssertTrue(types.contains("gate"))
        XCTAssertTrue(types.contains("post_set"))
    }

    private static func houseEdgeDrawing() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1

        let v1 = DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0))
        let edge = DeckEdge(
            id: "house-edge",
            startVertexId: v1.id,
            endVertexId: v2.id,
            edgeType: .houseEdge,
            dimension: 144,
            houseEdgeMaterial: .brick
        )

        data.vertices = [v1, v2]
        data.edges = [edge]
        return data
    }

    private static func deckVocabularyDrawing() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1

        let v1 = DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0))
        let v2 = DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0))
        let v3 = DeckVertex(id: "v3", position: CGPoint(x: 144, y: 144))
        let v4 = DeckVertex(id: "v4", position: CGPoint(x: 0, y: 144))

        var e1 = DeckEdge(
            id: "deck-edge-1",
            startVertexId: v1.id,
            endVertexId: v2.id,
            dimension: 144,
            railingConfig: RailingConfig(railingType: .picket, maxPostSpacing: 84),
            stairConfig: StairConfig(width: 48),
            assignedItems: [AssignedItem(name: "Gate", unitType: .each, isGate: true)]
        )
        var e2 = DeckEdge(id: "deck-edge-2", startVertexId: v2.id, endVertexId: v3.id, dimension: 144)
        var e3 = DeckEdge(id: "deck-edge-3", startVertexId: v3.id, endVertexId: v4.id, dimension: 144)
        var e4 = DeckEdge(id: "deck-edge-4", startVertexId: v4.id, endVertexId: v1.id, dimension: 144)
        e1.edgeType = .deckEdge
        e2.edgeType = .deckEdge
        e3.edgeType = .deckEdge
        e4.edgeType = .deckEdge

        data.vertices = [v1, v2, v3, v4]
        data.edges = [e1, e2, e3, e4]
        data.footprint = DeckFootprint(isClosed: true)
        data.surfaces = []
        return data
    }
}

private extension Array where Element == DesignComponentRow {
    func singleComponent(_ componentType: String) -> DesignComponentRow? {
        let matches = filter { $0.componentType == componentType }
        return matches.count == 1 ? matches[0] : nil
    }
}
