//
//  DeckViewerEdgeLabelRenderingTests.swift
//  OPSTests
//
//  Regression coverage for persisted custom edge labels in the read-only
//  Project Details deck viewer. The test renders the real Canvas twice and
//  proves that adding an edge label changes the customer-visible output.
//

#if DEBUG
import CoreGraphics
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class DeckViewerEdgeLabelRenderingTests: XCTestCase {

    private let renderSize = CGSize(width: 393, height: 393)

    func testReadOnlyViewerRendersPersistedCustomEdgeLabel() throws {
        let unlabeledFixture = drawingData(edgeLabel: nil)
        let firstUnlabeled = try FixedSizeSnapshot.render(
            DeckTab2DView(
                drawingData: unlabeledFixture,
                toolState: DeckViewerToolState()
            ),
            size: renderSize
        )
        let secondUnlabeled = try FixedSizeSnapshot.render(
            DeckTab2DView(
                drawingData: unlabeledFixture,
                toolState: DeckViewerToolState()
            ),
            size: renderSize
        )
        let labeled = try FixedSizeSnapshot.render(
            DeckTab2DView(
                drawingData: drawingData(edgeLabel: "6’ tall"),
                toolState: DeckViewerToolState()
            ),
            size: renderSize
        )

        let baselineNoise = try differingByteCount(firstUnlabeled, secondUnlabeled)
        let labelDifference = try differingByteCount(secondUnlabeled, labeled)

        XCTAssertGreaterThan(
            labelDifference,
            baselineNoise + 128,
            "A persisted custom edge label must change the read-only viewer's rendered output"
        )

        if let data = labeled.pngData() {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "deck-viewer-custom-edge-label.png"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func drawingData(edgeLabel: String?) -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 60, y: 120)),
            DeckVertex(id: "v2", position: CGPoint(x: 300, y: 120)),
            DeckVertex(id: "v3", position: CGPoint(x: 300, y: 300)),
            DeckVertex(id: "v4", position: CGPoint(x: 60, y: 300)),
        ]
        data.edges = [
            DeckEdge(
                id: "e1",
                startVertexId: "v1",
                endVertexId: "v2",
                dimension: 96,
                label: edgeLabel
            ),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]
        return data
    }

    private func differingByteCount(_ lhs: UIImage, _ rhs: UIImage) throws -> Int {
        let lhsImage = try XCTUnwrap(lhs.cgImage)
        let rhsImage = try XCTUnwrap(rhs.cgImage)
        XCTAssertEqual(lhsImage.width, rhsImage.width)
        XCTAssertEqual(lhsImage.height, rhsImage.height)

        let lhsData = try XCTUnwrap(lhsImage.dataProvider?.data)
        let rhsData = try XCTUnwrap(rhsImage.dataProvider?.data)
        let byteCount = min(CFDataGetLength(lhsData), CFDataGetLength(rhsData))
        let lhsBytes = try XCTUnwrap(CFDataGetBytePtr(lhsData))
        let rhsBytes = try XCTUnwrap(CFDataGetBytePtr(rhsData))

        return (0..<byteCount).reduce(into: 0) { difference, index in
            if lhsBytes[index] != rhsBytes[index] {
                difference += 1
            }
        }
    }
}
#endif
