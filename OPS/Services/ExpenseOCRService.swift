//
//  ExpenseOCRService.swift
//  OPS
//
//  On-device receipt OCR using Apple Vision framework.
//  Protocol-based for future swappability (e.g. Veryfi SDK).
//
//  Pipeline: Image Preprocessing → Vision Recognition → Spatial-Aware Parsing
//

import UIKit
import Vision
import CoreImage

// MARK: - Recognized Line

/// A single line of text recognized by Vision, enriched with spatial metadata.
struct RecognizedLine {
    let text: String
    let confidence: Float
    /// Vision normalized coordinates — origin at bottom-left, values 0–1.
    /// y=0 is the BOTTOM of the image (bottom of receipt), y=1 is the TOP.
    let boundingBox: CGRect

    /// Vertical center of this line, normalized 0–1 (0 = bottom, 1 = top).
    var verticalPosition: Float {
        Float(boundingBox.origin.y + boundingBox.size.height / 2)
    }

    /// Whether this line is in the bottom portion of the receipt (likely totals area).
    var isInBottomRegion: Bool {
        verticalPosition < 0.35
    }

    /// Whether this line is in the top portion of the receipt (likely merchant/header area).
    var isInTopRegion: Bool {
        verticalPosition > 0.70
    }
}

// MARK: - OCR Result

struct OCRResult {
    let merchantName: String?
    let merchantNameConfidence: Float
    let date: Date?
    let dateConfidence: Float
    let total: Double?
    let totalConfidence: Float
    let subtotal: Double?
    let taxAmount: Double?
    let paymentMethod: String?
    let rawText: String
    let overallConfidence: Float

    var rawDataDict: [String: String] {
        var dict: [String: String] = ["raw_text": rawText]
        if let m = merchantName { dict["merchant_name"] = m }
        if let d = date { dict["date"] = ISO8601DateFormatter().string(from: d) }
        if let t = total { dict["total"] = String(format: "%.2f", t) }
        if let s = subtotal { dict["subtotal"] = String(format: "%.2f", s) }
        if let tx = taxAmount { dict["tax_amount"] = String(format: "%.2f", tx) }
        if let p = paymentMethod { dict["payment_method"] = p }
        return dict
    }
}

// MARK: - Protocol

protocol ExpenseOCRServiceProtocol {
    func extractData(from image: UIImage) async throws -> OCRResult
    var isAvailable: Bool { get }
}

// MARK: - Apple Vision Implementation

class AppleVisionOCRService: ExpenseOCRServiceProtocol {

    var isAvailable: Bool { true }

    /// Receipt-specific vocabulary to improve Vision's recognition accuracy.
    /// Passed to `customWords` so Vision prefers these over visually similar alternatives.
    private static let receiptVocabulary: [String] = [
        // Totals
        "SUBTOTAL", "SUB-TOTAL", "SUB TOTAL",
        "TOTAL", "GRAND TOTAL", "TOTAL DUE", "AMOUNT DUE", "BALANCE DUE", "PAYMENT DUE",
        "MERCHANDISE TOTAL", "FOOD TOTAL", "ITEM TOTAL",
        // Tax
        "TAX", "GST", "HST", "PST", "QST", "SALES TAX", "VAT", "LEVY",
        // Payment
        "VISA", "MASTERCARD", "AMEX", "AMERICAN EXPRESS", "DISCOVER", "DEBIT",
        "CASH", "CHANGE DUE", "TENDERED",
        // Other receipt terms
        "TIP", "GRATUITY", "DONATION", "SURCHARGE",
        "AUTH", "APPROVAL", "TRANSACTION",
        "QUANTITY", "QTY", "PRICE", "EACH",
        "RECEIPT", "INVOICE", "ORDER"
    ]

    /// Reusable Core Image context for preprocessing (avoids re-creation per scan).
    private let ciContext = CIContext()

    func extractData(from image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        // Step 1: Preprocess image for optimal OCR.
        //
        // VNDocumentCameraViewController already perspective-corrects, deskews,
        // and enhances contrast on the scanned page — running aggressive filters
        // on top can blow out faded thermal print and degrade Vision's accuracy.
        // We apply only a light grayscale + sharpen pass which empirically helps
        // worn receipts without hurting clean ones.
        let preprocessed = preprocessImage(cgImage)
        print("[OCR] Image preprocessed: \(cgImage.width)x\(cgImage.height) → \(preprocessed.width)x\(preprocessed.height)")

        // Step 2: Recognize text with tuned request
        let observations = try await recognizeText(in: preprocessed)

        // Step 3: Build recognized lines with spatial metadata
        let lines: [RecognizedLine] = observations
            .compactMap { observation -> RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return RecognizedLine(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox
                )
            }
            // Sort top-to-bottom (high Y = top of receipt → first in reading order)
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }

