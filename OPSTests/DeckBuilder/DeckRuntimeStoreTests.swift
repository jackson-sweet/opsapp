import CoreGraphics
import DeckKit
import XCTest
@testable import OPS

@MainActor
final class DeckRuntimeStoreTests: XCTestCase {
    func testViewModelSaveDelegatesToInjectedDeckStoreAndSyncQueue() {
        let store = SpyDeckStore()
        let syncQueue = SpyDeckSyncQueue()
        let runtime = DeckRuntime(
            context: DeckRuntimeContext(
                companyId: "company-1",
                projectId: nil,
                projectName: nil,
                appSurface: .opsDecks
            ),
            store: store,
            syncQueue: syncQueue,
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
        XCTAssertEqual(syncQueue.enqueuedDrawingData.count, 1)
        XCTAssertEqual(syncQueue.enqueuedDrawingData[0].vertices, data.vertices)
        XCTAssertEqual(syncQueue.enqueuedDrawingData[0].edges, data.edges)
    }

    func testProductionInitializerBuildsRuntimeBackedSavePathWithoutModelContext() {
        let design = DeckDesign(
            companyId: "company-1",
            projectId: nil,
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        let viewModel = DeckBuilderViewModel(
            deckDesign: design,
            modelContext: nil,
            syncEngine: nil,
            projectName: "Alpha"
        )

        var updated = DeckDrawingData()
        updated.vertices = [
            DeckVertex(id: "v1", position: .zero),
            DeckVertex(id: "v2", position: CGPoint(x: 120, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 120, y: 120))
        ]
        updated.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v1")
        ]
        viewModel.drawingData = updated

        viewModel.save()

        XCTAssertEqual(viewModel.runtimeContext?.projectName, "Alpha")
        XCTAssertEqual(design.drawingData.vertices, updated.vertices)
        XCTAssertEqual(design.drawingData.edges, updated.edges)
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

@MainActor
private final class SpyDeckSyncQueue: DeckSyncQueue {
    var enqueuedDrawingData: [DeckDrawingData] = []

    func enqueueSave(drawingData: DeckDrawingData) {
        enqueuedDrawingData.append(drawingData)
    }
}
