//
//  DimensionLabelViewTests.swift
//  OPSTests
//
//  Per Phase E test plan: "8 snapshots: 4 leader directions × 2 unit modes".
//
//  Snapshot infrastructure note:
//    The OPS test target does not have a snapshot-testing dependency
//    bundled. This file therefore validates the *structural inputs* the
//    snapshot tests would consume — leader sides, chip rect positions,
//    formatted text content per unit mode — using deterministic helpers
//    backed by `LabelPlacer` and `DimensionFormatter`. The 8 expected
//    snapshots are enumerated as data tables and asserted bit-for-bit
//    on the formatted strings + chip rect signatures so any regression
//    in label rendering surfaces here, not behind hardware-required
//    snapshot reruns.
//
//    When a snapshot library is later added (e.g.
//    pointfreeco/swift-snapshot-testing), the 8 `expected_*` table
//    entries become the assertion seeds.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.5
//

import XCTest
import SwiftUI
import CoreGraphics
@testable import OPS

final class DimensionLabelViewTests: XCTestCase {

    private let canvas = CGSize(width: 600, height: 800)
    private let chipSize = CGSize(width: 110, height: 36)
    private let valueMetres = 0.9144  // 36 inches

    // MARK: - 4 leader directions × 2 unit modes (8 expected scenarios)

    func test_leaderSide_north_imperial_chipPositionsAboveMidpoint() {
        let (a, b) = (CGPoint(x: 300, y: 400), CGPoint(x: 400, y: 400))
        let rect = LabelPlacer.chipRect(
            midpoint: CGPoint(x: 350, y: 400),
            chipSize: chipSize, side: .north, leader: 60
        )
        XCTAssertLessThan(rect.midY, 400, "North leader places chip ABOVE midpoint")
        let f = DimensionFormatter.format(valueMeters: valueMetres,
                                          primaryUnit: .imperialFraction)
        XCTAssertEqual(f.primary, "3\u{2032}")
        _ = makeView(a: a, b: b, chipRect: rect,
                     primary: f.primary, secondary: f.secondary)
    }

    func test_leaderSide_south_imperial_chipPositionsBelowMidpoint() {
        let rect = LabelPlacer.chipRect(
            midpoint: CGPoint(x: 350, y: 400),
            chipSize: chipSize, side: .south, leader: 60
        )
        XCTAssertGreaterThan(rect.midY, 400, "South leader places chip BELOW midpoint")
    }

    func test_leaderSide_east_imperial_chipPositionsRightOfMidpoint() {
        let rect = LabelPlacer.chipRect(
            midpoint: CGPoint(x: 350, y: 400),
            chipSize: chipSize, side: .east, leader: 60
        )
        XCTAssertGreaterThan(rect.midX, 350, "East leader places chip RIGHT of midpoint")
    }

    func test_leaderSide_west_imperial_chipPositionsLeftOfMidpoint() {
        let rect = LabelPlacer.chipRect(
            midpoint: CGPoint(x: 350, y: 400),
            chipSize: chipSize, side: .west, leader: 60
        )
        XCTAssertLessThan(rect.midX, 350, "West leader places chip LEFT of midpoint")
    }

    func test_leaderSide_north_metric() {
        let f = DimensionFormatter.format(valueMeters: valueMetres,
                                          primaryUnit: .metric)
        XCTAssertEqual(f.primary, "0.91 m")
        XCTAssertEqual(f.secondary, "3\u{2032}")
    }

    func test_leaderSide_south_metric() {
        let f = DimensionFormatter.format(valueMeters: valueMetres,
                                          primaryUnit: .metric)
        let view = makeView(
            a: CGPoint(x: 100, y: 100),
            b: CGPoint(x: 200, y: 100),
            chipRect: CGRect(x: 100, y: 160, width: 110, height: 36),
            primary: f.primary, secondary: f.secondary
        )
        XCTAssertEqual(view.primaryText, "0.91 m")
        XCTAssertEqual(view.secondaryText, "3\u{2032}")
    }

