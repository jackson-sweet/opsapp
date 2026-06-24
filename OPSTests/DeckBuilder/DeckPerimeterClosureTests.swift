//
//  DeckPerimeterClosureTests.swift
//  OPSTests
//
//  Deck Drop 1, Task 5 — render reliability.
//
//  Repro + regression lock for the "I closed it but the 3D won't render"
//  complaint. A perimeter the user BELIEVES is closed reads as open
//  (`isClosed == false`), so DeckTabView shows the incomplete-design message
//  instead of the 3D model. The 3D gate (`hasAnyClosedSurface`) and the
//  magnetic snap (`SnapEngine.findSnapTarget`) both already exist.
//
//  ROOT CAUSE — cause (c) in the plan's taxonomy. `DeckBuilderViewModel.endLine`
//  resolves the closing endpoint through `resolveActiveEnd` (angle/length snap →
//  axis-alignment → GRID snap) and then runs the close-detection
//  `findSnapTarget` against THAT fully-resolved point — not against the raw
//  finger release. When the closing edge arrives from a far previous corner,
//  angle-snap + grid-snap can land the resolved endpoint a whole grid cell away
//  from the start vertex even though the user released INSIDE the snap radius of
//  it. The close query then misses the start, so `endLine` commits a FRESH end
//  vertex, leaving the start a loose end (degree 1) and the perimeter open.
//
//  Worked example reproduced below: grid pitch 24 (scale 4), start S=(20,20),
//  closing edge from a far corner, raw release at (1,14) — 19.9 pt from S (inside
//  the 20 pt radius) — resolves to grid cell (0,0), which is 28.3 pt from S, so
//  the close misses and the loop stays open.
//
//  THE FIX (in endLine): before grid-snap can displace the query, test the RAW
//  release against existing vertices within `endpointSnapRadius`. If it lands on
//  one, reuse that vertex id for the edge's end so the perimeter closes onto the
//  real start vertex. `isClosed`/`SurfaceDetector`/the broad snap are untouched —
//  only the closing edge reuses the existing vertex.
//

import CoreGraphics
import XCTest
@testable import OPS

@MainActor
final class DeckPerimeterClosureTests: XCTestCase {

    private func deckDesign(drawingData: DeckDrawingData) -> DeckDesign {
        DeckDesign(
            companyId: "company-1",
            title: "Closure deck",
            drawingDataJSON: drawingData.toJSON()
        )
    }

    /// Three pre-seeded edges of a rectangle whose start vertex `S` is off-grid,
    /// at calibrated scale 4 (grid pitch = lengthSnapIncrement 6" × 4 = 24 pt).
    /// The final corner `D` sits far enough away that the closing edge's
    /// angle-snap, followed by grid-snap, lands the resolved endpoint a full
    /// cell off `S`.
    private func makeOpenPerimeter() -> DeckBuilderViewModel {
        var data = DeckDrawingData()
        data.scaleFactor = 4.0
        data.config.snappingEnabled = true

        let s = DeckVertex(id: "S", position: CGPoint(x: 20, y: 20))     // start — off grid
        let b = DeckVertex(id: "B", position: CGPoint(x: 420, y: 20))
        let c = DeckVertex(id: "C", position: CGPoint(x: 420, y: 420))
        let d = DeckVertex(id: "D", position: CGPoint(x: -200, y: -200)) // far last corner
        data.vertices = [s, b, c, d]
        data.edges = [
            DeckEdge(id: "e_sb", startVertexId: "S", endVertexId: "B"),
            DeckEdge(id: "e_bc", startVertexId: "B", endVertexId: "C"),
            DeckEdge(id: "e_cd", startVertexId: "C", endVertexId: "D"),
        ]

        let vm = DeckBuilderViewModel(deckDesign: deckDesign(drawingData: data))
        vm.activeTool = .draw
        return vm
    }

    /// Walk the closing gesture through the VM exactly as the canvas does:
    /// beginLine from the last corner (an existing vertex), drag to the release
    /// near the start, end there.
    private func drawClosingEdge(_ vm: DeckBuilderViewModel, fromCorner: CGPoint, release: CGPoint) {
        vm.beginLine(from: fromCorner)
        vm.updateLine(to: release)
        vm.endLine(at: release)
    }

    // MARK: - Repro → regression: a near close must reuse the start and close

    func testNearCloseSnapsToStartAndClosesPerimeter() {
        let vm = makeOpenPerimeter()
        let dPos = vm.drawingData.vertex(byId: "D")?.position ?? .zero

        // Raw release 19.9 pt from S — inside the 20 pt snap radius (the user
        // reads this as "on the corner"). Pre-fix the resolve chain pushes the
        // committed end to grid cell (0,0), 28.3 pt away, and the close misses.
        drawClosingEdge(vm, fromCorner: dPos, release: CGPoint(x: 1, y: 14))

        XCTAssertTrue(vm.drawingData.isClosed,
            "the near close must reuse the start vertex and close the perimeter")
        XCTAssertEqual(vm.drawingData.vertices.count, 4,
            "closing must NOT create a coincident extra vertex")
        XCTAssertEqual(vm.drawingData.edges.count, 4,
            "closing must add exactly one edge (D→S), not a dangling stub")
        XCTAssertEqual(vm.drawingData.openEndpointCount, 0,
            "a closed perimeter has zero open endpoints")

        let touchesStart = vm.drawingData.edges.contains { e in
            (e.startVertexId == "D" && e.endVertexId == "S") ||
            (e.startVertexId == "S" && e.endVertexId == "D")
        }
        XCTAssertTrue(touchesStart, "the closing edge must connect D directly to the start vertex S")
    }

    // MARK: - Guard: an honest gap (release truly far from start) stays open

    /// Releasing the final edge well outside the snap radius is a genuinely
    /// unfinished perimeter — it must remain open. We close near-misses, not
    /// arbitrary gaps.
    func testFarCloseDoesNotFalselyClose() {
        let vm = makeOpenPerimeter()
        let dPos = vm.drawingData.vertex(byId: "D")?.position ?? .zero

        // Release 200+ pt from S — nowhere near the corner.
        drawClosingEdge(vm, fromCorner: dPos, release: CGPoint(x: 220, y: 220))

        XCTAssertFalse(vm.drawingData.isClosed,
            "a release far from the start vertex must NOT auto-close the loop")
        XCTAssertGreaterThan(vm.drawingData.openEndpointCount, 0,
            "the genuinely-open perimeter must report loose ends")
    }

    // MARK: - openEndpointCount helper characterization

    func testOpenEndpointCount_zeroForClosedRectangle() {
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 100, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 100)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]
        XCTAssertEqual(data.openEndpointCount, 0)
        XCTAssertTrue(data.isClosed)
    }

    func testOpenEndpointCount_countsLooseEndsOfAnOpenPolyline() {
        // An open three-edge polyline: the two outer vertices are loose ends
        // (degree 1), the two interior vertices are degree 2.
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 100, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 100)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
        ]
        XCTAssertEqual(data.openEndpointCount, 2)
        XCTAssertFalse(data.isClosed)
    }
}
