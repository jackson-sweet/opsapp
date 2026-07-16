//
//  DeckTabModeSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the deck tab's three-way mode row: 3D | 2D | MATERIALS.
//  The materials list is a sibling tab of the two renderings — not a section
//  scrolling below them. Renders the REAL `DeckTabView` (live @Query +
//  environment objects) per mode to PNGs via UIHostingController + UIWindow +
//  drawHierarchy. NOT pass/fail — writes images for inspection.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/DeckTabModeSnapshotTests
//

#if DEBUG
import CoreGraphics
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class DeckTabModeSnapshotTests: XCTestCase {

    private let frameSize = CGSize(width: 393, height: 720)

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-deck-tab-mode-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Fixtures

    /// Closed 12'×20' rectangle with dimensioned edges — renderable geometry
    /// for the viewport modes and a resolvable footprint for materials.
    private func rectDrawingData() -> DeckDrawingData {
        var data = DeckDrawingData()
        data.scaleFactor = 1.0
        data.vertices = [
            DeckVertex(id: "v1", position: CGPoint(x: 0, y: 0)),
            DeckVertex(id: "v2", position: CGPoint(x: 144, y: 0)),
            DeckVertex(id: "v3", position: CGPoint(x: 144, y: 240)),
            DeckVertex(id: "v4", position: CGPoint(x: 0, y: 240))
        ]
        data.edges = [
            DeckEdge(id: "e1", startVertexId: "v1", endVertexId: "v2", dimension: 144),
            DeckEdge(id: "e2", startVertexId: "v2", endVertexId: "v3", dimension: 240),
            DeckEdge(id: "e3", startVertexId: "v3", endVertexId: "v4", dimension: 144),
            DeckEdge(id: "e4", startVertexId: "v4", endVertexId: "v1", dimension: 240)
        ]
        return data
    }

    private func orderedSnapshot() -> DeckMaterialsSnapshot {
        DeckMaterialsSnapshot(
            orderedAt: Date(timeIntervalSince1970: 1_749_700_000),
            orderedBy: "user-1",
            settings: DeckMaterialsSettings(),
            vinylSettings: .default,
            vinylColor: "Sandstone",
            vinylOrderedSqFt: 260,
            vinylSurfaceAreaSqFt: 240,
            cutGroups: [
                DeckMaterialsSnapshot.CutGroup(surfaceLabel: "Main", count: 2, lengthInches: 252, rollWidthInches: 72),
                DeckMaterialsSnapshot.CutGroup(surfaceLabel: "Main", count: 1, lengthInches: 144, rollWidthInches: 72)
            ],
            dripEdgeFeet: 44, dripSticks: 6,
            clipFeet: 44, clipSticks: 5,
            ninetyFeet: 20, ninetySticks: 3,
            glueAreaSqFt: 240, glueBuckets: 1,
            vinylSurfaceCount: 1
        )
    }

    /// Insert a design + project into an in-memory container so DeckTabView's
    /// live @Query resolves exactly like production.
    private func makeStage(ordered: Bool) throws -> (container: ModelContainer, project: Project) {
        let container = try ModelContainer(
            for: DeckDesign.self, Project.self, ProjectTask.self, Product.self, CatalogItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let project = Project(id: "proj-1", title: "MERIDIAN DECK", status: .inProgress)
        let design = DeckDesign(companyId: "co-1", title: "MERIDIAN DECK")
        design.projectId = project.id
        var data = rectDrawingData()
        if ordered { data.orderedMaterials = orderedSnapshot() }
        design.drawingData = data
        container.mainContext.insert(project)
        container.mainContext.insert(design)
        try container.mainContext.save()
        return (container, project)
    }

    // MARK: - Render

    private func snapshot(_ name: String, mode: DeckTabViewMode, ordered: Bool) throws {
        let stage = try makeStage(ordered: ordered)
        let view = ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()
            DeckTabView(
                project: stage.project,
                onCreateDeckDesign: {},
                onEditDeckDesign: { _ in },
                viewMode: .constant(mode)
            )
        }
        .environmentObject(PermissionStore())
        .environmentObject(DataController())
        .modelContainer(stage.container)

        let host = UIHostingController(rootView: view.frame(width: frameSize.width, height: frameSize.height))
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: frameSize)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: CGRect(origin: .zero, size: frameSize))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Let onAppear + @Query + the materials .task settle before capture.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.8))

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

    func testRenderDeckTabModes() throws {
        // 1. 2D plan — control row reads 3D | 2D | MATERIALS with EDIT trailing.
        try snapshot("01-tab-2d", mode: .twoD, ordered: true)

        // 2. MATERIALS with an ordered list — the list IS the tab body:
        //    flush under the control row, no `// MATERIALS` header.
        try snapshot("02-tab-materials-ordered", mode: .materials, ordered: true)

        // 3. MATERIALS on a non-vinyl design — the empty state names the path
        //    forward instead of rendering a blank tab.
        try snapshot("03-tab-materials-empty", mode: .materials, ordered: false)

        // 4. 3D — SceneKit may rasterize dark under drawHierarchy; the proof
        //    target is the control row staying coherent in every mode.
        try snapshot("04-tab-3d", mode: .threeD, ordered: true)
    }
}
#endif
