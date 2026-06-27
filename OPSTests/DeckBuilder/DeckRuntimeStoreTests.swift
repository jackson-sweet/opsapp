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

    func testGenerateFramingSetsBlockAndDelegatesToStoreAndSyncQueue() {
        var data = Self.closedRectangleDrawingData()
        data.edges[0].edgeType = .houseEdge
        let design = DeckDesign(
            companyId: "company-1",
            projectId: nil,
            drawingDataJSON: data.toJSON()
        )
        let store = SpyDeckStore(persisting: design)
        let syncQueue = SpyDeckSyncQueue()
        let runtime = Self.runtime(store: store, syncQueue: syncQueue)
        let viewModel = DeckBuilderViewModel(deckDesign: design, runtime: runtime)

        viewModel.generateFraming()

        XCTAssertNotNil(viewModel.drawingData.framing)
        XCTAssertEqual(store.savedDrawingData.count, 1)
        XCTAssertEqual(syncQueue.enqueuedDrawingData.count, 1)
        XCTAssertTrue(design.needsSync)
    }

    func testSetLoadPresetRestampsExistingMembersAndLeavesSizingNil() {
        var data = Self.closedRectangleDrawingData()
        data.framing = AutoFramingEngine.generate(from: data, preset: LoadPreset())
        let design = DeckDesign(
            companyId: "company-1",
            projectId: nil,
            drawingDataJSON: data.toJSON()
        )
        let store = SpyDeckStore(persisting: design)
        let syncQueue = SpyDeckSyncQueue()
        let viewModel = DeckBuilderViewModel(
            deckDesign: design,
            runtime: Self.runtime(store: store, syncQueue: syncQueue)
        )

        viewModel.setLoadPreset(LoadPreset(species: .douglasFirLarch, grade: .no1))

        let members = viewModel.drawingData.framing?.members.flatMap(\.members) ?? []
        XCTAssertFalse(members.isEmpty)
        XCTAssertTrue(members.allSatisfy { $0.species == .douglasFirLarch })
        XCTAssertTrue(members.allSatisfy { $0.grade == .no1 })
        XCTAssertTrue(members.allSatisfy { $0.sizing == nil })
        XCTAssertEqual(store.savedDrawingData.count, 1)
    }

    func testCanFrameFalseWithoutCapabilityAndGenerateIsNoop() {
        let data = Self.closedRectangleDrawingData()
        let design = DeckDesign(
            companyId: "company-1",
            projectId: nil,
            drawingDataJSON: data.toJSON()
        )
        let store = SpyDeckStore(persisting: design)
        let viewModel = DeckBuilderViewModel(
            deckDesign: design,
            runtime: Self.runtime(store: store, syncQueue: SpyDeckSyncQueue()),
            capabilities: .materials
        )

        XCTAssertFalse(viewModel.canFrame)
        viewModel.generateFraming()

        XCTAssertNil(viewModel.drawingData.framing)
        XCTAssertTrue(store.savedDrawingData.isEmpty)
    }

    func testEmbeddedOPSProductionRuntimeIsViewerOnlyByDefault() {
        let data = Self.closedRectangleDrawingData()
        let design = DeckDesign(
            companyId: "company-1",
            projectId: nil,
            drawingDataJSON: data.toJSON()
        )
        let viewModel = DeckBuilderViewModel(
            deckDesign: design,
            modelContext: nil,
            syncEngine: nil,
            projectName: "Embedded OPS"
        )

        XCTAssertEqual(viewModel.runtimeContext?.appSurface, .ops)
        XCTAssertFalse(viewModel.canFrame)
        XCTAssertFalse(viewModel.canPickGround)

        viewModel.generateFraming()
        viewModel.setGroundCover(.gravel, forZoneId: nil)

        XCTAssertNil(viewModel.drawingData.framing)
        XCTAssertNil(viewModel.drawingData.terrain)
    }

    private static func runtime(store: DeckStore, syncQueue: DeckSyncQueue) -> DeckRuntime {
        DeckRuntime(
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
    }

    private static func closedRectangleDrawingData() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.overallElevation = 3.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 144, y: 144)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 144)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]
        return data
    }
}

@MainActor
private final class SpyDeckStore: DeckStore {
    var savedDrawingData: [DeckDrawingData] = []
    private let design: DeckDesign?

    init(persisting design: DeckDesign? = nil) {
        self.design = design
    }

    func save(drawingData: DeckDrawingData) throws {
        savedDrawingData.append(drawingData)
        design?.drawingData = drawingData
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
