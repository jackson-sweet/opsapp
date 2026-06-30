import CoreGraphics
import XCTest
@testable import DeckKit

final class StairsToGradeEngineTests: XCTestCase {
    func test_totalRiseFromFloorLineToZeroGrade() {
        var data = DeckDrawingData()
        data.house = HouseModel(floorLineFeet: 10)

        XCTAssertEqual(
            StairsToGradeEngine.totalRiseToGradeInches(levelId: nil, data: data),
            120
        )
    }

    func test_totalRiseUsesLevelElevationWhenNoFloorLine() {
        var upper = DeckLevel(id: "upper", name: "Upper")
        upper.elevation = 8

        var data = DeckDrawingData()
        data.levels = [upper]
        data.house = HouseModel(floorLineFeet: nil)

        XCTAssertEqual(
            StairsToGradeEngine.totalRiseToGradeInches(levelId: "upper", data: data),
            96
        )
    }

    func test_totalRiseAddsLowestCapturedTerrainDrop() {
        var data = DeckDrawingData()
        data.house = HouseModel(floorLineFeet: 4)
        data.terrain = TerrainModel(
            gradePoints: [
                GradePoint(position: CGPoint(x: 0, y: 0), dropFeet: 0.5),
                GradePoint(position: CGPoint(x: 120, y: 0), dropFeet: 2),
            ]
        )

        XCTAssertEqual(
            StairsToGradeEngine.totalRiseToGradeInches(levelId: nil, data: data),
            72
        )
    }

    func test_singleFlightForShortRise() throws {
        var data = DeckDrawingData()
        data.house = HouseModel(floorLineFeet: 4)

        let result = StairsToGradeEngine.stairsToGrade(
            levelId: nil,
            widthInches: 42,
            data: data
        )
        let expected = StairCalculator.calculate(totalRise: 48, width: 42)

        XCTAssertEqual(result.flights.count, 1)
        XCTAssertEqual(result.landingCount, 0)
        XCTAssertFalse(result.landingInserted)
        XCTAssertEqual(result.totalRiseInches, 48)
        try assertSpec(result.flights[0], equals: expected)
    }

    func test_landingInsertedForTallRise() {
        var data = DeckDrawingData()
        data.house = HouseModel(floorLineFeet: 15)

        let result = StairsToGradeEngine.stairsToGrade(
            levelId: nil,
            widthInches: 48,
            data: data,
            maxRiseWithoutLandingInches: 147
        )

        XCTAssertTrue(result.landingInserted)
        XCTAssertEqual(result.flights.count, 2)
        XCTAssertEqual(result.landingCount, 1)
        XCTAssertEqual(result.flights.reduce(0) { $0 + $1.totalRise }, 180, accuracy: 0.0001)
        XCTAssertTrue(result.flights.allSatisfy { $0.totalRise <= 147 })
    }

    func test_eachFlightUsesStairCalculatorUnchanged() throws {
        var data = DeckDrawingData()
        data.house = HouseModel(floorLineFeet: 18)

        let result = StairsToGradeEngine.stairsToGrade(
            levelId: nil,
            widthInches: 54,
            data: data,
            maxRiseWithoutLandingInches: 100
        )

        let expected = StairCalculator.calculate(totalRise: 72, width: 54)
        let firstFlight = try XCTUnwrap(result.flights.first)

        XCTAssertEqual(result.flights.count, 3)
        try assertSpec(firstFlight, equals: expected)
    }

    func test_zeroRiseYieldsNoFlights() {
        var data = DeckDrawingData()
        data.house = HouseModel(floorLineFeet: 0)

        let result = StairsToGradeEngine.stairsToGrade(
            levelId: nil,
            widthInches: 48,
            data: data
        )

        XCTAssertEqual(result.flights.count, 0)
        XCTAssertEqual(result.landingCount, 0)
        XCTAssertEqual(result.totalRiseInches, 0)
        XCTAssertFalse(result.landingInserted)
    }

    private func assertSpec(
        _ actual: StairCalculator.StairSpec,
        equals expected: StairCalculator.StairSpec,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(actual.treadCount, expected.treadCount, file: file, line: line)
        XCTAssertEqual(actual.risePerStep, expected.risePerStep, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.runPerTread, expected.runPerTread, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.totalRise, expected.totalRise, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.totalRun, expected.totalRun, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.stringerLength, expected.stringerLength, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.stringerCount, expected.stringerCount, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.0001, file: file, line: line)
    }
}
