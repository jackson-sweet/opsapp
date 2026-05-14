//
//  DimensionFormatterTests.swift
//  OPSTests
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.5
//

import XCTest
@testable import OPS

final class DimensionFormatterTests: XCTestCase {

    // MARK: - Imperial fraction

    func test_imperialFraction_renders14ft6AndAHalfInches() {
        // 14′ 6½″ == 14*12 + 6.5 = 174.5″ == 4.4323 m
        let metres = 174.5 * 0.0254
        let s = DimensionFormatter.string(for: metres, unit: .imperialFraction)
        XCTAssertEqual(s, "14\u{2032} 6\u{00BD}\u{2033}")
    }

    func test_imperialFraction_exactFoot() {
        // 1 ft == 0.3048 m
        XCTAssertEqual(
            DimensionFormatter.string(for: 0.3048, unit: .imperialFraction),
            "1\u{2032}"
        )
    }

    func test_imperialFraction_smallSubInch() {
        // 1/4 inch == 0.00635 m
        XCTAssertEqual(
            DimensionFormatter.string(for: 0.00635, unit: .imperialFraction),
            "\u{00BC}\u{2033}"
        )
    }

    func test_imperialFraction_pureInches() {
        // 6 in == 0.1524 m → 6″, no feet
        XCTAssertEqual(
            DimensionFormatter.string(for: 0.1524, unit: .imperialFraction),
            "6\u{2033}"
        )
    }

    func test_imperialFraction_roundsUpToWholeFoot() {
        // 11 15/16 inches rounds up to 12 → 1 foot
        // 11 + 15/16 = 11.9375 in → 11.97 in is closer to 12 → 1′
        // Use a value that lands within 1/32 of a full foot.
        let metres = (12.0 - 1.0 / 32.0) * 0.0254  // 11 31/32 in
        let s = DimensionFormatter.string(for: metres, unit: .imperialFraction)
        XCTAssertEqual(s, "1\u{2032}")
    }

    func test_imperialFraction_reducesFraction() {
        // 4/16 == 1/4
        let metres = (6 + 4.0 / 16.0) * 0.0254
        let s = DimensionFormatter.string(for: metres, unit: .imperialFraction)
        XCTAssertEqual(s, "6\u{00BC}\u{2033}")
    }

    func test_imperialFraction_sixteenthsFallbackToAscii() {
        // 6 3/16 in — no single Unicode glyph for 3/16, expect ascii form.
        let metres = (6 + 3.0 / 16.0) * 0.0254
        let s = DimensionFormatter.string(for: metres, unit: .imperialFraction)
        XCTAssertEqual(s, "6 3/16\u{2033}")
    }

    func test_imperialFraction_oneSixteenthUsesAsciiFraction() {
        let metres = (1.0 / 16.0) * 0.0254
        let s = DimensionFormatter.string(for: metres, unit: .imperialFraction)
        XCTAssertEqual(s, "1/16\u{2033}")
    }

    func test_imperialFraction_wholeInchesPlusOneSixteenthUsesAsciiFraction() {
        let metres = (6 + 1.0 / 16.0) * 0.0254
        let s = DimensionFormatter.string(for: metres, unit: .imperialFraction)
        XCTAssertEqual(s, "6 1/16\u{2033}")
    }

    func test_imperialFraction_eightFootGenericMeasurementStaysFeet() {
        let metres = 96.0 * 0.0254
        let s = DimensionFormatter.string(for: metres, unit: .imperialFraction)
        XCTAssertEqual(s, "8\u{2032}")
    }

    func test_imperialFraction_wholeInchesPlusThreeSixteenthsRemainAsciiFraction() {
        let metres = (36 + 3.0 / 16.0) * 0.0254
        let s = DimensionFormatter.string(for: metres, unit: .imperialFraction)
        XCTAssertEqual(s, "3\u{2032} 3/16\u{2033}")
    }

    func test_openingContext_thirtySixInchWindowWidthStaysInches() {
        let metres = 36.0 * 0.0254
        let s = DimensionFormatter.string(
            for: metres,
            unit: .imperialFraction,
            displayContext: .opening
        )
        XCTAssertEqual(s, "36\u{2033}")
    }

    func test_openingContext_sixtyInchDoorHeightStaysInches() {
        let metres = 60.0 * 0.0254
        let s = DimensionFormatter.string(
            for: metres,
            unit: .imperialFraction,
            displayContext: .opening
        )
        XCTAssertEqual(s, "60\u{2033}")
    }

    func test_displayContext_usesWindowDoorMeasurementIdsOnly() {
        let windowID = UUID()
        let doorID = UUID()
        let wallID = UUID()
        let openings: [DimensionsData.Opening] = [
            .init(type: .window,
                  boundingPolygon: [],
                  classificationConfidence: 0.9,
                  measurementIds: [windowID]),
            .init(type: .door,
                  boundingPolygon: [],
                  classificationConfidence: 0.9,
                  measurementIds: [doorID]),
            .init(type: .wallSection,
                  boundingPolygon: [],
                  classificationConfidence: 0.9,
                  measurementIds: [wallID])
        ]

        XCTAssertEqual(DimensionFormatter.displayContext(for: windowID, openings: openings), .opening)
        XCTAssertEqual(DimensionFormatter.displayContext(for: doorID, openings: openings), .opening)
        XCTAssertEqual(DimensionFormatter.displayContext(for: wallID, openings: openings), .standard)
    }

    // MARK: - Accessibility speech

    func test_accessibilityLabel_openingWidthSpeaksThirtySixInchesNotFeet() {
        let metres = 36.0 * 0.0254
        let label = DimensionFormatter.accessibilityLabel(
            measurementLabel: "Width",
            valueMeters: metres,
            primaryUnit: .imperialFraction,
            displayContext: .opening
        )
        XCTAssertEqual(label, "Width: 36 inches, 0.91 meters")
    }

