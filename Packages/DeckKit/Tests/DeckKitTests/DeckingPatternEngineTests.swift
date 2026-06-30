import CoreGraphics
import XCTest
@testable import DeckKit

final class DeckingPatternEngineTests: XCTestCase {
    func testParallelRectangleBoardCountUsesRawCoverageWithoutWaste() {
        let layout = DeckingPatternEngine.layout(
            surfacePolygon: rectangle(width: 192, height: 144),
            scaleFactor: 1,
            spec: SurfacePatternSpec(surfaceId: "surface-main", pattern: .parallel),
            boardWidthInches: 5.5,
            boardLengthInches: 192,
            gapInches: 0.1875
        )

        XCTAssertEqual(layout.boardCount, 26)
        XCTAssertEqual(layout.boards.count, 26)
        XCTAssertEqual(layout.coveredAreaSqFt, 192, accuracy: 0.001)
        XCTAssertTrue(layout.boards.allSatisfy { $0.lengthInches == 192 })
        XCTAssertTrue(layout.boards.allSatisfy { $0.runAxisDegrees == 0 })
        XCTAssertTrue(layout.boards.allSatisfy { $0.startMiterDegrees == 0 && $0.endMiterDegrees == 0 })
        XCTAssertTrue(layout.boards.allSatisfy { !$0.isBorder })
        XCTAssertTrue(layout.pictureFrameCourses.isEmpty)
        XCTAssertNil(layout.blockingRequirement.maxBlockingSpacingInchesOC)
        XCTAssertFalse(layout.blockingRequirement.perimeterBlockingRequired)
        XCTAssertEqual(layout.blockingRequirement.codeSection, "")
    }

    func testDiagonalTriggersDCA6BlockingAndMiteredCuts() {
        let layout = DeckingPatternEngine.layout(
            surfacePolygon: rectangle(width: 120, height: 120),
            scaleFactor: 1,
            spec: SurfacePatternSpec(surfaceId: "surface-main", pattern: .diagonal, boardAngleDegrees: 45),
            boardWidthInches: 5.5,
            boardLengthInches: 240,
            gapInches: 0.1875
        )

        XCTAssertEqual(layout.boardCount, 30)
        XCTAssertEqual(layout.boards.count, 30)
        XCTAssertTrue(layout.boards.allSatisfy { $0.runAxisDegrees == 45 })
        XCTAssertTrue(layout.boards.allSatisfy { $0.startMiterDegrees == 45 && $0.endMiterDegrees == 45 })
        XCTAssertEqual(layout.boards.first?.lengthInches ?? 0, 169.706, accuracy: 0.01)
        XCTAssertEqual(layout.blockingRequirement.maxBlockingSpacingInchesOC, 12)
        XCTAssertFalse(layout.blockingRequirement.perimeterBlockingRequired)
        XCTAssertTrue(layout.blockingRequirement.codeSection.contains("DCA6"))
        XCTAssertTrue(layout.blockingRequirement.codeSection.contains("diagonal"))
    }

    func testPictureFrameCoursesAndPerimeterBlocking() {
        let layout = DeckingPatternEngine.layout(
            surfacePolygon: rectangle(width: 120, height: 96),
            scaleFactor: 1,
            spec: SurfacePatternSpec(
                surfaceId: "surface-main",
                pattern: .pictureFrame,
                boardAngleDegrees: 0,
                pictureFrameCourses: 2
            ),
            boardWidthInches: 5.5,
            boardLengthInches: 240,
            gapInches: 0.1875
        )

        XCTAssertEqual(layout.pictureFrameCourses.count, 2)
        XCTAssertEqual(layout.pictureFrameCourses[0].ringIndex, 0)
        XCTAssertEqual(layout.pictureFrameCourses[0].perimeterFeet, 36, accuracy: 0.001)
        XCTAssertEqual(layout.pictureFrameCourses[1].ringIndex, 1)
        XCTAssertEqual(layout.pictureFrameCourses[1].perimeterFeet, 32.208, accuracy: 0.001)
        XCTAssertEqual(layout.boards.filter(\.isBorder).count, 8)
        XCTAssertTrue(layout.boards.filter(\.isBorder).allSatisfy { $0.startMiterDegrees == 45 && $0.endMiterDegrees == 45 })
        XCTAssertTrue(layout.boards.contains { !$0.isBorder })
        XCTAssertTrue(layout.blockingRequirement.perimeterBlockingRequired)
        XCTAssertNil(layout.blockingRequirement.maxBlockingSpacingInchesOC)
        XCTAssertTrue(layout.blockingRequirement.codeSection.contains("picture-frame"))
    }