        print("[OCR] Recognized \(lines.count) lines:")
        for (i, line) in lines.enumerated() {
            print("[OCR]   [\(i)] y=\(String(format: "%.3f", line.verticalPosition)) conf=\(String(format: "%.2f", line.confidence)): \"\(line.text)\"")
        }

        let rawText = lines.map { $0.text }.joined(separator: "\n")
        return ReceiptParser.parse(lines: lines, rawText: rawText)
    }

    // MARK: - Image Preprocessing

    /// Applies a light CIFilter pass to enhance receipt text for OCR.
    ///
    /// VisionKit's document scanner already does heavy lifting (perspective
    /// correction, deskew, auto-contrast). Layering aggressive contrast +
    /// exposure + brightness on top of that empirically degrades accuracy on
    /// faded thermal print — bright stretches get pushed out of range and
    /// finer characters disappear. We keep only a small contrast bump and
    /// edge sharpen, which helped library-imported (non-VisionKit) photos
    /// without hurting clean scans.
    ///
    /// Pipeline: Grayscale (no brightness lift) → Mild contrast → Sharpen
    private func preprocessImage(_ cgImage: CGImage) -> CGImage {
        var ciImage = CIImage(cgImage: cgImage)

        // 1. Grayscale + mild contrast.
        //    Removes color noise (colored receipt paper, tinted lighting).
        //    Contrast bump is intentionally smaller (1.10 vs 1.20) and we no
        //    longer push brightness — both pushed faded thermal text outside
        //    the recognizer's preferred range on real receipts.
        if let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setValue(ciImage, forKey: kCIInputImageKey)
            colorControls.setValue(0.0, forKey: kCIInputSaturationKey)
            colorControls.setValue(1.10, forKey: kCIInputContrastKey)
            colorControls.setValue(0.0, forKey: kCIInputBrightnessKey)
            if let output = colorControls.outputImage {
                ciImage = output
            }
        }

        // 2. Sharpen luminance — enhances text edges.
        //    Critical for slightly blurry phone photos taken at arm's length.
        if let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(ciImage, forKey: kCIInputImageKey)
            sharpen.setValue(0.45, forKey: kCIInputSharpnessKey)
            if let output = sharpen.outputImage {
                ciImage = output
            }
        }

        // (Removed) Exposure adjust — when stacked on VisionKit's auto-enhanced
        // output it tended to clip dark serif glyphs and merge adjacent line
        // items on dot-matrix print. Vision handles natural lighting variance.

        // Render back to CGImage
        if let outputCG = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            return outputCG
        }
        return cgImage
    }

    // MARK: - Text Recognition

    private func recognizeText(in image: CGImage) async throws -> [VNRecognizedTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: observations)
            }

            // Pin to the newest text-recognition revision the host iOS supports.
            // Higher revisions consistently outperform older ones on faded
            // thermal print and tightly spaced receipt rows. We deliberately
            // do NOT hardcode a revision constant so the app picks up future
            // model bumps automatically as users upgrade iOS.
            if let latest = type(of: request).supportedRevisions.max() {
                request.revision = latest
            }

            // Accuracy: use the most accurate (slower) recognition level.
            request.recognitionLevel = .accurate

            // Language correction: improves word recognition using language model.
            request.usesLanguageCorrection = true

            // Language: restrict to English so the recognizer doesn't waste
            // capacity guessing alternate scripts. Auto-detect adds latency
            // for receipts that are reliably one of en-US/en-CA/en-GB.
            request.recognitionLanguages = ["en-US"]
            request.automaticallyDetectsLanguage = false

            // Custom vocabulary: receipt-specific terms Vision should prefer.
            request.customWords = Self.receiptVocabulary

            // Minimum text height — lowered from 0.01 to 0.006. Real receipts
            // pack 40+ lines into a tall narrow image; line items can be 0.7%
            // of image height. The previous 1% threshold dropped legitimate
            // line items without removing all barcode noise. The parser
            // already filters lines that look like serial/auth numbers, so
            // letting smaller text through nets more useful tokens than it
            // adds noise.
            request.minimumTextHeight = 0.006

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Receipt Parser

