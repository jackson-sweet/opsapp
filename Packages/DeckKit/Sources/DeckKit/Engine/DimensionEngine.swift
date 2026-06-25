// OPS/OPS/DeckBuilder/Engine/DimensionEngine.swift

import Foundation

public struct DimensionEngine {

    // MARK: - Formatting

    /// Format inches as feet and inches string (e.g., 294 → "24' 6\"")
    public static func formatImperial(_ totalInches: Double) -> String {
        guard totalInches >= 0 else {
            print("[DeckBuilder] formatImperial: negative value \(totalInches), using absolute")
            return formatImperial(abs(totalInches))
        }
        var feet = Int(totalInches) / 12
        let inches = totalInches - Double(feet * 12)

        // Round to nearest 0.5". 11.95" → 12.0" must roll over to the next foot,
        // otherwise we print nonsense like "11' 12\"". Roll BEFORE the < 0.5 check
        // so e.g. 11.99" reaches the rollover branch.
        var roundedInches = (inches * 2).rounded() / 2
        if roundedInches >= 12 {
            feet += 1
            roundedInches = 0
        }

        if roundedInches < 0.5 {
            return "\(feet)'"
        }
        if roundedInches == roundedInches.rounded() {
            return "\(feet)' \(Int(roundedInches))\""
        }
        return String(format: "%d' %.1f\"", feet, roundedInches)
    }

    /// Format centimeters as meters and cm (e.g., 245 → "2.45 m")
    public static func formatMetric(_ totalCm: Double) -> String {
        if totalCm >= 100 {
            return String(format: "%.2f m", totalCm / 100.0)
        }
        return String(format: "%.0f cm", totalCm)
    }

    /// Format a dimension based on the measurement system
    public static func format(_ valueInInches: Double, system: MeasurementSystem) -> String {
        switch system {
        case .imperial:
            return formatImperial(valueInInches)
        case .metric:
            let cm = valueInInches * 2.54
            return formatMetric(cm)
        }
    }

    // MARK: - Area Formatting

    /// Format area in square feet (e.g., 56448 sq inches → "392 sq ft")
    public static func formatAreaImperial(_ sqInches: Double) -> String {
        let sqFeet = sqInches / 144.0
        if sqFeet >= 10 {
            return "\(Int(sqFeet.rounded())) sq ft"
        }
        return String(format: "%.1f sq ft", sqFeet)
    }

    public static func formatArea(_ sqInches: Double, system: MeasurementSystem) -> String {
        switch system {
        case .imperial:
            return formatAreaImperial(sqInches)
        case .metric:
            let sqMeters = sqInches * 0.00064516
            return String(format: "%.1f m²", sqMeters)
        }
    }

    // MARK: - Scale Calculation

    /// Calculate scale factor from one known dimension
    /// - Parameters:
    ///   - canvasLength: Length of the edge in canvas points
    ///   - realWorldInches: Known dimension in inches
    /// - Returns: Scale factor (canvas points per inch)
    public static func calculateScaleFactor(canvasLength: Double, realWorldInches: Double) -> Double? {
        guard canvasLength > 0, realWorldInches > 0 else { return nil }
        return canvasLength / realWorldInches
    }

    /// Auto-fill dimensions for all edges using a scale factor.
    /// Critical for the "first manual dimension establishes scale" flow: every
    /// other edge that was storing a canvas-point length as if it were inches
    /// must be converted now or the UI will show confidently-wrong dimensions.
    /// Manual / laser / AR sources are preserved (they are user-authoritative).
    /// - Parameters:
    ///   - drawingData: The current drawing data (mutated in place)
    ///   - scaleFactor: Canvas points per real-world inch
    /// - Returns: Updated drawing data with dimensions filled
    public static func autoFillDimensions(
        drawingData: DeckDrawingData,
        scaleFactor: Double
    ) -> DeckDrawingData {
        var updated = drawingData
        updated.scaleFactor = scaleFactor

        // Single-level edges
        for i in 0..<updated.edges.count {
            let edge = updated.edges[i]
            guard edge.dimensionSource == .scale || edge.dimension == nil else { continue }
            if let start = updated.vertex(byId: edge.startVertexId),
               let end = updated.vertex(byId: edge.endVertexId) {
                let canvasLength = SnapEngine.distance(start.position, end.position)
                updated.edges[i].dimension = canvasLength / scaleFactor
                updated.edges[i].dimensionSource = .scale
            }
        }

        // Multi-level edges — same rule, just nested.
        for li in 0..<updated.levels.count {
            for ei in 0..<updated.levels[li].edges.count {
                let edge = updated.levels[li].edges[ei]
                guard edge.dimensionSource == .scale || edge.dimension == nil else { continue }
                if let start = updated.levels[li].vertex(byId: edge.startVertexId),
                   let end = updated.levels[li].vertex(byId: edge.endVertexId) {
                    let canvasLength = SnapEngine.distance(start.position, end.position)
                    updated.levels[li].edges[ei].dimension = canvasLength / scaleFactor
                    updated.levels[li].edges[ei].dimensionSource = .scale
                }
            }
        }
        return updated
    }