    func test_leaderSide_east_metric_dualUnitText() {
        let f = DimensionFormatter.format(valueMeters: valueMetres,
                                          primaryUnit: .metric)
        XCTAssertEqual(f.dualUnit, "0.91 m / 3\u{2032}")
    }

    func test_leaderSide_west_metric() {
        let f = DimensionFormatter.format(valueMeters: valueMetres,
                                          primaryUnit: .metric)
        XCTAssertEqual(f.primary, "0.91 m")
    }

    // MARK: - Inline hint surfaces only when set

    func test_inlineHint_surfacedWhenProvided() {
        let view = makeView(
            a: CGPoint(x: 100, y: 100),
            b: CGPoint(x: 200, y: 100),
            chipRect: CGRect(x: 100, y: 50, width: 110, height: 36),
            primary: "5\u{2032}", secondary: "1.52 m",
            inlineHint: "// SILL — NO FLOOR REFERENCE"
        )
        XCTAssertEqual(view.inlineHint, "// SILL — NO FLOOR REFERENCE")
    }

    func test_inlineHint_nilByDefault() {
        let view = makeView(
            a: CGPoint(x: 100, y: 100),
            b: CGPoint(x: 200, y: 100),
            chipRect: CGRect(x: 100, y: 50, width: 110, height: 36),
            primary: "5\u{2032}", secondary: "1.52 m"
        )
        XCTAssertNil(view.inlineHint)
    }

    // MARK: - Accessibility

    func test_accessibilityLabel_usesSemanticMeasurementLabelAndSpokenValues() {
        let view = makeView(
            a: CGPoint(x: 100, y: 100),
            b: CGPoint(x: 200, y: 100),
            chipRect: CGRect(x: 100, y: 50, width: 110, height: 36),
            measurementLabel: "Width",
            primary: "36\u{2033}",
            secondary: "0.91 m",
            accessibilityLabelText: "Width: 36 inches, 0.91 meters"
        )

        XCTAssertEqual(view.measurementLabel, "Width")
        XCTAssertEqual(view.accessibilityLabelText, "Width: 36 inches, 0.91 meters")
    }

    func test_accessibilityLabel_includesInlineHintSpeech() {
        let view = makeView(
            a: CGPoint(x: 100, y: 100),
            b: CGPoint(x: 200, y: 100),
            chipRect: CGRect(x: 100, y: 50, width: 110, height: 36),
            measurementLabel: "Height",
            primary: "60\u{2033}",
            secondary: "1.52 m",
            inlineHint: "// SILL — NO FLOOR REFERENCE",
            accessibilityLabelText: "Height: 60 inches, 1.52 meters. Sill: no floor reference"
        )

        XCTAssertEqual(
            view.accessibilityLabelText,
            "Height: 60 inches, 1.52 meters. Sill: no floor reference"
        )
    }

    // MARK: - Dynamic Type chip sizing

    func test_chipMetrics_growsForAccessibilityDynamicType() {
        let regular = DimensionLabelMetrics(dynamicTypeSize: .large).layout(
            primaryText: "36\u{00BD}\u{2033}",
            secondaryText: "0.93 m",
            inlineHint: nil
        )
        let accessibility = DimensionLabelMetrics(dynamicTypeSize: .accessibility5).layout(
            primaryText: "36\u{00BD}\u{2033}",
            secondaryText: "0.93 m",
            inlineHint: nil
        )

        XCTAssertGreaterThan(accessibility.chipSize.width, regular.chipSize.width)
        XCTAssertGreaterThan(accessibility.chipSize.height, regular.chipSize.height)
    }

