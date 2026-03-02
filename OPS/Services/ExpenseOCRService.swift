//
//  ExpenseOCRService.swift
//  OPS
//
//  On-device receipt OCR using Apple Vision framework.
//  Protocol-based for future swappability (e.g. Veryfi SDK).
//

import UIKit
import Vision

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

    func extractData(from image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        let observations = try await recognizeText(in: cgImage)
        let lines = observations
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
            .compactMap { observation -> (String, Float)? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return (candidate.string, candidate.confidence)
            }

        let rawText = lines.map { $0.0 }.joined(separator: "\n")
        return ReceiptParser.parse(lines: lines, rawText: rawText)
    }

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
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

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

    // Total keywords
    private static let totalKeywords = ["TOTAL", "AMOUNT DUE", "BALANCE DUE", "GRAND TOTAL", "AMOUNT", "BALANCE"]
    private static let subtotalKeywords = ["SUBTOTAL", "SUB-TOTAL", "SUB TOTAL"]
    private static let taxKeywords = ["TAX", "GST", "HST", "SALES TAX", "VAT"]

    // Payment method keywords
    private static let cardKeywords = ["VISA", "MASTERCARD", "AMEX", "AMERICAN EXPRESS", "DISCOVER", "DEBIT"]
    private static let cashKeywords = ["CASH", "CHANGE DUE"]

    static func parse(lines: [(String, Float)], rawText: String) -> OCRResult {
        let merchantName = extractMerchant(from: lines)
        let date = extractDate(from: rawText)
        let amounts = extractAmounts(from: lines)
        let paymentMethod = extractPaymentMethod(from: rawText)

        let confidences = lines.map { $0.1 }
        let avgConfidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Float(confidences.count)

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

    private static func extractMerchant(from lines: [(String, Float)]) -> (String?, Float) {
        // Merchant is typically the first 1-2 non-empty lines
        // Skip lines that look like dates, amounts, or addresses
        for (text, confidence) in lines.prefix(3) {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // Skip if it looks like a date or amount
            if trimmed.range(of: amountPattern, options: .regularExpression) != nil { continue }
            if trimmed.range(of: "\\d{1,2}/\\d{1,2}/\\d{2,4}", options: .regularExpression) != nil { continue }
            // Skip if mostly numbers (likely an address or phone)
            let digits = trimmed.filter { $0.isNumber }
            if digits.count > trimmed.count / 2 { continue }
            return (trimmed, confidence)
        }
        return (nil, 0)
    }

    private static func extractDate(from text: String) -> (Date?, Float) {
        // Formatters ordered by specificity — try 4-digit year first, then 2-digit, then European
        let formatters: [DateFormatter] = {
            let f1 = DateFormatter(); f1.dateFormat = "MM/dd/yyyy"
            let f2 = DateFormatter(); f2.dateFormat = "M/d/yyyy"
            let f3 = DateFormatter(); f3.dateFormat = "dd/MM/yyyy"   // European: 25/09/2024
            let f4 = DateFormatter(); f4.dateFormat = "MM/dd/yy"
            let f5 = DateFormatter(); f5.dateFormat = "M/d/yy"
            let f6 = DateFormatter(); f6.dateFormat = "dd/MM/yy"    // European: 25/09/24
            let f7 = DateFormatter(); f7.dateFormat = "MM-dd-yyyy"
            let f8 = DateFormatter(); f8.dateFormat = "dd-MM-yyyy"  // European with dash
            let f9 = DateFormatter(); f9.dateFormat = "yyyy-MM-dd"
            let f10 = DateFormatter(); f10.dateFormat = "MMMM d, yyyy"
            let f11 = DateFormatter(); f11.dateFormat = "MMM d, yyyy"
            return [f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11]
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

    private static func extractAmounts(from lines: [(String, Float)]) -> (total: Double?, totalConfidence: Float, subtotal: Double?, tax: Double?) {
        var total: Double? = nil
        var totalConfidence: Float = 0
        var subtotal: Double? = nil
        var tax: Double? = nil
        var allAmounts: [(Double, Float)] = []

        for (text, confidence) in lines {
            let upper = text.uppercased()

            // Extract dollar amount from this line
            guard let amount = extractDollarAmount(from: text) else { continue }
            allAmounts.append((amount, confidence))

            // Check for total keywords
            if totalKeywords.contains(where: { upper.contains($0) }) && !subtotalKeywords.contains(where: { upper.contains($0) }) {
                if total == nil || amount > (total ?? 0) {
                    total = amount
                    totalConfidence = confidence
                }
            }

            // Check for subtotal
            if subtotalKeywords.contains(where: { upper.contains($0) }) {
                subtotal = amount
            }

            // Check for tax
            if taxKeywords.contains(where: { upper.contains($0) }) {
                tax = amount
            }
        }

        // Fallback: if no total found, use the largest amount
        if total == nil, let largest = allAmounts.max(by: { $0.0 < $1.0 }) {
            total = largest.0
            totalConfidence = largest.1 * 0.5 // Lower confidence for guessed total
        }

        return (total, totalConfidence, subtotal, tax)
    }

    private static func extractDollarAmount(from text: String) -> Double? {
        guard let range = text.range(of: amountPattern, options: .regularExpression) else { return nil }
        var match = String(text[range])
        match = match.replacingOccurrences(of: "$", with: "")
        match = match.replacingOccurrences(of: ",", with: "")
        return Double(match)
    }

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
