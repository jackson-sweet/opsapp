import SwiftData
import UIKit
import XCTest
@testable import OPS

@MainActor
final class DeckExitResponsivenessTests: XCTestCase {
    func testExitEncodesOnceAndInterruptionKeepsDurableRevisionHeld() throws {
        let schema = Schema([DeckDesign.self, SyncOperation.self, PhotoAnnotation.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        let design = DeckDesign(companyId: UUID().uuidString)
        context.insert(design)
        try context.save()
        let sync = SyncEngine()
        sync.configure(modelContext: context, connectivity: OfflineDeckConnectivity())
        defer { sync.stopForLogoutSync() }
        var encodes = 0
        let vm = DeckBuilderViewModel(deckDesign: design, modelContext: context, syncEngine: sync, drawingEncoder: {
            encodes += 1
            return $0.toJSON()
        }, thumbnailRenderer: { _ in nil })
        vm.drawingData.config.snappingEnabled.toggle()
        vm.flushLocallyForInterruption()
        XCTAssertEqual(encodes, 1)
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(operations.filter { $0.entityType == "deckDesign" }.count, 1)
        XCTAssertTrue(DeckEditingSessionRegistry.shared.isHeld(entityType: "deckDesign", entityId: design.id))
        vm.flushBeforeExit()
        XCTAssertEqual(encodes, 1, "Already persisted exit data must be reused for the queue identity")
        XCTAssertFalse(DeckEditingSessionRegistry.shared.isHeld(entityType: "deckDesign", entityId: design.id))
        vm.resumeEditingSession()
        XCTAssertTrue(DeckEditingSessionRegistry.shared.isHeld(entityType: "deckDesign", entityId: design.id))
        vm.flushBeforeExit()
    }

    func testThumbnailRendersOffMainAndCannotOverwriteReopenedDrawing() async throws {
        var drawing = DeckDrawingData()
        drawing.vertices = [DeckVertex(id: "a", position: .zero), DeckVertex(id: "b", position: CGPoint(x: 120, y: 0))]
        drawing.edges = [DeckEdge(id: "edge", startVertexId: "a", endVertexId: "b")]
        let design = DeckDesign(companyId: UUID().uuidString, drawingDataJSON: drawing.toJSON())
        let rendered = expectation(description: "rendered off main")
        let uploadStarted = expectation(description: "upload started")
        let release = DeckThumbnailTestGate()
        let vm = DeckBuilderViewModel(deckDesign: design, thumbnailRenderer: { _ in
            XCTAssertFalse(Thread.isMainThread)
            rendered.fulfill()
            return UIImage()
        }, thumbnailUploader: { _, _ in
            uploadStarted.fulfill()
            await release.wait()
            return "https://example.invalid/old-thumbnail.png"
        })
        let thumbnail = vm.saveForExit()
        vm.flushBeforeExit()
        await fulfillment(of: [rendered, uploadStarted], timeout: 2)
        let newer = DeckBuilderViewModel(deckDesign: design, thumbnailRenderer: { _ in nil })
        newer.drawingData.config.snappingEnabled.toggle()
        newer.save()
        let newerJSON = design.drawingDataJSON
        await release.release()
        await thumbnail?.value
        XCTAssertEqual(design.drawingDataJSON, newerJSON)
        XCTAssertNil(design.thumbnailURL)
        newer.flushBeforeExit()
    }
}

@MainActor
private final class OfflineDeckConnectivity: ConnectivityManager {
    override var shouldAttemptSync: Bool { false }
}

private actor DeckThumbnailTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