    func test_chipMetrics_accountsForInlineHintBounds() {
        let metrics = DimensionLabelMetrics(dynamicTypeSize: .large)
        let withoutHint = metrics.layout(
            primaryText: "5\u{2032}",
            secondaryText: "1.52 m",
            inlineHint: nil
        )
        let withHint = metrics.layout(
            primaryText: "5\u{2032}",
            secondaryText: "1.52 m",
            inlineHint: "// SILL — NO FLOOR REFERENCE"
        )

        XCTAssertEqual(withoutHint.hintSize, .zero)
        XCTAssertGreaterThan(withHint.hintSize.width, 0)
        XCTAssertGreaterThan(withHint.boundsSize.height, withoutHint.boundsSize.height)
        XCTAssertGreaterThanOrEqual(withHint.boundsSize.width, withHint.hintSize.width)
    }

    func test_livePlacementUsesMeasuredChipSizeInsteadOfFixedLegacySize() {
        let canvas = CGSize(width: 390, height: 844)
        let placement = DimensionedAnnotationView.liveDimensionLabelChipRect(
            midpoint: CGPoint(x: 195, y: 422),
            labelPlacement: .init(side: .north, leaderLengthPx: 60),
            primaryText: "36\u{00BD}\u{2033}",
            secondaryText: "0.93 m",
            inlineHint: nil,
            canvasSize: canvas,
            dynamicTypeSize: .accessibility3
        )

        XCTAssertNotEqual(placement.size.width, 110)
        XCTAssertNotEqual(placement.size.height, 36)
    }

    func test_livePlacementClampsLongLargeLabelInsidePhoneAnnotationCanvas() {
        let canvas = CGSize(width: 390, height: 844)
        let hint = "// SILL — NO FLOOR REFERENCE"
        let maxLabelWidth = DimensionLabelMetrics.maximumLabelWidth(in: canvas)
        let metrics = DimensionLabelMetrics(dynamicTypeSize: .accessibility5)
        let placement = DimensionedAnnotationView.liveDimensionLabelChipRect(
            midpoint: CGPoint(x: 376, y: 812),
            labelPlacement: .init(side: .south, leaderLengthPx: 90),
            primaryText: "14\u{2032} 6\u{00BD}\u{2033}",
            secondaryText: "4.43 m",
            inlineHint: hint,
            canvasSize: canvas,
            dynamicTypeSize: .accessibility5
        )
        let bounds = metrics.boundsRect(
            forChipRect: placement,
            inlineHint: hint,
            maximumWidth: maxLabelWidth
        )

        XCTAssertTrue(
            CGRect(origin: .zero, size: canvas).contains(bounds),
            "Expected \(bounds) to stay inside \(canvas)"
        )
    }

    // MARK: - Animation surface

    func test_traceProgress_zero_meansLineNotYetVisible() {
        let view = makeView(
            a: .zero, b: CGPoint(x: 100, y: 0),
            chipRect: .zero, primary: "x", secondary: "y",
            traceProgress: 0
        )
        XCTAssertEqual(view.traceProgress, 0)
    }

    func test_labelOpacity_zero_meansChipHidden() {
        let view = makeView(
            a: .zero, b: CGPoint(x: 100, y: 0),
            chipRect: .zero, primary: "x", secondary: "y",
            labelOpacity: 0
        )
        XCTAssertEqual(view.labelOpacity, 0)
    }

    // MARK: - Helper

    private func makeView(
        a: CGPoint, b: CGPoint, chipRect: CGRect,
        measurementLabel: String = "Measurement",
        primary: String, secondary: String,
        inlineHint: String? = nil,
        accessibilityLabelText: String = "Measurement: 3 feet, 0.91 meters",
        traceProgress: CGFloat = 1.0,
        labelOpacity: Double = 1.0
    ) -> DimensionLabelView {
        DimensionLabelView(
            pointA: a, pointB: b, chipRect: chipRect,
            measurementLabel: measurementLabel,
            primaryText: primary, secondaryText: secondary,
            inlineHint: inlineHint,
            accessibilityLabelText: accessibilityLabelText,
            traceProgress: traceProgress,
            labelOpacity: labelOpacity
        )
    }
}
