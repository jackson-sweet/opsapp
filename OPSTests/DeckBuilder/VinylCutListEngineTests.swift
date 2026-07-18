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

    func testAutomaticSolidUsesDiagonalRunOnlyWhenItClearlyReducesWaste() {
        let surface = rotatedRectangle(
            id: "main",
            label: "Main deck",
            width: 300,
            height: 48,
            angleDegrees: 45,
            edgeType: .deckEdge
        )

        let axisOnlyPlan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: VinylOrderSettings(
                color: "",
                rollWidthInches: 72,
                seamOverlapInches: 0,
                edgeWrapInches: 0,
                direction: .lengthwise
            )
        )
        let angleAwarePlan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: VinylOrderSettings(
                color: "",
                rollWidthInches: 72,
                seamOverlapInches: 0,
                edgeWrapInches: 0,
                direction: .automatic,
                patternMode: .solid
            )
        )

        let axisOnly = try! XCTUnwrap(axisOnlyPlan.surfaces.first)
        let angleAware = try! XCTUnwrap(angleAwarePlan.surfaces.first)
        XCTAssertEqual(angleAware.runDirectionLabel, "MIN WASTE")
        XCTAssertEqual(angleAware.runAngleDegrees, 135, accuracy: 0.1)
        XCTAssertLessThan(angleAware.cutAreaSqFt, axisOnly.cutAreaSqFt * 0.75)
    }

    func testAutomaticLinearUsesDominantHouseEdgeAcrossSurfaces() {
        let main = rotatedRectangle(
            id: "main",
            label: "Main deck",
            width: 300,
            height: 96,
            angleDegrees: 45,
            edgeType: .houseEdge
        )
        let landing = rotatedRectangle(
            id: "landing",
            label: "Landing",
            width: 96,
            height: 48,
            angleDegrees: 0,
            edgeType: .deckEdge
        )

        let plan = VinylCutListEngine.makePlan(
            surfaces: [main, landing],
            settings: VinylOrderSettings(
                color: "",
                rollWidthInches: 72,
                seamOverlapInches: 0,
                edgeWrapInches: 0,
                direction: .automatic,
                patternMode: .linear
            )
        )

        XCTAssertEqual(plan.surfaces.count, 2)
        XCTAssertTrue(plan.surfaces.allSatisfy { $0.runDirectionLabel == "HOUSE EDGE" })
        XCTAssertTrue(plan.surfaces.allSatisfy { abs($0.runAngleDegrees - 45) < 0.1 })
    }

    func testAutomaticLinearFallsBackToExistingAutoWhenNoVisualAxisExists() {
        let surface = rectangle(id: "main", width: 288, height: 192)

        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: VinylOrderSettings(
                color: "",
                rollWidthInches: 72,
                seamOverlapInches: 1.5,
                edgeWrapInches: 6,
                direction: .automatic,
                patternMode: .linear
            )
        )

        let cut = try! XCTUnwrap(plan.surfaces.first)
        XCTAssertEqual(cut.resolvedDirection, .lengthwise)
        XCTAssertEqual(cut.runDirectionLabel, "MIN WASTE")
        XCTAssertEqual(cut.runAngleDegrees, 0, accuracy: 0.1)
        XCTAssertEqual(cut.stripCount, 3)
        XCTAssertEqual(plan.totalOrderedSqFt, 450)
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

    /// Bug 2cb701e4: the operator can drop the project name into the supplier
    /// message with a [project] token. Absent the token the project name never
    /// leaks (existing templates are unaffected).
    func testTextMessageBodyInsertsProjectNameToken() {
        let surface = rectangle(id: "main", label: "Main deck", width: 96, height: 36)
        let settings = VinylOrderSettings(
            color: "Slate",
            rollWidthInches: 72,
            seamOverlapInches: 0,
            edgeWrapInches: 0,
            direction: .lengthwise
        )

        let plan = VinylCutListEngine.makePlan(surfaces: [surface], settings: settings)

        let body = plan.textMessageBody(
            messageTemplate: "Order for [project] in [color]:\n[cuts]",
            cutTemplate: "[quantity] @ [length]",
            cutSeparator: .lines,
            projectTitle: "Rear deck rebuild"
        )

        XCTAssertEqual(body, """
        Order for Rear deck rebuild in Slate:
        1 @ 8'
        """)
    }

    func testTextMessageBodyProjectTokenEmptyWhenNoTitle() {
        let surface = rectangle(id: "main", label: "Main deck", width: 96, height: 36)
        let settings = VinylOrderSettings(
            color: "Slate",
            rollWidthInches: 72,
            seamOverlapInches: 0,
            edgeWrapInches: 0,
            direction: .lengthwise
        )

        let plan = VinylCutListEngine.makePlan(surfaces: [surface], settings: settings)

        // Default template carries no [project] token, so the existing text-cuts
        // flow is untouched even though the parameter now exists.
        let body = plan.textMessageBody(projectTitle: "Rear deck rebuild")
        XCTAssertFalse(body.contains("Rear deck rebuild"))
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

    func testUnlockedMixedRunUsesOnlyHouseCollinearSeamEvenWhenInvalidSplitIsCheaper() {
        let positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 300, y: 0),
            CGPoint(x: 300, y: 70),
            CGPoint(x: 60, y: 70),
            CGPoint(x: 60, y: 300),
            CGPoint(x: 0, y: 300)
        ]
        let surface = VinylOrderSurfaceInput(
            id: "main",
            label: "Main deck",
            levelName: nil,
            positions: positions,
            scaleFactor: 1,
            edges: positions.indices.map { index in
                VinylOrderSurfaceEdge(
                    id: index == 3 ? "house-wall" : "edge-\(index)",
                    start: positions[index],
                    end: positions[(index + 1) % positions.count],
                    edgeType: index == 3 ? .houseEdge : .deckEdge,
                    label: nil
                )
            }
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
        XCTAssertTrue(turnedPlan.isOrderable)
        XCTAssertEqual(turnedCut.directionRegions.count, 2)

        let transition = try! XCTUnwrap(turnedCut.directionTransitions.first)
        XCTAssertEqual(transition.houseEdgeId, "house-wall")
        XCTAssertEqual(transition.segments.count, 1)
        let seam = try! XCTUnwrap(transition.segments.first)
        XCTAssertEqual(seam.start.x, 60, accuracy: 0.01)
        XCTAssertEqual(seam.end.x, 60, accuracy: 0.01)
        XCTAssertEqual([seam.start.y, seam.end.y].min() ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual([seam.start.y, seam.end.y].max() ?? -1, 70, accuracy: 0.01)

        let regionIds = Set(turnedCut.directionRegions.map(\.id))
        XCTAssertEqual(Set(turnedCut.cuts.compactMap(\.directionRegionId)), regionIds)
        XCTAssertTrue(turnedCut.cuts.allSatisfy { $0.directionRegionId != nil })
        XCTAssertLessThanOrEqual(turnedCut.cutAreaSqFt, sameRunCut.cutAreaSqFt)
    }

    func testUnlockedMixedRunCanFollowHorizontalHouseWallExtension() {
        let positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 300, y: 0),
            CGPoint(x: 300, y: 60),
            CGPoint(x: 70, y: 60),
            CGPoint(x: 70, y: 300),
            CGPoint(x: 0, y: 300)
        ]
        let surface = VinylOrderSurfaceInput(
            id: "main",
            label: "Main deck",
            levelName: nil,
            positions: positions,
            scaleFactor: 1,
            edges: positions.indices.map { index in
                VinylOrderSurfaceEdge(
                    id: index == 2 ? "house-wall" : "edge-\(index)",
                    start: positions[index],
                    end: positions[(index + 1) % positions.count],
                    edgeType: index == 2 ? .houseEdge : .deckEdge,
                    label: nil
                )
            }
        )

        let plan = VinylCutListEngine.makePlan(
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

        let surfacePlan = try! XCTUnwrap(plan.surfaces.first)
        guard let seam = surfacePlan.directionTransitions.first?.segments.first else {
            return XCTFail(
                "missing horizontal transition; issues=\(plan.issues), regions=\(surfacePlan.directionRegions), cuts=\(surfacePlan.cuts.map { $0.runAngleDegrees })"
            )
        }
        XCTAssertTrue(plan.isOrderable)
        XCTAssertEqual(seam.start.y, 60, accuracy: 0.01)
        XCTAssertEqual(seam.end.y, 60, accuracy: 0.01)
        XCTAssertEqual([seam.start.x, seam.end.x].min() ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual([seam.start.x, seam.end.x].max() ?? -1, 70, accuracy: 0.01)
    }

    func testWallAlignedTransitionDoesNotReceiveExteriorEdgeWrap() {
        let positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 300, y: 0),
            CGPoint(x: 300, y: 70),
            CGPoint(x: 60, y: 70),
            CGPoint(x: 60, y: 300),
            CGPoint(x: 0, y: 300)
        ]
        let surface = VinylOrderSurfaceInput(
            id: "main",
            label: "Main deck",
            levelName: nil,
            positions: positions,
            scaleFactor: 1,
            edges: positions.indices.map { index in
                VinylOrderSurfaceEdge(
                    id: index == 3 ? "house-wall" : "edge-\(index)",
                    start: positions[index],
                    end: positions[(index + 1) % positions.count],
                    edgeType: index == 3 ? .houseEdge : .deckEdge,
                    label: nil
                )
            }
        )
        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: VinylOrderSettings(
                color: "",
                rollWidthInches: 72,
                seamOverlapInches: 0,
                edgeWrapInches: 6,
                direction: .automatic,
                allowsDirectionalChanges: true
            )
        )

        let surfacePlan = try! XCTUnwrap(plan.surfaces.first)
        let transition = try! XCTUnwrap(surfacePlan.directionTransitions.first)
        let seam = try! XCTUnwrap(transition.segments.first)

        for region in surfacePlan.directionRegions {
            let radians = region.runAngleDegrees * .pi / 180
            func project(_ point: CGPoint) -> CGPoint {
                CGPoint(
                    x: (point.x * cos(radians)) + (point.y * sin(radians)),
                    y: (-point.x * sin(radians)) + (point.y * cos(radians))
                )
            }

            let projectedStart = project(seam.start)
            let projectedEnd = project(seam.end)
            let projectedCentroid = project(CGPoint(
                x: region.polygon.map(\.x).reduce(0, +) / CGFloat(region.polygon.count),
                y: region.polygon.map(\.y).reduce(0, +) / CGFloat(region.polygon.count)
            ))
            let cuts = surfacePlan.cuts.filter { $0.directionRegionId == region.id }
            XCTAssertFalse(cuts.isEmpty)

            if abs(projectedStart.x - projectedEnd.x) < 0.01 {
                let seamRun = Double(projectedStart.x)
                if Double(projectedCentroid.x) < seamRun {
                    XCTAssertLessThanOrEqual(cuts.map(\.runEndInches).max() ?? .infinity, seamRun + 0.01)
                } else {
                    XCTAssertGreaterThanOrEqual(cuts.map(\.runStartInches).min() ?? -.infinity, seamRun - 0.01)
                }
            } else if abs(projectedStart.y - projectedEnd.y) < 0.01 {
                let seamCross = Double(projectedStart.y)
                if Double(projectedCentroid.y) < seamCross {
                    XCTAssertLessThanOrEqual(cuts.map(\.bandEndInches).max() ?? .infinity, seamCross + 0.01)
                } else {
                    XCTAssertGreaterThanOrEqual(cuts.map(\.bandStartInches).min() ?? -.infinity, seamCross - 0.01)
                }
            } else {
                XCTFail("Fixture must project the wall seam onto one cut axis.")
            }
        }
    }

    func testUnlockedMixedRunKeepsTransitionCollinearOnRotatedDeck() {
        let radians = 30.0 * Double.pi / 180
        func rotate(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: (point.x * cos(radians)) - (point.y * sin(radians)),
                y: (point.x * sin(radians)) + (point.y * cos(radians))
            )
        }

        let basePositions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 300, y: 0),
            CGPoint(x: 300, y: 70),
            CGPoint(x: 60, y: 70),
            CGPoint(x: 60, y: 300),
            CGPoint(x: 0, y: 300)
        ]
        let positions = basePositions.map(rotate)
        let surface = VinylOrderSurfaceInput(
            id: "main",
            label: "Main deck",
            levelName: nil,
            positions: positions,
            scaleFactor: 1,
            edges: positions.indices.map { index in
                VinylOrderSurfaceEdge(
                    id: index == 3 ? "rotated-house-wall" : "edge-\(index)",
                    start: positions[index],
                    end: positions[(index + 1) % positions.count],
                    edgeType: index == 3 ? .houseEdge : .deckEdge,
                    label: nil
                )
            }
        )

        let plan = VinylCutListEngine.makePlan(
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

        let surfacePlan = try! XCTUnwrap(plan.surfaces.first)
        guard let transition = surfacePlan.directionTransitions.first else {
            return XCTFail(
                "missing rotated transition; issues=\(plan.issues), regions=\(surfacePlan.directionRegions), cuts=\(surfacePlan.cuts.map { $0.runAngleDegrees })"
            )
        }
        let wall = try! XCTUnwrap(surface.edges.first { $0.id == transition.houseEdgeId })
        let wallDX = Double(wall.end.x - wall.start.x)
        let wallDY = Double(wall.end.y - wall.start.y)
        let wallLength = sqrt((wallDX * wallDX) + (wallDY * wallDY))
        for point in transition.segments.flatMap({ [$0.start, $0.end] }) {
            let cross = abs(
                (wallDX * Double(point.y - wall.start.y)) -
                    (wallDY * Double(point.x - wall.start.x))
            )
            XCTAssertLessThanOrEqual(cross / wallLength, 0.01)
        }

        let angles = Set(surfacePlan.directionRegions.map { Int($0.runAngleDegrees.rounded()) })
        XCTAssertEqual(angles, Set([30, 120]))
        XCTAssertTrue(plan.isOrderable)
    }

    func testUnlockedTurnIsBlockedWhenNoHouseWallCanCarryTheSeam() {
        let surface = lShape(
            id: "main",
            width: 300,
            height: 300,
            notchWidth: 230,
            notchHeight: 230
        )

        let plan = VinylCutListEngine.makePlan(
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

        let surfacePlan = try! XCTUnwrap(plan.surfaces.first)
        XCTAssertFalse(plan.isOrderable)
        XCTAssertEqual(
            plan.issues,
            [.mixedRunMissingHouseAlignedTransition(surfaceId: "main")]
        )
        XCTAssertEqual(plan.blockingMessage, "NO HOUSE-WALL SPLIT · LOCK RUN OR MARK WALL")
        XCTAssertFalse(surfacePlan.hasMixedRunAxes)
        XCTAssertTrue(surfacePlan.directionTransitions.isEmpty)
        XCTAssertEqual(plan.orderNotes(projectTitle: "P", deckTitle: "D"), "")
        XCTAssertEqual(plan.textMessageBody(projectTitle: "P"), "")
        XCTAssertTrue(VinylCutListTextTemplate.cutLines(for: plan).isEmpty)
    }

    func testUnlockedManualLengthUsesTheHouseWallTransition() {
        let positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 300, y: 0),
            CGPoint(x: 300, y: 70),
            CGPoint(x: 60, y: 70),
            CGPoint(x: 60, y: 300),
            CGPoint(x: 0, y: 300)
        ]
        let surface = VinylOrderSurfaceInput(
            id: "main",
            label: "Main deck",
            levelName: nil,
            positions: positions,
            scaleFactor: 1,
            edges: positions.indices.map { index in
                VinylOrderSurfaceEdge(
                    id: index == 3 ? "house-wall" : "edge-\(index)",
                    start: positions[index],
                    end: positions[(index + 1) % positions.count],
                    edgeType: index == 3 ? .houseEdge : .deckEdge,
                    label: nil
                )
            }
        )

        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: VinylOrderSettings(
                color: "",
                rollWidthInches: 72,
                seamOverlapInches: 0,
                edgeWrapInches: 0,
                direction: .lengthwise,
                allowsDirectionalChanges: true
            )
        )

        let surfacePlan = try! XCTUnwrap(plan.surfaces.first)
        XCTAssertTrue(plan.isOrderable)
        XCTAssertTrue(surfacePlan.hasMixedRunAxes)
        XCTAssertEqual(surfacePlan.directionTransitions.first?.houseEdgeId, "house-wall")
        XCTAssertEqual(Set(surfacePlan.cuts.map(\.runDirectionLabel)), Set(["LENGTH"]))
        XCTAssertTrue(surfacePlan.cuts.allSatisfy { $0.directionRegionId != nil })
    }

    func testUnlockedManualLengthWithoutHouseWallIsBlocked() {
        let surface = lShape(
            id: "main",
            width: 300,
            height: 300,
            notchWidth: 240,
            notchHeight: 230
        )

        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: VinylOrderSettings(
                color: "",
                rollWidthInches: 72,
                seamOverlapInches: 0,
                edgeWrapInches: 0,
                direction: .lengthwise,
                allowsDirectionalChanges: true
            )
        )

        XCTAssertFalse(plan.isOrderable)
        XCTAssertEqual(
            plan.issues,
            [.mixedRunMissingHouseAlignedTransition(surfaceId: "main")]
        )
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

    // MARK: - U-shape (bug 3ab9c10b)

    /// Bug 3ab9c10b: with all rolls horizontal, a band crossing the U's two
    /// upstands must produce a separate cut per upstand — never one cut spanning
    /// the centre void. U: 240 × 192 overall, 72"-wide upstands, 96 × 120 void.
    /// Optimal horizontal plan (72" roll, no seam/wrap) aligns a band edge with
    /// the base line: 4 upstand cuts @ 6' + 1 base cut @ 20' = 264 sq ft.
    /// The void-spanning algorithm produced 3 cuts @ 20' = 360 sq ft instead.
    func testUShapedDeckHorizontalRunsCutEachUpstandSeparately() {
        let surface = uShape(
            id: "main",
            width: 240,
            height: 192,
            upstandWidth: 72,
            voidDepth: 120
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
        XCTAssertEqual(cut.stripCount, 5, cut.orderLine)
        XCTAssertEqual(cut.cutAreaSqFt, 264, accuracy: 0.01)
        XCTAssertTrue(cut.orderLine.contains("4 CUTS @ 6'"), cut.orderLine)
        XCTAssertTrue(cut.orderLine.contains("1 CUT @ 20'"), cut.orderLine)
        // Exactly one full-width cut (the base). Any second 20' cut means a
        // band bridged the void.
        XCTAssertEqual(cut.cuts.filter { abs($0.lengthInches - 240) < 0.01 }.count, 1)
        // A sane single-surface plan at zero wrap never exceeds the bounding
        // box (240 × 192 = 320 sq ft); the void-spanning plan did (360).
        XCTAssertLessThan(plan.totalPurchasedCutAreaSqFt, 320)
    }

    func testUShapedDeckDoesNotChargeTheVoidAsWaste() {
        let surface = uShape(
            id: "main",
            width: 240,
            height: 192,
            upstandWidth: 72,
            voidDepth: 120
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

        // Surface area: 240×192 − 96×120 void = 240 sq ft. Real cut waste is the
        // 24 sq ft of roll overhang on the upstand bands — NOT the 120 sq ft the
        // void-spanning algorithm charged (void treated as purchased material).
        XCTAssertEqual(plan.totalSurfaceAreaSqFt, 240, accuracy: 0.01)
        XCTAssertEqual(plan.totalWasteSqFt, 24, accuracy: 0.01)
    }

    /// The two upstand cuts inside one band are symmetric (identical length and
    /// width), so their ids must still be unique and their run geometry must
    /// stay per-upstand — an id collision would silently drop one cut during
    /// offcut assignment.
    func testUShapedDeckCutsCarrySeparateRunGeometryPerUpstand() {
        let surface = uShape(
            id: "main",
            width: 240,
            height: 192,
            upstandWidth: 72,
            voidDepth: 120
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
        XCTAssertEqual(Set(cut.cuts.map(\.id)).count, cut.cuts.count, "cut ids must be unique")

        let upstandCuts = cut.cuts.filter { abs($0.lengthInches - 72) < 0.01 }
        XCTAssertEqual(upstandCuts.count, 4, cut.orderLine)
        let leftCuts = upstandCuts.filter { abs($0.runStartInches - 0) < 0.01 && abs($0.runEndInches - 72) < 0.01 }
        let rightCuts = upstandCuts.filter { abs($0.runStartInches - 168) < 0.01 && abs($0.runEndInches - 240) < 0.01 }
        XCTAssertEqual(leftCuts.count, 2)
        XCTAssertEqual(rightCuts.count, 2)
    }

    /// A band that genuinely contains connected material (part base, part
    /// upstands) stays ONE cut — splitting applies only to truly disjoint
    /// material. At offset 0 the middle band [72,144) touches the base strip
    /// below y=120, so its material is connected and one 20' piece is correct.
    /// The optimiser must still land on the aligned 5-cut plan, proving the
    /// split logic never fragments connected bands to game the area metric.
    func testUShapedDeckKeepsConnectedBandsAsSingleCuts() {
        let surface = uShape(
            id: "main",
            width: 240,
            height: 192,
            upstandWidth: 72,
            voidDepth: 120
        )
        let settings = VinylOrderSettings(
            color: "",
            rollWidthInches: 72,
            seamOverlapInches: 0,
            edgeWrapInches: 0,
            direction: .lengthwise
        )

        let plan = VinylCutListEngine.makePlan(surfaces: [surface], settings: settings)
        let cut = try! XCTUnwrap(plan.surfaces.first)

        // The base band is a single full-width piece; upstand bands are pairs.
        let fullWidth = cut.cuts.filter { abs($0.lengthInches - 240) < 0.01 }
        XCTAssertEqual(fullWidth.count, 1)
        XCTAssertEqual(fullWidth.first?.runStartInches ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(fullWidth.first?.runEndInches ?? -1, 240, accuracy: 0.01)
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

    private func rotatedRectangle(
        id: String,
        label: String = "Surface",
        width: Double,
        height: Double,
        angleDegrees: Double,
        edgeType: EdgeType
    ) -> VinylOrderSurfaceInput {
        let radians = angleDegrees * .pi / 180
        let run = CGVector(dx: cos(radians), dy: sin(radians))
        let cross = CGVector(dx: -sin(radians), dy: cos(radians))
        func point(_ runDistance: Double, _ crossDistance: Double) -> CGPoint {
            CGPoint(
                x: (run.dx * runDistance) + (cross.dx * crossDistance),
                y: (run.dy * runDistance) + (cross.dy * crossDistance)
            )
        }

        let positions = [
            point(0, 0),
            point(width, 0),
            point(width, height),
            point(0, height)
        ]
        let edges = positions.indices.map { index in
            VinylOrderSurfaceEdge(
                id: "\(id)-edge-\(index)",
                start: positions[index],
                end: positions[(index + 1) % positions.count],
                edgeType: index == 0 ? edgeType : .deckEdge,
                label: nil
            )
        }

        return VinylOrderSurfaceInput(
            id: id,
            label: label,
            levelName: nil,
            positions: positions,
            scaleFactor: 1,
            edges: edges
        )
    }

    /// U-shape opening toward y=0: two upstands (left/right) flanking a centre
    /// void of `width − 2×upstandWidth` by `voidDepth`, joined by a base strip.
    private func uShape(
        id: String,
        label: String = "Surface",
        width: Double,
        height: Double,
        upstandWidth: Double,
        voidDepth: Double
    ) -> VinylOrderSurfaceInput {
        VinylOrderSurfaceInput(
            id: id,
            label: label,
            levelName: nil,
            positions: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: upstandWidth, y: 0),
                CGPoint(x: upstandWidth, y: voidDepth),
                CGPoint(x: width - upstandWidth, y: voidDepth),
                CGPoint(x: width - upstandWidth, y: 0),
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

    // MARK: - Full-roll ordering (spec § 5.3)

    /// The `[rolls]` message token fills with the supplied roll summary in roll
    /// mode; the cut-list default ("") makes the token disappear, leaving every
    /// existing template byte-identical.
    func testTextMessageBodyRollsToken() {
        let surface = rectangle(id: "main", label: "Main deck", width: 96, height: 36)
        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: VinylOrderSettings(color: "Slate", rollWidthInches: 72, seamOverlapInches: 0, edgeWrapInches: 0, direction: .lengthwise)
        )

        let rollBody = plan.textMessageBody(messageTemplate: "ROLLS [rolls]\n[cuts]", rolls: "3 ROLLS @ 75'")
        XCTAssertTrue(rollBody.contains("3 ROLLS @ 75'"))

        // Cut-list default resolves [rolls] to empty — no roll length leaks in.
        let cutBody = plan.textMessageBody(messageTemplate: "ROLLS [rolls]\n[cuts]")
        XCTAssertFalse(cutBody.contains("75'"))
    }

    /// `orderNotes` adds a ROLLS line only when a roll summary is supplied.
    func testOrderNotesRollsLine() {
        let surface = rectangle(id: "main", label: "Main deck", width: 96, height: 36)
        let plan = VinylCutListEngine.makePlan(
            surfaces: [surface],
            settings: VinylOrderSettings(color: "Slate", rollWidthInches: 72, seamOverlapInches: 0, edgeWrapInches: 0, direction: .lengthwise)
        )

        let rollNotes = plan.orderNotes(projectTitle: "P", deckTitle: "D", rolls: "3 ROLLS @ 75'")
        XCTAssertTrue(rollNotes.contains("ROLLS: 3 ROLLS @ 75'"))

        let cutNotes = plan.orderNotes(projectTitle: "P", deckTitle: "D")
        XCTAssertFalse(cutNotes.contains("ROLLS:"))
    }
}
