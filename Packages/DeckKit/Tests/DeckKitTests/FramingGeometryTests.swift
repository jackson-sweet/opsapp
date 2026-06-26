import CoreGraphics
import XCTest
@testable import DeckKit

final class FramingGeometryTests: XCTestCase {
    func test_joistAxis_perpendicularToHouseEdge() throws {
        let data = try XCTUnwrap(DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 120]))
        let positions = data.vertices.map(\.position)
        let houseEdge = try XCTUnwrap(data.edges.first(where: { $0.edgeType == .houseEdge }))

        let axis = FramingGeometry.joistAxis(
            forSurface: positions,
            edges: data.edges,
            houseEdge: houseEdge,
            scaleFactor: data.effectiveScaleFactor
        )
        let houseDirection = vector(from: positions[0], to: positions[1])
        let dot = Double(axis.joist.dx) * houseDirection.dx + Double(axis.joist.dy) * houseDirection.dy

        XCTAssertEqual(dot, 0, accuracy: 0.000001)
    }

    func test_joistLines_countMatchesSpacing() throws {
        let data = try XCTUnwrap(DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 120]))
        let positions = data.vertices.map(\.position)
        let houseEdge = try XCTUnwrap(data.edges.first(where: { $0.edgeType == .houseEdge }))
        let axis = FramingGeometry.joistAxis(
            forSurface: positions,
            edges: data.edges,
            houseEdge: houseEdge,
            scaleFactor: data.effectiveScaleFactor
        )

        let lines = FramingGeometry.joistLines(
            surface: positions,
            axis: axis.joist,
            spacingInchesOC: 16,
            scaleFactor: data.effectiveScaleFactor
        )

        XCTAssertEqual(lines.count, 10)
        XCTAssertTrue(lines.allSatisfy { pointIsInsideOrOn($0.start, polygon: positions) })
        XCTAssertTrue(lines.allSatisfy { pointIsInsideOrOn($0.end, polygon: positions) })
    }

    func test_postPoints_spacing() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 144, y: 0)
        let posts = FramingGeometry.postPoints(
            alongBeam: start,
            end: end,
            maxSpacingInches: 72,
            scaleFactor: 1
        )

        XCTAssertEqual(posts.count, 3)
        XCTAssertEqual(posts[1].x, 72, accuracy: 0.000001)
    }

    func test_blockingRows_belowCapReturnsEmpty() throws {
        let data = try XCTUnwrap(DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 84]))
        let positions = data.vertices.map(\.position)
        let houseEdge = try XCTUnwrap(data.edges.first(where: { $0.edgeType == .houseEdge }))
        let axis = FramingGeometry.joistAxis(
            forSurface: positions,
            edges: data.edges,
            houseEdge: houseEdge,
            scaleFactor: data.effectiveScaleFactor
        )

        let rows = FramingGeometry.blockingRows(
            joistSpanInches: 84,
            surface: positions,
            joistAxis: axis.joist,
            capInches: 96,
            scaleFactor: data.effectiveScaleFactor
        )

        XCTAssertTrue(rows.isEmpty)
    }

    func test_blockingRows_aboveCapAddsRow() throws {
        let data = try XCTUnwrap(DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 144]))
        let positions = data.vertices.map(\.position)
        let houseEdge = try XCTUnwrap(data.edges.first(where: { $0.edgeType == .houseEdge }))
        let axis = FramingGeometry.joistAxis(
            forSurface: positions,
            edges: data.edges,
            houseEdge: houseEdge,
            scaleFactor: data.effectiveScaleFactor
        )

        let rows = FramingGeometry.blockingRows(
            joistSpanInches: 144,
            surface: positions,
            joistAxis: axis.joist,
            capInches: 96,
            scaleFactor: data.effectiveScaleFactor
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(pointIsInsideOrOn(rows[0].start, polygon: positions))
        XCTAssertTrue(pointIsInsideOrOn(rows[0].end, polygon: positions))
    }

    func test_rimAndLedger_classification() throws {
        let data = try XCTUnwrap(DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 120]))
        let positions = data.vertices.map(\.position)

        let segments = FramingGeometry.rimAndLedgerSegments(surface: positions, edges: data.edges)

        XCTAssertEqual(segments.ledger.count, 1)
        XCTAssertEqual(segments.rim.count, 3)
    }

    private func vector(from start: CGPoint, to end: CGPoint) -> CGVector {
        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        let length = max(sqrt(dx * dx + dy * dy), 0.000001)
        return CGVector(dx: dx / length, dy: dy / length)
    }

    private func pointIsInsideOrOn(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        if PolygonMath.pointInPolygon(point, vertices: polygon) { return true }
        return polygon.indices.contains { index in
            let next = (index + 1) % polygon.count
            return PolygonMath.closestPointOnSegment(
                point: point,
                segStart: polygon[index],
                segEnd: polygon[next]
            ).distance < 0.0001
        }
    }
}