struct ReceiptParser {
    // Date patterns
    private static let datePatterns: [String] = [
        "\\d{1,2}/\\d{1,2}/\\d{2,4}",       // MM/DD/YYYY or M/D/YY
        "\\d{1,2}-\\d{1,2}-\\d{2,4}",        // MM-DD-YYYY
        "\\d{4}-\\d{2}-\\d{2}",              // YYYY-MM-DD
        "[A-Za-z]{3,9}\\s+\\d{1,2},?\\s+\\d{4}", // Month DD, YYYY
    ]

    // Amount patterns
    private static let amountPattern = "\\$?\\d{1,6}[,.]\\d{2}"

    // Total keywords — specific phrases that indicate the final amount owed
    private static let totalKeywords = ["GRAND TOTAL", "TOTAL DUE", "AMOUNT DUE", "BALANCE DUE", "PAYMENT DUE", "TOTAL"]
    private static let subtotalKeywords = ["SUBTOTAL", "SUB-TOTAL", "SUB TOTAL", "MERCHANDISE TOTAL", "FOOD TOTAL", "ITEM TOTAL"]
    private static let taxKeywords = ["TAX", "GST", "HST", "PST", "QST", "SALES TAX", "VAT", "LEVY"]
    // Lines containing these should never be treated as the total
    private static let totalExclusionKeywords = ["TIP", "GRATUITY", "DONATION", "SURCHARGE", "CASHBACK", "CASH BACK", "CHANGE DUE", "CHANGE", "TENDERED", "CARD #", "CARD NUM", "AUTH"]

    // Payment method keywords
    private static let cardKeywords = ["VISA", "MASTERCARD", "AMEX", "AMERICAN EXPRESS", "DISCOVER", "DEBIT"]
    private static let cashKeywords = ["CASH", "CHANGE DUE"]

    static func parse(lines: [RecognizedLine], rawText: String) -> OCRResult {
        print("[OCR_PARSE] ── Receipt parsing started (\(lines.count) lines) ──")

        let merchantName = extractMerchant(from: lines)
        let date = extractDate(from: rawText)
        let amounts = extractAmounts(from: lines)
        let paymentMethod = extractPaymentMethod(from: rawText)

        let confidences = lines.map { $0.confidence }
        let avgConfidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Float(confidences.count)

        print("[OCR_PARSE] ── Results ──")
        print("[OCR_PARSE]   Merchant: \(merchantName.0 ?? "nil")")
        print("[OCR_PARSE]   Date: \(date.0?.description ?? "nil")")
        print("[OCR_PARSE]   Total: \(amounts.total.map { String(format: "$%.2f", $0) } ?? "nil") (confidence: \(String(format: "%.0f%%", amounts.totalConfidence * 100)))")
        print("[OCR_PARSE]   Subtotal: \(amounts.subtotal.map { String(format: "$%.2f", $0) } ?? "nil")")
        print("[OCR_PARSE]   Tax: \(amounts.tax.map { String(format: "$%.2f", $0) } ?? "nil")")
        print("[OCR_PARSE]   Payment: \(paymentMethod ?? "nil")")
        print("[OCR_PARSE] ── End ──")

        return OCRResult(
            merchantName: merchantName.0,
            merchantNameConfidence: merchantName.1,
            date: date.0,
            dateConfidence: date.1,
            total: amounts.total,
            totalConfidence: amounts.totalConfidence,
            subtotal: amounts.subtotal,
            taxAmount: amounts.tax,
            paymentMethod: paymentMethod,
            rawText: rawText,
            overallConfidence: avgConfidence
        )
    }

    // MARK: - Merchant Extraction (spatial-aware)

