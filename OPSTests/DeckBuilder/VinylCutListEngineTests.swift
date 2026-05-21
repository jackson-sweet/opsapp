// OPS/OPSTests/DeckBuilder/VinylCutListEngineTests.swift

import CoreGraphics
import XCTest
@testable import OPS

final class VinylCutListEngineTests: XCTestCase {

    func testAutomaticDirectionChoosesLowerWasteForRectangle() {
        let surface = rectangle(id: "main", width: 288, height: 192)

        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: .default
        )

        XCTAssertEqual(plan.surfaces.count, 1)
        let cut = try! XCTUnwrap(plan.surfaces.first)
        XCTAssertEqual(cut.resolvedDirection, .lengthwise)
        XCTAssertEqual(cut.stripCount, 3)
        XCTAssertEqual(cut.stripLengthInches, 300, accuracy: 0.01)
        XCTAssertEqual(cut.targetCrossInches, 204, accuracy: 0.01)
        XCTAssertEqual(plan.totalOrderedSqFt, 450)
        XCTAssertEqual(plan.totalSurfaceAreaSqFt, 384, accuracy: 0.01)
        XCTAssertEqual(plan.totalWasteSqFt, 66, accuracy: 0.01)
    }

    func testSettingsChangeStripCountAndOrderLineRollWidth() {
        let surface = rectangle(id: "main", width: 240, height: 120)
        let settings = VinylOrderSettings(
            color: "Weathered grey",
            rollWidthInches: 60,
            seamOverlapInches: 2,
            edgeWrapInches: 4,
            direction: .widthwise
        )

        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: settings
        )

        let cut = try! XCTUnwrap(plan.surfaces.first)
        XCTAssertEqual(cut.resolvedDirection, .widthwise)
        XCTAssertEqual(cut.stripCount, 5)
        XCTAssertEqual(cut.stripLengthInches, 128, accuracy: 0.01)
        XCTAssertTrue(cut.orderLine.contains("128\" X 60\""))
        XCTAssertEqual(plan.totalOrderedSqFt, 267)
    }

    func testReuseNotesIdentifyWhenOneSurfaceFitsFromAnotherOffcut() {
        let main = rectangle(id: "main", label: "Main deck", width: 288, height: 132)
        let landing = rectangle(id: "landing", label: "Landing", width: 96, height: 8)
        let settings = VinylOrderSettings(
            color: "",
            rollWidthInches: 72,
            seamOverlapInches: 2,
            edgeWrapInches: 0,
            direction: .lengthwise
        )

        let plan = VinylCutListEngine.makePlan(
            surfaces: [main, landing],
            settings: settings
        )

        XCTAssertEqual(plan.reuseNotes.count, 1)
        let note = try! XCTUnwrap(plan.reuseNotes.first)
        XCTAssertEqual(note.sourceSurfaceLabel, "Main deck")
        XCTAssertEqual(note.targetSurfaceLabel, "Landing")
        XCTAssertTrue(note.line.contains("LANDING CAN FIT FROM MAIN DECK OFFCUT"))
    }

    func testOrderNotesIncludeFieldColorCutListAndReuseBlock() {
        let main = rectangle(id: "main", label: "Main deck", width: 288, height: 132)
        let landing = rectangle(id: "landing", label: "Landing", width: 96, height: 8)
        let plan = VinylCutListEngine.makePlan(
            surfaces: [main, landing],
            settings: VinylOrderSettings(
                color: "",
                rollWidthInches: 72,
                seamOverlapInches: 2,
                edgeWrapInches: 0,
                direction: .lengthwise
            )
        )

        let notes = plan.orderNotes(projectTitle: "Canpro test", deckTitle: "Rear deck")

        XCTAssertTrue(notes.contains("// VINYL ORDER"))
        XCTAssertTrue(notes.contains("PROJECT: Canpro test"))
        XCTAssertTrue(notes.contains("DESIGN: Rear deck"))
        XCTAssertTrue(notes.contains("COLOR: FIELD CONFIRM"))
        XCTAssertTrue(notes.contains("ORDER AREA:"))
        XCTAssertTrue(notes.contains("// CUT LIST"))
        XCTAssertTrue(notes.contains("MAIN DECK:"))
        XCTAssertTrue(notes.contains("// OFFCUT REUSE"))
    }

    private func rectangle(
        id: String,
        label: String = "Surface",
        width: Double,
        height: Double
    ) -> VinylOrderSurfaceInput {
        VinylOrderSurfaceInput(
            id: id,
            label: label,
            levelName: nil,
            positions: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: width, y: 0),
                CGPoint(x: width, y: height),
                CGPoint(x: 0, y: height)
            ],
            scaleFactor: 1
        )
    }
}
