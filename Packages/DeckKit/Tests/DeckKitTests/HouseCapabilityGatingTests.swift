import CoreGraphics
import XCTest
@testable import DeckKit

@MainActor
final class HouseCapabilityGatingTests: XCTestCase {
    func test_fullCapabilitiesShowHouseEntries() {
        let entries = DeckHouseToolEntry.houseToolEntries(for: .full)

        XCTAssertEqual(entries.map(\.kind), [
            .houseAndOpenings,
            .elevation,
            .schedule,
        ])
        XCTAssertEqual(entries.map(\.title), [
            "House & openings",
            "Elevation",
            "Schedule",
        ])
        XCTAssertTrue(entries.allSatisfy(\.isActionable))
        XCTAssertFalse(entries.contains { $0.isUpsell })
    }

    func test_lightCapabilitiesHideHouseEntriesAndExposeSingleUpsellStub() {
        let entries = DeckHouseToolEntry.houseToolEntries(for: .light)

        XCTAssertEqual(entries.map(\.kind), [.opsDecksUpsell])
        XCTAssertEqual(entries.first?.title, "Available in OPS Decks")
        XCTAssertEqual(entries.first?.systemImage, "lock")
        XCTAssertEqual(entries.filter { $0.isUpsell }.count, 1)
        XCTAssertFalse(entries.contains { $0.isActionable })
    }

    func test_lightModelNeverInvokesHouseEngines() {
        var persisted: [DeckDrawingData] = []
        let original = drawingDataWithHouse()
        let model = DeckDrawingEditorModel(
            drawingData: original,
            capabilities: .light,
            onPersist: { persisted.append($0) }
        )

        XCTAssertFalse(model.canEditHouseOpenings)
        XCTAssertTrue(HouseElevationViewModel(data: model.drawingData, capabilities: .light).isEmpty)
        XCTAssertTrue(HouseOpeningScheduleViewModel(data: model.drawingData, capabilities: .light).isEmpty)

        let existingOpening = original.house?.openings.first
        let updatedOpening = existingOpening.map {
            WallOpening(
                id: $0.id,
                edgeId: $0.edgeId,
                kind: $0.kind,
                widthInches: 96,
                heightInches: $0.heightInches,
                sillHeightInches: $0.sillHeightInches,
                offsetAlongEdgeInches: $0.offsetAlongEdgeInches
            )
        }

        XCTAssertEqual(updatedOpening.map { model.updateOpening($0) }, .some(.unavailable))
        XCTAssertFalse(model.setFloorLine(feet: 2))
        XCTAssertFalse(model.setStoryHeights([10]))
        XCTAssertFalse(model.setLedgerDetail(LedgerDetail(cladding: .brick, attachmentAllowed: false)))
        XCTAssertNil(model.resolveLedger(forEdge: "house-edge", houseSideBeamSpanInches: 144))
        XCTAssertEqual(model.drawingData.house, original.house)
        XCTAssertTrue(persisted.isEmpty)
    }

    private func drawingDataWithHouse() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 240, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 240, y: 120)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 120)),
        ]
        data.edges = [
            DeckEdge(
                id: "house-edge",
                startVertexId: "v1",
                endVertexId: "v2",
                edgeType: .houseEdge,
                dimension: 120,
                label: "Kitchen wall"
            ),
            DeckEdge(id: "side-edge", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "front-edge", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "return-edge", startVertexId: "v4", endVertexId: "v1"),
        ]
        data.scaleFactor = 2
        data.house = HouseModel(
            floorLineFeet: 1,
            storyHeights: [9],
            openings: [
                WallOpening(
                    id: "opening-1",
                    edgeId: "house-edge",
                    kind: .patioDoor,
                    widthInches: 72,
                    heightInches: 80,
                    sillHeightInches: 0,
                    offsetAlongEdgeInches: 24
                ),
            ],
            ledger: LedgerDetail(cladding: .stucco, attachmentAllowed: true)
        )
        return data
    }
}
