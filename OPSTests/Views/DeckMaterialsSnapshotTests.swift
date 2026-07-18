//
//  DeckMaterialsSnapshotTests.swift
//  OPSTests
//
//  Visual-proof harness for the deck-tab `// MATERIALS` section. Renders the real
//  `DeckMaterialsSection` across its four states to PNGs via UIHostingController +
//  UIWindow + drawHierarchy (ImageRenderer is banned here — it renders asset
//  colors as yellow and never runs the SwiftUI lifecycle). NOT a pass/fail test:
//  it writes images for inspection and copies them into docs/artifacts/.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/DeckMaterialsSnapshotTests
//

#if DEBUG
import CoreGraphics
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class DeckMaterialsSnapshotTests: XCTestCase {

    private let frameSize = CGSize(width: 393, height: 720)

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-deck-materials-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Fixtures

    private func project() -> Project {
        Project(id: "proj-1", title: "MERIDIAN DECK", status: .inProgress)
    }

    private func design(
        materialsSettings: DeckMaterialsSettings? = nil,
        orderedMaterials: DeckMaterialsSnapshot? = nil
    ) -> DeckDesign {
        let design = DeckDesign(companyId: "co-1", title: "MERIDIAN DECK")
        var data = design.drawingData
        if let materialsSettings { data.materialsSettings = materialsSettings }
        if let orderedMaterials { data.orderedMaterials = orderedMaterials }
        design.drawingData = data
        return design
    }

    /// Full-roll materials settings — 75' rolls.
    private func rollModeSettings() -> DeckMaterialsSettings {
        var s = DeckMaterialsSettings()
        s.orderMode = .fullRolls
        s.fullRollLengthFeet = 75
        return s
    }

    /// 12'×20' rect, one 20' house edge, "Sandstone" vinyl → drip 44/6, clip 44/5,
    /// 90 flash 20/3, glue 240/1.
    private func liveResolved() -> DeckMaterialsResolver.Resolved {
        let p = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 144, y: 0),
            CGPoint(x: 144, y: 240),
            CGPoint(x: 0, y: 240)
        ]
        let ids = ["v1", "v2", "v3", "v4"]
        let dims = [144.0, 240.0, 144.0, 240.0]
        let edges = (0..<4).map { i in
            VinylOrderSurfaceEdge(
                id: "e\(i)", start: p[i], end: p[(i + 1) % 4],
                edgeType: i == 3 ? .houseEdge : .deckEdge, label: nil,
                startVertexId: ids[i], endVertexId: ids[(i + 1) % 4],
                isParapet: false, dimensionInches: dims[i]
            )
        }
        let input = VinylOrderSurfaceInput(id: "s1", label: "Main", levelName: nil, positions: p, scaleFactor: 1.0, edges: edges)
        var vinyl = VinylOrderSettings.default
        vinyl.color = "Sandstone"
        let materials = DeckMaterialsEngine.compute(
            vinylInputs: [input],
            allDetectedFacesByLevel: [],
            settings: DeckMaterialsSettings(),
            vinylSettings: vinyl
        )
        return DeckMaterialsResolver.Resolved(scale: 1.0, vinylInputs: [input], materials: materials)
    }

    /// Same 12'×20' rect, computed in full-roll mode → materials.rollCount > 0 so
    /// the live vinyl block reads `N ROLLS @ 75' × 72"`.
    private func liveResolvedRollMode() -> DeckMaterialsResolver.Resolved {
        let p = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 144, y: 0),
            CGPoint(x: 144, y: 240),
            CGPoint(x: 0, y: 240)
        ]
        let ids = ["v1", "v2", "v3", "v4"]
        let dims = [144.0, 240.0, 144.0, 240.0]
        let edges = (0..<4).map { i in
            VinylOrderSurfaceEdge(
                id: "e\(i)", start: p[i], end: p[(i + 1) % 4],
                edgeType: i == 3 ? .houseEdge : .deckEdge, label: nil,
                startVertexId: ids[i], endVertexId: ids[(i + 1) % 4],
                isParapet: false, dimensionInches: dims[i]
            )
        }
        let input = VinylOrderSurfaceInput(id: "s1", label: "Main", levelName: nil, positions: p, scaleFactor: 1.0, edges: edges)
        var vinyl = VinylOrderSettings.default
        vinyl.color = "Sandstone"
        let materials = DeckMaterialsEngine.compute(
            vinylInputs: [input],
            allDetectedFacesByLevel: [],
            settings: rollModeSettings(),
            vinylSettings: vinyl
        )
        return DeckMaterialsResolver.Resolved(scale: 1.0, vinylInputs: [input], materials: materials)
    }

    /// Vinyl set present but no resolvable scale — CONFIRM ONE EDGE LENGTH.
    private func confirmDimsResolved() -> DeckMaterialsResolver.Resolved {
        let input = VinylOrderSurfaceInput(id: "s1", label: "Main", levelName: nil, positions: [], scaleFactor: 1.0, edges: [])
        return DeckMaterialsResolver.Resolved(scale: nil, vinylInputs: [input], materials: nil)
    }

    /// Unlocked L-shaped plan with no house edge: the Materials card must show
    /// the canonical blocker instead of order quantities or fabricated cuts.
    private func blockedDirectionResolved() -> DeckMaterialsResolver.Resolved {
        let positions = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 300, y: 0),
            CGPoint(x: 300, y: 70),
            CGPoint(x: 70, y: 70),
            CGPoint(x: 70, y: 300),
            CGPoint(x: 0, y: 300)
        ]
        let edges = positions.indices.map { index in
            VinylOrderSurfaceEdge(
                id: "e\(index)",
                start: positions[index],
                end: positions[(index + 1) % positions.count],
                edgeType: .deckEdge,
                label: nil
            )
        }
        let input = VinylOrderSurfaceInput(
            id: "s1",
            label: "Main",
            levelName: nil,
            positions: positions,
            scaleFactor: 1,
            edges: edges
        )
        var vinyl = VinylOrderSettings.default
        vinyl.seamOverlapInches = 0
        vinyl.edgeWrapInches = 0
        vinyl.allowsDirectionalChanges = true
        let materials = DeckMaterialsEngine.compute(
            vinylInputs: [input],
            allDetectedFacesByLevel: [],
            settings: DeckMaterialsSettings(),
            vinylSettings: vinyl
        )
        XCTAssertFalse(materials.vinylPlan.isOrderable)
        return DeckMaterialsResolver.Resolved(scale: 1, vinylInputs: [input], materials: materials)
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

    /// Ordered in full-roll mode → `3 ROLLS @ 75' × 72"` headline, cut guide below.
    private func orderedSnapshotRollMode() -> DeckMaterialsSnapshot {
        var s = orderedSnapshot()
        s.orderMode = .fullRolls
        s.fullRollLengthFeet = 75
        s.orderedRollCount = 3
        s.vinylOrderedSqFt = 312
        return s
    }

    /// Ordered with hand-edited quantities → subtle ADJUSTED tag by the stamp.
    private func orderedSnapshotAdjusted() -> DeckMaterialsSnapshot {
        var s = orderedSnapshot()
        s.isOrderedEdited = true
        s.dripSticks = 8      // operator bought spare sticks
        s.glueBuckets = 2
        return s
    }

    // MARK: - Render

    private func snapshot(
        _ name: String,
        design: DeckDesign,
        resolved: DeckMaterialsResolver.Resolved?,
        drift: Bool
    ) {
        renderToPNG(name) {
            ZStack(alignment: .top) {
                OPSStyle.Colors.background.ignoresSafeArea()
                DeckMaterialsSection(
                    design: design,
                    project: project(),
                    injectedResolved: resolved,
                    driftFlagged: drift
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
            .frame(width: frameSize.width, height: frameSize.height)
        }
    }

    /// Render any view to a PNG at `frameSize` via UIHostingController + UIWindow +
    /// drawHierarchy (dark mode) and stash it for inspection + docs/artifacts copy.
    private func renderToPNG(_ name: String, @ViewBuilder _ make: () -> some View) {
        let host = UIHostingController(rootView: make().frame(width: frameSize.width, height: frameSize.height))
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: frameSize)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: CGRect(origin: .zero, size: frameSize))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))

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
        print("📸 SNAPSHOT \(name) -> \(outDir.appendingPathComponent("\(name).png").path)")
    }

    // MARK: - Renders

    func testRenderMaterialsStates() {
        // 3 · Live — rows + editable presets.
        snapshot("deck-materials-live", design: design(), resolved: liveResolved(), drift: false)

        // 4 · Ordered — frozen snapshot values, ORDERED stamp, presets locked.
        snapshot("deck-materials-ordered", design: design(orderedMaterials: orderedSnapshot()), resolved: nil, drift: false)

        // 4b · Ordered + drift — DESIGN CHANGED SINCE ORDER banner.
        snapshot("deck-materials-ordered-drift", design: design(orderedMaterials: orderedSnapshot()), resolved: nil, drift: true)

        // 2 · Confirm dimensions — vinyl set but unresolved scale.
        snapshot("deck-materials-confirm-dims", design: design(), resolved: confirmDimsResolved(), drift: false)

        // 2b · Invalid mixed run — blocker only, no fabricated materials list.
        snapshot("deck-materials-direction-blocked", design: design(), resolved: blockedDirectionResolved(), drift: false)

        // 3b · Live full-roll — ROLLS headline + cut guide + ORDER preset.
        snapshot("deck-materials-live-rolls", design: design(materialsSettings: rollModeSettings()), resolved: liveResolvedRollMode(), drift: false)

        // 4b · Ordered full-roll — N ROLLS @ L' × W".
        snapshot("deck-materials-ordered-rolls", design: design(orderedMaterials: orderedSnapshotRollMode()), resolved: nil, drift: false)

        // 4c · Ordered adjusted — ADJUSTED tag by the ORDERED stamp.
        snapshot("deck-materials-ordered-adjusted", design: design(orderedMaterials: orderedSnapshotAdjusted()), resolved: nil, drift: false)
    }

    /// The order-confirm sheet in both modes — cut-list (ORDER SQ FT) and full
    /// roll (ROLLS + ≈ SQ FT echo). Editable quantities pre-filled from the calc.
    func testRenderOrderConfirmSheet() {
        let cutListCalc = DeckMaterialsOrderConfirmation(
            orderMode: .cutList, fullRollLengthFeet: 75,
            vinylOrderedSqFt: 260, rollCount: 0,
            dripSticks: 6, clipSticks: 5, ninetySticks: 3, glueBuckets: 1
        )
        renderToPNG("deck-materials-confirm-sheet") {
            VinylOrderConfirmSheet(
                projectTitle: "MERIDIAN DECK", deckTitle: "MAIN LEVEL",
                rollWidthInches: 72, calculated: cutListCalc, onConfirm: { _ in }
            )
        }

        let rollCalc = DeckMaterialsOrderConfirmation(
            orderMode: .fullRolls, fullRollLengthFeet: 75,
            vinylOrderedSqFt: 312, rollCount: 3,
            dripSticks: 6, clipSticks: 5, ninetySticks: 3, glueBuckets: 1
        )
        renderToPNG("deck-materials-confirm-sheet-rolls") {
            VinylOrderConfirmSheet(
                projectTitle: "MERIDIAN DECK", deckTitle: "MAIN LEVEL",
                rollWidthInches: 72, calculated: rollCalc, onConfirm: { _ in }
            )
        }
    }
}
#endif