    func testHerringboneAndChevronUseComplementaryMitersAndScaledCounts() {
        let herringbone = DeckingPatternEngine.layout(
            surfacePolygon: rectangle(width: 96, height: 96),
            scaleFactor: 1,
            spec: SurfacePatternSpec(surfaceId: "surface-main", pattern: .herringbone, boardAngleDegrees: 45),
            boardWidthInches: 5.5,
            boardLengthInches: 120,
            gapInches: 0.1875
        )

        XCTAssertEqual(herringbone.boardCount, 48)
        XCTAssertEqual(Set(herringbone.boards.map(\.runAxisDegrees)), [45, 135])
        XCTAssertTrue(herringbone.boards.allSatisfy { $0.startMiterDegrees == 45 && $0.endMiterDegrees == 45 })
        XCTAssertTrue(herringbone.layoutWarnings.isEmpty)

        let chevron = DeckingPatternEngine.layout(
            surfacePolygon: rectangle(width: 96, height: 96),
            scaleFactor: 1,
            spec: SurfacePatternSpec(surfaceId: "surface-main", pattern: .chevron, boardAngleDegrees: 45),
            boardWidthInches: 5.5,
            boardLengthInches: 120,
            gapInches: 0.1875
        )

        XCTAssertEqual(chevron.boardCount, 48)
        XCTAssertEqual(Set(chevron.boards.map(\.runAxisDegrees)), [45, 135])
        XCTAssertTrue(chevron.boards.allSatisfy { $0.startMiterDegrees == 45 && $0.endMiterDegrees == -45 })
        XCTAssertTrue(chevron.layoutWarnings.isEmpty)
    }

    func testNonRectilinearHerringboneCarriesApproximationWarning() {
        let layout = DeckingPatternEngine.layout(
            surfacePolygon: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 120, y: 0),
                CGPoint(x: 96, y: 72),
                CGPoint(x: 0, y: 96),
            ],
            scaleFactor: 1,
            spec: SurfacePatternSpec(surfaceId: "surface-main", pattern: .herringbone, boardAngleDegrees: 45),
            boardWidthInches: 5.5,
            boardLengthInches: 120,
            gapInches: 0.1875
        )

        XCTAssertEqual(layout.layoutWarnings.count, 1)
        XCTAssertEqual(layout.layoutWarnings[0].code, .nonRectilinearPatternApproximation)
        XCTAssertEqual(layout.layoutWarnings[0].affectedPattern, .herringbone)
        XCTAssertLessThan(layout.layoutWarnings[0].quantityConfidence, 1)
        XCTAssertGreaterThan(layout.layoutWarnings[0].quantityConfidence, 0)
    }

    func testWasteIsAppliedByEstimateLayerNotPatternEngine() {
        let layout = DeckingPatternEngine.layout(
            surfacePolygon: rectangle(width: 192, height: 144),
            scaleFactor: 1,
            spec: SurfacePatternSpec(surfaceId: "surface-main", pattern: .parallel),
            boardWidthInches: 5.5,
            boardLengthInches: 192,
            gapInches: 0.1875
        )

        let manuallyWastedCount = Int(ceil(Double(layout.boardCount) * 1.1))

        XCTAssertEqual(layout.boardCount, 26)
        XCTAssertEqual(manuallyWastedCount, 29)
        XCTAssertNotEqual(layout.boardCount, manuallyWastedCount)
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
