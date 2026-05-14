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

    public enum DisplayContext: Equatable {
        case standard
        case opening
    }

    // MARK: - Public API

    /// Formats a measurement value (in metres) into a dual-unit string set.
    /// Returns an `emptyDash`-filled `Formatted` when `valueMeters` is not
    /// finite or non-positive — measurements of zero or NaN are surfaced as
    /// the empty state, never as "0.00 m".
    public static func format(
        valueMeters: Double,
        primaryUnit: DimensionsData.Measurement.DisplayUnit,
        displayContext: DisplayContext = .standard,
        separator: Separator = .slash
    ) -> Formatted {
        guard valueMeters.isFinite, valueMeters > 0 else {
            return Formatted(primary: emptyDash, secondary: emptyDash, dualUnit: emptyDash)
        }
        let primary = string(for: valueMeters, unit: primaryUnit, displayContext: displayContext)
        let secondaryUnit = secondary(for: primaryUnit)
        let secondary = string(for: valueMeters, unit: secondaryUnit, displayContext: displayContext)
        let dual = primary + separator.rawValue + secondary
        return Formatted(primary: primary, secondary: secondary, dualUnit: dual)
    }

    /// Single-unit string only. Used by the PDF dimension table and any other
    /// caller that does not want a dual-unit line.
    public static func string(
        for valueMeters: Double,
        unit: DimensionsData.Measurement.DisplayUnit,
        displayContext: DisplayContext = .standard
    ) -> String {
        guard valueMeters.isFinite, valueMeters > 0 else {
            return emptyDash
        }
        switch unit {
        case .imperialFraction:
            switch displayContext {
            case .standard: return formatImperialFraction(metres: valueMeters)
            case .opening:  return formatImperialOpeningInches(metres: valueMeters)
            }
        case .decimalFeet:      return formatDecimalFeet(metres: valueMeters)
        case .metric:           return formatMetric(metres: valueMeters)
        }
    }

    public static func displayContext(
        for measurementID: UUID,
        openings: [DimensionsData.Opening]
    ) -> DisplayContext {
        let isWindowOrDoorMeasurement = openings.contains { opening in
            switch opening.type {
            case .window, .door:
                return opening.measurementIds.contains(measurementID)
            case .wallSection:
                return false
            }
        }
        return isWindowOrDoorMeasurement ? .opening : .standard
    }

    // MARK: - Accessibility speech

    public static func accessibilityLabel(
        measurementLabel: String,
        valueMeters: Double,
        primaryUnit: DimensionsData.Measurement.DisplayUnit,
        displayContext: DisplayContext = .standard,
        inlineHint: String? = nil,
        includeSecondaryUnit: Bool = true
    ) -> String {
        let label = spokenMeasurementLabel(measurementLabel)
        guard valueMeters.isFinite, valueMeters > 0 else {
            return "\(label): no measurement"
        }

        var parts = [
            spokenString(for: valueMeters, unit: primaryUnit, displayContext: displayContext)
        ]
        if includeSecondaryUnit {
            let secondaryUnit = secondary(for: primaryUnit)
            parts.append(spokenString(for: valueMeters, unit: secondaryUnit, displayContext: displayContext))
        }

        var result = "\(label): \(parts.joined(separator: ", "))"
        if let hint = spokenInlineHint(inlineHint) {
            result += ". \(hint)"
        }
        return result
    }

    public static func spokenString(
        for valueMeters: Double,
        unit: DimensionsData.Measurement.DisplayUnit,
        displayContext: DisplayContext = .standard
    ) -> String {
        guard valueMeters.isFinite, valueMeters > 0 else {
            return "no measurement"
        }

        switch unit {
        case .imperialFraction:
            return spokenImperialFraction(metres: valueMeters, displayContext: displayContext)
        case .decimalFeet:
            return String(format: "%.2f feet", valueMeters * 3.280839895)
        case .metric:
            return String(format: "%.2f meters", valueMeters)
        }
    }

    // MARK: - Imperial fraction

    /// `14′ 6½″`, `36″`, `0″`. Rounds to the nearest 1/16″.
    /// Reduces the fraction (e.g. 8/16 → ½). Hides whole-zero feet (`6½″`,
    /// not `0′ 6½″`). Hides zero-inches when feet is non-zero (`14′`, not
    /// `14′ 0″`). When the rounded value lands exactly on a whole foot at
    /// finer precision (e.g. 11 15/16″ rounds up to 12″ → 1′), recompose.
    static func formatImperialFraction(metres: Double) -> String {
        let components = imperialComponents(metres: metres, displayContext: .standard)
        let feet = components.feet
        let wholeInches = components.wholeInches
        let fracSixteenths = components.fractionSixteenths
        let remSixteenths = wholeInches * 16 + fracSixteenths

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

    static func formatImperialOpeningInches(metres: Double) -> String {
        let components = imperialComponents(metres: metres, displayContext: .opening)
        return inchesPartString(
            wholeInches: components.wholeInches,
            fractionSixteenths: components.fractionSixteenths
        ) + "\u{2033}"
    }

    private static func imperialComponents(
        metres: Double,
        displayContext: DisplayContext
    ) -> (feet: Int, wholeInches: Int, fractionSixteenths: Int) {
        let totalInches = metres / 0.0254
        let totalSixteenths = Int((totalInches * 16).rounded())

        switch displayContext {
        case .opening:
            let wholeInches = totalSixteenths / 16
            let fractionSixteenths = totalSixteenths - wholeInches * 16
            return (0, wholeInches, fractionSixteenths)
        case .standard:
            let sixteenthsPerFoot = 16 * 12
            var feet = totalSixteenths / sixteenthsPerFoot
            var remainder = totalSixteenths - feet * sixteenthsPerFoot
            var wholeInches = remainder / 16
            var fractionSixteenths = remainder - wholeInches * 16

            if fractionSixteenths == 16 {
                fractionSixteenths = 0
                wholeInches += 1
            }
            if wholeInches == 12 {
                wholeInches = 0
                feet += 1
            }
            remainder = wholeInches * 16 + fractionSixteenths
            if remainder == 0 {
                return (feet, 0, 0)
            }
            return (feet, wholeInches, fractionSixteenths)
        }
    }

    private static func inchesPartString(wholeInches: Int, fractionSixteenths: Int) -> String {
        let fraction = fractionText(sixteenths: fractionSixteenths)
        if wholeInches == 0 {
            return fraction.text.isEmpty ? "0" : fraction.text
        }
        if fraction.text.isEmpty {
            return "\(wholeInches)"
        }
        if fraction.joinsToWholeInches {
            return "\(wholeInches)\(fraction.text)"
        }
        return "\(wholeInches) \(fraction.text)"
    }

    /// Returns the Unicode glyph for the common fractions, or an ascii
    /// `n/16` form for sixteenths that lack a single glyph. Empty string
    /// when sixteenths == 0.
    private static func fractionText(sixteenths: Int) -> (text: String, joinsToWholeInches: Bool) {
        if sixteenths == 0 {
            return ("", true)
        }

        // Reduce 16ths fraction to lowest terms.
        let g = gcd(sixteenths, 16)
        let num = sixteenths / g
        let den = 16 / g
        switch (num, den) {
        case (1, 8):  return ("\u{215B}", true) // ⅛
        case (3, 8):  return ("\u{215C}", true) // ⅜
        case (5, 8):  return ("\u{215D}", true) // ⅝
        case (7, 8):  return ("\u{215E}", true) // ⅞
        case (1, 4):  return ("\u{00BC}", true) // ¼
        case (3, 4):  return ("\u{00BE}", true) // ¾
        case (1, 2):  return ("\u{00BD}", true) // ½
        default:
            return ("\(num)/\(den)", false)
        }
    }

    private static func spokenImperialFraction(
        metres: Double,
        displayContext: DisplayContext
    ) -> String {
        let components = imperialComponents(metres: metres, displayContext: displayContext)
        let feet = components.feet
        let wholeInches = components.wholeInches
        let fractionSixteenths = components.fractionSixteenths
        let hasInches = wholeInches > 0 || fractionSixteenths > 0 || feet == 0

        var parts: [String] = []
        if feet > 0 {
            parts.append("\(feet) \(feet == 1 ? "foot" : "feet")")
        }
        if hasInches {
            parts.append(spokenInches(wholeInches: wholeInches, fractionSixteenths: fractionSixteenths))
        }
        return parts.joined(separator: ", ")
    }

    private static func spokenInches(wholeInches: Int, fractionSixteenths: Int) -> String {
        guard fractionSixteenths > 0 else {
            return "\(wholeInches) \(wholeInches == 1 ? "inch" : "inches")"
        }
        guard wholeInches > 0 else {
            return "\(fractionWords(sixteenths: fractionSixteenths)) inch"
        }
        return "\(wholeInches) \(wholeInches == 1 ? "inch" : "inches") and \(fractionWords(sixteenths: fractionSixteenths))"
    }

    private static func fractionWords(sixteenths: Int) -> String {
        let g = gcd(sixteenths, 16)
        let numerator = sixteenths / g
        let denominator = 16 / g
        let numeratorText = numberWord(numerator)

        switch denominator {
        case 2: return numerator == 1 ? "one half" : "\(numeratorText) halves"
        case 4: return numerator == 1 ? "one quarter" : "\(numeratorText) quarters"
        case 8: return numerator == 1 ? "one eighth" : "\(numeratorText) eighths"
        case 16: return numerator == 1 ? "one sixteenth" : "\(numeratorText) sixteenths"
        default: return "\(numeratorText) over \(denominator)"
        }
    }

    private static func numberWord(_ value: Int) -> String {
        switch value {
        case 0: return "zero"
        case 1: return "one"
        case 2: return "two"
        case 3: return "three"
        case 4: return "four"
        case 5: return "five"
        case 6: return "six"
        case 7: return "seven"
        case 8: return "eight"
        case 9: return "nine"
        case 10: return "ten"
        case 11: return "eleven"
        case 12: return "twelve"
        case 13: return "thirteen"
        case 14: return "fourteen"
        case 15: return "fifteen"
        default: return "\(value)"
        }
    }

    private static func spokenMeasurementLabel(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Measurement" : trimmed
    }

    private static func spokenInlineHint(_ hint: String?) -> String? {
        guard let hint else { return nil }
        let stripped = hint
            .replacingOccurrences(of: "//", with: "")
            .replacingOccurrences(of: "—", with: ":")
            .replacingOccurrences(of: "–", with: ":")
            .replacingOccurrences(of: "·", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }

        let collapsed = stripped
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let parts = collapsed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 {
            let subject = sentenceCase(String(parts[0]))
            let detail = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return "\(subject): \(detail)"
        }
        return sentenceCase(collapsed)
    }

    private static func sentenceCase(_ value: String) -> String {
        let lowercased = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let first = lowercased.first else { return lowercased }
        return String(first).uppercased() + String(lowercased.dropFirst())
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
