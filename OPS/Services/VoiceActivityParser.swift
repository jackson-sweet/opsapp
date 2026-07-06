//
//  VoiceActivityParser.swift
//  OPS
//
//  Parses a raw voice transcription into structured activity data:
//  activity type, matched contact, and cleaned notes.
//  All local, all synchronous, all offline-capable.
//

import Foundation

struct ActivityDraft {
    var type: ActivityType
    var matchedOpportunityId: String?
    var matchedContactName: String?
    var notes: String
    var confidence: MatchConfidence

    enum MatchConfidence {
        case exact       // Levenshtein score >= 0.9
        case high        // score >= 0.7
        case ambiguous   // multiple matches above threshold
        case noMatch     // no match found
        case noContact   // no "with" pattern detected
    }

    /// All candidate matches when ambiguous
    var ambiguousCandidates: [(opportunityId: String, contactName: String, score: Double)] = []

    /// The raw parsed contact name (before matching)
    var parsedContactName: String?

    /// A suggested follow-up due date, detected from a follow-up cue + date
    /// mention in the raw transcription (e.g. "callback Tuesday"). Nil unless
    /// both a cue phrase and a resolvable date are present.
    var suggestedFollowUpDueAt: Date?

    /// A suggested follow-up title paired with `suggestedFollowUpDueAt`.
    var suggestedFollowUpTitle: String?
}

struct VoiceActivityParser {

    // MARK: - Public

    /// Parse a raw transcription into an ActivityDraft.
    /// `opportunities` is the list of active opportunities to match against.
    /// `now` is the reference "current time" used to resolve/roll-forward any
    /// detected follow-up date — defaulted so existing call sites are unaffected.
    static func parse(
        transcription: String,
        opportunities: [(id: String, contactName: String)],
        now: Date = Date()
    ) -> ActivityDraft {
        let trimmed = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ActivityDraft(type: .note, notes: "", confidence: .noContact)
        }

        // Step 1: Extract activity type
        let (type, afterType) = extractType(from: trimmed)

        // Step 2: Extract contact name
        let (parsedName, afterContact) = extractContact(from: afterType)

        // Step 3: Clean remaining text into notes
        let notes = cleanNotes(afterContact)

        // Step 4: Fuzzy match contact against opportunities
        var draft: ActivityDraft
        if let parsedName {
            let matches = fuzzyMatch(name: parsedName, against: opportunities)

            if matches.count == 1 {
                let match = matches[0]
                let confidence: ActivityDraft.MatchConfidence = match.score >= 0.9 ? .exact : .high
                draft = ActivityDraft(
                    type: type,
                    matchedOpportunityId: match.opportunityId,
                    matchedContactName: match.contactName,
                    notes: notes,
                    confidence: confidence,
                    parsedContactName: parsedName
                )
            } else if matches.count > 1 {
                draft = ActivityDraft(
                    type: type,
                    notes: notes,
                    confidence: .ambiguous,
                    ambiguousCandidates: matches,
                    parsedContactName: parsedName
                )
            } else {
                // No match — will create new lead on save
                draft = ActivityDraft(
                    type: type,
                    notes: notes,
                    confidence: .noMatch,
                    parsedContactName: parsedName
                )
            }
        } else {
            // No "with" pattern found
            draft = ActivityDraft(type: type, notes: notes, confidence: .noContact)
        }

        // Step 5: Detect an optional follow-up suggestion from the raw transcript.
        if let followUp = detectFollowUp(rawTranscription: trimmed, contactName: parsedName, now: now) {
            draft.suggestedFollowUpDueAt = followUp.dueAt
            draft.suggestedFollowUpTitle = followUp.title
        }

