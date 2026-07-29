//
//  DeckPropertySheetSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the Properties sheet rebuild (bug ee41a0a0). Shows the
//  surface card with vocabulary the operator has NOT chosen reading as an em
//  dash rather than the model default "composite"/"Brown" it used to claim,
//  the mixed-selection state, and an edge card with its measured length
//  demoted below the controls. NOT pass/fail — writes images for inspection.
//
//  Rendered via FixedSizeSnapshot: hosted in the APP'S OWN window at a fixed
//  logical size (see AppHostWindow.swift).
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/DeckPropertySheetSnapshotTests
//

#if DEBUG
import CoreGraphics
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class DeckPropertySheetSnapshotTests: XCTestCase {

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-deck-property-sheet-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func snapshot<V: View>(_ name: String, view: V, size: CGSize) {
        let image: UIImage
        do {
            image = try FixedSizeSnapshot.render(view, size: size)
        } catch {
            XCTFail("Could not acquire the app host window for \(name): \(error)")
            return
        }
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name)")
    }

    // MARK: - Fixture

    /// A closed 12'x12' deck with two surfaces so multi-select has something
    /// to disagree about.
    private func drawing() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 144, y: 144)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 144)),
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2", dimension: 150, label: "Hot tub side"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3", dimension: 144),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4", dimension: 144),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1", dimension: 144),
        ]
        return data
    }

    private func viewModel(_ data: DeckDrawingData) -> DeckBuilderViewModel {
        let viewModel = DeckBuilderViewModel(deckDesign: DeckDesign(
            companyId: "company-1",
            title: "Properties proof deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        ))
        viewModel.drawingData = data
        return viewModel
    }

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: Product.self, ProductOption.self, ProductOptionValue.self,
            CompanyDefaultProduct.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    // MARK: - Proofs

    func testRenderSurfaceCardVocabulary() throws {
        let store = try container()

        // 1. A surface nobody has specified. Both vocabulary fields read the
        //    em dash — this is exactly where "composite"/"Brown" used to sit,
        //    presenting a choice no one had made.
        let unsetVM = viewModel(drawing())
        unsetVM.activePersistedSurfaces = [
            DeckSurface(id: "s1", vertexIds: ["v1", "v2", "v3", "v4"])
        ]
        unsetVM.selection.selectedSurfaceIds = ["s1"]
        snapshot(
            "01-surface-vocabulary-unset",
            view: PropertySheetView(viewModel: unsetVM).modelContainer(store),
            size: CGSize(width: 393, height: 1100)
        )

        // 2. The same card once the operator has answered.
        let setVM = viewModel(drawing())
        setVM.activePersistedSurfaces = [
            DeckSurface(
                id: "s1",
                vertexIds: ["v1", "v2", "v3", "v4"],
                label: "Hot tub deck",
                color: "Slate",
                boardMaterial: "pvc"
            )
        ]
        setVM.selection.selectedSurfaceIds = ["s1"]
        snapshot(
            "02-surface-vocabulary-chosen",
            view: PropertySheetView(viewModel: setVM).modelContainer(store),
            size: CGSize(width: 393, height: 1100)
        )

        // 3. Two surfaces that disagree. The sheet says so instead of showing
        //    the first one's answer as if it spoke for both.
        let mixedVM = viewModel(drawing())
        mixedVM.activePersistedSurfaces = [
            DeckSurface(id: "s1", vertexIds: ["v1", "v2"], color: "Slate", boardMaterial: "pvc"),
            DeckSurface(id: "s2", vertexIds: ["v3", "v4"], color: "Cedar", boardMaterial: "cedar"),
        ]
        mixedVM.selection.selectedSurfaceIds = ["s1", "s2"]
        snapshot(
            "03-surface-vocabulary-mixed",
            view: PropertySheetView(viewModel: mixedVM).modelContainer(store),
            size: CGSize(width: 393, height: 1100)
        )
    }

    func testRenderEdgeCardReadoutDemoted() throws {
        let store = try container()

        // 4. Edge card — Type, label, railing and stairs lead; the measured
        //    Length sits at the bottom as reference.
        let edgeVM = viewModel(drawing())
        edgeVM.selection.selectedEdgeIds = ["e1"]
        snapshot(
            "04-edge-card-length-demoted",
            view: PropertySheetView(viewModel: edgeVM).modelContainer(store),
            size: CGSize(width: 393, height: 1100)
        )

        // 5. Three edges labelled in one visit — the flow behind bug 71129ae2.
        var labelled = drawing()
        labelled.edges[1].label = "BBQ wall"
        labelled.edges[2].label = "Gate run"
        let multiVM = viewModel(labelled)
        multiVM.selection.selectedEdgeIds = ["e1", "e2", "e3"]
        snapshot(
            "05-three-edges-labelled",
            view: PropertySheetView(viewModel: multiVM).modelContainer(store),
            size: CGSize(width: 393, height: 2200)
        )
    }
}
#endif
