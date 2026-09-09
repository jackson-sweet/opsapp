//
//  VinylPreviewDimensionLabelTests.swift
//  OPSTests
//
//  The deck's own dimensions, drawn on the vinyl ORDER LAYOUT (bug 1a8e48af:
//  "need to show the deck dimensions"). The drawing already showed cut widths;
//  it never showed how big the deck was.
//
//  The labels read in the SAME format the deck canvas uses for the same edge —
//  `DimensionEngine.format(_:system:)` against the drawing's own
//  `measurementSystem` — so one deck never renders two different numbers.
//

import CoreGraphics
import XCTest
@testable import OPS

final class VinylPreviewDimensionLabelTests: XCTestCase {

    // MARK: - Placement

    func testEveryDimensionLabelSitsOutsideTheOutline() {
        let surface = rectangularSurface()
        let plan = VinylPreviewAnnotationPlanner.plan(
            surface: surface,
            settings: .default,
            viewportScale: 1,
            measurementSystem: .imperial
        )

        XCTAssertFalse(plan.dimensionLabels.isEmpty)
        for label in plan.dimensionLabels {
            XCTAssertFalse(
                PolygonMath.pointInPolygon(label.point, vertices: surface.positions),
                "\(label.edgeId) label fell inside the deck outline"
            )
        }
    }

    /// Every dimension label clears the wrap band — it is a callout about the
    /// deck, not something painted over the material.
    func testDimensionLabelsClearTheWrapBand() {
        let surface = rectangularSurface()
        let plan = VinylPreviewAnnotationPlanner.plan(
            surface: surface,
            settings: .default,
            viewportScale: 1,
            measurementSystem: .imperial
        )

        // A band's polygon is [edge.start, edge.end, outerEnd, outerStart], so
        // the distance between its first and last vertex IS the wrap depth the
        // planner used — no need to re-derive the surface scale here.
        let band = try! XCTUnwrap(plan.bands.first { $0.edgeType == .deckEdge })
        let wrapDepth = hypot(
            band.polygon[3].x - band.polygon[0].x,
            band.polygon[3].y - band.polygon[0].y
        )

        XCTAssertFalse(plan.dimensionLabels.isEmpty)
        for label in plan.dimensionLabels {
            XCTAssertGreaterThan(label.distanceFromEdge, wrapDepth)
        }
    }

    /// The deck's dimensions are the INNER ring; the lap callout steps outside
    /// them. The old precedence was the other way round, and one `DECK LAP 6"`
    /// label set a worst-case ring the fit then honoured on all four sides.
    func testTheLapCalloutStandsOutsideTheDimensionOnTheSameEdge() {
        let dimensionReach = VinylPreviewAnnotationPlanner
            .dimensionRing(for: rectangularSurface(), measurementSystem: .imperial)
            .reachPoints

        let standoff = VinylPreviewAnnotationPlanner.leaderStandoffPoints(
            clearingPoints: dimensionReach,
            halfExtentAlongNormal: 0
        )

        XCTAssertGreaterThan(dimensionReach, 0)
        XCTAssertGreaterThan(standoff, dimensionReach)
    }

    /// A lap callout runs its leader line out along the same normal the edge's
    /// dimension sits on, so the line used to be drawn straight THROUGH the
    /// dimension text. The dimension steps along its edge to leave a lane.
    func testALapLeadersLineHasAClearLaneThroughTheDimensions() {
        for surface in [rectangularSurface(), tallSurface(), notchedSurface()] {
            let plan = VinylPreviewAnnotationPlanner.plan(
                surface: surface,
                settings: .default,
                viewportScale: 1,
                measurementSystem: .imperial
            )

            for leader in plan.leaders {
                for label in plan.dimensionLabels {
                    XCTAssertGreaterThanOrEqual(
                        distance(from: label.point, toSegment: leader.lineStart, leader.labelPoint),
                        VinylPreviewAnnotationPlanner.dimensionLabelClearancePoints,
                        "\(label.text) sits on \(leader.label)'s leader line"
                    )
                }
            }
        }
    }

