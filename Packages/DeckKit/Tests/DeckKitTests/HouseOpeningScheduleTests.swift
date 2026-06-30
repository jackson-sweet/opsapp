import XCTest
@testable import DeckKit

final class HouseOpeningScheduleTests: XCTestCase {
    func test_doorsGetDWindowsGetW() throws {
        let door = opening(
            id: "patio-door",
            kind: .patioDoor,
            widthInches: 72,
            heightInches: 80,
            sillHeightInches: 0,
            offsetAlongEdgeInches: 24
        )
        let window = opening(
            id: "kitchen-window",
            kind: .window,
            widthInches: 48,
            heightInches: 42,
            sillHeightInches: 30,
            offsetAlongEdgeInches: 108
        )
        let rows = HouseOpeningSchedule.rows(for: data(openings: [window, door]))

        let doorRow = try XCTUnwrap(rows.first { $0.id == "patio-door" })
        XCTAssertEqual(doorRow.calloutTag, "D1")
        XCTAssertEqual(doorRow.kindDisplay, "Patio door")
        XCTAssertEqual(doorRow.widthInches, 72)
        XCTAssertEqual(doorRow.heightInches, 80)
        XCTAssertEqual(doorRow.sillHeightInches, 0)
        XCTAssertEqual(doorRow.edgeId, "edge-a")

        let windowRow = try XCTUnwrap(rows.first { $0.id == "kitchen-window" })
        XCTAssertEqual(windowRow.calloutTag, "W1")
        XCTAssertEqual(windowRow.kindDisplay, "Window")
        XCTAssertEqual(windowRow.widthInches, 48)
        XCTAssertEqual(windowRow.heightInches, 42)
        XCTAssertEqual(windowRow.sillHeightInches, 30)
        XCTAssertEqual(windowRow.edgeId, "edge-a")
    }

    func test_numberingIsStableByEdgeThenOffset() {
        let openings = [
            opening(id: "door-edge-a-second", kind: .patioDoor, edgeId: "edge-a", offsetAlongEdgeInches: 80),
            opening(id: "window-edge-b-first", kind: .window, edgeId: "edge-b", offsetAlongEdgeInches: 10),
            opening(id: "door-edge-b-first", kind: .sliderDoor, edgeId: "edge-b", offsetAlongEdgeInches: 20),
            opening(id: "window-edge-a-first", kind: .window, edgeId: "edge-a", offsetAlongEdgeInches: 40),
            opening(id: "door-edge-a-first", kind: .frenchDoor, edgeId: "edge-a", offsetAlongEdgeInches: 10),
        ]
        let firstPass = HouseOpeningSchedule.rows(for: data(openings: openings))
        let secondPass = HouseOpeningSchedule.rows(for: data(openings: Array(openings.reversed())))
        let tags = tagsById(firstPass)

        XCTAssertEqual(firstPass, secondPass)
        XCTAssertEqual(tags["door-edge-a-first"], "D1")
        XCTAssertEqual(tags["door-edge-a-second"], "D2")
        XCTAssertEqual(tags["door-edge-b-first"], "D3")
        XCTAssertEqual(tags["window-edge-a-first"], "W1")
        XCTAssertEqual(tags["window-edge-b-first"], "W2")
    }

    func test_calloutTagMatchesRows() {
        let openings = [
            opening(id: "side-door", kind: .sliderDoor, edgeId: "edge-b", offsetAlongEdgeInches: 12),
            opening(id: "bedroom-window", kind: .window, edgeId: "edge-a", offsetAlongEdgeInches: 24),
        ]
        let drawing = data(openings: openings)

        for row in HouseOpeningSchedule.rows(for: drawing) {
            XCTAssertEqual(HouseOpeningSchedule.calloutTag(for: row.id, in: drawing), row.calloutTag)
        }
        XCTAssertNil(HouseOpeningSchedule.calloutTag(for: "missing-opening", in: drawing))
    }

    func test_emptyHouseYieldsNoRows() {
        XCTAssertEqual(HouseOpeningSchedule.rows(for: DeckDrawingData()), [])

        var emptyHouseData = DeckDrawingData()
        emptyHouseData.house = HouseModel(openings: [])

        XCTAssertEqual(HouseOpeningSchedule.rows(for: emptyHouseData), [])
        XCTAssertNil(HouseOpeningSchedule.calloutTag(for: "missing", in: emptyHouseData))
    }

    func test_frenchDoorAndSliderDoorCountAsDoors() {
        let openings = [
            opening(id: "window", kind: .window, edgeId: "edge-a", offsetAlongEdgeInches: 5),
            opening(id: "slider", kind: .sliderDoor, edgeId: "edge-a", offsetAlongEdgeInches: 10),
            opening(id: "patio", kind: .patioDoor, edgeId: "edge-a", offsetAlongEdgeInches: 20),
            opening(id: "french", kind: .frenchDoor, edgeId: "edge-b", offsetAlongEdgeInches: 10),
        ]
        let rows = HouseOpeningSchedule.rows(for: data(openings: openings))
        let tags = tagsById(rows)

        XCTAssertEqual(tags["slider"], "D1")
        XCTAssertEqual(tags["patio"], "D2")
        XCTAssertEqual(tags["french"], "D3")
        XCTAssertEqual(tags["window"], "W1")
    }

    private func data(openings: [WallOpening]) -> DeckDrawingData {
        var data = DeckDrawingData()
        data.house = HouseModel(floorLineFeet: 9, storyHeights: [9], openings: openings)
        return data
    }

    private func opening(
        id: String,
        kind: OpeningKind,
        edgeId: String = "edge-a",
        widthInches: Double = 48,
        heightInches: Double = 42,
        sillHeightInches: Double = 30,
        offsetAlongEdgeInches: Double
    ) -> WallOpening {
        WallOpening(
            id: id,
            edgeId: edgeId,
            kind: kind,
            widthInches: widthInches,
            heightInches: heightInches,
            sillHeightInches: sillHeightInches,
            offsetAlongEdgeInches: offsetAlongEdgeInches
        )
    }

    private func tagsById(_ rows: [HouseOpeningSchedule.ScheduleRow]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.calloutTag) })
    }
}