    func test_accessibilityLabel_fractionalImperialSpeaksFeetInchesAndFractionWords() {
        let metres = 174.5 * 0.0254
        let label = DimensionFormatter.accessibilityLabel(
            measurementLabel: "Height",
            valueMeters: metres,
            primaryUnit: .imperialFraction,
            displayContext: .standard
        )
        XCTAssertEqual(label, "Height: 14 feet, 6 inches and one half, 4.43 meters")
    }

    func test_accessibilityLabel_metricPrimaryIncludesImperialSecondarySpeech() {
        let label = DimensionFormatter.accessibilityLabel(
            measurementLabel: "Width",
            valueMeters: 1.0,
            primaryUnit: .metric,
            displayContext: .standard
        )
        XCTAssertEqual(label, "Width: 1.00 meters, 3 feet, 3 inches and three eighths")
    }

    func test_accessibilityLabel_inlineHintSpeaksHintWithoutTacticalGlyphs() {
        let metres = 60.0 * 0.0254
        let label = DimensionFormatter.accessibilityLabel(
            measurementLabel: "Height",
            valueMeters: metres,
            primaryUnit: .imperialFraction,
            displayContext: .opening,
            inlineHint: "// SILL — NO FLOOR REFERENCE"
        )
        XCTAssertEqual(label, "Height: 60 inches, 1.52 meters. Sill: no floor reference")
    }

    func test_visualOpeningFormatterStringsRemainUnchanged() {
        let metres = 36.0 * 0.0254
        let f = DimensionFormatter.format(
            valueMeters: metres,
            primaryUnit: .imperialFraction,
            displayContext: .opening
        )
        XCTAssertEqual(f.primary, "36\u{2033}")
        XCTAssertEqual(f.secondary, "0.91 m")
        XCTAssertEqual(f.dualUnit, "36\u{2033} / 0.91 m")
    }

    func test_imperialFraction_neverContainsOneNinthGlyph() {
        let formattedValues = (1...31).map { sixteenths in
            DimensionFormatter.string(
                for: (Double(sixteenths) / 16.0) * 0.0254,
                unit: .imperialFraction
            )
        }

        XCTAssertFalse(
            formattedValues.contains { $0.contains("\u{2151}") },
            "Imperial 1/16-inch formatting must not emit U+2151."
        )
    }

    // MARK: - Decimal feet

    func test_decimalFeet_twoDecimals() {
        // 14′ 6½″ == 14.5417 ft → "14.54′"
        let metres = 174.5 * 0.0254
        let s = DimensionFormatter.string(for: metres, unit: .decimalFeet)
        XCTAssertEqual(s, "14.54\u{2032}")
    }

    // MARK: - Metric

    func test_metric_twoDecimals() {
        // 174.5″ == 4.4323 m → "4.43 m"
        let metres = 174.5 * 0.0254
        let s = DimensionFormatter.string(for: metres, unit: .metric)
        XCTAssertEqual(s, "4.43 m")
    }

    // MARK: - Dual-unit

    func test_dualUnit_imperialPrimary_pairsWithMetric() {
        let metres = 174.5 * 0.0254
        let f = DimensionFormatter.format(valueMeters: metres, primaryUnit: .imperialFraction)
        XCTAssertEqual(f.primary, "14\u{2032} 6\u{00BD}\u{2033}")
        XCTAssertEqual(f.secondary, "4.43 m")
        XCTAssertEqual(f.dualUnit, "14\u{2032} 6\u{00BD}\u{2033} / 4.43 m")
    }

    func test_dualUnit_metricPrimary_pairsWithImperialFraction() {
        let metres = 1.0
        let f = DimensionFormatter.format(valueMeters: metres, primaryUnit: .metric)
        XCTAssertEqual(f.primary, "1.00 m")
        XCTAssertEqual(f.secondary, "3\u{2032} 3\u{215C}\u{2033}")  // 1 m == 3′ 3⅜″
        XCTAssertEqual(f.dualUnit, "1.00 m / 3\u{2032} 3\u{215C}\u{2033}")
    }

    func test_dualUnit_decimalFeetPrimary_pairsWithMetric() {
        let metres = 0.5
        let f = DimensionFormatter.format(valueMeters: metres, primaryUnit: .decimalFeet)
        XCTAssertEqual(f.primary, "1.64\u{2032}")
        XCTAssertEqual(f.secondary, "0.50 m")
        XCTAssertEqual(f.dualUnit, "1.64\u{2032} / 0.50 m")
    }

    func test_dualUnit_interpunctSeparator() {
        let metres = 1.0
        let f = DimensionFormatter.format(
            valueMeters: metres,
            primaryUnit: .metric,
            separator: .interpunct
        )
        XCTAssertEqual(f.dualUnit, "1.00 m \u{00B7} 3\u{2032} 3\u{215C}\u{2033}")
    }

    // MARK: - Empty state

    func test_zeroValue_returnsEmptyDash() {
        let f = DimensionFormatter.format(valueMeters: 0, primaryUnit: .imperialFraction)
        XCTAssertEqual(f.primary, "\u{2014}")
        XCTAssertEqual(f.secondary, "\u{2014}")
        XCTAssertEqual(f.dualUnit, "\u{2014}")
    }

    func test_nanValue_returnsEmptyDash() {
        let f = DimensionFormatter.format(valueMeters: .nan, primaryUnit: .metric)
        XCTAssertEqual(f.primary, "\u{2014}")
    }

    func test_negativeValue_returnsEmptyDash() {
        let s = DimensionFormatter.string(for: -1.0, unit: .metric)
        XCTAssertEqual(s, "\u{2014}")
    }
}
