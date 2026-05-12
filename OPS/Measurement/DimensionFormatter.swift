//
//  DimensionFormatter.swift
//  OPS
//
//  Pure-Swift formatter for converting a measurement (metres) to OPS-voice
//  display strings. Drives the Hover-style dimension labels (§3.5) and the
//  PDF dimension table (§3.7).
//
//  OPS voice rules:
//    • JetBrains Mono is applied at the view layer; this struct produces
//      plain Strings with tabular-lining-compatible digits.
//    • Empty state is `—` (U+2014), never "N/A".
//    • Imperial fractions use Unicode glyphs (½ ¼ ¾ ⅛ etc.) at common
//      denominators, fall back to ascii `N/16″` past those.
//    • Prime (′) and double-prime (″) are U+2032 / U+2033.
//    • The interpunct in dual-unit display is U+00B7 (`·`) wrapped in
//      spaces — the spec writes `/` for readability, but `·` is the OPS
//      separator. Public callers can request either via `separator`.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.5
//

import Foundation

public enum DimensionFormatter {

    public static let emptyDash = "—"

    /// Primary + secondary display strings for a measurement value, plus a
    /// pre-composed dual-unit single-line form.
    public struct Formatted: Equatable {
        public let primary: String
        public let secondary: String
        public let dualUnit: String

        public init(primary: String, secondary: String, dualUnit: String) {
            self.primary = primary
            self.secondary = secondary
            self.dualUnit = dualUnit
        }
    }

    public enum Separator: String {
        case slash = " / "
        case interpunct = " · "
    }

    // MARK: - Public API

    /// Formats a measurement value (in metres) into a dual-unit string set.
    /// Returns an `emptyDash`-filled `Formatted` when `valueMeters` is not
    /// finite or non-positive — measurements of zero or NaN are surfaced as
    /// the empty state, never as "0.00 m".
    public static func format(
        valueMeters: Double,
        primaryUnit: DimensionsData.Measurement.DisplayUnit,
        separator: Separator = .slash
    ) -> Formatted {
        guard valueMeters.isFinite, valueMeters > 0 else {
            return Formatted(primary: emptyDash, secondary: emptyDash, dualUnit: emptyDash)
        }
        let primary = string(for: valueMeters, unit: primaryUnit)
        let secondaryUnit = secondary(for: primaryUnit)
        let secondary = string(for: valueMeters, unit: secondaryUnit)
        let dual = primary + separator.rawValue + secondary
        return Formatted(primary: primary, secondary: secondary, dualUnit: dual)
    }

    /// Single-unit string only. Used by the PDF dimension table and any other
    /// caller that does not want a dual-unit line.
    public static func string(
        for valueMeters: Double,
        unit: DimensionsData.Measurement.DisplayUnit
    ) -> String {
        guard valueMeters.isFinite, valueMeters > 0 else {
            return emptyDash
        }
        switch unit {
        case .imperialFraction: return formatImperialFraction(metres: valueMeters)
        case .decimalFeet:      return formatDecimalFeet(metres: valueMeters)
        case .metric:           return formatMetric(metres: valueMeters)
        }
    }

    // MARK: - Imperial fraction

    /// `14′ 6½″`, `36″`, `0″`. Rounds to the nearest 1/16″.
    /// Reduces the fraction (e.g. 8/16 → ½). Hides whole-zero feet (`6½″`,
    /// not `0′ 6½″`). Hides zero-inches when feet is non-zero (`14′`, not
    /// `14′ 0″`). When the rounded value lands exactly on a whole foot at
    /// finer precision (e.g. 11 15/16″ rounds up to 12″ → 1′), recompose.
    static func formatImperialFraction(metres: Double) -> String {
        let totalInches = metres * 39.37007874
        let sixteenths = (totalInches * 16).rounded()
        let totalSixteenths = Int(sixteenths)

        // Whole feet + remainder sixteenths
        let inchesTimes16PerFoot = 16 * 12 // 192
        var feet = totalSixteenths / inchesTimes16PerFoot
        var remSixteenths = totalSixteenths - feet * inchesTimes16PerFoot
        // Split into whole inches + fractional sixteenths
        var wholeInches = remSixteenths / 16
        var fracSixteenths = remSixteenths - wholeInches * 16

        // Already in normal form because of integer division; guard anyway.
        if fracSixteenths == 16 { fracSixteenths = 0; wholeInches += 1 }
        if wholeInches == 12 { wholeInches = 0; feet += 1 }
        remSixteenths = wholeInches * 16 + fracSixteenths

        var parts: [String] = []
        if feet > 0 {
            parts.append("\(feet)\u{2032}")
        }
        if remSixteenths > 0 || feet == 0 {
            let inchesPart = inchesPartString(wholeInches: wholeInches,
                                              fractionSixteenths: fracSixteenths)
            parts.append(inchesPart + "\u{2033}")
        }
        return parts.joined(separator: " ")
    }

    private static func inchesPartString(wholeInches: Int, fractionSixteenths: Int) -> String {
        let fracGlyph = fractionGlyph(sixteenths: fractionSixteenths)
        if wholeInches == 0 {
            return fracGlyph.isEmpty ? "0" : fracGlyph
        }
        if fracGlyph.isEmpty {
            return "\(wholeInches)"
        }
        return "\(wholeInches)\(fracGlyph)"
    }

    /// Returns the Unicode glyph for the common fractions, or an ascii
    /// `n/16` form for sixteenths that lack a single glyph. Empty string
    /// when sixteenths == 0.
    private static func fractionGlyph(sixteenths: Int) -> String {
        switch sixteenths {
        case 0:  return ""
        case 1:  return "\u{2151}" // ⅑ — not standard; we use 1/16 instead
        default: break
        }
        // Reduce 16ths fraction to lowest terms.
        let g = gcd(sixteenths, 16)
        let num = sixteenths / g
        let den = 16 / g
        switch (num, den) {
        case (1, 8):  return "\u{215B}" // ⅛
        case (3, 8):  return "\u{215C}" // ⅜
        case (5, 8):  return "\u{215D}" // ⅝
        case (7, 8):  return "\u{215E}" // ⅞
        case (1, 4):  return "\u{00BC}" // ¼
        case (3, 4):  return "\u{00BE}" // ¾
        case (1, 2):  return "\u{00BD}" // ½
        default:
            return "\(num)/\(den)"
        }
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = abs(a), b = abs(b)
        while b != 0 { (a, b) = (b, a % b) }
        return a == 0 ? 1 : a
    }

    // MARK: - Decimal feet

    /// `14.54′`. Two decimals, no thousands separator (tape-measure idiom).
    static func formatDecimalFeet(metres: Double) -> String {
        let feet = metres * 3.280839895
        return String(format: "%.2f\u{2032}", feet)
    }

    // MARK: - Metric

    /// `4.43 m`. Always metres, two decimals. Sub-metre values still render
    /// in metres (`0.43 m`) — we do NOT switch to centimetres mid-flight,
    /// the chip is meant to be predictable.
    static func formatMetric(metres: Double) -> String {
        return String(format: "%.2f m", metres)
    }

    // MARK: - Secondary unit pairing

    /// Secondary unit chosen for dual-unit display when primary is `unit`.
    /// Imperial-primary pairs with metric; metric-primary pairs with the
    /// imperial-fraction form (richer than decimal feet).
    static func secondary(for unit: DimensionsData.Measurement.DisplayUnit)
        -> DimensionsData.Measurement.DisplayUnit
    {
        switch unit {
        case .imperialFraction: return .metric
        case .decimalFeet:      return .metric
        case .metric:           return .imperialFraction
        }
    }
}
