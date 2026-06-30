import XCTest
@testable import DeckKit

final class HouseOpeningScheduleViewModelTests: XCTestCase {
    func test_scheduleViewModel_emptyState() {
        let model = HouseOpeningScheduleViewModel(rows: [])

        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(model.emptyStateText, "—")
        XCTAssertEqual(model.displayRows, [])
    }

    func test_scheduleViewModel_formatsRowsForPermitTable() {
        let sourceRows = [
            HouseOpeningSchedule.ScheduleRow(
                id: "door",
                calloutTag: "D1",
                kindDisplay: "Patio door",
                widthInches: 72,
                heightInches: 80,
                sillHeightInches: 0,
                edgeId: "house-a"
            ),
            HouseOpeningSchedule.ScheduleRow(
                id: "window",
                calloutTag: "W1",
                kindDisplay: "Window",
                widthInches: 48,
                heightInches: 42,
                sillHeightInches: 30,
                edgeId: "house-b"
            ),
        ]

        let model = HouseOpeningScheduleViewModel(
            rows: sourceRows,
            edgeLabelsById: [
                "house-a": "Kitchen wall",
            ]
        )

        XCTAssertFalse(model.isEmpty)
        XCTAssertEqual(model.displayRows.map(\.calloutTag), ["D1", "W1"])
        XCTAssertEqual(model.displayRows.map(\.kindLabel), ["PATIO DOOR", "WINDOW"])
        XCTAssertEqual(model.displayRows.map(\.sizeLabel), ["6′-0″ × 6′-8″", "4′-0″ × 3′-6″"])
        XCTAssertEqual(model.displayRows.map(\.sillLabel), ["0″", "2′-6″"])
        XCTAssertEqual(model.displayRows.map(\.edgeLabel), ["KITCHEN WALL", "HOUSE-B"])
    }
}
