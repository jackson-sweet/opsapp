// OPS/OPSTests/DeckBuilder/DeckMeasurementPickerTests.swift

import XCTest
@testable import OPS

final class DeckMeasurementPickerTests: XCTestCase {

    func testImperialOverflowNormalizesThroughStandardValue() {
        let value = DeckMeasurementValue.imperial(feet: 2, inches: 48, sixteenths: 0)
        let components = value.imperialComponents

        XCTAssertEqual(value.totalInches, 72, accuracy: 0.0001)
        XCTAssertEqual(components.feet, 6)
        XCTAssertEqual(components.inches, 0)
        XCTAssertEqual(components.sixteenths, 0)
    }

    func testMetricComponentsRoundTripThroughStandardValue() {
        let value = DeckMeasurementValue.metric(meters: 2, centimeters: 40, millimeters: 5)
        let components = value.metricComponents

        XCTAssertEqual(value.totalInches, 2405.0 / 25.4, accuracy: 0.0001)
        XCTAssertEqual(components.meters, 2)
        XCTAssertEqual(components.centimeters, 40)
        XCTAssertEqual(components.millimeters, 5)
    }

    func testLegacyPerimeterDraftAliasesStandardValue() {
        let value: PerimeterLengthDraft = .imperial(feet: 6, inches: 0, sixteenths: 0)

        XCTAssertEqual(value.totalInches, DeckMeasurementValue.imperial(feet: 6, inches: 0, sixteenths: 0).totalInches)
    }

    func testMeasurementWheelDataClampsSelectionIntoConfiguredRange() {
        XCTAssertEqual(DeckMeasurementWheelData.clampedValue(-4, in: 0...10), 0)
        XCTAssertEqual(DeckMeasurementWheelData.clampedValue(7, in: 0...10), 7)
        XCTAssertEqual(DeckMeasurementWheelData.clampedValue(22, in: 0...10), 10)
    }

    func testMeasurementWheelDataMapsRowsToRangeValues() {
        XCTAssertEqual(DeckMeasurementWheelData.row(for: 12, in: 10...15), 2)
        XCTAssertEqual(DeckMeasurementWheelData.row(for: 99, in: 10...15), 5)
        XCTAssertEqual(DeckMeasurementWheelData.value(forRow: 0, in: 10...15), 10)
        XCTAssertEqual(DeckMeasurementWheelData.value(forRow: 4, in: 10...15), 14)
        XCTAssertEqual(DeckMeasurementWheelData.value(forRow: 100, in: 10...15), 15)
    }
}