        return draft
    }

    // MARK: - Type Extraction

    private static let typeKeywords: [(keywords: [String], type: ActivityType)] = [
        (["site visit", "visited", "went to site"], .siteVisit),
        (["phone call", "called"], .call),
        (["call with", "call to", "call from", "call"], .call),
        (["emailed", "email to", "email from", "email"], .email),
        (["met with", "meeting with", "meeting"], .meeting),
        (["noting", "note"], .note),
    ]

    private static func extractType(from text: String) -> (ActivityType, String) {
        let lower = text.lowercased()

        for entry in typeKeywords {
            for keyword in entry.keywords {
                if lower.hasPrefix(keyword) {
                    let remaining = String(text.dropFirst(keyword.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    // If keyword already contains "with", don't strip it from the contact parser
                    if keyword.contains("with") {
                        return (entry.type, "with " + remaining)
                    }
                    return (entry.type, remaining)
                }
            }
        }

        return (.note, text)
    }

    // MARK: - Contact Extraction

    /// Looks for "with [1-3 words]" or "to [1-3 words]" near the start.
    /// Returns the parsed name and the remaining text.
    private static func extractContact(from text: String) -> (String?, String) {
        let lower = text.lowercased()

        for preposition in ["with ", "to ", "from "] {
            guard lower.hasPrefix(preposition) else { continue }

            let afterPrep = String(text.dropFirst(preposition.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let words = afterPrep.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            guard !words.isEmpty else { continue }

            // Try to find where the name ends and the notes begin.
            // Heuristic: name is 1-3 capitalized words before a transition word or comma.
            let transitionWords = Set([
                "spoke", "discussed", "regarding", "about", "re", "sent", "no",
                "left", "scheduled", "confirmed", "cancelled", "canceled",
                "they", "he", "she", "we", "i", "the", "said", "asked",
                "needs", "wants", "will", "has", "had", "told", "mentioned"
            ])

            var nameWords: [String] = []
            var restStartIndex = 0

            for (i, word) in words.enumerated() {
                let cleanWord = word.trimmingCharacters(in: CharacterSet.punctuationCharacters)

                // Stop at transition words
                if transitionWords.contains(cleanWord.lowercased()) {
                    restStartIndex = i
                    break
                }

                // Stop at comma
                if word.hasSuffix(",") {
                    nameWords.append(String(word.dropLast()))
                    restStartIndex = i + 1
                    break
                }

                // Stop after 3 words (max name length)
                if nameWords.count >= 3 {
                    restStartIndex = i
                    break
                }

                nameWords.append(word)
                restStartIndex = i + 1
            }

            guard !nameWords.isEmpty else { continue }

            let parsedName = nameWords.joined(separator: " ")
            let remainingWords = Array(words[restStartIndex...])
            let remaining = remainingWords.joined(separator: " ")

            return (parsedName, remaining)
        }

        return (nil, text)
    }

    // MARK: - Notes Cleanup

    private static let fillerPrefixes = [
        "spoke about", "discussed", "regarding", "about", "re ",
        "talked about", "went over", "covered"
    ]

    private static func cleanNotes(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove leading filler phrases
        let lower = cleaned.lowercased()
        for filler in fillerPrefixes {
            if lower.hasPrefix(filler) {
                cleaned = String(cleaned.dropFirst(filler.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Remove leading comma
        if cleaned.hasPrefix(",") {
            cleaned = String(cleaned.dropFirst())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Capitalize first letter
        guard !cleaned.isEmpty else { return cleaned }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    // MARK: - Follow-Up Detection

    /// Cue phrases that gate follow-up detection. Without one of these present
    /// in the transcript, an incidental date mention (e.g. "met him Monday")
    /// must NOT produce a suggested follow-up.
    private static let followUpCues = [
        "follow up", "follow-up", "followup", "call back", "callback",
        "circle back", "check in", "reach out", "remind me", "next week", "next month"
    ]

    /// NSDataDetector's documented convention: a date match with no explicit
    /// time-of-day spoken resolves to local noon. Anything else means a time
    /// was actually stated (e.g. "at 3pm") and must be preserved as-is.
    private static func isDateOnlyMatch(_ date: Date, calendar: Calendar) -> Bool {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return comps.hour == 12 && comps.minute == 0
    }

    /// Detects a suggested follow-up (due date + title) from the raw transcription.
    /// Returns nil unless BOTH a follow-up cue phrase and a resolvable date are present.
    private static func detectFollowUp(
        rawTranscription: String,
        contactName: String?,
        now: Date
    ) -> (dueAt: Date, title: String)? {
        let lower = rawTranscription.lowercased()

        // Gate: require an explicit follow-up cue before doing any date detection work.
        guard followUpCues.contains(where: { lower.contains($0) }) else {
            return nil
        }

        let calendar = Calendar.current
        var resolvedDate: Date

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let fullRange = NSRange(rawTranscription.startIndex..., in: rawTranscription)
            let match = detector.firstMatch(in: rawTranscription, options: [], range: fullRange)

            if let matchedDate = match?.date {
                if isDateOnlyMatch(matchedDate, calendar: calendar) {
                    // Date-only match (NSDataDetector defaults to noon) — normalize to 09:00 local.
                    var dateOnlyComponents = calendar.dateComponents(
                        [.year, .month, .day], from: matchedDate
                    )
                    dateOnlyComponents.hour = 9
                    dateOnlyComponents.minute = 0
                    dateOnlyComponents.second = 0
                    resolvedDate = calendar.date(from: dateOnlyComponents) ?? matchedDate
                } else {
                    // An explicit time-of-day was spoken — preserve it.
                    resolvedDate = matchedDate
                }
            } else if lower.contains("next week") {
                // NSDataDetector does not resolve bare relative phrases like "next week"
                // into a concrete date — resolve manually, defaulting to 09:00 local.
                resolvedDate = defaultTime(daysFromNow: 7, now: now, calendar: calendar)
            } else if lower.contains("next month") {
                resolvedDate = defaultTime(monthsFromNow: 1, now: now, calendar: calendar)
            } else {
                return nil
            }
        } else if lower.contains("next week") {
            resolvedDate = defaultTime(daysFromNow: 7, now: now, calendar: calendar)
        } else if lower.contains("next month") {
            resolvedDate = defaultTime(monthsFromNow: 1, now: now, calendar: calendar)
        } else {
            return nil
        }

        // Mandatory roll-forward: if the resolved date is in the past or the same
        // instant relative to `now`, advance by whole weeks until it's strictly future.
        // (A bare weekday spoken on that same weekday must roll to NEXT week's occurrence.)
        while resolvedDate <= now {
            guard let advanced = calendar.date(byAdding: .day, value: 7, to: resolvedDate) else {
                break
            }
            resolvedDate = advanced
        }

        let title: String
        if let contactName, !contactName.isEmpty {
            title = "Follow up with \(contactName)"
        } else {
            title = "Follow up"
        }

        return (dueAt: resolvedDate, title: title)
    }

    /// Resolves a relative-phrase follow-up date (e.g. "next week") to a concrete
    /// Date, defaulted to 09:00 local on the target day.
    private static func defaultTime(
        daysFromNow: Int = 0,
        monthsFromNow: Int = 0,
        now: Date,
        calendar: Calendar
    ) -> Date {
        var target = now
        if daysFromNow != 0 {
            target = calendar.date(byAdding: .day, value: daysFromNow, to: target) ?? target
        }
        if monthsFromNow != 0 {
            target = calendar.date(byAdding: .month, value: monthsFromNow, to: target) ?? target
        }
        var comps = calendar.dateComponents([.year, .month, .day], from: target)
        comps.hour = 9
        comps.minute = 0
        comps.second = 0
        return calendar.date(from: comps) ?? target
    }

    // MARK: - Fuzzy Matching

    /// Returns all opportunities with a normalized Levenshtein score >= 0.7,
    /// sorted by score descending.
    private static func fuzzyMatch(
        name: String,
        against opportunities: [(id: String, contactName: String)],
        threshold: Double = 0.7
    ) -> [(opportunityId: String, contactName: String, score: Double)] {
        let normalizedInput = name.lowercased().trimmingCharacters(in: .whitespaces)

        var matches: [(opportunityId: String, contactName: String, score: Double)] = []

        for opp in opportunities {
            let normalizedContact = opp.contactName.lowercased().trimmingCharacters(in: .whitespaces)
            let score = normalizedLevenshteinScore(normalizedInput, normalizedContact)

            if score >= threshold {
                matches.append((opportunityId: opp.id, contactName: opp.contactName, score: score))
            }
        }

        return matches.sorted { $0.score > $1.score }
    }

    /// Returns a score from 0.0 (completely different) to 1.0 (identical).
    private static func normalizedLevenshteinScore(_ a: String, _ b: String) -> Double {
        let aChars = Array(a)
        let bChars = Array(b)
        let aLen = aChars.count
        let bLen = bChars.count

        if aLen == 0 && bLen == 0 { return 1.0 }
        if aLen == 0 || bLen == 0 { return 0.0 }

        // Also check if input is a prefix/substring match (e.g., "John" matching "John Smith")
        if b.hasPrefix(a) || a.hasPrefix(b) {
            let prefixScore = Double(min(aLen, bLen)) / Double(max(aLen, bLen))
            if prefixScore >= 0.5 {
                // Boost prefix matches — "John" matching "John Smith" should score high
                return max(prefixScore, 0.75)
            }
        }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: bLen + 1), count: aLen + 1)

        for i in 0...aLen { matrix[i][0] = i }
        for j in 0...bLen { matrix[0][j] = j }

        for i in 1...aLen {
            for j in 1...bLen {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,       // deletion
                    matrix[i][j - 1] + 1,       // insertion
                    matrix[i - 1][j - 1] + cost  // substitution
                )
            }
        }

        let distance = matrix[aLen][bLen]
        let maxLen = max(aLen, bLen)
        return 1.0 - (Double(distance) / Double(maxLen))
    }
}
