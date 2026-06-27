import CoreGraphics
import XCTest
@testable import DeckKit

@MainActor
final class DeckDrawingEditorModelTests: XCTestCase {
    func testDrawLineCreatesPersistedDimensionedEdge() {
        var persisted: [DeckDrawingData] = []
        let model = DeckDrawingEditorModel(
            drawingData: DeckDrawingData(),
            capabilities: .full,
            onPersist: { persisted.append($0) }
        )

        model.beginLine(at: CGPoint(x: 100, y: 100))
        model.updateLine(to: CGPoint(x: 148, y: 100))
        model.endLine(at: CGPoint(x: 148, y: 100))

        XCTAssertEqual(model.drawingData.vertices.count, 2)
        XCTAssertEqual(model.drawingData.edges.count, 1)
        XCTAssertEqual(model.drawingData.edges.first?.dimension, 24)
        XCTAssertEqual(persisted.last?.edges.count, 1)
    }

    func testClosingLineSnapsToExistingVertexAndClosesSurface() {
        let model = DeckDrawingEditorModel(drawingData: DeckDrawingData(), capabilities: .full)

        drawLine(model, from: CGPoint(x: 120, y: 120), to: CGPoint(x: 360, y: 120))
        drawLine(model, from: CGPoint(x: 360, y: 120), to: CGPoint(x: 360, y: 360))
        drawLine(model, from: CGPoint(x: 360, y: 360), to: CGPoint(x: 120, y: 360))
        drawLine(model, from: CGPoint(x: 120, y: 360), to: CGPoint(x: 120, y: 120))

        XCTAssertEqual(model.drawingData.vertices.count, 4)
        XCTAssertEqual(model.drawingData.edges.count, 4)
        XCTAssertTrue(model.drawingData.isClosed)
        XCTAssertTrue(model.drawingData.hasAnyClosedSurface)
    }

    func testGenerateFramingRequiresFullAuthoringCapability() throws {
        let data = try XCTUnwrap(DeckTemplateEngine.generate(template: .rectangle, dimensions: [144, 120]))
        let lightModel = DeckDrawingEditorModel(drawingData: data, capabilities: .light)
        let fullModel = DeckDrawingEditorModel(drawingData: data, capabilities: .full)

        XCTAssertFalse(lightModel.generateFraming())
        XCTAssertNil(lightModel.drawingData.framing)

        XCTAssertTrue(fullModel.generateFraming())
        XCTAssertFalse(fullModel.drawingData.framing?.members.flatMap(\.members).isEmpty ?? true)
    }

    private func drawLine(_ model: DeckDrawingEditorModel, from start: CGPoint, to end: CGPoint) {
        model.beginLine(at: start)
        model.updateLine(to: end)
        model.endLine(at: end)
    }
}
