//
//  DeckFullscreenSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for the deck fullscreen viewer. Renders the real
//  `DeckFullscreenViewer` (2D mode) across tool states to PNGs via SwiftUI's
//  `ImageRenderer`, so the new top bar + tool rail + peek-sheet chrome can be
//  eyeballed headlessly. NOT a pass/fail test — it writes images for inspection.
//
//  3D is covered by DeckSceneSnapshotTests (SCNRenderer). ImageRenderer cannot
//  capture SceneKit, and it does not run `onAppear` — so these fixtures are
//  pre-centered for the 393pt viewport (the live viewer centers in onAppear).
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/DeckFullscreenSnapshotTests
//  Extract: xcrun xcresulttool export attachments --path <result.xcresult> ...
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class DeckFullscreenSnapshotTests: XCTestCase {

    private let frameSize = CGSize(width: 393, height: 852) // iPhone 17

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-deck-fullscreen-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Render via a real `UIHostingController` in a visible `UIWindow`. Unlike
    /// `ImageRenderer`, this resolves asset-catalog colors (OPS's canvas/accent
    /// colors are `Color("…")`) AND runs the SwiftUI lifecycle — so
    /// `DeckTab2DView.centerViewport()` fires in `onAppear` and the plan is framed.
    private func snapshot(_ name: String, toolState: DeckViewerToolState, drawingData: DeckDrawingData, title: String) {
        let view = DeckFullscreenViewer(
            title: title,
            drawingData: drawingData,
            viewMode: .constant(.twoD),
            toolState: toolState,
            onClose: {}
        )

        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: frameSize)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: CGRect(origin: .zero, size: frameSize))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Let onAppear + the centering re-layout settle before capture.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))

        let renderer = UIGraphicsImageRenderer(size: frameSize)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
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

    // MARK: - Renders

    func testRenderFullscreenChrome() {
        // 1. Single-level, no tools — top bar + base rail (measure/select/dims/fit).
        snapshot("01-single-idle", toolState: DeckViewerToolState(),
                 drawingData: Self.centeredSingleLevel(), title: "MERIDIAN DECK")

        // 2. Single-level, select mode with a railing edge picked — peek sheet readout.
        let selecting = DeckViewerToolState()
        selecting.toggleSelect()
        selecting.selectedEdgeIds = ["e2"] // right glass railing (14')
        snapshot("02-single-select-readout", toolState: selecting,
                 drawingData: Self.centeredSingleLevel(), title: "MERIDIAN DECK")

        // 3. Single-level, measure mode — the degenerate two-point run: one
        //    dashed segment + its length pill, undo/finish rail buttons.
        let measuring = DeckViewerToolState()
        measuring.toggleMeasure()
        measuring.recordMeasureTap(raw: CGPoint(x: 76, y: 296), closeThreshold: 12)
        measuring.recordMeasureTap(raw: CGPoint(x: 316, y: 296), closeThreshold: 12)
        snapshot("03-single-measure", toolState: measuring,
                 drawingData: Self.centeredSingleLevel(), title: "MERIDIAN DECK")

        // 4. Multi-level, no tools — full 5-tool rail (isolate present).
        snapshot("04-multi-idle", toolState: DeckViewerToolState(),
                 drawingData: Self.centeredMultiLevel(), title: "HILLSIDE TWO-TIER")

        // 5. Multi-level, isolate active on the upper level — others dimmed.
        let isolatedData = Self.centeredMultiLevel()
        let isolating = DeckViewerToolState()
        isolating.isolatedLevelId = isolatedData.levels.last?.id
        snapshot("05-multi-isolate", toolState: isolating,
                 drawingData: isolatedData, title: "HILLSIDE TWO-TIER")

        // 6. Measure polyline mid-draw — per-segment pills, first-dot close
        //    halo + faint close preview, measure card with running total,
        //    undo/finish rail buttons, "TAP FIRST TO CLOSE" hint.
        let polyline = DeckViewerToolState()
        polyline.toggleMeasure()
        polyline.recordMeasureTap(raw: CGPoint(x: 76, y: 276), closeThreshold: 12)
        polyline.recordMeasureTap(raw: CGPoint(x: 316, y: 276), closeThreshold: 12)
        polyline.recordMeasureTap(raw: CGPoint(x: 316, y: 444), closeThreshold: 12)
        snapshot("06-measure-polyline", toolState: polyline,
                 drawingData: Self.centeredSingleLevel(), title: "MERIDIAN DECK")

        // 7. Measure loop closed around the deck — amber fill, centroid area
        //    pill, AREA + PERIMETER card, "TAP TO RESET" hint.
        let closedLoop = DeckViewerToolState()
        closedLoop.toggleMeasure()
        closedLoop.recordMeasureTap(raw: CGPoint(x: 76, y: 276), closeThreshold: 12)
        closedLoop.recordMeasureTap(raw: CGPoint(x: 316, y: 276), closeThreshold: 12)
        closedLoop.recordMeasureTap(raw: CGPoint(x: 316, y: 444), closeThreshold: 12)
        closedLoop.recordMeasureTap(raw: CGPoint(x: 76, y: 444), closeThreshold: 12)
        closedLoop.recordMeasureTap(raw: CGPoint(x: 78, y: 278), closeThreshold: 12) // close on first dot
        snapshot("07-measure-closed", toolState: closedLoop,
                 drawingData: Self.centeredSingleLevel(), title: "MERIDIAN DECK")

        // 8. Split armed on the footprint surface with a valid diagonal-ish
        //    cut — tinted halves, white chord, SIDE A/B card, scissors active.
        let splitData = Self.centeredSingleLevel()
        let splitting = DeckViewerToolState()
        splitting.toggleSelect()
        if let face = splitData.detectedSurfaces.first {
            splitting.selectedSurfaceIds = [face.id]
        }
        splitting.toggleSplitting()
        splitting.recordSplitTap(CGPoint(x: 196, y: 250))
        splitting.recordSplitTap(CGPoint(x: 196, y: 470))
        snapshot("08-select-split", toolState: splitting,
                 drawingData: splitData, title: "MERIDIAN DECK")
    }

    // MARK: - Viewport-centered fixtures (≈ centered in a 393×852 pt canvas)

    /// 20' × 14' deck centered near (196, 360): stair front, glass rail right,
    /// house edge back, wood rail left.
    static func centeredSingleLevel() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.overallElevation = 3.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 76, y: 276)),
            DeckVertex(id: "v2", position: CGPoint(x: 316, y: 276)),
            DeckVertex(id: "v3", position: CGPoint(x: 316, y: 444)),
            DeckVertex(id: "v4", position: CGPoint(x: 76, y: 444)),
        ]
        var front = DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2")
        front.dimension = 240
        front.stairConfig = StairConfig(width: 48,
                                        railingConfig: RailingConfig(railingType: .glass, maxPostSpacing: 48),
                                        totalRiseInches: 36)
        var right = DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3")
        right.dimension = 168
        right.railingConfig = RailingConfig(railingType: .glass, maxPostSpacing: 48)
        var back = DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4")
        back.dimension = 240
        back.edgeType = .houseEdge
        back.houseEdgeMaterial = .hardie
        var left = DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1")
        left.dimension = 168
        left.railingConfig = RailingConfig(railingType: .wood, maxPostSpacing: 72)
        data.edges = [front, right, back, left]
        return data
    }

    /// Two stacked levels centered near (196, 360) for the multi-level rail + isolate.
    static func centeredMultiLevel() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0

        var lower = DeckLevel(name: "Lower")
        lower.elevation = 2.0
        lower.vertices = [
            DeckVertex(id: "l1", position: CGPoint(x: 76, y: 276)),
            DeckVertex(id: "l2", position: CGPoint(x: 316, y: 276)),
            DeckVertex(id: "l3", position: CGPoint(x: 316, y: 456)),
            DeckVertex(id: "l4", position: CGPoint(x: 76, y: 456)),
        ]
        lower.edges = [
            Self.edge("le1", "l1", "l2", dim: 240),
            Self.edge("le2", "l2", "l3", dim: 180, rail: .glass),
            Self.edge("le3", "l3", "l4", dim: 240, rail: .glass),
            Self.edge("le4", "l4", "l1", dim: 180, rail: .glass),
        ]

        var upper = DeckLevel(name: "Upper")
        upper.elevation = 5.0
        upper.vertices = [
            DeckVertex(id: "u1", position: CGPoint(x: 136, y: 300)),
            DeckVertex(id: "u2", position: CGPoint(x: 256, y: 300)),
            DeckVertex(id: "u3", position: CGPoint(x: 256, y: 420)),
            DeckVertex(id: "u4", position: CGPoint(x: 136, y: 420)),
        ]
        upper.edges = [
            Self.edge("ue1", "u1", "u2", dim: 120),
            Self.edge("ue2", "u2", "u3", dim: 120, rail: .glass),
            Self.edge("ue3", "u3", "u4", dim: 120, rail: .glass),
            Self.edge("ue4", "u4", "u1", dim: 120, rail: .glass),
        ]

        data.levels = [lower, upper]
        return data
    }

    private static func edge(_ id: String, _ s: String, _ e: String, dim: Double, rail: RailingType? = nil) -> DeckEdge {
        var edge = DeckEdge(id: id, startVertexId: s, endVertexId: e)
        edge.dimension = dim
        if let rail { edge.railingConfig = RailingConfig(railingType: rail, maxPostSpacing: 48) }
        return edge
    }
}
#endif