    private static func extractMerchant(from lines: [RecognizedLine]) -> (String?, Float) {
        // Merchant name is typically in the TOP region of the receipt.
        // Strategy: look at the top lines, prefer those spatially in the top region,
        // skip lines that look like dates, amounts, addresses, or URLs.

        // First pass: prefer lines that are spatially in the top region
        let topCandidates = lines.prefix(5).filter { $0.isInTopRegion }
        let candidates = topCandidates.isEmpty ? Array(lines.prefix(3)) : Array(topCandidates.prefix(3))

        for line in candidates {
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.count < 2 { continue }

            // Skip if it looks like a date or amount
            if trimmed.range(of: amountPattern, options: .regularExpression) != nil { continue }
            if trimmed.range(of: "\\d{1,2}/\\d{1,2}/\\d{2,4}", options: .regularExpression) != nil { continue }

            // Skip if mostly numbers (likely an address, phone, or store number)
            let digits = trimmed.filter { $0.isNumber }
            if digits.count > trimmed.count / 2 { continue }

            // Skip common non-merchant header lines
            let upper = trimmed.uppercased()
            if upper.hasPrefix("TEL") || upper.hasPrefix("PHONE") || upper.hasPrefix("FAX") { continue }
            if upper.contains("WWW.") || upper.contains(".COM") || upper.contains(".CA") || upper.contains(".NET") { continue }

            print("[OCR_PARSE] Merchant candidate: \"\(trimmed)\" at y=\(String(format: "%.3f", line.verticalPosition))")
            return (trimmed, line.confidence)
        }
        return (nil, 0)
    }

    // MARK: - Date Extraction

