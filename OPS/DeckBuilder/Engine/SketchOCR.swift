// OPS/OPS/DeckBuilder/Engine/SketchOCR.swift

import Foundation
import Vision

struct SketchOCR {

    // MARK: - Main Entry Point

    /// Recognize handwritten text from a sketch image using Apple Vision OCR.
    /// Returns classified text blocks with image-coordinate bounding boxes.
    static func recognize(image: CGImage) async -> [RecognizedText] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else {
            return []
        }

        let imageSize = CGSize(width: image.width, height: image.height)
        var results: [RecognizedText] = []

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }

            let text = candidate.string
            let confidence = candidate.confidence

            // Vision coordinates: normalized 0-1, origin bottom-left.
            // Convert to image coordinates: origin top-left, pixel units.
            let visionBox = observation.boundingBox
            let imageBox = CGRect(
                x: visionBox.origin.x * CGFloat(image.width),
                y: (1.0 - visionBox.origin.y - visionBox.height) * CGFloat(image.height),
                width: visionBox.width * CGFloat(image.width),
                height: visionBox.height * CGFloat(image.height)
            )

            let classification = classifyText(text, boundingBox: imageBox, imageSize: imageSize)

            results.append(RecognizedText(
                text: text,
                boundingBox: imageBox,
                confidence: confidence,
                classification: classification
            ))
        }

        return results
    }

    // MARK: - Text Classification

    /// Classify a recognized text string based on its content and position in the image.
    ///
    /// Classification rules are applied in order — first match wins:
    /// 1. Dimension (feet, inches, meters, NxN, plain number)
    /// 2. Stair count ("13 treads", "4 steps")
    /// 3. Client name (top 20% of image, mostly alphabetic, has capitals)
    /// 4. Label (known structural terms like "deck", "stairs", "house")
    /// 5. Unknown
    static func classifyText(_ text: String, boundingBox: CGRect, imageSize: CGSize) -> TextClassification {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // 1. Dimension detection
        if let dimensionResult = classifyAsDimension(trimmed) {
            return dimensionResult
        }

        // 2. Stair count detection
        if let stairResult = classifyAsStairCount(trimmed) {
            return stairResult
        }

        // 3. Client name detection (position-dependent)
        if let clientResult = classifyAsClientName(trimmed, boundingBox: boundingBox, imageSize: imageSize) {
            return clientResult
        }

        // 4. Label detection
        if let labelResult = classifyAsLabel(trimmed) {
            return labelResult
        }

        // 5. Unknown
        return .unknown
    }

    // MARK: - Classification Helpers

    /// Attempt to classify text as a dimension measurement.
    /// Matches feet markers, inch markers, unit words, NxN format, and plain numbers.
    private static func classifyAsDimension(_ text: String) -> TextClassification? {
        // Normalize Unicode prime/double-prime to ASCII equivalents for regex and parsing
        let normalized = text
            .replacingOccurrences(of: "\u{2032}", with: "'")   // ′ → '
            .replacingOccurrences(of: "\u{2033}", with: "\"")  // ″ → "

        // Feet marker: 24', 24.5'
        let feetPattern = #"\d+\.?\d*\s*'"#
        // Inches marker: 6", 6.5"
        let inchesPattern = #"\d+\.?\d*\s*""#
        // Unit words: 24ft, 7.5m, 150cm, 24 feet
        let unitWordsPattern = #"\d+\.?\d*\s*(ft|feet|m|cm)"#
        // NxN format: 24x16, 24X16, 24×16
        let crossPattern = #"\d+\s*[xX\u{00D7}]\s*\d+"#
        // Plain number with no alphabetic characters
        let plainNumberPattern = #"^\d+\.?\d*$"#

        let isDimension =
            matches(normalized, pattern: feetPattern) ||
            matches(normalized, pattern: inchesPattern) ||
            matches(normalized, pattern: unitWordsPattern) ||
            matches(normalized, pattern: crossPattern) ||
            matches(normalized, pattern: plainNumberPattern)

        guard isDimension else { return nil }

        // Determine measurement system based on unit markers
        let isMetric = normalized.range(
            of: #"\d+\.?\d*\s*(m|cm)\b"#,
            options: .regularExpression,
            range: normalized.startIndex..<normalized.endIndex
        ) != nil

        let system: MeasurementSystem = isMetric ? .metric : .imperial

        // For NxN format, parse each side separately
        if let crossRange = normalized.range(of: #"(\d+)\s*[xX\u{00D7}]\s*(\d+)"#, options: .regularExpression) {
            let crossText = String(normalized[crossRange])
            let parts = crossText.components(separatedBy: CharacterSet(charactersIn: "xX\u{00D7}"))
            if parts.count == 2,
               let first = DimensionEngine.parseToInches(parts[0].trimmingCharacters(in: .whitespaces), system: .imperial),
               let second = DimensionEngine.parseToInches(parts[1].trimmingCharacters(in: .whitespaces), system: .imperial) {
                // Use the larger dimension as the primary value
                return .dimension(inches: max(first, second))
            }
        }

        // Standard parse
        if let inches = DimensionEngine.parseToInches(normalized, system: system) {
            return .dimension(inches: inches)
        }

        return nil
    }

    /// Attempt to classify text as a stair/tread/riser count.
    private static func classifyAsStairCount(_ text: String) -> TextClassification? {
        let pattern = #"(\d+)\s*(tread|step|riser)s?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange) else {
            return nil
        }

        guard match.numberOfRanges >= 2,
              let countRange = Range(match.range(at: 1), in: text),
              let count = Int(text[countRange]) else {
            return nil
        }

        return .stairCount(count: count)
    }

    /// Attempt to classify text as a client name based on content and position.
    /// Must be in the top 20% of the image, mostly alphabetic, have at least one capital,
    /// and be at least 2 characters.
    private static func classifyAsClientName(
        _ text: String,
        boundingBox: CGRect,
        imageSize: CGSize
    ) -> TextClassification? {
        // Must be in the top 20% of the image
        guard boundingBox.origin.y < imageSize.height * 0.20 else { return nil }

        // Must be at least 2 characters
        guard text.count >= 2 else { return nil }

        // Must have at least one capital letter
        guard text.contains(where: { $0.isUppercase }) else { return nil }

        // Must be mostly alphabetic (>70% alpha characters, counting spaces as non-alpha)
        let alphaCount = text.filter { $0.isLetter }.count
        let totalCount = text.count
        guard totalCount > 0 else { return nil }
        let alphaRatio = Double(alphaCount) / Double(totalCount)
        guard alphaRatio > 0.70 else { return nil }

        return .clientName(name: text.trimmingCharacters(in: .whitespaces))
    }

    /// Attempt to classify text as a known structural label.
    private static func classifyAsLabel(_ text: String) -> TextClassification? {
        let knownLabels: Set<String> = [
            "stairs", "stair", "deck", "house", "railing", "rail",
            "porch", "landing", "pool", "fence", "gate", "door",
            "window", "wall"
        ]

        let lowered = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard knownLabels.contains(lowered) else { return nil }

        return .label(text: lowered)
    }

    // MARK: - Regex Utility

    /// Check if a string contains a match for the given regex pattern.
    private static func matches(_ string: String, pattern: String) -> Bool {
        return string.range(
            of: pattern,
            options: .regularExpression,
            range: string.startIndex..<string.endIndex
        ) != nil
    }
}
