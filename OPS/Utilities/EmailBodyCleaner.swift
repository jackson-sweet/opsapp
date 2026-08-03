//
//  EmailBodyCleaner.swift
//  OPS
//
//  Reduces one email body to the text its sender actually typed — quoted reply
//  chain and trailing signature removed.
//
//  Bug 183f7ec9: a lead's activity feed showed each message's full body, so
//  every reply in a thread carried the entire thread underneath it and the feed
//  read as the same wall of text over and over.
//
//  Ported from the ops-web reference that already governs this in the inbox
//  pipeline — `src/lib/api/services/conversation-state/message-cleaner.ts`
//  (signature anchors) and `src/lib/utils/email-parsing.ts` (QUOTE_MARKERS).
//  Kept deliberately in step with it so the two surfaces do not disagree about
//  what a message says. Cross-message overlap stripping is NOT ported: it needs
//  the prior bodies of the thread, which the feed does not load.
//
//  DESIGN RULE — conservative: a cut must never eat the customer's actual
//  message. Every anchor is a strong trailing delimiter, and if stripping would
//  leave nothing the original is returned untouched. When in doubt, keep it.
//
//  (The server has a `body_text_clean` column, but only ~10% of email activity
//  rows carry one, so it cannot be the read path.)
//

import Foundation

enum EmailBodyCleaner {

    // MARK: - Public

