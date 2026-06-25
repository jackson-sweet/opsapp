import CoreGraphics
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

        XCTAssertEqual(store.savedDesignIds, [design.id])
        XCTAssertEqual(store.savedProjectIds, [nil])
    }
}

@MainActor
private final class SpyDeckStore: DeckStore {
    var savedDesignIds: [String] = []
    var savedProjectIds: [String?] = []

    func save(deckDesign: DeckDesign, drawingData: DeckDrawingData) throws {
        savedDesignIds.append(deckDesign.id)
        savedProjectIds.append(deckDesign.projectId)
    }

    func delete(deckDesign: DeckDesign) throws {}
}
