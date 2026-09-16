//
//  VinylOrderWorkspaceSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the rebuilt vinyl ORDER LAYOUT workspace. Renders the REAL
//  `VinylOrderWorkspace` (and the inline entry card it opens from) to PNGs via
//  the shared fixed-size host, at 393 × 852 — one point size NARROWER than the
//  founder's iPhone 16 Pro (402 × 874), so it is the tighter frame — against the
//  synthetic L-shaped deck the QA launch gate also drives.
//
//  What each PNG has to show, against the founder's own words:
//    · fitted-peek        — the drawing runs the full width, nothing "cuts off
//                           at about 48px in from the right edge"; the deck's
//                           own dimensions are on it; no +/- rail anywhere; the
//                           settings panel rests at its 80pt peek.
//    · zoomed-fit-chip    — zoomed, the FIT chip is the ONLY zoom control.
//    · half-sheet         — the panel pulled up: RUN / PATTERN / LOCK RUN /
//                           ROLL / SEAM / WRAP and the cut list, in place.
//    · reduce-motion      — the same screen with Reduce Motion on: layout is
//                           identical, only the motion softens.
//    · entry-card         — the inline card with NO hairline under its title.
//
//  NOT a pass/fail image test — it writes PNGs for inspection, and asserts only
//  the things a picture cannot: that every band is non-degenerate and that the
//  workspace's motion is entirely token-based (and therefore reduce-motion
//  aware by construction).
//
//  Run:  xcodebuild test-without-building -scheme OPS \
//          -destination 'platform=iOS Simulator,id=<udid>' \
//          -only-testing:OPSTests/VinylOrderWorkspaceSnapshotTests
//