    private func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = (dx * dx) + (dy * dy)
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, (((point.x - a.x) * dx) + ((point.y - a.y) * dy)) / lengthSquared))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    /// The callout is centred on its edge's normal, so half of a wide label used
    /// to land back INSIDE the deck on a vertical edge — `DECK LAP 6"` printed
    /// straight over the cut widths. It now carries its own half-extent.
    func testALapCalloutNeverPaintsBackOverTheDeck() {
        for surface in [rectangularSurface(), tallSurface()] {
            let plan = VinylPreviewAnnotationPlanner.plan(
                surface: surface,
                settings: .default,
                viewportScale: 1,
                measurementSystem: .imperial
            )

            XCTAssertFalse(plan.leaders.isEmpty)
            for leader in plan.leaders {
                let rect = leader.labelRect
                for corner in [
                    CGPoint(x: rect.minX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.minY),
                    CGPoint(x: rect.minX, y: rect.maxY),
                    CGPoint(x: rect.maxX, y: rect.maxY)
                ] {
                    XCTAssertFalse(
                        PolygonMath.pointInPolygon(corner, vertices: surface.positions),
                        "\(leader.label) painted back over the deck at \(corner)"
                    )
                }
            }
        }
    }

    // MARK: - Which edges earn a label

    func testEdgesUnderTwoFeetAreSkipped() {
        let plan = VinylPreviewAnnotationPlanner.plan(
            surface: notchedSurface(),
            settings: .default,
            viewportScale: 1,
            measurementSystem: .imperial
        )

        XCTAssertFalse(plan.dimensionLabels.contains { $0.edgeId == "stub" })
        XCTAssertTrue(plan.dimensionLabels.contains { $0.edgeId == "long" })
    }

    func testTwoFootThresholdIsTheDocumentedFloor() {
        XCTAssertEqual(VinylPreviewAnnotationPlanner.dimensionLabelMinimumInches, 24)
    }

    // MARK: - The ring is computed, not assumed

    /// The ring is the label's own text, nothing else: a dimension stands one
    /// `spacing2` off the band plus half its own extent along the normal. It no
    /// longer inherits a lap callout's width, which is what used to cost the
    /// drawing ~30% of the phone's width on every side.
    func testTheRingIsTheDimensionTextAndNothingElse() {
        let ring = VinylPreviewAnnotationPlanner.dimensionRing(
            for: rectangularSurface(),
            measurementSystem: .imperial
        )

        let standoff = VinylPreviewAnnotationPlanner.dimensionLabelStandoffPoints
        XCTAssertGreaterThan(ring.offsetPoints, standoff)
        XCTAssertEqual(ring.reachPoints, (ring.offsetPoints - standoff) * 2 + standoff, accuracy: 0.001)

        // A `24'`-class callout is a handful of mono glyphs — the whole ring
        // stays inside one 44pt touch target's worth of canvas.
        XCTAssertLessThan(ring.reachPoints, CGFloat(OPSStyle.Layout.touchTargetMin))
    }

    /// The wrap band is added by the drawing in source units, so the ring the
    /// planner reports in POINTS does not move when the wrap does.
    func testTheDimensionRingIsIndependentOfTheWrapSetting() {
        let ring = VinylPreviewAnnotationPlanner.dimensionRing(
            for: rectangularSurface(),
            measurementSystem: .imperial
        )

        XCTAssertGreaterThanOrEqual(
            ring.offsetPoints,
            VinylPreviewAnnotationPlanner.dimensionLabelStandoffPoints
        )

        // The reserve the fit honours DOES fall back when the wrap goes away —
        // no bands, no lap callouts, so only the dimensions need clearing.
        var noWrap = VinylOrderSettings.default
        noWrap.edgeWrapInches = 0
        let bare = VinylPreviewAnnotationPlanner.dimensionRingReachPoints(
            for: [rectangularSurface()],
            settings: noWrap,
            measurementSystem: .imperial
        )
        let wrapped = VinylPreviewAnnotationPlanner.dimensionRingReachPoints(
            for: [rectangularSurface()],
            settings: .default,
            measurementSystem: .imperial
        )

        XCTAssertEqual(bare, ring.reachPoints, accuracy: 0.001)
        XCTAssertGreaterThan(wrapped, bare)
    }

    /// A surface with nothing worth labelling reserves nothing.
    func testASurfaceWithNoLabelledEdgesReservesNothing() {
        let ring = VinylPreviewAnnotationPlanner.dimensionRing(
            for: tinySurface(),
            measurementSystem: .imperial
        )

        XCTAssertEqual(ring.offsetPoints, 0)
        XCTAssertEqual(ring.reachPoints, 0)
    }

    /// The reserve the drawing's fit honours is the widest ring across the plan.
    func testReachIsTheWidestRingAcrossEverySurface() {
        let reach = VinylPreviewAnnotationPlanner.dimensionRingReachPoints(
            for: [rectangularSurface(), tallSurface()],
            settings: .default,
            measurementSystem: .imperial
        )

        XCTAssertGreaterThanOrEqual(
            reach,
            max(
                VinylPreviewAnnotationPlanner.dimensionRing(
                    for: rectangularSurface(),
                    measurementSystem: .imperial
                ).reachPoints,
                VinylPreviewAnnotationPlanner.dimensionRing(
                    for: tallSurface(),
                    measurementSystem: .imperial
                ).reachPoints
            )
        )
    }

    // MARK: - Text

    func testLabelTextMatchesTheDeckCanvasFormatterForAKnownEdge() {
        let plan = VinylPreviewAnnotationPlanner.plan(
            surface: measuredSurface(),
            settings: .default,
            viewportScale: 1,
            measurementSystem: .imperial
        )

        let label = try! XCTUnwrap(plan.dimensionLabels.first { $0.edgeId == "measured" })

        XCTAssertEqual(label.text, DimensionEngine.format(294, system: .imperial))
        XCTAssertEqual(label.text, "24' 6\"")
    }

    func testMetricDrawingsRenderMetricDimensions() {
        let plan = VinylPreviewAnnotationPlanner.plan(
            surface: measuredSurface(),
            settings: .default,
            viewportScale: 1,
            measurementSystem: .metric
        )

        let label = try! XCTUnwrap(plan.dimensionLabels.first { $0.edgeId == "measured" })

        XCTAssertEqual(label.text, DimensionEngine.format(294, system: .metric))
        XCTAssertNotEqual(label.text, DimensionEngine.format(294, system: .imperial))
    }

    /// An edge the deck never measured falls back to canvas length ÷ the
    /// surface's own scale — the same fallback `DeckMaterialsEngine` uses.
    func testUnmeasuredEdgeFallsBackToCanvasLengthOverScale() {
        let surface = rectangularSurface()
        let plan = VinylPreviewAnnotationPlanner.plan(
            surface: surface,
            settings: .default,
            viewportScale: 1,
            measurementSystem: .imperial
        )

        let label = try! XCTUnwrap(plan.dimensionLabels.first { $0.edgeId == "house" })
        let houseEdge = try! XCTUnwrap(surface.edges.first { $0.id == "house" })
        let canvasLength = hypot(
            houseEdge.end.x - houseEdge.start.x,
            houseEdge.end.y - houseEdge.start.y
        )

        XCTAssertNil(houseEdge.dimensionInches)
        XCTAssertEqual(
            label.text,
            DimensionEngine.format(Double(canvasLength) / surface.scaleFactor, system: .imperial)
        )
    }

    // MARK: - The fit reserves room for the ring

    /// The founder's phone, the workspace's drawing band, and decks from a
    /// balcony to a 60-footer — the outermost dimension label has to land on
    /// the canvas in every one of them, wrapped or not.
    func testTheFitKeepsTheDimensionRingOnTheCanvasAtEveryDeckSize() {
        let canvas = CGSize(width: 393, height: 636)
        let target = CGRect(
            x: VinylOrderLayout.previewInset,
            y: VinylOrderLayout.previewInset,
            width: canvas.width - (VinylOrderLayout.previewInset * 2),
            height: canvas.height - (VinylOrderLayout.previewInset * 2)
        )
        let ringReach: CGFloat = 60 // a long label: `24' 6"` and then some

        for contentSide in [CGFloat(48), 120, 288, 720, 2_400] {
            for wrapCanvas in [CGFloat(0), 6, 24] {
                let content = CGRect(x: 0, y: 0, width: contentSide, height: contentSide * 0.5)
                let wrapReserve = max(wrapCanvas * 4, CGFloat(OPSStyle.Layout.spacing4))
                let fit = VinylPreviewFit.resolve(
                    content: content,
                    wrapCanvas: wrapCanvas,
                    wrapReserve: wrapReserve,
                    ringReachPoints: ringReach,
                    target: target
                )

                // Outermost point the ring reaches, mapped into canvas points.
                let ringSource = content.maxX + wrapCanvas + (ringReach / fit.scale)
                let ringCanvasX = fit.origin.x + ((ringSource - fit.bounds.minX) * fit.scale)

                XCTAssertLessThanOrEqual(
                    ringCanvasX,
                    canvas.width,
                    "deck \(contentSide) / wrap \(wrapCanvas): ring at \(ringCanvasX) fell off a \(canvas.width)pt canvas"
                )
                XCTAssertGreaterThan(fit.scale, 0)
            }
        }
    }

    /// The refinement must not eat the drawing: with no ring to reserve, the
    /// fit is the plain wrap-band fit it always was.
    func testAZeroRingLeavesTheLegacyWrapFitUntouched() {
        let target = CGRect(x: 16, y: 16, width: 361, height: 604)
        let content = CGRect(x: 0, y: 0, width: 288, height: 144)
        let wrapReserve = CGFloat(OPSStyle.Layout.spacing4)

        let fit = VinylPreviewFit.resolve(
            content: content,
            wrapCanvas: 0,
            wrapReserve: wrapReserve,
            ringReachPoints: 0,
            target: target
        )

        let expectedBounds = content.insetBy(dx: -wrapReserve, dy: -wrapReserve)
        XCTAssertEqual(fit.bounds, expectedBounds)
        XCTAssertEqual(
            fit.scale,
            min(target.width / expectedBounds.width, target.height / expectedBounds.height),
            accuracy: 0.001
        )
    }

    // MARK: - Bounding size for the header context line

    func testBoundingSizeReadsWidthByHeightInTheDrawingsOwnFormat() {
        let plan = VinylCutListEngine.makePlan(
            surfaces: [rectangularInput()],
            settings: .default
        )

        let text = try! XCTUnwrap(
            VinylOrderWorkspaceCopy.boundingSizeLine(for: plan, measurementSystem: .imperial)
        )
        let surface = plan.surfaces[0]

        XCTAssertEqual(
            text,
            "\(DimensionEngine.format(surface.boundingWidthInches, system: .imperial))"
                + " × "
                + "\(DimensionEngine.format(surface.boundingHeightInches, system: .imperial))"
        )
    }

    func testMultiSurfacePlansShowTheFirstSurfaceAndACount() {
        let plan = VinylCutListEngine.makePlan(
            surfaces: [rectangularInput(), rectangularInput(id: "second")],
            settings: .default
        )

        let text = try! XCTUnwrap(
            VinylOrderWorkspaceCopy.boundingSizeLine(for: plan, measurementSystem: .imperial)
        )

        XCTAssertTrue(text.hasSuffix(" +1"), "expected a surface count suffix, got \(text)")
    }

    func testEmptyPlanHasNoBoundingSizeLine() {
        let plan = VinylCutListEngine.makePlan(surfaces: [], settings: .default)

        XCTAssertNil(
            VinylOrderWorkspaceCopy.boundingSizeLine(for: plan, measurementSystem: .imperial)
        )
    }

    // MARK: - Fixtures

    private func rectangularInput(id: String = "surface") -> VinylOrderSurfaceInput {
        VinylOrderSurfaceInput(
            id: id,
            label: "Deck",
            levelName: nil,
            positions: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 288, y: 0),
                CGPoint(x: 288, y: 144),
                CGPoint(x: 0, y: 144)
            ],
            scaleFactor: 1,
            edges: [
                VinylOrderSurfaceEdge(
                    id: "house",
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 288, y: 0),
                    edgeType: .houseEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "right",
                    start: CGPoint(x: 288, y: 0),
                    end: CGPoint(x: 288, y: 144),
                    edgeType: .deckEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "front",
                    start: CGPoint(x: 288, y: 144),
                    end: CGPoint(x: 0, y: 144),
                    edgeType: .deckEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "left",
                    start: CGPoint(x: 0, y: 144),
                    end: CGPoint(x: 0, y: 0),
                    edgeType: .deckEdge,
                    label: nil
                )
            ]
        )
    }

    private func rectangularSurface() -> VinylSurfaceCutPlan {
        VinylCutListEngine.makePlan(
            surfaces: [rectangularInput()],
            settings: .default
        ).surfaces[0]
    }

    /// A deck deeper than it is wide, so its longest deck edge — the one that
    /// carries the lap leader — runs vertically and pushes its label sideways.
    private func tallSurface() -> VinylSurfaceCutPlan {
        let positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 144, y: 0),
            CGPoint(x: 144, y: 288),
            CGPoint(x: 0, y: 288)
        ]
        let input = VinylOrderSurfaceInput(
            id: "tall",
            label: "Deck",
            levelName: nil,
            positions: positions,
            scaleFactor: 1,
            edges: [
                VinylOrderSurfaceEdge(
                    id: "house",
                    start: positions[0],
                    end: positions[1],
                    edgeType: .houseEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "east",
                    start: positions[1],
                    end: positions[2],
                    edgeType: .deckEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "south",
                    start: positions[2],
                    end: positions[3],
                    edgeType: .deckEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "west",
                    start: positions[3],
                    end: positions[0],
                    edgeType: .deckEdge,
                    label: nil
                )
            ]
        )
        return VinylCutListEngine.makePlan(surfaces: [input], settings: .default).surfaces[0]
    }

    /// Every edge under the two-foot floor — a landing pad, not a deck.
    private func tinySurface() -> VinylSurfaceCutPlan {
        let positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 18, y: 0),
            CGPoint(x: 18, y: 18),
            CGPoint(x: 0, y: 18)
        ]
        let input = VinylOrderSurfaceInput(
            id: "tiny",
            label: "Landing",
            levelName: nil,
            positions: positions,
            scaleFactor: 1,
            edges: [
                VinylOrderSurfaceEdge(
                    id: "n",
                    start: positions[0],
                    end: positions[1],
                    edgeType: .deckEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "e",
                    start: positions[1],
                    end: positions[2],
                    edgeType: .deckEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "s",
                    start: positions[2],
                    end: positions[3],
                    edgeType: .deckEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "w",
                    start: positions[3],
                    end: positions[0],
                    edgeType: .deckEdge,
                    label: nil
                )
            ]
        )
        return VinylCutListEngine.makePlan(surfaces: [input], settings: .default).surfaces[0]
    }

    /// One edge carries the deck's measured dimension (24' 6"); the drawn
    /// canvas length deliberately does NOT agree, so the test proves the
    /// measured value wins.
    private func measuredSurface() -> VinylSurfaceCutPlan {
        var input = rectangularInput()
        input.edges = input.edges.map { edge in
            guard edge.id == "front" else { return edge }
            return VinylOrderSurfaceEdge(
                id: "measured",
                start: edge.start,
                end: edge.end,
                edgeType: edge.edgeType,
                label: nil,
                dimensionInches: 294
            )
        }
        return VinylCutListEngine.makePlan(surfaces: [input], settings: .default).surfaces[0]
    }

    /// A deck with a 12" notch return — under the two-foot floor.
    private func notchedSurface() -> VinylSurfaceCutPlan {
        let positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 288, y: 0),
            CGPoint(x: 288, y: 144),
            CGPoint(x: 276, y: 144),
            CGPoint(x: 276, y: 156),
            CGPoint(x: 0, y: 156)
        ]
        let input = VinylOrderSurfaceInput(
            id: "surface",
            label: "Deck",
            levelName: nil,
            positions: positions,
            scaleFactor: 1,
            edges: [
                VinylOrderSurfaceEdge(
                    id: "long",
                    start: positions[0],
                    end: positions[1],
                    edgeType: .houseEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "right",
                    start: positions[1],
                    end: positions[2],
                    edgeType: .deckEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "stub",
                    start: positions[2],
                    end: positions[3],
                    edgeType: .deckEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "notch",
                    start: positions[3],
                    end: positions[4],
                    edgeType: .deckEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "front",
                    start: positions[4],
                    end: positions[5],
                    edgeType: .deckEdge,
                    label: nil
                ),
                VinylOrderSurfaceEdge(
                    id: "left",
                    start: positions[5],
                    end: positions[0],
                    edgeType: .deckEdge,
                    label: nil
                )
            ]
        )
        return VinylCutListEngine.makePlan(surfaces: [input], settings: .default).surfaces[0]
    }
}
