//
//  SiteVisitLeadSearchAutofill.swift
//  OPS
//
//  Extracts quick-start lead fields from the site-visit lead search box.
//

import Foundation

struct SiteVisitLeadSearchAutofill: Equatable {
    var contactName: String?
    var phone: String?
    var email: String?
    var address: String?

    static let empty = SiteVisitLeadSearchAutofill()

    static func make(from rawValue: String) -> SiteVisitLeadSearchAutofill {
        let raw = rawValue.normalizedSearchAutofillWhitespace
        guard !raw.isEmpty else { return .empty }

        var working = raw
        let email = firstMatch(
            in: working,
            pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            options: [.caseInsensitive]
        )
        if let email {
            working = working.replacingOccurrences(of: email, with: " ")
        }

        let phone = phoneMatch(in: working)
        if let phone {
            working = working.replacingOccurrences(of: phone, with: " ")
        }

        working = working.normalizedSearchAutofillWhitespace

        let address = addressMatch(in: working)
        if let address {
            working = working.replacingOccurrences(of: address, with: " ")
        }

        let contactName = working.normalizedSearchAutofillWhitespace.nilIfBlank

        return SiteVisitLeadSearchAutofill(
            contactName: contactName,
            phone: phone,
            email: email,
            address: address
        )
    }

    private static func phoneMatch(in value: String) -> String? {
        let candidates = matches(
            in: value,
            pattern: #"(?:\+?1[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?)\d{3}[\s.-]?\d{4}"#
        )
        return candidates.first { candidate in
            candidate.filter(\.isNumber).count >= 10
        }
    }

    private static func addressMatch(in value: String) -> String? {
        firstMatch(
            in: value,
            pattern: #"\b\d{1,6}\s+[A-Z0-9][A-Z0-9\s.'#-]*\b(?:street|st|avenue|ave|road|rd|drive|dr|lane|ln|court|ct|way|boulevard|blvd|crescent|cres|terrace|ter|place|pl)\b\.?"#,
            options: [.caseInsensitive]
        )?.normalizedSearchAutofillWhitespace
    }

    private static func firstMatch(
        in value: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        matches(in: value, pattern: pattern, options: options).first
    }

    private static func matches(
        in value: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { result in
            guard let matchRange = Range(result.range, in: value) else { return nil }
            return String(value[matchRange]).normalizedSearchAutofillWhitespace
        }
    }
}

private extension String {
    var normalizedSearchAutofillWhitespace: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