    /// True when the user's current locale formats dates day-first (e.g. en-CA,
    /// en-GB, most of Europe). Used to disambiguate numeric dates like
    /// `03/05/2026` — in en-US that's March 5; in en-CA/en-GB it's May 3.
    private static func preferDayFirstForCurrentLocale() -> Bool {
        let template = "MMddy"
        guard let pattern = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: Locale.current) else {
            return false
        }
        // The first `M` or `d` token wins. If `d` appears before `M`, the
        // locale formats day-first.
        let firstD = pattern.firstIndex(of: "d")
        let firstM = pattern.firstIndex(of: "M")
        switch (firstD, firstM) {
        case let (d?, m?): return d < m
        case (.some, nil): return true
        default:           return false
        }
    }

    private static func extractDate(from text: String) -> (Date?, Float) {
        // Formatters ordered by likelihood for the user's locale. The same
        // numeric date — say 03/05/2026 — parses as March 5 in US-style
        // locales and May 3 in day-first locales (CA-EN, en-GB, most of EU).
        // Trying the locale's preferred ordering first prevents systematically
        // mis-reading non-US receipts as US dates.
        let formatters: [DateFormatter] = {
            let dayFirst: [DateFormatter] = {
                let a = DateFormatter(); a.dateFormat = "dd/MM/yyyy"
                let b = DateFormatter(); b.dateFormat = "d/M/yyyy"
                let c = DateFormatter(); c.dateFormat = "dd/MM/yy"
                let d = DateFormatter(); d.dateFormat = "d/M/yy"
                let e = DateFormatter(); e.dateFormat = "dd-MM-yyyy"
                return [a, b, c, d, e]
            }()
            let monthFirst: [DateFormatter] = {
                let a = DateFormatter(); a.dateFormat = "MM/dd/yyyy"
                let b = DateFormatter(); b.dateFormat = "M/d/yyyy"
                let c = DateFormatter(); c.dateFormat = "MM/dd/yy"
                let d = DateFormatter(); d.dateFormat = "M/d/yy"
                let e = DateFormatter(); e.dateFormat = "MM-dd-yyyy"
                return [a, b, c, d, e]
            }()
            let unambiguous: [DateFormatter] = {
                let a = DateFormatter(); a.dateFormat = "yyyy-MM-dd"
                let b = DateFormatter(); b.dateFormat = "MMMM d, yyyy"
                let c = DateFormatter(); c.dateFormat = "MMM d, yyyy"
                return [a, b, c]
            }()

            let ordered = preferDayFirstForCurrentLocale()
                ? dayFirst + monthFirst
                : monthFirst + dayFirst
            return ordered + unambiguous
        }()

        let calendar = Calendar.current
        let now = Date()
        let fiveYearsAgo = calendar.date(byAdding: .year, value: -5, to: now) ?? now

        for pattern in datePatterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let match = String(text[range])
                for formatter in formatters {
                    guard var date = formatter.date(from: match) else { continue }

                    // Fix 2-digit year misinterpretation: year < 100 → add 2000
                    let year = calendar.component(.year, from: date)
                    if year < 100 {
                        date = calendar.date(byAdding: .year, value: 2000, to: date) ?? date
                    }

                    // Reject dates outside valid range (5 years ago to today)
                    if date < fiveYearsAgo || date > now { continue }

                    return (date, 0.8)
                }
            }
        }
        return (nil, 0)
    }

    // MARK: - Amount Extraction (spatial-aware)

    private static func extractAmounts(from lines: [RecognizedLine]) -> (total: Double?, totalConfidence: Float, subtotal: Double?, tax: Double?) {

        /// A candidate total found on the receipt, scored by both OCR confidence
        /// and spatial position for disambiguation when multiple "TOTAL" lines exist.
        struct TotalCandidate {
            let amount: Double
            let ocrConfidence: Float
            let verticalPosition: Float  // 0 = bottom, 1 = top
            let keywordMatch: String
            let lineText: String

            /// Spatial score: totals at the bottom of the receipt score higher.
            /// On a real receipt, the final total is almost always in the bottom 25-35%.
            var spatialScore: Float {
                if verticalPosition < 0.25 { return 1.0 }   // Bottom quarter — strongest signal
                if verticalPosition < 0.40 { return 0.8 }   // Lower-middle
                if verticalPosition < 0.55 { return 0.5 }   // Middle — could be section total
                return 0.2                                     // Upper half — likely dept/section total
            }

            /// Combined score factoring in OCR confidence and spatial position.
            /// Spatial position is weighted more heavily (60%) because it's the strongest
            /// disambiguation signal when multiple total lines exist.
            var combinedScore: Float {
                ocrConfidence * 0.4 + spatialScore * 0.6
            }
        }

        var totalCandidates: [TotalCandidate] = []
        var subtotal: Double? = nil
        var subtotalPosition: Float = 1.0
        var taxAccumulated: Double = 0
        var taxFound = false
        var allAmounts: [(amount: Double, confidence: Float, verticalPosition: Float)] = []

        for line in lines {
            let upper = line.text.uppercased()

            // Extract dollar amount from this line
            guard let amount = extractDollarAmount(from: line.text) else { continue }

            let isTaxLine = taxKeywords.contains(where: { upper.contains($0) })
            let isSubtotalLine = subtotalKeywords.contains(where: { upper.contains($0) })
            let isExcluded = totalExclusionKeywords.contains(where: { upper.contains($0) })

            // Check for tax FIRST — accumulate multiple tax lines (GST + PST, etc.)
            if isTaxLine {
                taxAccumulated += amount
                taxFound = true
                print("[OCR_PARSE] Tax line: \"\(line.text)\" → $\(String(format: "%.2f", amount)) at y=\(String(format: "%.3f", line.verticalPosition)) (running: $\(String(format: "%.2f", taxAccumulated)))")
                continue
            }

            // Check for subtotal — prefer the lowest one on the receipt if multiple exist
            if isSubtotalLine {
                if subtotal == nil || line.verticalPosition < subtotalPosition {
                    subtotal = amount
                    subtotalPosition = line.verticalPosition
                }
                print("[OCR_PARSE] Subtotal line: \"\(line.text)\" → $\(String(format: "%.2f", amount)) at y=\(String(format: "%.3f", line.verticalPosition))")
                continue
            }

            // Skip excluded lines (tips, change, card numbers, etc.)
            if isExcluded {
                print("[OCR_PARSE] Excluded line: \"\(line.text)\" → $\(String(format: "%.2f", amount))")
                continue
            }

            allAmounts.append((amount, line.confidence, line.verticalPosition))

            // Collect ALL total-keyword candidates for spatial ranking
            for keyword in totalKeywords {
                if upper.contains(keyword) {
                    let candidate = TotalCandidate(
                        amount: amount,
                        ocrConfidence: line.confidence,
                        verticalPosition: line.verticalPosition,
                        keywordMatch: keyword,
                        lineText: line.text
                    )
                    totalCandidates.append(candidate)
                    print("[OCR_PARSE] Total candidate: \"\(line.text)\" → $\(String(format: "%.2f", amount)) keyword=\"\(keyword)\" y=\(String(format: "%.3f", line.verticalPosition)) spatial=\(String(format: "%.2f", candidate.spatialScore)) combined=\(String(format: "%.2f", candidate.combinedScore))")
                    break // Don't double-count the same line for multiple keyword matches
                }
            }
        }

        let tax: Double? = taxFound ? taxAccumulated : nil

        // Select the best total from candidates using spatial + confidence scoring
        var total: Double? = nil
        var totalConfidence: Float = 0

        if !totalCandidates.isEmpty {
            // Sort by combined score (spatial + OCR confidence), highest first
            let ranked = totalCandidates.sorted { $0.combinedScore > $1.combinedScore }
            let best = ranked[0]
            total = best.amount
            totalConfidence = best.ocrConfidence

            print("[OCR_PARSE] Selected total: $\(String(format: "%.2f", best.amount)) from \"\(best.lineText)\" (score=\(String(format: "%.2f", best.combinedScore)))")

            if ranked.count > 1 {
                print("[OCR_PARSE]   Runner-up: $\(String(format: "%.2f", ranked[1].amount)) from \"\(ranked[1].lineText)\" (score=\(String(format: "%.2f", ranked[1].combinedScore)))")
            }
        }

        // Cross-validation: if we have subtotal + tax but no keyword-matched total, compute it
        if total == nil, let sub = subtotal, let tx = tax {
            total = sub + tx
            totalConfidence = 0.7
            print("[OCR_PARSE] Computed total from subtotal + tax: $\(String(format: "%.2f", total!))")
        }

        // Cross-validation: if we have total + tax but no subtotal, derive subtotal
        if subtotal == nil, let tot = total, let tx = tax {
            subtotal = tot - tx
            print("[OCR_PARSE] Derived subtotal from total - tax: $\(String(format: "%.2f", subtotal!))")
        }

        // Sanity check: if total, subtotal, and tax all exist, verify they add up
        if let tot = total, let sub = subtotal, let tx = tax {
            let expected = sub + tx
            let diff = abs(tot - expected)
            if diff > 0.02 {
                print("[OCR_PARSE] Mismatch: total=$\(String(format: "%.2f", tot)) vs subtotal+tax=$\(String(format: "%.2f", expected)) (diff=$\(String(format: "%.2f", diff)))")

                // If another total candidate matches subtotal+tax, prefer it
                if let matchingCandidate = totalCandidates.first(where: { abs($0.amount - expected) < 0.02 }) {
                    print("[OCR_PARSE]   Correcting total to $\(String(format: "%.2f", matchingCandidate.amount)) (matches subtotal+tax)")
                    total = matchingCandidate.amount
                    totalConfidence = matchingCandidate.ocrConfidence
                }
            }
        }

        // Fallback: if no total from keywords, use spatial heuristic.
        // Prefer the largest amount in the bottom region of the receipt.
        if total == nil {
            let bottomAmounts = allAmounts.filter { $0.verticalPosition < 0.40 }
            if let best = bottomAmounts.max(by: { $0.amount < $1.amount }) {
                total = best.amount
                totalConfidence = best.confidence * 0.4 // Low confidence for position-guessed total
                print("[OCR_PARSE] Fallback total (largest in bottom region): $\(String(format: "%.2f", total!)) at y=\(String(format: "%.3f", best.verticalPosition))")
            } else if let largest = allAmounts.max(by: { $0.amount < $1.amount }) {
                total = largest.amount
                totalConfidence = largest.confidence * 0.2 // Very low confidence for blind largest
                print("[OCR_PARSE] Fallback total (largest amount anywhere): $\(String(format: "%.2f", total!))")
            }
        }

        return (total, totalConfidence, subtotal, tax)
    }

    // MARK: - Dollar Amount Extraction

    private static func extractDollarAmount(from text: String) -> Double? {
        guard let range = text.range(of: amountPattern, options: .regularExpression) else { return nil }
        var match = String(text[range])
        match = match.replacingOccurrences(of: "$", with: "")
        match = match.replacingOccurrences(of: ",", with: "")
        return Double(match)
    }

    // MARK: - Payment Method Extraction

    private static func extractPaymentMethod(from text: String) -> String? {
        let upper = text.uppercased()
        for keyword in cardKeywords {
            if upper.contains(keyword) { return "personal_card" }
        }
        for keyword in cashKeywords {
            if upper.contains(keyword) { return "cash" }
        }
        return nil
    }
}

// MARK: - Errors

enum OCRError: Error, LocalizedError {
    case invalidImage
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not process image for text recognition"
        case .recognitionFailed: return "Text recognition failed"
        }
    }
}
