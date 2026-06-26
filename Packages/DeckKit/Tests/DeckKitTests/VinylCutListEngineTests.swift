// OPS/OPSTests/DeckBuilder/VinylCutListEngineTests.swift

import CoreGraphics
import XCTest
@testable import DeckKit

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

    func testSettingsChangeStripCountAndOrderLineLength() {
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
        XCTAssertTrue(cut.orderLine.contains("10' 8\""))
        XCTAssertFalse(cut.orderLine.contains("X 60\""))
        XCTAssertEqual(plan.totalOrderedSqFt, 267)
    }

    func testLShapedSurfaceCutsUseVariableLengthsToReduceWaste() {
        let surface = lShape(
            id: "main",
            width: 240,
            height: 192,
            notchWidth: 144,
            notchHeight: 96
        )
        let settings = VinylOrderSettings(
            color: "",
            rollWidthInches: 72,
            seamOverlapInches: 0,
            edgeWrapInches: 0,
            direction: .lengthwise
        )

        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: settings
        )

        let cut = try! XCTUnwrap(plan.surfaces.first)
        XCTAssertEqual(cut.stripCount, 3)
        XCTAssertEqual(cut.cutAreaSqFt, 288, accuracy: 0.01)
        XCTAssertTrue(cut.orderLine.contains("2 CUTS @ 20'"), cut.orderLine)
        XCTAssertTrue(cut.orderLine.contains("1 CUT @ 8'"), cut.orderLine)
        XCTAssertFalse(cut.orderLine.contains("3 CUTS @ 20'"), cut.orderLine)
        XCTAssertFalse(cut.orderLine.contains("SQ FT"), cut.orderLine)
    }

    func testLShapedSurfaceCutPiecesCarryPreviewGeometry() {
        let surface = lShape(
            id: "main",
            width: 240,
            height: 192,
            notchWidth: 144,
            notchHeight: 96
        )
        let settings = VinylOrderSettings(
            color: "",
            rollWidthInches: 72,
            seamOverlapInches: 0,
            edgeWrapInches: 0,
            direction: .lengthwise
        )

        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: settings
        )

        let surfacePlan = try! XCTUnwrap(plan.surfaces.first)
        let shortCut = try! XCTUnwrap(surfacePlan.cuts.first { abs($0.lengthInches - 96) < 0.01 })
        let longCut = try! XCTUnwrap(surfacePlan.cuts.first { abs($0.lengthInches - 240) < 0.01 })

        XCTAssertEqual(shortCut.runStartInches, 0, accuracy: 0.01)
        XCTAssertEqual(shortCut.runEndInches, 96, accuracy: 0.01)
        XCTAssertEqual(longCut.runStartInches, 0, accuracy: 0.01)
        XCTAssertEqual(longCut.runEndInches, 240, accuracy: 0.01)
        XCTAssertNotEqual(shortCut.bandStartInches, longCut.bandStartInches)
    }

    func testTextMessageBodyOnlyIncludesColorAndCuts() {
        let surface = lShape(
            id: "main",
            label: "Main deck",
            width: 240,
            height: 192,
            notchWidth: 144,
            notchHeight: 96
        )
        let settings = VinylOrderSettings(
            color: "Weathered grey",
            rollWidthInches: 72,
            seamOverlapInches: 0,
            edgeWrapInches: 0,
            direction: .lengthwise
        )

        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: settings
        )

        let body = plan.textMessageBody()

        XCTAssertEqual(body, """
        Color: Weathered grey
        -2 @ 20'
        -1 @ 8'
        """)
        XCTAssertFalse(body.contains("PROJECT"))
        XCTAssertFalse(body.contains("ORDER AREA"))
        XCTAssertFalse(body.contains("OFFCUT"))
        XCTAssertFalse(body.contains("SQ FT"))
        XCTAssertFalse(body.contains(" X 72\""))
        XCTAssertFalse(body.contains("240\""))
    }

    func testTextMessageBodyUsesCustomTemplate() {
        let surface = rectangle(id: "main", label: "Main deck", width: 96, height: 36)
        let settings = VinylOrderSettings(
            color: "Slate",
            rollWidthInches: 72,
            seamOverlapInches: 0,
            edgeWrapInches: 0,
            direction: .lengthwise
        )

        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: settings
        )

        let body = plan.textMessageBody(
            messageTemplate: "VINYL [color]\nCOUNT [cut_count]\n[cuts]",
            cutTemplate: "[surface]: [quantity] @ [length]",
            cutSeparator: .lines
        )

        XCTAssertEqual(body, """
        VINYL Slate
        COUNT 1
        MAIN DECK: 1 @ 8'
        """)
    }

    func testTextMessageBodyCanUseInlineCutTemplate() {
        let surface = lShape(
            id: "main",
            label: "Main deck",
            width: 240,
            height: 192,
            notchWidth: 144,
            notchHeight: 96
        )
        let settings = VinylOrderSettings(
            color: "Weathered grey",
            rollWidthInches: 72,
            seamOverlapInches: 0,
            edgeWrapInches: 0,
            direction: .lengthwise
        )

        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: settings
        )

        let body = plan.textMessageBody(
            messageTemplate: "Hi there, please order in [Color] for [Cuts].",
            cutTemplate: "[length] x [quantity]",
            cutSeparator: .comma
        )

        XCTAssertEqual(body, "Hi there, please order in Weathered grey for 20' x 2, 8' x 1.")
    }

    func testPlanCarriesHouseEdgesForPreviewLabels() {
        var surface = rectangle(id: "main", label: "Main deck", width: 240, height: 120)
        surface.edges = [
            VinylOrderSurfaceEdge(
                id: "house",
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 240, y: 0),
                edgeType: .houseEdge,
                label: nil
            ),
            VinylOrderSurfaceEdge(
                id: "outer",
                start: CGPoint(x: 240, y: 120),
                end: CGPoint(x: 0, y: 120),
                edgeType: .deckEdge,
                label: nil
            )
        ]
        let settings = VinylOrderSettings(
            color: "Weathered grey",
            rollWidthInches: 72,
            seamOverlapInches: 0,
            edgeWrapInches: 6,
            direction: .lengthwise
        )

        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: settings
        )

        let surfacePlan = try! XCTUnwrap(plan.surfaces.first)
        XCTAssertEqual(surfacePlan.edges.filter { $0.edgeType == .houseEdge }.count, 1)
        XCTAssertEqual(surfacePlan.edges.filter { $0.edgeType == .deckEdge }.count, 1)
    }

    func testAutomaticCanAllowTurnedCutsWhenTheyReduceWaste() {
        let surface = lShape(
            id: "main",
            width: 300,
            height: 300,
            notchWidth: 230,
            notchHeight: 230
        )

        let sameRunPlan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: VinylOrderSettings(
                color: "",
                rollWidthInches: 72,
                seamOverlapInches: 0,
                edgeWrapInches: 0,
                direction: .automatic,
                allowsDirectionalChanges: false
            )
        )
        let turnedPlan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: VinylOrderSettings(
                color: "",
                rollWidthInches: 72,
                seamOverlapInches: 0,
                edgeWrapInches: 0,
                direction: .automatic,
                allowsDirectionalChanges: true
            )
        )

        let sameRunCut = try! XCTUnwrap(sameRunPlan.surfaces.first)
        let turnedCut = try! XCTUnwrap(turnedPlan.surfaces.first)
        XCTAssertFalse(sameRunCut.hasMixedRunAxes)
        XCTAssertTrue(turnedCut.hasMixedRunAxes)
        XCTAssertLessThan(turnedCut.cutAreaSqFt, sameRunCut.cutAreaSqFt)
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
        XCTAssertEqual(plan.totalReusedCutAreaSqFt, 48, accuracy: 0.01)
        XCTAssertEqual(plan.totalOrderedSqFt, 288)
    }

    func testOffcutReuseDoesNotCombineShorterPiecesIntoButtJoint() {
        let shortA = rectangle(id: "short-a", label: "Short A", width: 96, height: 36)
        let shortB = rectangle(id: "short-b", label: "Short B", width: 96, height: 36)
        let longPatch = rectangle(id: "long-patch", label: "Long patch", width: 120, height: 36)
        let settings = VinylOrderSettings(
            color: "",
            rollWidthInches: 72,
            seamOverlapInches: 0,
            edgeWrapInches: 0,
            direction: .lengthwise
        )

        let plan = VinylCutListEngine.makePlan(
            surfaces: [shortA, shortB, longPatch],
            settings: settings
        )

        XCTAssertFalse(plan.reuseNotes.contains { $0.targetSurfaceLabel == "Long patch" })
        let longPlan = try! XCTUnwrap(plan.surfaces.first { $0.label == "Long patch" })
        XCTAssertEqual(longPlan.purchasedCuts.count, 1)
        XCTAssertTrue(longPlan.reusedCuts.isEmpty)
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
        XCTAssertTrue(notes.contains("REUSED AREA: 48.0 SQ FT"))
        XCTAssertTrue(notes.contains("// CUT LIST"))
        XCTAssertTrue(notes.contains("MAIN DECK:"))
        XCTAssertTrue(notes.contains("// OFFCUT REUSE"))
    }

    func testCatalogMatcherRejectsDiverterAndPrefersMembrane() {
        let diverter = candidate(
            itemId: "item-diverter",
            variantId: "variant-diverter",
            name: "Vinyl Diverter",
            description: "Deck drainage diverter",
            sku: "VINYL-DIVERTER-RIGHT"
        )
        let deckSheet = candidate(
            itemId: "item-sheet",
            variantId: "variant-sheet",
            name: "Vinyl deck sheet",
            description: "72 in roll",
            sku: "VINYL-DECK-SHEET"
        )
        let membrane = candidate(
            itemId: "item-membrane",
            variantId: "variant-membrane",
            name: "Vinyl membrane roll",
            description: "72 in waterproof deck membrane",
            sku: "VINYL-MEMBRANE-72"
        )

        let match = VinylCatalogMatcher.bestMatch(
            from: [diverter, deckSheet, membrane],
            preferredRollWidthInches: 72
        )

        XCTAssertEqual(match?.variantId, "variant-membrane")
    }

    func testCatalogMatcherIsDeterministicForEqualMatches() {
        let zed = candidate(
            itemId: "item-zed",
            variantId: "variant-zed",
            name: "Zed vinyl membrane",
            description: "72 in roll",
            sku: "VINYL-ZED"
        )
        let alpha = candidate(
            itemId: "item-alpha",
            variantId: "variant-alpha",
            name: "Alpha vinyl membrane",
            description: "72 in roll",
            sku: "VINYL-ALPHA"
        )

        let match = VinylCatalogMatcher.bestMatch(
            from: [zed, alpha],
            preferredRollWidthInches: 72
        )

        XCTAssertEqual(match?.variantId, "variant-alpha")
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

    private func lShape(
        id: String,
        label: String = "Surface",
        width: Double,
        height: Double,
        notchWidth: Double,
        notchHeight: Double
    ) -> VinylOrderSurfaceInput {
        VinylOrderSurfaceInput(
            id: id,
            label: label,
            levelName: nil,
            positions: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: width, y: 0),
                CGPoint(x: width, y: height - notchHeight),
                CGPoint(x: width - notchWidth, y: height - notchHeight),
                CGPoint(x: width - notchWidth, y: height),
                CGPoint(x: 0, y: height)
            ],
            scaleFactor: 1
        )
    }

    private func candidate(
        itemId: String,
        variantId: String,
        name: String,
        description: String,
        sku: String
    ) -> VinylCatalogCandidate {
        VinylCatalogCandidate(
            itemId: itemId,
            variantId: variantId,
            itemName: name,
            itemDescription: description,
            itemNotes: nil,
            variantSku: sku,
            itemUnitId: nil,
            variantUnitId: nil,
            isItemActive: true,
            itemDeleted: false,
            isVariantActive: true,
            variantDeleted: false
        )
    }
}