    /// Quote-stripped and signature-stripped body. Returns the input unchanged
    /// when no confident anchor is found or when stripping would blank it.
    static func clean(_ body: String) -> String {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return body
        }
        let normalized = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let quoteStripped = stripQuotedContent(normalized)
        let signatureStripped = stripSignatureBlock(quoteStripped)
        let result = signatureStripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? body : result
    }

    /// One-line preview for a collapsed row: cleaned, whitespace-collapsed, and
    /// capped so a long message cannot push the row's layout around.
    static func preview(_ body: String, limit: Int = 140) -> String {
        let collapsed = clean(body)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        // Reserve one character for the ellipsis and break on a word boundary
        // so the preview never ends mid-word.
        let hardCut = collapsed.index(collapsed.startIndex, offsetBy: limit - 1)
        let head = collapsed[..<hardCut]
        if let lastSpace = head.lastIndex(of: " "), lastSpace > collapsed.startIndex {
            return head[..<lastSpace].trimmingCharacters(in: .whitespaces) + "…"
        }
        return head.trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Quote stripping

    /// Mirrors ops-web QUOTE_MARKERS, in the same order. Each pattern marks
    /// where the NEW text ends and the quoted chain begins.
    private static let quoteMarkers: [NSRegularExpression] = {
        let patterns: [(String, NSRegularExpression.Options)] = [
            // Gmail: "On Mon, Jan 15, 2026 at 3:45 PM John Smith <john@…> wrote:"
            ("^On .{10,80} wrote:[ \\t]*$", [.anchorsMatchLines]),
            // Gmail, line-wrapped: "On … <email>\nwrote:"
            ("^On .{10,120}>[ \\t]*\\nwrote:", [.anchorsMatchLines]),
            // Outlook: "-----Original Message-----"
            ("^-{3,}\\s*Original Message\\s*-{3,}", [.anchorsMatchLines, .caseInsensitive]),
            // Outlook header triplet: "From: … / Sent: … / To: …"
            ("^From:\\s.+\\nSent:\\s.+\\nTo:\\s", [.anchorsMatchLines]),
            // Apple Mail: "On Jan 15, 2026, at 3:45 PM, John Smith wrote:"
            ("^On .{10,60}, at .{5,20}, .{2,60} wrote:", [.anchorsMatchLines]),
            // Forwarded message banner
            ("^-{5,}\\s*Forwarded message\\s*-{5,}", [.anchorsMatchLines, .caseInsensitive]),
            ("^Begin forwarded message:", [.anchorsMatchLines, .caseInsensitive]),
            // Three or more consecutive ">" lines — a real quote block. Two is
            // someone quoting a line inline, which is content. The final line
            // may end the body with no trailing newline, so the line terminator
            // has to accept end-of-input as well.
            ("(?:^>.*(?:\\n|$)){3,}", [.anchorsMatchLines]),
            // Outlook web divider above the quoted header
            ("^_{10,}[ \\t]*\\nFrom:", [.anchorsMatchLines]),
            // Device footer that opens a non-content tail
            ("^Get Outlook for (?:iOS|Android)", [.anchorsMatchLines]),
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0.0, options: $0.1) }
    }()

    private static func stripQuotedContent(_ body: String) -> String {
        let ns = body as NSString
        let full = NSRange(location: 0, length: ns.length)
        var earliest = ns.length

        for marker in quoteMarkers {
            if let match = marker.firstMatch(in: body, options: [], range: full),
               match.range.location < earliest {
                earliest = match.range.location
            }
        }
        guard earliest < ns.length else { return body }

        let stripped = ns.substring(to: earliest)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // If the whole message IS a quote, showing the quote beats showing
        // nothing. `clean` re-checks this, but keeping the guard here means the
        // signature pass never runs against an already-empty body.
        return stripped.isEmpty ? body : stripped
    }

    // MARK: - Signature stripping

    /// A line that is exactly "--" or "-- " — the RFC 3676 delimiter.
    private static let sigDelimiter = regex("^[ \\t]*--[ \\t]*$")
    /// Device / mail-client footers.
    private static let clientFooter = regex(
        "^[ \\t]*(?:sent from my\\b.*|sent via\\b.*|get outlook for (?:ios|android)\\b.*|get the outlook app\\b.*)[ \\t]*$",
        caseInsensitive: true
    )
    /// A labelled footer line: "Phone: …", "Address: …".
    private static let labelledFooter = regex(
        "^[ \\t]*(?:phone|tel|telephone|mobile|cell|fax|address|email|e-mail|web|website|office|direct|toll[- ]?free)[ \\t]*:",
        caseInsensitive: true
    )
    /// A line carrying contact-shaped data (phone digits, email, or url).
    private static let contactShape = regex(
        "(?:\\+?\\d[\\d().\\s-]{6,}\\d|[\\w.+-]+@[\\w.-]+\\.[A-Za-z]{2,}|https?://|www\\.)",
        caseInsensitive: true
    )

    private static let signOffWords = [
        "thanks", "thank you", "thanks so much", "many thanks", "thanks again",
        "regards", "best regards", "kind regards", "warm regards",
        "best", "best wishes", "all the best",
        "cheers", "sincerely", "respectfully", "talk soon", "speak soon",
    ]

    /// A line that is ONLY a sign-off word (optionally trailed by punctuation).
    /// Anchoring to a whole line is what keeps "Thanks for getting back to me"
    /// from triggering a cut.
    private static let signOffLine: NSRegularExpression? = {
        let alternation = signOffWords
            .map { $0.replacingOccurrences(of: " ", with: "\\s+") }
            .joined(separator: "|")
        return regex("^[ \\t]*(?:\(alternation))[ \\t]*[,\\-—–]?[ \\t]*$", caseInsensitive: true)
    }()

    /// Longest a signature line may be before it reads as prose.
    private static let maxSigLineLength = 60
    /// A sign-off tail this many non-blank lines or fewer reads as a signature.
    private static let maxSignOffTailLines = 6

    private static func stripSignatureBlock(_ body: String) -> String {
        let lines = body.components(separatedBy: "\n")
        var cutAt = lines.count

        for (index, line) in lines.enumerated() {
            // Hard delimiters — everything from here down is footer.
            if matches(sigDelimiter, line) || matches(clientFooter, line) {
                cutAt = min(cutAt, index)
                break
            }
            // A sign-off word alone on its line, followed by a signature-shaped
            // tail (short lines, or a line carrying contact data).
            if matches(signOffLine, line),
               looksLikeSignatureTail(Array(lines[(index + 1)...])) {
                cutAt = min(cutAt, index)
                break
            }
        }

        // A run of labelled footer lines at the very end, when nothing else hit.
        if cutAt == lines.count {
            var firstFooter = lines.count
            for index in stride(from: lines.count - 1, through: 0, by: -1) {
                let line = lines[index]
                if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                if matches(labelledFooter, line) {
                    firstFooter = index
                    continue
                }
                break
            }
            if firstFooter < lines.count { cutAt = firstFooter }
        }

        guard cutAt < lines.count else { return body }
        let kept = lines[..<cutAt]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Never blank out the message: if stripping ate everything, the
        // "signature" WAS the content.
        return kept.isEmpty ? body : kept
    }

    private static func looksLikeSignatureTail(_ tail: [String]) -> Bool {
        let nonBlank = tail.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonBlank.isEmpty, nonBlank.count <= maxSignOffTailLines else { return false }
        guard !nonBlank.contains(where: {
            $0.trimmingCharacters(in: .whitespaces).count > maxSigLineLength
        }) else { return false }
        if nonBlank.contains(where: { matches(contactShape, $0) }) { return true }
        // No contact data: only a single short line (a bare name) is confident
        // enough to cut. Several short non-contact lines are ambiguous — keep
        // them rather than risk eating content.
        return nonBlank.count == 1
    }

    // MARK: - Regex helpers

    private static func regex(
        _ pattern: String,
        caseInsensitive: Bool = false
    ) -> NSRegularExpression? {
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if caseInsensitive { options.insert(.caseInsensitive) }
        return try? NSRegularExpression(pattern: pattern, options: options)
    }

    private static func matches(_ regex: NSRegularExpression?, _ line: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(location: 0, length: (line as NSString).length)
        return regex.firstMatch(in: line, options: [], range: range) != nil
    }
}
