//
//  LeadDeckScreenSnapshotTests.swift
//  OPSTests
//
//  Visual proof for `LeadDeckScreen` — the pushed destination behind the lead
//  dossier's DECK row, where the drawing gets the whole display.
//
//  Renders the REAL screen (live `@Query`, real `DeckTabView`, real permission
//  gates) into a `UIHostingController` + `UIWindow` and captures with
//  `drawHierarchy`, the harness `DaySheetViewSnapshotTests` uses. NOT pass/fail
//  — writes images for inspection.
//
//  What the shots are for:
//    · the two-segment mode picker — a lead has no MATERIALS tab, because
//      materials read the project's tasks/catalog and write a vinyl order
//    · EDIT present/absent purely on `deck_builder.edit`
//    · the canonical screen header carrying the lead's name
//    · the empty state a design with nothing drawn into it lands on
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/LeadDeckScreenSnapshotTests
//

#if DEBUG
import CoreGraphics
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class LeadDeckScreenSnapshotTests: XCTestCase {

    private let frameSize = CGSize(width: 393, height: 852)

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-lead-deck-screen-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Fixtures

    /// Closed 12'×20' rectangle with dimensioned edges — renderable geometry, so
    /// the screen shows the canvas rather than the empty state.
    private func closedRect() -> DeckDrawingData {
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

    /// Three sides of the same rectangle — geometry the tab will render, but no
    /// closed surface, so 3D reports the outline instead of a solid.
    private func openRect() -> DeckDrawingData {
        var data = closedRect()
        data.edges.removeLast()
        return data
    }

    private func lead() -> Opportunity {
        let opportunity = Opportunity.preview(
            id: "lead-deck-1",
            title: "Back deck, wraparound",
            contactName: "Helen Calloway",
            stage: .quoted,
            estimatedValue: 18_400,
            daysInStage: 4
        )
        opportunity.address = "1240 Maple Ave"
        return opportunity
    }

    /// In-memory container holding one design attached to the lead, so the
    /// screen's `@Query` + `displayCandidate` resolve exactly like production.
    private func stage(
        for opportunity: Opportunity,
        drawing: DeckDrawingData?
    ) throws -> ModelContainer {
        let container = try ModelContainer(
            for: DeckDesign.self, Project.self, ProjectTask.self, Product.self, CatalogItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let design = DeckDesign(
            companyId: "preview-company",
            opportunityId: opportunity.id,
            title: "Back deck — wraparound"
        )
        if let drawing { design.drawingData = drawing }
        container.mainContext.insert(design)
        try container.mainContext.save()
        return container
    }

    /// A delegate on his own lead: `assigned` view/edit on the pipeline, plus
    /// the deck grants. `canEdit` decides whether the deck tab renders EDIT.
    private func store(canEdit: Bool) -> PermissionStore {
        let permissions = PermissionStore.previewWithAssignedAccess()
        permissions.permissions["deck_builder.view"] = "assigned"
        permissions.permissions["deck_builder.create"] = "assigned"
        if canEdit { permissions.permissions["deck_builder.edit"] = "assigned" }
        return permissions
    }

    // MARK: - Render

    private func snapshot(
        _ name: String,
        drawing: DeckDrawingData?,
        canEdit: Bool = true
    ) throws {
        let opportunity = lead()
        let container = try stage(for: opportunity, drawing: drawing)

        let view = NavigationStack {
            LeadDeckScreen(opportunity: opportunity)
        }
        .environmentObject(store(canEdit: canEdit))
        .environmentObject(DataController())
        .modelContainer(container)
        .frame(width: frameSize.width, height: frameSize.height)
        .ignoresSafeArea()

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
        // Let onAppear + @Query + the tab's self-repair task settle.
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

    // MARK: - Shots

    /// The screen as an operator who can draw sees it: `HELEN CALLOWAY` under a
    /// ‹ LEAD back control, the canvas below, and a control row reading 3D | 2D
    /// with EDIT trailing — TWO segments, never three.
    func testRenderLeadDeckScreenEditor() throws {
        try snapshot("lead_deck_screen_editor", drawing: closedRect())
    }

    /// Same lead, an operator without `deck_builder.edit`: identical screen with
    /// no EDIT verb. A viewer is never shown an action that can only refuse.
    func testRenderLeadDeckScreenViewer() throws {
        try snapshot("lead_deck_screen_viewer", drawing: closedRect(), canEdit: false)
    }

    /// Geometry that never closed — 3D names the gap and points at the plan
    /// instead of rendering an empty stage. Proves the canvas region is live and
    /// correctly sized under the screen's header.
    func testRenderLeadDeckScreenOpenOutline() throws {
        try snapshot("lead_deck_screen_open_outline", drawing: openRect())
    }

    /// A design row that was never drawn into: the deck surface's own empty
    /// state, with the create path intact.
    func testRenderLeadDeckScreenEmpty() throws {
        try snapshot("lead_deck_screen_empty", drawing: nil)
    }
}
#endif
