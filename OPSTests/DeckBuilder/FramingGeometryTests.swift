import CoreGraphics
import XCTest
@testable import OPS

final class FramingGeometryTests: XCTestCase {
    func testOrderedBoundaryEdgesMatchDetectedLoopWhenStorageAndEndpointsArePermuted() throws {
        let drawing = live2114Drawing()
        let detected = try XCTUnwrap(
            SurfaceDetector.detect(vertices: drawing.vertices, edges: drawing.edges).first
        )
        let permutedEdges = drawing.edges.reversed().map { edge in
            var reversed = edge
            reversed.startVertexId = edge.endVertexId
            reversed.endVertexId = edge.startVertexId
            return reversed
        }

        let ordered = SurfaceDetector.orderedBoundaryEdges(
            for: detected,
            edges: Array(permutedEdges)
        )

        XCTAssertEqual(ordered.count, detected.vertexIds.count)
        XCTAssertEqual(Set(ordered.map(\.id)), Set(drawing.edges.map(\.id)))
        for index in detected.vertexIds.indices {
            let next = (index + 1) % detected.vertexIds.count
            XCTAssertEqual(
                Set([ordered[index].startVertexId, ordered[index].endVertexId]),
                Set([detected.vertexIds[index], detected.vertexIds[next]]),
                "Boundary edge \(ordered[index].id) must map to the consecutive detected-surface pair."
            )
        }
    }

    func testBlockingRowsClipUShapeWithoutBridgingItsVoid() {
        let uShape = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 120, y: 0),
            CGPoint(x: 120, y: 120),
            CGPoint(x: 80, y: 120),
            CGPoint(x: 80, y: 40),
            CGPoint(x: 40, y: 40),
            CGPoint(x: 40, y: 120),
            CGPoint(x: 0, y: 120),
        ]

        let rows = FramingGeometry.blockingRows(
            joistSpanInches: 120,
            surface: uShape,
            joistAxis: CGVector(dx: 0, dy: 1),
            capInches: 48,
            scaleFactor: 1
        )
        let lowerRow = rows.filter {
            abs(Double(($0.start.y + $0.end.y) / 2) - 80) < 0.001
        }

        XCTAssertEqual(lowerRow.count, 2, "The row below the notch must split into the two U-shape legs.")
        XCTAssertTrue(lowerRow.allSatisfy { segment in
            let minX = min(segment.start.x, segment.end.x)
            let maxX = max(segment.start.x, segment.end.x)
            return maxX <= 40.001 || minX >= 79.999
        })
        XCTAssertFalse(lowerRow.contains { segment in
            min(segment.start.x, segment.end.x) < 40 && max(segment.start.x, segment.end.x) > 80
        }, "No framing segment may bridge the open void between the U-shape legs.")
    }

    private func live2114Drawing() -> DeckDrawingData {
        var drawing = DeckDrawingData()
        drawing.overallElevation = 5.5
        drawing.vertices = [
            DeckVertex(id: "95EB0302-244C-4BDC-B639-DCD4F0B40B6E", position: CGPoint(x: 2388, y: 2364)),
            DeckVertex(id: "49EB52D6-28C0-47A8-84E8-9009FE8A85A0", position: CGPoint(x: 2520, y: 2364)),
            DeckVertex(id: "E8C262FD-081D-4617-BC9F-FC4D2554F017", position: CGPoint(x: 2520, y: 2400)),
            DeckVertex(id: "1F45EE10-1BAA-4A09-B848-850C20394322", position: CGPoint(x: 2388, y: 2436)),
            DeckVertex(id: "2CFFDE64-FA51-4D2C-80A6-BEE5447B6A4A", position: CGPoint(x: 2232, y: 2436)),
            DeckVertex(id: "187AF134-849A-4231-A7D1-FAE177E97E18", position: CGPoint(x: 2520, y: 2436)),
            DeckVertex(id: "E7DA228A-CBDE-486B-947C-922BEFE1EE70", position: CGPoint(x: 2520, y: 2724)),
            DeckVertex(id: "2D7C5BDD-EF0A-4233-A5B9-EE3B523A4A09", position: CGPoint(x: 2472, y: 2724)),
            DeckVertex(id: "6CF06C30-083C-48B4-A0E2-689DA2C55848", position: CGPoint(x: 2472, y: 2916)),
            DeckVertex(id: "72499BA4-8F0A-4E28-84F2-DC594359C614", position: CGPoint(x: 2232, y: 2916)),
        ]
        drawing.edges = [
            edge("196B3A15-D5C3-4D7B-883D-DDEDA1CCCC97", "95EB0302-244C-4BDC-B639-DCD4F0B40B6E", "49EB52D6-28C0-47A8-84E8-9009FE8A85A0", 66),
            edge("31AE48D6-4298-421B-BE4F-27974F959FE2", "49EB52D6-28C0-47A8-84E8-9009FE8A85A0", "E8C262FD-081D-4617-BC9F-FC4D2554F017", 18),
            edge("9E0337D1-1AB9-49EF-8042-1B5E0F87E969", "95EB0302-244C-4BDC-B639-DCD4F0B40B6E", "1F45EE10-1BAA-4A09-B848-850C20394322", 36),
            edge("7B91B112-54A5-48D7-92FF-A19869B21F0D", "1F45EE10-1BAA-4A09-B848-850C20394322", "2CFFDE64-FA51-4D2C-80A6-BEE5447B6A4A", 78),
            edge("232924E5-8EE3-4F61-9A10-427F3AABF30B", "E8C262FD-081D-4617-BC9F-FC4D2554F017", "187AF134-849A-4231-A7D1-FAE177E97E18", 18),
            edge("F6FCB95B-1124-4307-B2EC-21618AAC4EC3", "187AF134-849A-4231-A7D1-FAE177E97E18", "E7DA228A-CBDE-486B-947C-922BEFE1EE70", 144),
            edge("4A958E9F-1969-4AA1-8822-AC1A20D4A035", "E7DA228A-CBDE-486B-947C-922BEFE1EE70", "2D7C5BDD-EF0A-4233-A5B9-EE3B523A4A09", 24),
            edge("C3ACE162-9199-4968-8A26-3A07DB56F1B3", "2D7C5BDD-EF0A-4233-A5B9-EE3B523A4A09", "6CF06C30-083C-48B4-A0E2-689DA2C55848", 96),
            edge("988C36C0-D25E-4921-8FB3-3DCAF484E93B", "6CF06C30-083C-48B4-A0E2-689DA2C55848", "72499BA4-8F0A-4E28-84F2-DC594359C614", 120, type: .houseEdge),
            edge("44EA3162-0E6D-46FB-840C-4A8007D1A0FC", "2CFFDE64-FA51-4D2C-80A6-BEE5447B6A4A", "72499BA4-8F0A-4E28-84F2-DC594359C614", 240),
        ]
        drawing.footprint.isClosed = true
        return drawing
    }

    private func edge(
        _ id: String,
        _ start: String,
        _ end: String,
        _ dimension: Double,
        type: EdgeType = .deckEdge
    ) -> DeckEdge {
        DeckEdge(
            id: id,
            startVertexId: start,
            endVertexId: end,
            edgeType: type,
            dimension: dimension,
            dimensionSource: .scale
        )
    }
}
