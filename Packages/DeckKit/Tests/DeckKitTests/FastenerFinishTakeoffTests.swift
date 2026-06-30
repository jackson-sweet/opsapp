import CoreGraphics
import XCTest
@testable import DeckKit

final class FastenerFinishTakeoffTests: XCTestCase {
    func testHiddenClipCountsOneClipPerBoardToJoistCrossing() {
        let takeoff = FastenerFinishTakeoff.fasteners(
            system: .hiddenClip,
            boards: [
                board("board-a", length: 192),
                board("board-b", length: 192),
                board("board-c", length: 192),
            ],
            joistSpacingInchesOC: 16,
            surfacePolygon: rectangle(width: 192, height: 144),
            scaleFactor: 1
        )

        XCTAssertEqual(takeoff.system, .hiddenClip)
        XCTAssertEqual(takeoff.boardToJoistCrossings, 39)
        XCTAssertEqual(takeoff.clipCount, 39)
        XCTAssertEqual(takeoff.screwCount, 0)
        XCTAssertEqual(takeoff.joistSpacingInchesOC, 16, accuracy: 0.001)
        XCTAssertEqual(takeoff.basis, .layoutDerived)
    }

    func testFaceScrewCountsTwoScrewsPerBoardToJoistCrossing() {
        let takeoff = FastenerFinishTakeoff.fasteners(
            system: .faceScrew,
            boards: [
                board("board-a", length: 192),
                board("board-b", length: 192),
            ],
            joistSpacingInchesOC: 16,
            surfacePolygon: rectangle(width: 192, height: 144),
            scaleFactor: 1
        )

        XCTAssertEqual(takeoff.system, .faceScrew)
        XCTAssertEqual(takeoff.boardToJoistCrossings, 26)
        XCTAssertEqual(takeoff.clipCount, 0)
        XCTAssertEqual(takeoff.screwCount, 52)
        XCTAssertEqual(takeoff.basis, .layoutDerived)
    }

    func testInvalidSpacingFallsBackToEstimateGradeFieldDefault() {
        let takeoff = FastenerFinishTakeoff.fasteners(
            system: .hiddenClip,
            boards: [board("board-a", length: 192)],
            joistSpacingInchesOC: 0,
            surfacePolygon: rectangle(width: 192, height: 144),
            scaleFactor: 1
        )

        XCTAssertEqual(takeoff.boardToJoistCrossings, 13)
        XCTAssertEqual(takeoff.clipCount, 13)
        XCTAssertEqual(takeoff.screwCount, 0)
        XCTAssertEqual(takeoff.joistSpacingInchesOC, 16, accuracy: 0.001)
        XCTAssertEqual(takeoff.basis, .estimateGrade)
    }

    func testZeroBoardsProduceZeroFasteners() {
        let takeoff = FastenerFinishTakeoff.fasteners(
            system: .faceScrew,
            boards: [],
            joistSpacingInchesOC: 16,
            surfacePolygon: rectangle(width: 192, height: 144),
            scaleFactor: 1
        )

        XCTAssertEqual(takeoff.boardToJoistCrossings, 0)
        XCTAssertEqual(takeoff.clipCount, 0)
        XCTAssertEqual(takeoff.screwCount, 0)
        XCTAssertEqual(takeoff.basis, .layoutDerived)
    }

    func testFinishTakeoffUsesRawAreaTimesCoatsOverCoverage() {
        let takeoffs = FastenerFinishTakeoff.finishes(
            specs: [
                FinishSpec(kind: "stain", coats: 2),
                FinishSpec(kind: "sealant", coats: 1),
            ],
            coatedAreaSqFt: 200,
            coveragePerUnitSqFt: 250
        )

        XCTAssertEqual(takeoffs, [
            FinishTakeoff(kind: "stain", coats: 2, unitsRequired: 1.6),
            FinishTakeoff(kind: "sealant", coats: 1, unitsRequired: 0.8),
        ])
    }

    func testFinishTakeoffNeverReturnsNegativeQuantities() {
        let takeoffs = FastenerFinishTakeoff.finishes(
            specs: [FinishSpec(kind: "stain", coats: -2)],
            coatedAreaSqFt: -200,
            coveragePerUnitSqFt: 0
        )

        XCTAssertEqual(takeoffs, [
            FinishTakeoff(kind: "stain", coats: 0, unitsRequired: 0),
        ])
    }

    private func board(_ id: String, length: Double) -> DeckBoardCut {
        DeckBoardCut(
            id: id,
            lengthInches: length,
            startMiterDegrees: 0,
            endMiterDegrees: 0,
            runAxisDegrees: 0,
            isBorder: false
        )
    }

    private func rectangle(width: Double, height: Double) -> [CGPoint] {
        [
            CGPoint(x: 0, y: 0),
            CGPoint(x: width, y: 0),
            CGPoint(x: width, y: height),
            CGPoint(x: 0, y: height),
        ]
    }
}
