//
//  VinylOrderWorkspaceGeometryTests.swift
//  OPSTests
//
//  Geometry proof for the full-screen vinyl ORDER LAYOUT workspace.
//
//  Bug 317da29f: the old fullscreen layout reserved a 56pt zoom rail on the
//  right and drew into what was left, so the drawing read as "cut off at about
//  48px in from the right edge". The workspace has no rail — the drawing owns
//  the full container width, and the only bands that take height are the header
//  and the settings sheet at its peek detent.
//

import CoreGraphics
import XCTest
@testable import OPS

final class VinylOrderWorkspaceGeometryTests: XCTestCase {

    /// Portrait, one size DOWN from the founder's iPhone 16 Pro (402 × 874) —
    /// the tighter of the two, so every band that tiles here tiles there.
    private let container = CGSize(width: 393, height: 852)

    /// MOBILE.md §1 bottom safe area (home indicator). Asserted against, not
    /// styled with — the peek band must clear it and still seat a content row.
    private let homeIndicatorInset: CGFloat = 34

    // MARK: - The bug

    func testDrawingOwnsTheFullContainerWidth() {
        let geometry = VinylOrderWorkspaceGeometry(containerSize: container)

        XCTAssertEqual(geometry.drawingSize.width, container.width, accuracy: 0.001)
        XCTAssertEqual(geometry.drawingRect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(geometry.drawingRect.maxX, container.width, accuracy: 0.001)
    }

    func testDrawingHeightIsWhatTheHeaderAndPeekLeaveBehind() {
        let geometry = VinylOrderWorkspaceGeometry(containerSize: container)

        XCTAssertEqual(
            geometry.drawingSize.height,
            container.height
                - VinylOrderWorkspaceGeometry.headerHeight
                - VinylOrderWorkspaceGeometry.sheetPeekHeight,
            accuracy: 0.001
        )
        XCTAssertEqual(
            geometry.drawingCenter.y,
            VinylOrderWorkspaceGeometry.headerHeight + (geometry.drawingSize.height / 2),
            accuracy: 0.001
        )
    }

    /// Header, drawing and peek tile the container edge to edge: no seam, no
    /// double-booked band, nothing left over.
    func testHeaderDrawingAndPeekTileTheContainerExactly() {
        let geometry = VinylOrderWorkspaceGeometry(containerSize: container)

        XCTAssertEqual(geometry.headerRect.minY, 0, accuracy: 0.001)
        XCTAssertEqual(geometry.headerRect.maxY, geometry.drawingRect.minY, accuracy: 0.001)
        XCTAssertEqual(geometry.drawingRect.maxY, geometry.sheetPeekRect.minY, accuracy: 0.001)
        XCTAssertEqual(geometry.sheetPeekRect.maxY, container.height, accuracy: 0.001)

        for rect in [geometry.headerRect, geometry.drawingRect, geometry.sheetPeekRect] {
            XCTAssertEqual(rect.width, container.width, accuracy: 0.001)
        }
    }

    // MARK: - FIT chip

    /// The chip floats over the drawing, but it must never collide with the
    /// header's controls above it or the settings sheet below it, and it must
    /// stand off the trailing bezel rather than sitting flush to it.
    func testFitChipClearsTheHeaderThePeekAndTheTrailingBezel() {
        let geometry = VinylOrderWorkspaceGeometry(containerSize: container)
        let chip = geometry.fitChipRect

        XCTAssertFalse(chip.intersects(geometry.headerRect))
        XCTAssertFalse(chip.intersects(geometry.sheetPeekRect))
        XCTAssertTrue(geometry.drawingRect.contains(chip))
        XCTAssertEqual(
            container.width - chip.maxX,
            VinylOrderWorkspaceGeometry.fitChipInset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            chip.minY - geometry.drawingRect.minY,
            VinylOrderWorkspaceGeometry.fitChipInset,
            accuracy: 0.001
        )
    }

    func testFitChipMeetsTheTouchTargetFloor() {
        let chip = VinylOrderWorkspaceGeometry(containerSize: container).fitChipRect

        XCTAssertGreaterThanOrEqual(chip.height, OPSStyle.Layout.touchTargetMin)
        XCTAssertGreaterThanOrEqual(chip.width, OPSStyle.Layout.touchTargetMin)
    }

    // MARK: - Peek band

    /// MOBILE.md §6.1: an 80pt peek. It has to seat the handle plus one summary
    /// row entirely above the home indicator, or the summary reads as clipped.
    func testPeekBandSeatsAContentRowAboveTheHomeIndicator() {
        XCTAssertGreaterThanOrEqual(VinylOrderWorkspaceGeometry.sheetPeekHeight, 80)
        XCTAssertGreaterThanOrEqual(
            VinylOrderWorkspaceGeometry.sheetPeekHeight - homeIndicatorInset,
            OPSStyle.Layout.touchTargetMin
        )
    }

    // MARK: - Safe areas

    /// The workspace runs under the status bar so the drawing can reach the
    /// bezels; the header band puts the inset back so the title clears the
    /// Dynamic Island. The drawing never pays for the top inset twice.
    func testTopInsetGrowsTheHeaderBandAndNothingElse() {
        let bare = VinylOrderWorkspaceGeometry(containerSize: container)
        let inset = VinylOrderWorkspaceGeometry(
            containerSize: container,
            topInset: 59,
            bottomInset: homeIndicatorInset
        )

        XCTAssertEqual(inset.headerRect.height, bare.headerRect.height + 59, accuracy: 0.001)
        XCTAssertEqual(inset.drawingRect.minY, inset.headerRect.maxY, accuracy: 0.001)
        XCTAssertEqual(inset.drawingSize.width, container.width, accuracy: 0.001)
        XCTAssertEqual(
            inset.drawingSize.height,
            bare.drawingSize.height - 59,
            accuracy: 0.001
        )
    }

    /// The peek band is measured from the screen edge, not from the top of the
    /// home indicator — the panel's own content pads the indicator away. If the
    /// band grew by the inset the drawing would sit above a dead strip.
    func testBottomInsetDoesNotGrowThePeekBand() {
        let inset = VinylOrderWorkspaceGeometry(
            containerSize: container,
            topInset: 59,
            bottomInset: homeIndicatorInset
        )

        XCTAssertEqual(
            inset.sheetPeekRect.height,
            VinylOrderWorkspaceGeometry.sheetPeekHeight,
            accuracy: 0.001
        )
        XCTAssertEqual(inset.sheetPeekRect.maxY, container.height, accuracy: 0.001)
        XCTAssertEqual(inset.drawingRect.maxY, inset.sheetPeekRect.minY, accuracy: 0.001)
    }

    /// A phone one size below the founder's: bezel-to-bezel width, and a drawing
    /// band that is still the majority of the screen.
    func testFoundersDeviceLeavesTheDrawingTheMajorityOfTheScreen() {
        let geometry = VinylOrderWorkspaceGeometry(
            containerSize: container,
            topInset: 59,
            bottomInset: homeIndicatorInset
        )

        XCTAssertEqual(geometry.drawingSize.width, container.width, accuracy: 0.001)
        XCTAssertGreaterThan(geometry.drawingSize.height, container.height / 2)
    }

    // MARK: - Settings panel

    /// MOBILE.md §6.2 caps a half sheet at 50% of the screen, and the panel can
    /// never rest shorter than its own peek.
    func testHalfDetentIsHalfTheScreenAndNeverBelowThePeek() {
        let geometry = VinylOrderWorkspaceGeometry(containerSize: container)

        XCTAssertEqual(geometry.sheetHalfHeight, (container.height / 2).rounded(), accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(
            geometry.sheetHalfHeight,
            VinylOrderWorkspaceGeometry.sheetPeekHeight
        )

        let tiny = VinylOrderWorkspaceGeometry(containerSize: CGSize(width: 393, height: 100))
        XCTAssertEqual(
            tiny.sheetHalfHeight,
            VinylOrderWorkspaceGeometry.sheetPeekHeight,
            accuracy: 0.001
        )
    }

    func testPanelHeightClampsToItsTwoRestHeights() {
        let peek = VinylOrderWorkspaceGeometry.sheetPeekHeight
        let half = VinylOrderWorkspaceGeometry(containerSize: container).sheetHalfHeight

        // A hard flick up past the half detent still stops at half.
        XCTAssertEqual(
            VinylOrderSettingsPanel.height(
                detent: .peek,
                dragOffset: -2_000,
                peekHeight: peek,
                halfHeight: half
            ),
            half,
            accuracy: 0.001
        )

        // A hard flick down past the peek still stops at peek — the panel is
        // part of the workspace and cannot be dismissed.
        XCTAssertEqual(
            VinylOrderSettingsPanel.height(
                detent: .half,
                dragOffset: 2_000,
                peekHeight: peek,
                halfHeight: half
            ),
            peek,
            accuracy: 0.001
        )

        // Mid-drag it tracks the finger.
        XCTAssertEqual(
            VinylOrderSettingsPanel.height(
                detent: .peek,
                dragOffset: -60,
                peekHeight: peek,
                halfHeight: half
            ),
            peek + 60,
            accuracy: 0.001
        )
    }

    func testReleaseSettlesToTheNearerDetent() {
        let peek = VinylOrderWorkspaceGeometry.sheetPeekHeight
        let half = VinylOrderWorkspaceGeometry(containerSize: container).sheetHalfHeight
        let midpoint = (peek + half) / 2

        XCTAssertEqual(
            VinylOrderSettingsPanel.settledDetent(
                forHeight: midpoint - 1,
                peekHeight: peek,
                halfHeight: half
            ),
            .peek
        )
        XCTAssertEqual(
            VinylOrderSettingsPanel.settledDetent(
                forHeight: midpoint + 1,
                peekHeight: peek,
                halfHeight: half
            ),
            .half
        )
    }

    /// The grab strip carries a tap AND a drag on one recogniser, so the
    /// release has to classify itself. The threshold is deliberately looser
    /// than UIKit's 10pt `allowableMovement`: this screen gets a gloved thumb,
    /// and a tap that wobbles must still toggle rather than die as a drag that
    /// settles back where it started.
    func testAWobblingThumbStillCountsAsATap() {
        XCTAssertGreaterThan(
            VinylOrderSettingsPanel.tapTravelCeiling,
            10,
            "the tap slop must clear UIKit's own allowableMovement for gloves"
        )

        for travel in [CGFloat(0), 6, -6, -9, 9] {
            XCTAssertEqual(
                VinylOrderSettingsPanel.release(forTravel: travel),
                .tap,
                "\(travel)pt of travel is a tap"
            )
        }

        for travel in [CGFloat(40), -40, 300, -300] {
            XCTAssertEqual(
                VinylOrderSettingsPanel.release(forTravel: travel),
                .drag,
                "\(travel)pt of travel is a drag"
            )
        }
    }

    // MARK: - Degenerate containers

    /// A zero-height container (first layout pass, or a hosting controller that
    /// has not sized yet) must never hand `Canvas` a negative frame.
    func testDegenerateContainerStillYieldsAPositiveDrawingSize() {
        let geometry = VinylOrderWorkspaceGeometry(containerSize: .zero)

        XCTAssertGreaterThan(geometry.drawingSize.width, 0)
        XCTAssertGreaterThan(geometry.drawingSize.height, 0)
    }
}
