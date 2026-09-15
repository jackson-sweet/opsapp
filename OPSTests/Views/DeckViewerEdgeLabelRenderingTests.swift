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

    /// Bug f7dd3673 — the surface name must fill the space its surface offers
    /// and never cross an edge. Renders the real viewer, then asserts the
    /// placement the view computes from the same inputs: the label's rectangle
    /// lies inside the surface, the pill fits that rectangle, and the type
    /// lands between the 11pt legibility floor and the 28pt display ceiling
    /// ON SCREEN at the camera's fit scale.
    func testSurfaceLabelFillsItsSurfaceAndStaysInside() throws {
        let label = "Upper deck"
        let data = labeledSurfaceDrawing(label: label)

        let rendered = try FixedSizeSnapshot.render(
            DeckTab2DView(drawingData: data, toolState: DeckViewerToolState()),
            size: renderSize
        )
        if let png = rendered.pngData() {
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "deck-viewer-surface-label.png"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let surface = try XCTUnwrap(data.detectedSurfaces.first)
        let positions = surface.positions
        let xs = positions.map(\.x)
        let ys = positions.map(\.y)
        let canvasScale = DeckTab2DView.fitScale(
            spanX: xs.max()! - xs.min()!,
            spanY: ys.max()! - ys.min()!,
            viewportSize: renderSize
        )

        let rect = try XCTUnwrap(DeckSurfaceLabelPlacement.largestInscribedRect(in: positions))
        XCTAssertTrue(
            DeckSurfaceLabelPlacement.isInside(rect, polygon: positions),
            "the label's rectangle must lie inside the surface it names"
        )

        let padding = min(
            CGFloat(OPSStyle.Layout.spacing1) / canvasScale,
            min(rect.width, rect.height) / 4
        )
        let fit = DeckSurfaceLabelPlacement.fit(
            text: label,
            in: rect,
            canvasScale: canvasScale,
            padding: padding,
            measure: { text, size in
                let attributes = [NSAttributedString.Key.font: monoFont(size: size)]
                return (text as NSString).size(withAttributes: attributes)
            }
        )

        XCTAssertEqual(fit.text, label, "a 400x300 surface has room for its whole name")
        XCTAssertGreaterThanOrEqual(
            fit.fontSize * canvasScale,
            DeckSurfaceLabelPlacement.screenFloorPoints,
            "the surface name must clear the 11pt on-screen floor at fit zoom"
        )
        XCTAssertLessThanOrEqual(
            fit.fontSize * canvasScale,
            DeckSurfaceLabelPlacement.screenCapPoints,
            "the surface name must stay under the 28pt display ceiling"
        )
        // The drawn pill is the text plus the same padding the text was fitted
        // inside, so it can never reach past the rectangle onto the geometry.
        XCTAssertLessThanOrEqual(fit.size.width + padding * 2, rect.width)
        XCTAssertLessThanOrEqual(fit.size.height + padding, rect.height)
    }

    private func monoFont(size: CGFloat) -> UIFont {
        UIFont(name: Font.dataVoiceFamily, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private func labeledSurfaceDrawing(label: String) -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 100, y: 100)),
            DeckVertex(id: "v2", position: CGPoint(x: 500, y: 100)),
            DeckVertex(id: "v3", position: CGPoint(x: 500, y: 400)),
            DeckVertex(id: "v4", position: CGPoint(x: 100, y: 400)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2", dimension: 400),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3", dimension: 300),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4", dimension: 400),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1", dimension: 300),
        ]
        data.footprint.isClosed = true
        data.footprint.label = label
        return data
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