    // MARK: - Parsing

    /// Parse a dimension string like "24' 6\"", "24.5'", "24", "7.5m" into inches.
    /// Imperial supports:
    ///   feet only: `24'`, `24.5 ft`, `24 feet`
    ///   inches only: `6"`, `6 in`, `6 inches`
    ///   feet+inches: `24' 6"`, `24'6"`, `24-6`, `24 6` (when both apostrophe absent: first=feet, second=inches)
    ///   fractions: `24' 6 1/2"`, `6 1/2"`, `1/2"`
    ///   metric: `7.5m`, `150cm`, `0.9` (defaults cm)
    /// Returns nil only if input is empty or contains no parseable numbers.
    public static func parseToInches(_ input: String, system: MeasurementSystem) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        switch system {
        case .imperial:
            return parseImperialToInches(trimmed)
        case .metric:
            return parseMetricToInches(trimmed)
        }
    }

    /// Normalize smart quotes and word-unit suffixes to a canonical form:
    /// ' for feet, " for inches, word suffixes stripped to symbols.
    ///
    /// Handles every common way a field user types feet/inches:
    ///   U+2018 / U+2019 / U+02BC smart single quotes  → '
    ///   U+201C / U+201D smart double quotes            → "
    ///   "inches" / "inch" / "in"                       → "
    ///   "feet" / "ft"                                  → '
    ///   Prime / double prime U+2032 / U+2033           → ' / "
    public static func normalizeDimensionInput(_ input: String) -> String {
        input
            // Smart / typographic single quotes → '
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
            .replacingOccurrences(of: "\u{2032}", with: "'")  // prime
            // Smart / typographic double quotes → "
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2033}", with: "\"")  // double prime
            // Inch word suffixes → "
            .replacingOccurrences(of: "inches", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "inch", with: "\"", options: .caseInsensitive)
            // "ft" and "feet" come AFTER "inches" so we don't eat the "e" inside "feet" when
            // rewriting "inches". Order matters: longest first.
            .replacingOccurrences(of: "feet", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "ft", with: "'", options: .caseInsensitive)
            // "in" alone (common shorthand). Use a word-boundary regex so we
            // don't eat the "in" inside unrelated tokens (e.g. a stray "min"
            // or contractor's notes appended to a dimension field).
            .replacingOccurrences(
                of: "\\bin\\b",
                with: "\"",
                options: [.regularExpression, .caseInsensitive]
            )
    }

    /// Backwards-compatible shim — callers inside DimensionEngine keep using the
    /// private name. The public `normalizeDimensionInput` is intended for input
    /// fields that want to sanitize as the user types.
    private static func normalizeImperialInput(_ input: String) -> String {
        normalizeDimensionInput(input)
    }

    /// Live-typing sanitizer. Swaps ONLY smart quotes to ASCII `'`/`"`, leaves
    /// word suffixes like "ft"/"in"/"feet"/"inches" alone so the user doesn't
    /// see their text rewritten mid-word. Apply in a TextField's onChange.
    public static func sanitizeQuotesForLiveInput(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
            .replacingOccurrences(of: "\u{2032}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2033}", with: "\"")
    }

    /// Tokenizer-based imperial parser. Walks the string left-to-right, merging mixed
    /// numbers (`W N/D`) eagerly so each pending entry is a single complete value.
    ///
    /// Handles every field-contractor format I've seen:
    ///   `24'` · `6"` · `24' 6"` · `24'6"` · `4 1/2'` (mixed feet) · `6 1/2"` (mixed inches) ·
    ///   `24' 6 1/2"` · `1/2"` · `24` (lone → feet) · `24 6` (→ 24' 6") · `24-6` · smart quotes.
    private static func parseImperialToInches(_ input: String) -> Double? {
        let normalized = normalizeImperialInput(input)
        let chars = Array(normalized)
        var i = 0
        var totalInches: Double = 0
        var sawAnyNumber = false
        var sawFeetMarker = false  // once a `'` is consumed, unmarked trailing numbers are inches
        var pendingNumbers: [Double] = []

        // Read one number token starting at i. Merges an immediately-following fraction
        // (both bare `N/D` and mixed `W N/D` forms) into a single value. Advances `i`.
        func readNumber() -> Double? {
            guard i < chars.count else { return nil }

            // Read first digit run / decimal
            let wholeStart = i
            var sawDot = false
            var foundDigit = false
            while i < chars.count, chars[i].isNumber || (chars[i] == "." && !sawDot) {
                if chars[i] == "." { sawDot = true }
                if chars[i].isNumber { foundDigit = true }
                i += 1
            }
            guard foundDigit, let whole = Double(String(chars[wholeStart..<i])) else {
                return nil
            }

            // Bare `N/D` form: the digits we just read are the numerator
            // (only valid if the caller sees no whitespace between digits and `/`).
            if i < chars.count, chars[i] == "/" {
                let slashIndex = i
                i += 1
                let denStart = i
                while i < chars.count, chars[i].isNumber { i += 1 }
                if i > denStart, let den = Double(String(chars[denStart..<i])), den > 0 {
                    return whole / den
                }
                // Not a valid fraction — rewind to slash, treat number as whole
                i = slashIndex
                return whole
            }

            // Mixed `W N/D` form: whole, whitespace, numerator, `/`, denominator
            var lookahead = i
            while lookahead < chars.count, chars[lookahead].isWhitespace { lookahead += 1 }
            if lookahead < chars.count, chars[lookahead].isNumber {
                let numStart = lookahead
                while lookahead < chars.count, chars[lookahead].isNumber { lookahead += 1 }
                let numEnd = lookahead
                var afterNum = lookahead
                while afterNum < chars.count, chars[afterNum].isWhitespace { afterNum += 1 }
                if afterNum < chars.count, chars[afterNum] == "/" {
                    afterNum += 1
                    while afterNum < chars.count, chars[afterNum].isWhitespace { afterNum += 1 }
                    let denStart = afterNum
                    while afterNum < chars.count, chars[afterNum].isNumber { afterNum += 1 }
                    if afterNum > denStart,
                       let numerator = Double(String(chars[numStart..<numEnd])),
                       let denom = Double(String(chars[denStart..<afterNum])), denom > 0 {
                        i = afterNum
                        return whole + (numerator / denom)
                    }
                }
            }

            return whole
        }

        while i < chars.count {
            let c = chars[i]

            if c.isWhitespace || c == "-" || c == "," { i += 1; continue }

            if c.isNumber || c == "." {
                if let v = readNumber() {
                    pendingNumbers.append(v)
                    sawAnyNumber = true
                } else {
                    i += 1
                }
                continue
            }

            if c == "'" {
                // Feet marker: the first pending number is feet, any extra tail → inches.
                if let feet = pendingNumbers.first {
                    totalInches += feet * 12.0
                    pendingNumbers.removeFirst()
                }
                // Rare case: leftover pending numbers before a feet marker — treat as inches
                for n in pendingNumbers { totalInches += n }
                pendingNumbers.removeAll()
                sawFeetMarker = true
                i += 1
                continue
            }

            if c == "\"" {
                // Inches marker: every pending number is inches (already merged mixed numbers)
                for n in pendingNumbers { totalInches += n }
                pendingNumbers.removeAll()
                i += 1
                continue
            }

            i += 1 // unknown character — skip defensively
        }

        // Resolve trailing unmarked numbers
        if !pendingNumbers.isEmpty {
            if sawFeetMarker {
                // Already consumed a `'` — trailing numbers are inches ("8' 6" → 8ft + 6in).
                // Covers the common "user forgot the quote mark" case.
                for n in pendingNumbers { totalInches += n }
            } else {
                switch pendingNumbers.count {
                case 1:
                    // Lone number → feet (contractor shorthand: "12" = 12 feet)
                    totalInches += pendingNumbers[0] * 12.0
                case 2:
                    // Two numbers with no marker → feet + inches: "12 6" = 12' 6"
                    totalInches += pendingNumbers[0] * 12.0 + pendingNumbers[1]
                default:
                    totalInches += pendingNumbers[0] * 12.0
                    for n in pendingNumbers.dropFirst() { totalInches += n }
                }
            }
        }

        guard sawAnyNumber else { return nil }
        return totalInches >= 0 ? totalInches : nil
    }

    /// Tokenizer-based metric parser. Walks the string left-to-right matching
    /// number tokens against the longest unit suffix at each position (mm > cm > m).
    /// Sums every (number, unit) pair into total centimeters, then converts to inches.
    ///
    /// Handles every field-contractor format I've seen:
    ///   `7.5m` · `150cm` · `100mm` · `2m 50cm` (compound) · `2.5m 30cm 5mm` ·
    ///   `150` (lone → cm fallback) · whitespace / dash / comma separators.
    ///
    /// Previous implementation had two breaking bugs:
    /// - `100mm` matched `.contains("m")` and was treated as 100 metres (off by 100×).
    /// - Compound entries (`2m 50cm`) cleaned to `"2 50"` which Double can't parse,
    ///   so the field returned nil and the user's input was silently rejected.
    private static func parseMetricToInches(_ input: String) -> Double? {
        let chars = Array(input.lowercased())
        var i = 0
        var totalCm: Double = 0
        var sawAnyNumber = false
        var pendingValue: Double?

        // Read one numeric token starting at i; advances `i` past the digits.
        func readNumber() -> Double? {
            let start = i
            var sawDot = false
            var foundDigit = false
            while i < chars.count, chars[i].isNumber || (chars[i] == "." && !sawDot) {
                if chars[i] == "." { sawDot = true }
                if chars[i].isNumber { foundDigit = true }
                i += 1
            }
            guard foundDigit, let v = Double(String(chars[start..<i])) else { return nil }
            return v
        }

        // Flush a pending number using the supplied unit multiplier (cm per unit).
        func consume(unitToCm: Double) {
            if let v = pendingValue {
                totalCm += v * unitToCm
                pendingValue = nil
            }
        }

        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace || c == "-" || c == "," {
                i += 1; continue
            }
            if c.isNumber || c == "." {
                if let v = readNumber() {
                    // Two numbers in a row with no unit between them — flush
                    // the previous one as cm (default), then queue the new value.
                    if let prev = pendingValue {
                        totalCm += prev
                    }
                    pendingValue = v
                    sawAnyNumber = true
                } else {
                    i += 1
                }
                continue
            }
            // Unit detection — longest suffix first so `mm` doesn't get eaten by `m`.
            if i + 1 < chars.count, chars[i] == "m", chars[i + 1] == "m" {
                consume(unitToCm: 0.1)   // mm → cm
                i += 2
                continue
            }
            if i + 1 < chars.count, chars[i] == "c", chars[i + 1] == "m" {
                consume(unitToCm: 1.0)   // cm
                i += 2
                continue
            }
            if c == "m" {
                consume(unitToCm: 100.0) // m → cm
                i += 1
                continue
            }
            // Unknown character — skip defensively
            i += 1
        }

        // Trailing number with no unit → default to cm (matches the contractor
        // shorthand the previous parser used for raw numeric input).
        if let v = pendingValue {
            totalCm += v
        }

        guard sawAnyNumber else { return nil }
        return totalCm / 2.54
    }

    // MARK: - Post Calculation

    /// Calculate number of posts for an edge with railing
    /// - Parameters:
    ///   - edgeLengthInches: Total edge length in inches
    ///   - maxSpacing: Maximum spacing between posts in inches
    /// - Returns: Number of posts (including corner posts)
    public static func postCount(edgeLengthInches: Double, maxSpacing: Double) -> Int {
        guard edgeLengthInches > 0, maxSpacing > 0 else { return 0 }
        return Int(ceil(edgeLengthInches / maxSpacing)) + 1
    }
}
