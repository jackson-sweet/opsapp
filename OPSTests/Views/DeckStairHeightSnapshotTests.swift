//
//  DeckStairHeightSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the stair sheet overhaul + level-scoped HEIGHT tool.
//  Renders the stair sheet in its three rise modes (treads / height / level),
//  the Connect entry point's edge picker, and the height sheet scoped to a
//  named level. NOT pass/fail — writes images for inspection.
//
//  Rendered via FixedSizeSnapshot: hosted in the APP'S OWN window at a fixed
//  logical size, so asset-catalog colors resolve, onAppear runs, and the
//  capture is identical on any runner device (test-created windows render
//  blank in degraded full-suite runs — see AppHostWindow.swift).
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/DeckStairHeightSnapshotTests
//

#if DEBUG
import CoreGraphics
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class DeckStairHeightSnapshotTests: XCTestCase {

    private let frameSize = CGSize(width: 393, height: 852) // iPhone 17

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-deck-stair-height-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func snapshot<V: View>(_ name: String, view: V, size: CGSize? = nil) {
        let renderSize = size ?? frameSize
        let image: UIImage
        do {
            image = try FixedSizeSnapshot.render(view, size: renderSize)
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

    // MARK: - Fixtures

    private func squareLevel(idPrefix: String, name: String, originX: CGFloat, sortOrder: Int) -> DeckLevel {
        var level = DeckLevel(name: name, sortOrder: sortOrder)
        level.vertices = [
            DeckVertex(id: "\(idPrefix)v1", position: CGPoint(x: originX, y: 0)),
            DeckVertex(id: "\(idPrefix)v2", position: CGPoint(x: originX + 144, y: 0)),
            DeckVertex(id: "\(idPrefix)v3", position: CGPoint(x: originX + 144, y: 144)),
            DeckVertex(id: "\(idPrefix)v4", position: CGPoint(x: originX, y: 144)),
        ]
        level.edges = [
            DeckEdge(id: "\(idPrefix)e1", startVertexId: "\(idPrefix)v1", endVertexId: "\(idPrefix)v2"),
            DeckEdge(id: "\(idPrefix)e2", startVertexId: "\(idPrefix)v2", endVertexId: "\(idPrefix)v3"),
            DeckEdge(id: "\(idPrefix)e3", startVertexId: "\(idPrefix)v3", endVertexId: "\(idPrefix)v4"),
            DeckEdge(id: "\(idPrefix)e4", startVertexId: "\(idPrefix)v4", endVertexId: "\(idPrefix)v1"),
        ]
        return level
    }

    /// Two-level deck: Level 1 at an explicit 2' 6", Level 2 the upper deck at
    /// an explicit 5', which is the active level (the one the tapped edge is
    /// on). Dimensions set so the width defaults read real.
    private func multiLevelViewModel() -> DeckBuilderViewModel {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        var lower = squareLevel(idPrefix: "a", name: "Level 1", originX: 0, sortOrder: 0)
        lower.elevation = 2.5
        var upper = squareLevel(idPrefix: "b", name: "Level 2", originX: 240, sortOrder: 1)
        upper.elevation = 5.0
        for i in upper.edges.indices { upper.edges[i].dimension = 144 }
        data.levels = [lower, upper]

        let viewModel = DeckBuilderViewModel(deckDesign: DeckDesign(
            companyId: "company-1",
            title: "Stair proof deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        ))
        viewModel.drawingData = data
        viewModel.activeLevelIndex = 1
        return viewModel
    }

    // MARK: - Stair sheet

    func testRenderStairSheetModes() {
        // 1. Treads mode — the count is the input; rise derives from it.
        let treadsVM = multiLevelViewModel()
        treadsVM.editingEdgeId = "be1"
        snapshot(
            "01-stair-treads-mode",
            view: StairConfigView(viewModel: treadsVM, initialMode: .treads),
            size: CGSize(width: 393, height: 1400)
        )

        // 2. Height mode — feet/inches dials, prefilled from the level's
        //    height (5' — the stair spans grade to this level).
        let heightVM = multiLevelViewModel()
        heightVM.editingEdgeId = "be1"
        snapshot(
            "02-stair-height-mode",
            view: StairConfigView(viewModel: heightVM, initialMode: .height),
            size: CGSize(width: 393, height: 1400)
        )

        // 3. Level mode — pick the level the stairs connect down to; the
        //    drop and tread count derive from the two levels' heights.
        let levelVM = multiLevelViewModel()
        levelVM.editingEdgeId = "be1"
        snapshot(
            "03-stair-level-mode",
            view: StairConfigView(viewModel: levelVM, initialMode: .level),
            size: CGSize(width: 393, height: 1400)
        )

        // 4. Connect entry (level bar) — no edge selected yet, so the sheet
        //    leads with its edge picker.
        let connectVM = multiLevelViewModel()
        connectVM.editingEdgeId = nil
        snapshot(
            "04-stair-connect-entry-edge-picker",
            view: StairConfigView(viewModel: connectVM, initialMode: .level),
            size: CGSize(width: 393, height: 1400)
        )
    }

    // MARK: - 2D stair labels (treads + rail run)

    func testRenderStairRailLabels2D() {
        // 7. Edge stair in the read-only 2D viewer — WIDTH/RUN chips plus the
        //    new RAIL chip (30" rise over 40" run → 50" rail, the stair
        //    triangle's hypotenuse).
        var single = DeckDrawingData()
        single.scaleFactor = 1.0
        single.overallElevation = 2.5
        single.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 60, y: 120)),
            DeckVertex(id: "v2", position: CGPoint(x: 300, y: 120)),
            DeckVertex(id: "v3", position: CGPoint(x: 300, y: 320)),
            DeckVertex(id: "v4", position: CGPoint(x: 60, y: 320)),
        ]
        var stairEdge = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        stairEdge.stairConfig = StairConfig(width: 96, runPerTread: 10, treadCount: 4, totalRiseInches: 30)
        single.edges = [
            stairEdge,
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]
        snapshot(
            "07-2d-edge-stair-rail-label",
            view: DeckTab2DView(drawingData: single, toolState: DeckViewerToolState())
        )

        // 8. Connection stair in the 2D viewer — full stair geometry + chips
        //    (was a 16pt dot with no label). Rise derives from the levels'
        //    heights: 5' − 2' 6" = 30" drop.
        var multi = DeckDrawingData()
        multi.scaleFactor = 1.0
        var lower = squareLevel(idPrefix: "a", name: "Level 1", originX: 40, sortOrder: 0)
        lower.elevation = 2.5
        var upper = squareLevel(idPrefix: "b", name: "Level 2", originX: 220, sortOrder: 1)
        upper.elevation = 5.0
        multi.levels = [lower, upper]
        multi.levelConnections = [
            LevelConnection(
                upperLevelId: upper.id,
                lowerLevelId: lower.id,
                // Bottom edge — its outward perpendicular points into empty
                // canvas below the square, so the stair draws on-screen.
                upperEdgeId: "be3",
                stairConfig: StairConfig(width: 96, runPerTread: 10, treadCount: 4)
            )
        ]
        snapshot(
            "08-2d-connection-stair-rail-label",
            view: DeckTab2DView(drawingData: multi, toolState: DeckViewerToolState())
        )
    }

    // MARK: - Height sheet

    func testRenderHeightSheetScopes() {
        // 5. Multi-level — the sheet names the SELECTED level; setting height
        //    here writes that level only.
        let levelVM = multiLevelViewModel()
        snapshot(
            "05-height-sheet-level-scoped",
            view: ElevationInputView(viewModel: levelVM)
        )

        // 6. Single-level — plain deck height.
        var single = DeckDrawingData()
        single.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 144, y: 144)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 144)),
        ]
        single.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2"),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3"),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4"),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1"),
        ]
        single.overallElevation = 2.5
        let singleVM = DeckBuilderViewModel(deckDesign: DeckDesign(
            companyId: "company-1",
            title: "Height proof deck",
            drawingDataJSON: DeckDrawingData().toJSON()
        ))
        singleVM.drawingData = single
        snapshot(
            "06-height-sheet-single-level",
            view: ElevationInputView(viewModel: singleVM)
        )
    }
}
#endif
