import CoreGraphics
import DeckKit
import XCTest
@testable import OPS

@MainActor
final class DeckRuntimeStoreTests: XCTestCase {
    func testViewModelSaveDelegatesToInjectedDeckStore() {
        let store = SpyDeckStore()
        let runtime = DeckRuntime(
            context: DeckRuntimeContext(
                companyId: "company-1",
                projectId: nil,
                projectName: nil,
                appSurface: .opsDecks
            ),
            store: store,
            imageUploader: NoopDeckImageUploader(),
            ocrService: NoopDeckOCRService()
        )
        var data = DeckDrawingData()
        data.vertices = [
            DeckVertex(id: "v1", position: .zero),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0))
        ]
        data.edges = [DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")]
        let design = DeckDesign(
            companyId: "company-1",
            projectId: nil,
            drawingDataJSON: data.toJSON()
        )

        let viewModel = DeckBuilderViewModel(deckDesign: design, runtime: runtime)
        viewModel.save()

        XCTAssertEqual(store.savedDrawingData.count, 1)
        XCTAssertEqual(store.savedDrawingData[0].vertices, data.vertices)
        XCTAssertEqual(store.savedDrawingData[0].edges, data.edges)
    }
}

@MainActor
private final class SpyDeckStore: DeckStore {
    var savedDrawingData: [DeckDrawingData] = []

    func save(drawingData: DeckDrawingData) throws {
        savedDrawingData.append(drawingData)
    }

    func delete() throws {}
}