#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class VinylOrderWorkspaceSnapshotTests: XCTestCase {

    /// Portrait, one size DOWN from the founder's iPhone 16 Pro (402 × 874).
    /// Deliberate: the narrower frame is the one a full-width drawing and a
    /// three-up segmented control can fail on first.
    private let frameSize = CGSize(width: 393, height: 852)

    /// The repo's own artifact folder, not the simulator's temp directory —
    /// a proof nobody can find is not a proof, and a stale copy in the repo is
    /// worse than none. `#filePath` is the only handle a unit test has on the
    /// checkout it was built from.
    private var outDir: URL {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OPSTests/Views
            .deletingLastPathComponent()   // OPSTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("docs/artifacts/vinyl-order-workspace-20260908", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - The screens

    func testFittedWorkspaceWithThePanelAtItsPeek() throws {
        try capture("vinyl-workspace-fitted-peek", workspace())
    }

    func testZoomedWorkspaceShowsTheFitChip() throws {
        try capture(
            "vinyl-workspace-zoomed-fit-chip",
            workspace(
                viewport: VinylOrderViewportState(
                    scale: 2,
                    offset: CGSize(width: 40, height: -60)
                )
            )
        )
    }

    /// Zoomed 4× about the middle of the band — a state the operator can
    /// actually reach, resolved through the real camera and the real content
    /// rect. The picture has to show vector geometry (no bitmap smear: the
    /// transform is inside the live `Canvas` now) with its callouts still the
    /// same size on screen as they are in the fitted PNG. Bug 1a8e48af.
    func testZoomedDrawingKeepsItsCalloutsAtScreenSize() throws {
        let layout = VinylOrderWorkspaceGeometry(
            containerSize: frameSize,
            topInset: 59,
            bottomInset: 34
        )
        let content = try XCTUnwrap(
            VinylCutPreview(plan: VinylOrderQAFixture.plan(), measurementSystem: .imperial)
                .contentRect(in: layout.drawingSize),
            "the QA fixture has to draw something to zoom into"
        )

        var viewport = VinylOrderViewportState()
        viewport.applyZoom(
            multiplier: 4,
            anchor: CGPoint(x: layout.drawingSize.width / 2, y: layout.drawingSize.height / 2),
            viewportSize: layout.drawingSize,
            contentBounds: content
        )
        XCTAssertEqual(viewport.scale, 4, accuracy: 0.001)

        try capture("vinyl-workspace-zoomed-4x", workspace(viewport: viewport))
    }

    func testHalfSheetPutsTheSettingsUnderTheDrawing() throws {
        try capture(
            "vinyl-workspace-half-sheet",
            workspace(panelDetent: .half)
        )
    }

    /// Reduce Motion softens motion; it must not move a pixel of the layout.
    ///
    /// It cannot be injected: `\.accessibilityReduceMotion` is a read-only
    /// environment key, and OPS reads the setting through
    /// `OPSStyle.Animation.reduceMotion` → `UIAccessibility.isReduceMotionEnabled`
    /// anyway — a process-wide value. So this captures the screen under
    /// whatever the host simulator is set to and records which that was; the
    /// artifact run captures a second pass with the simulator's flag ON, and
    /// the two PNGs are compared. What proves the MOTION itself softens is
    /// `testEveryWorkspaceAnimationIsAReduceMotionAwareToken` below — a still
    /// picture cannot show motion, and pretending otherwise would be theatre.
    func testReduceMotionLeavesTheLayoutUntouched() throws {
        try capture("vinyl-workspace-reduce-motion", workspace())
        print("REDUCE_MOTION \(OPSStyle.Animation.reduceMotion)")

        // The layout cannot depend on the setting: the geometry is a pure value
        // over the container and the safe-area insets, and takes no other input.
        let layout = VinylOrderWorkspaceGeometry(
            containerSize: frameSize,
            topInset: 59,
            bottomInset: 34
        )
        XCTAssertEqual(layout.drawingRect.width, frameSize.width, accuracy: 0.001)
        XCTAssertEqual(
            layout.headerRect.height + layout.drawingRect.height
                + VinylOrderWorkspaceGeometry.sheetPeekHeight,
            frameSize.height,
            accuracy: 0.001,
            "the three bands must tile the screen exactly, Reduce Motion or not"
        )
    }

    /// The largest accessibility size. The header band, the FIT chip and the
    /// peek strip are capped (MOBILE.md §2.1 fixed-height nav bar), so the
    /// drawing keeps its room and nothing overlaps it; the settings the operator
    /// pulls up scale all the way.
    func testLargestAccessibilitySizeDoesNotEatTheDrawing() throws {
        try capture(
            "vinyl-workspace-accessibility-max",
            AnyView(
                workspace(panelDetent: .half)
                    .environment(\.dynamicTypeSize, .accessibility5)
            )
        )
    }

    func testEntryCardHasNoHairlineUnderItsTitle() throws {
        let card = ZStack {
            OPSStyle.Colors.background
            VinylOrderLayoutWindow(
                plan: VinylOrderQAFixture.plan(),
                projectTitle: VinylOrderQAFixture.projectTitle,
                subtitle: VinylOrderQAFixture.deckTitle,
                settings: .constant(.default),
                measurementSystem: .imperial,
                onSettingsChanged: {}
            )
            .padding(OPSStyle.Layout.spacing3)
        }
        try capture(
            "vinyl-order-entry-card",
            AnyView(card),
            size: CGSize(width: 393, height: 320)
        )
    }

    // MARK: - What a picture cannot prove

    /// Every band the workspace tiles is real at the founder's frame — no
    /// zero-height drawing, no peek swallowed by the header.
    func testEveryBandIsNonDegenerateAtTheFoundersFrame() {
        let layout = VinylOrderWorkspaceGeometry(
            containerSize: frameSize,
            topInset: 59,
            bottomInset: 34
        )

        XCTAssertGreaterThan(layout.headerRect.height, 0)
        XCTAssertGreaterThan(layout.drawingRect.height, 0)
        XCTAssertGreaterThan(layout.sheetPeekRect.height, 0)
        XCTAssertEqual(layout.drawingRect.width, frameSize.width, accuracy: 0.001)
    }

    /// Reduce Motion is honoured by construction: every animation in the
    /// workspace and its settings panel is an `OPSStyle.Animation` token, and
    /// those tokens resolve to a 150ms crossfade when the setting is on. A raw
    /// curve or a spring literal would bypass that — so the source must not
    /// contain one.
    func testEveryWorkspaceAnimationIsAReduceMotionAwareToken() throws {
        let banned = [".spring(", ".easeInOut(", ".easeIn(", ".easeOut(", ".linear(", ".timingCurve("]

        for file in ["VinylCutPreview.swift", "VinylOrderSettingsSheet.swift"] {
            let source = try sourceText(named: file)
            for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                let text = String(line)
                guard text.contains("withAnimation(") || text.contains(".animation(") else { continue }
                for token in banned {
                    XCTAssertFalse(
                        text.contains(token),
                        "\(file): raw animation \(token) bypasses the reduce-motion-aware OPSStyle tokens — \(text.trimmingCharacters(in: .whitespaces))"
                    )
                }
                XCTAssertTrue(
                    text.contains("OPSStyle.Animation."),
                    "\(file): animation without an OPSStyle token — \(text.trimmingCharacters(in: .whitespaces))"
                )
            }
        }
    }

    // MARK: - Fixtures

    private func workspace(
        viewport: VinylOrderViewportState = VinylOrderViewportState(),
        panelDetent: VinylOrderPanelDetent = .peek
    ) -> AnyView {
        AnyView(
            VinylOrderWorkspace(
                plan: VinylOrderQAFixture.plan(),
                projectTitle: VinylOrderQAFixture.projectTitle,
                deckTitle: VinylOrderQAFixture.deckTitle,
                measurementSystem: .imperial,
                settings: .constant(.default),
                viewport: .constant(viewport),
                panelDetent: panelDetent,
                onSettingsChanged: {},
                onClose: {}
            )
        )
    }

    private func capture<V: View>(
        _ name: String,
        _ view: V,
        size: CGSize? = nil
    ) throws {
        let image = try FixedSizeSnapshot.render(view, size: size ?? frameSize)
        let data = try XCTUnwrap(image.pngData(), "no PNG data for \(name)")

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)

        try data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("SNAPSHOT \(name)")
    }

    /// Walk up from this test file to the repo root and read an app source file.
    /// `#filePath` is the only handle a unit test has on the sources it guards.
    private func sourceText(named name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OPSTests/Views
            .deletingLastPathComponent()   // OPSTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("OPS/DeckBuilder/Views/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
#endif
