//
//  ProjectNoteMentionEditSync.swift
//  OPS
//
//  Authoritative mention parsing plus the durable, server-proven edit path for
//  existing project notes and photo comments.
//

import Foundation
import SwiftData

enum ProjectNoteMentionRecipient: Equatable {
    case user(id: String)
    case allTeam
    case unresolved
}

/// UI-invisible identity attached to one visible mention token while a draft is
/// being edited. The UTF-16 range matches UITextView/NSRange semantics, so
/// emoji and composed characters before the token cannot move it off target.
struct ProjectNoteMentionSpan: Equatable {
    var range: NSRange
    let displayText: String
    let recipient: ProjectNoteMentionRecipient
}

struct ProjectNoteMentionBaseline: Equatable {
    let content: String
    let mentionedUserIds: [String]
}

struct ProjectNoteMentionDraft: Equatable {
    let text: String
    let identitySpans: [ProjectNoteMentionSpan]
}

struct ProjectNoteMentionRenderSegment: Equatable {
    let text: String
    let recipient: ProjectNoteMentionRecipient?

    var isMention: Bool {
        recipient != nil
    }
}

struct ProjectNoteMentionEditPlan: Equatable {
    let content: String
    let mentionedUserIds: [String]
    let unresolvedMentionNames: [String]

    static func make(
        content: String,
        teamMembers: [TeamMember],
        currentUserId: String?,
        identitySpans: [ProjectNoteMentionSpan] = [],
        preferredMentionedUserIds: [String] = [],
        baseline: ProjectNoteMentionBaseline? = nil
    ) -> ProjectNoteMentionEditPlan {
        let resolution = ProjectNoteMentionParser.resolve(
            in: content,
            teamMembers: teamMembers,
            currentUserId: currentUserId,
            identitySpans: identitySpans,
            preferredMentionedUserIds: preferredMentionedUserIds
        )
        var mentionedUserIds = resolution.userIds
        var unresolvedMentionNames = resolution.unresolvedMentionNames

        if let baseline {
            let baselineDraft = ProjectNoteMentionParser.editableDraft(
                in: baseline.content,
                mentionedUserIds: baseline.mentionedUserIds,
                teamMembers: teamMembers,
                currentUserId: currentUserId
            )
            var representedBaselineIds = Set<String>()
            for span in baselineDraft.identitySpans {
                switch span.recipient {
                case .user(let id):
                    representedBaselineIds.insert(id.lowercased())
                case .allTeam:
                    representedBaselineIds.formUnion(
                        baseline.mentionedUserIds.map {
                            $0.lowercased()
                        }
                    )
                case .unresolved:
                    break
                }
            }
            let resolvedIds = Set(mentionedUserIds.map { $0.lowercased() })
            let staleBaselineIds = baseline.mentionedUserIds.filter {
                !representedBaselineIds.contains($0.lowercased())
                    && !resolvedIds.contains($0.lowercased())
            }

            if !staleBaselineIds.isEmpty {
                let baselineHasVisibleMention =
                    ProjectNoteMentionParser.containsPotentialMention(
                        in: baselineDraft.text
                    )
                let baselineHasInvalidCanonicalIdentity =
                    baselineDraft.identitySpans.contains {
                        $0.recipient == .unresolved
                    }
                if baselineDraft.text == content {
                    var seen = Set<String>()
                    mentionedUserIds = (
                        baseline.mentionedUserIds + mentionedUserIds
                    ).filter {
                        seen.insert($0.lowercased()).inserted
                    }
                    // Exact unchanged legacy content is allowed to retain an
                    // identity whose roster row is temporarily unavailable.
                    // A malformed canonical token remains blocked: clearing
                    // that diagnostic would preserve its ID while stripping
                    // the visible identity markup on save.
                    if !baselineHasInvalidCanonicalIdentity {
                        unresolvedMentionNames = []
                    }
                } else if baselineHasVisibleMention
                            && unresolvedMentionNames.isEmpty {
                    // Every unresolved baseline token was removed or replaced
                    // by an explicitly-resolved current mention. Its prior ID
                    // must be removed, not silently retained or made impossible
                    // to revoke.
                } else {
                    unresolvedMentionNames.append("@Retained teammate")
                }
            }
        }

        var seenUnresolved = Set<String>()
        let stableUnresolvedNames = unresolvedMentionNames.filter {
            seenUnresolved.insert($0.lowercased()).inserted
        }
        var persistenceSpans = ProjectNoteMentionParser
            .reconstructIdentitySpans(
                in: content,
                mentionedUserIds: mentionedUserIds,
                teamMembers: teamMembers,
                currentUserId: currentUserId
            )
        let persistedUserIds = Set(
            mentionedUserIds.map { $0.lowercased() }
        )
        for span in identitySpans where
            span.isPersistable(withUserIds: persistedUserIds) {
            persistenceSpans.removeAll {
                NSIntersectionRange($0.range, span.range).length > 0
            }
            persistenceSpans.append(span)
        }
        let persistedContent = ProjectNoteMentionParser.persistedContent(
            fromEditableText: content,
            identitySpans: persistenceSpans
        )

        return ProjectNoteMentionEditPlan(
            content: persistedContent,
            mentionedUserIds: mentionedUserIds,
            unresolvedMentionNames: stableUnresolvedNames
        )
    }
}

struct ProjectNoteMentionResolution: Equatable {
    let userIds: [String]
    let unresolvedMentionNames: [String]

    var isResolved: Bool {
        unresolvedMentionNames.isEmpty
    }
}

private extension ProjectNoteMentionSpan {
    func isPersistable(withUserIds userIds: Set<String>) -> Bool {
        switch recipient {
        case .user(let id):
            return userIds.contains(id.lowercased())
        case .allTeam, .unresolved:
            return true
        }
    }
}

enum ProjectNoteMentionParser {
    private static let reservedAllTeamName = "all team"
    private static let reservedPersonSuffix = " (person)"

    private enum VisibleRecipient {
        case users([TeamMember])
        case allTeam
    }

    private struct VisibleMention {
        let range: NSRange
        let displayText: String
        let recipient: VisibleRecipient
    }

    /// Exact visible text inserted for a selected teammate. The reserved group
    /// command always owns `@All Team`; a person with that legal name gets a
    /// stable human-readable disambiguator that survives save/reopen.
    static func visibleMentionText(for member: TeamMember) -> String {
        let name = canonicalName(member.fullName)
        guard normalizedName(name) == reservedAllTeamName else {
            return "@\(name)"
        }
        return "@\(name)\(reservedPersonSuffix)"
    }

    /// Converts web-authored `@[Display Name](userId)` mentions into the plain
    /// iOS editing grammar while retaining the embedded identity in an
    /// invisible span. UUIDs therefore never appear in the editor or rendered
    /// comment, while the next save round-trips the canonical shared markup.
    static func editableDraft(
        in content: String,
        mentionedUserIds: [String],
        teamMembers: [TeamMember],
        currentUserId: String? = nil
    ) -> ProjectNoteMentionDraft {
        let source = content as NSString
        let matches = webMentionRegex.matches(
            in: content,
            range: NSRange(location: 0, length: source.length)
        )
        let mutable = NSMutableString(string: content)
        var webSpans: [ProjectNoteMentionSpan] = []
        var runningDelta = 0
        let authoritativeIds = Set(
            mentionedUserIds.map { $0.lowercased() }
        )
        let membersById = Dictionary(
            teamMembers.map { ($0.id.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let expectedAllTeamIds = Set(
            teamMembers.compactMap { member -> String? in
                let id = member.id.lowercased()
                return id == currentUserId?.lowercased() ? nil : id
            }
        )

        for match in matches {
            guard match.numberOfRanges == 3 else { continue }
            let displayName = source.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let userId = source.substring(with: match.range(at: 2))
            guard !displayName.isEmpty, !userId.isEmpty else { continue }
            let isAllTeamSentinel =
                displayName == "All Team" && userId == "all-team"
            let visibleText: String
            if isAllTeamSentinel {
                visibleText = "@All Team"
            } else if normalizedName(displayName) == reservedAllTeamName {
                visibleText = "@\(displayName)\(reservedPersonSuffix)"
            } else {
                visibleText = "@\(displayName)"
            }
            let adjustedRange = NSRange(
                location: match.range.location + runningDelta,
                length: match.range.length
            )
            mutable.replaceCharacters(
                in: adjustedRange,
                with: visibleText
            )
            let canonicalId = userId.lowercased()
            let recipient: ProjectNoteMentionRecipient
            if isAllTeamSentinel,
               authoritativeIds == expectedAllTeamIds {
                recipient = .allTeam
            } else if UUID(uuidString: userId) != nil,
                      authoritativeIds.contains(canonicalId) {
                if let member = membersById[canonicalId] {
                    let expectedDisplay = String(
                        visibleMentionText(for: member).dropFirst()
                    )
                    recipient = expectedDisplay.caseInsensitiveCompare(
                        displayName
                    ) == .orderedSame
                        ? .user(id: member.id)
                        : .unresolved
                } else {
                    recipient = .user(id: userId)
                }
            } else {
                recipient = .unresolved
            }
            webSpans.append(
                ProjectNoteMentionSpan(
                    range: NSRange(
                        location: adjustedRange.location,
                        length: (visibleText as NSString).length
                    ),
                    displayText: visibleText,
                    recipient: recipient
                )
            )
            runningDelta += (visibleText as NSString).length
                - match.range.length
        }

        let text = mutable as String
        var spans = reconstructIdentitySpans(
            in: text,
            mentionedUserIds: mentionedUserIds,
            teamMembers: teamMembers,
            currentUserId: currentUserId
        )
        for webSpan in webSpans {
            spans.removeAll { rangesOverlap($0.range, webSpan.range) }
            spans.append(webSpan)
        }
        spans.sort { $0.range.location < $1.range.location }
        return ProjectNoteMentionDraft(
            text: text,
            identitySpans: spans
        )
    }

    static func displayText(from content: String) -> String {
        editableDraft(
            in: content,
            mentionedUserIds: [],
            teamMembers: []
        ).text
    }

    /// Produces one UUID-free display stream whose mention segments retain
    /// their authoritative recipient. Every note surface uses this instead of
    /// re-resolving links by visible name, which is ambiguous for duplicate
    /// names and the reserved `All Team` token.
    static func renderedSegments(
        in content: String,
        mentionedUserIds: [String],
        teamMembers: [TeamMember],
        currentUserId: String? = nil
    ) -> [ProjectNoteMentionRenderSegment] {
        let draft = editableDraft(
            in: content,
            mentionedUserIds: mentionedUserIds,
            teamMembers: teamMembers,
            currentUserId: currentUserId
        )
        let source = draft.text as NSString
        var spans = draft.identitySpans.filter {
            $0.range.location != NSNotFound
                && $0.range.location >= 0
                && $0.range.length > 0
                && NSMaxRange($0.range) <= source.length
                && source.substring(with: $0.range) == $0.displayText
                && hasCompleteMentionBoundary(
                    for: $0.range,
                    in: source
                )
        }
        for mention in visibleMentions(
            in: draft.text,
            teamMembers: teamMembers
        ) where
            !spans.contains(where: {
                rangesOverlap($0.range, mention.range)
            })
        {
            let recipient: ProjectNoteMentionRecipient
            switch mention.recipient {
            case .allTeam:
                recipient = .allTeam
            case .users:
                // A recognized roster name without authoritative identity is
                // still one full visible mention, but it must remain inert.
                recipient = .unresolved
            }
            spans.append(
                ProjectNoteMentionSpan(
                    range: mention.range,
                    displayText: mention.displayText,
                    recipient: recipient
                )
            )
        }
        for token in potentialMentionTokens(in: draft.text) where
            !spans.contains(where: {
                rangesOverlap($0.range, token.range)
            })
        {
            spans.append(
                ProjectNoteMentionSpan(
                    range: token.range,
                    displayText: token.displayText,
                    recipient: .unresolved
                )
            )
        }
        spans.sort {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.range.length > $1.range.length
        }

        var result: [ProjectNoteMentionRenderSegment] = []
        var cursor = 0
        for span in spans where span.range.location >= cursor {
            if span.range.location > cursor {
                result.append(
                    ProjectNoteMentionRenderSegment(
                        text: source.substring(
                            with: NSRange(
                                location: cursor,
                                length: span.range.location - cursor
                            )
                        ),
                        recipient: nil
                    )
                )
            }
            result.append(
                ProjectNoteMentionRenderSegment(
                    text: span.displayText,
                    recipient: span.recipient
                )
            )
            cursor = NSMaxRange(span.range)
        }
        if cursor < source.length {
            result.append(
                ProjectNoteMentionRenderSegment(
                    text: source.substring(
                        with: NSRange(
                            location: cursor,
                            length: source.length - cursor
                        )
                    ),
                    recipient: nil
                )
            )
        }
        if result.isEmpty, !draft.text.isEmpty {
            return [
                ProjectNoteMentionRenderSegment(
                    text: draft.text,
                    recipient: nil
                ),
            ]
        }
        return result
    }

    /// Converts UUID-free editable mentions back to the shared web/iOS storage
    /// grammar. The reserved group uses one exact non-UUID sentinel; malformed
    /// lookalikes never become `.allTeam`.
    static func persistedContent(
        fromEditableText text: String,
        identitySpans: [ProjectNoteMentionSpan]
    ) -> String {
        let source = text as NSString
        let mutable = NSMutableString(string: text)
        let validSpans = identitySpans.filter {
            $0.range.location != NSNotFound
                && $0.range.location >= 0
                && $0.range.length > 0
                && NSMaxRange($0.range) <= source.length
                && source.substring(with: $0.range) == $0.displayText
                && hasCompleteMentionBoundary(
                    for: $0.range,
                    in: source
                )
        }
        for span in validSpans.sorted(
            by: { $0.range.location > $1.range.location }
        ) {
            let canonical: String
            switch span.recipient {
            case .allTeam:
                canonical = "@[All Team](all-team)"
            case .user(let id):
                let displayName = String(span.displayText.dropFirst())
                canonical = "@[\(displayName)](\(id))"
            case .unresolved:
                continue
            }
            mutable.replaceCharacters(in: span.range, with: canonical)
        }
        return mutable as String
    }

    static func resolveUserIds(
        in text: String,
        teamMembers: [TeamMember],
        currentUserId: String?
    ) -> [String] {
        resolve(
            in: text,
            teamMembers: teamMembers,
            currentUserId: currentUserId
        ).userIds
    }

    /// Resolves each visible token to at most one selected person, except the
    /// reserved group token which intentionally expands to the active roster.
    /// Duplicate full names without a persisted/selected identity are reported
    /// as unresolved and never silently expanded.
    static func resolve(
        in text: String,
        teamMembers: [TeamMember],
        currentUserId: String?,
        identitySpans: [ProjectNoteMentionSpan] = [],
        preferredMentionedUserIds: [String] = []
    ) -> ProjectNoteMentionResolution {
        let currentUserId = currentUserId?.lowercased()
        let utf16Text = text as NSString
        let membersById = Dictionary(
            teamMembers.map { ($0.id.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let validSpans = identitySpans
            .filter { span in
                guard span.range.location != NSNotFound,
                      span.range.location >= 0,
                      span.range.length > 0,
                      NSMaxRange(span.range) <= utf16Text.length,
                      utf16Text.substring(with: span.range)
                        == span.displayText,
                      hasCompleteMentionBoundary(
                          for: span.range,
                          in: utf16Text
                      ) else {
                    return false
                }
                switch span.recipient {
                case .allTeam:
                    return span.displayText.caseInsensitiveCompare(
                        "@All Team"
                    ) == .orderedSame
                case .unresolved:
                    return true
                case .user(let id):
                    guard let member = membersById[id.lowercased()] else {
                        // A previously-authoritative identity remains valid
                        // when the active roster is temporarily incomplete.
                        return true
                    }
                    return span.displayText.caseInsensitiveCompare(
                        visibleMentionText(for: member)
                    ) == .orderedSame
                }
            }
            .sorted { lhs, rhs in
                if lhs.range.location != rhs.range.location {
                    return lhs.range.location < rhs.range.location
                }
                return lhs.range.length > rhs.range.length
            }

        var mentions = visibleMentions(in: text, teamMembers: teamMembers)
        for span in validSpans {
            mentions.removeAll { rangesOverlap($0.range, span.range) }
        }

        enum ResolvableMention {
            case visible(VisibleMention)
            case span(ProjectNoteMentionSpan)

            var range: NSRange {
                switch self {
                case .visible(let mention): return mention.range
                case .span(let span): return span.range
                }
            }
        }

        var orderedMentions = mentions.map(ResolvableMention.visible)
        orderedMentions.append(contentsOf: validSpans.map(ResolvableMention.span))
        orderedMentions.sort {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.range.length > $1.range.length
        }

        var availablePreferredIds = preferredMentionedUserIds.map {
            $0.lowercased()
        }
        var userIds: [String] = []
        var seenIds = Set<String>()
        var unresolvedNames: [String] = []
        var seenUnresolvedNames = Set<String>()

        func appendUserId(_ id: String) {
            let canonicalId = id.lowercased()
            guard canonicalId != currentUserId,
                  seenIds.insert(canonicalId).inserted else {
                return
            }
            userIds.append(id)
        }

        func appendAllTeam() {
            for member in teamMembers {
                appendUserId(member.id)
            }
        }

        func appendUnresolved(_ displayText: String) {
            let name = displayText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let canonical = name.lowercased()
            guard seenUnresolvedNames.insert(canonical).inserted else {
                return
            }
            unresolvedNames.append(name)
        }

        for mention in orderedMentions {
            switch mention {
            case .span(let span):
                switch span.recipient {
                case .user(let id):
                    appendUserId(id)
                case .allTeam:
                    appendAllTeam()
                case .unresolved:
                    appendUnresolved(span.displayText)
                }

            case .visible(let visible):
                switch visible.recipient {
                case .allTeam:
                    appendAllTeam()
                case .users(let candidates):
                    let candidatesById = Dictionary(
                        candidates.map { ($0.id.lowercased(), $0) },
                        uniquingKeysWith: { first, _ in first }
                    )
                    if candidatesById.count == 1,
                       let member = candidatesById.values.first {
                        appendUserId(member.id)
                        continue
                    }

                    guard let preferredIndex = availablePreferredIds
                        .firstIndex(where: { candidatesById[$0] != nil })
                    else {
                        appendUnresolved(visible.displayText)
                        continue
                    }
                    let preferredId = availablePreferredIds.remove(
                        at: preferredIndex
                    )
                    if let member = candidatesById[preferredId] {
                        appendUserId(member.id)
                    }
                }
            }
        }

        let coveredRanges = orderedMentions.map(\.range)
        for token in potentialMentionTokens(in: text) where
            !coveredRanges.contains(where: {
                rangesOverlap($0, token.range)
            })
        {
            appendUnresolved(token.displayText)
        }

        return ProjectNoteMentionResolution(
            userIds: userIds,
            unresolvedMentionNames: unresolvedNames
        )
    }

    /// Rebuilds draft spans from plain content plus the server-preserved ID
    /// order. One duplicate-name token consumes one same-name ID in textual
    /// order; a single retained identity may safely back repeated references to
    /// that same person. Legacy one-token/multiple-ID ambiguity is left
    /// untracked so save requires an explicit picker selection.
    static func reconstructIdentitySpans(
        in text: String,
        mentionedUserIds: [String],
        teamMembers: [TeamMember],
        currentUserId: String?
    ) -> [ProjectNoteMentionSpan] {
        let mentions = visibleMentions(in: text, teamMembers: teamMembers)
        let priorIds = mentionedUserIds.map { $0.lowercased() }
        let authoritativeIds = Set(priorIds)
        let expectedAllTeamIds = Set(
            teamMembers.compactMap { member -> String? in
                let id = member.id.lowercased()
                return id == currentUserId?.lowercased() ? nil : id
            }
        )
        var spans: [ProjectNoteMentionSpan] = []

        for mention in mentions {
            switch mention.recipient {
            case .allTeam:
                spans.append(
                    ProjectNoteMentionSpan(
                        range: mention.range,
                        displayText: mention.displayText,
                        recipient:
                            authoritativeIds == expectedAllTeamIds
                                ? .allTeam
                                : .unresolved
                    )
                )

            case .users(let candidates):
                let candidatesById = Dictionary(
                    candidates.map { ($0.id.lowercased(), $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                if candidatesById.count == 1,
                   let member = candidatesById.values.first,
                   priorIds.contains(member.id.lowercased()) {
                    spans.append(
                        ProjectNoteMentionSpan(
                            range: mention.range,
                            displayText: mention.displayText,
                            recipient: .user(id: member.id)
                        )
                    )
                }
            }
        }

        let duplicateGroups = Dictionary(
            grouping: mentions.filter {
                if case .users(let candidates) = $0.recipient {
                    return Set(candidates.map { $0.id.lowercased() }).count > 1
                }
                return false
            },
            by: { $0.displayText.lowercased() }
        )

        for group in duplicateGroups.values {
            guard let first = group.first,
                  case .users(let candidates) = first.recipient else {
                continue
            }
            let candidateIds = Set(candidates.map { $0.id.lowercased() })
            let retainedIds = priorIds.filter(candidateIds.contains)
            let assignedIds: [String]
            if retainedIds.count == 1 {
                assignedIds = Array(
                    repeating: retainedIds[0],
                    count: group.count
                )
            } else if retainedIds.count == group.count {
                assignedIds = retainedIds
            } else {
                // One visible token must never inherit multiple same-name IDs.
                continue
            }

            for (mention, id) in zip(
                group.sorted { $0.range.location < $1.range.location },
                assignedIds
            ) {
                guard let member = candidates.first(
                    where: { $0.id.lowercased() == id }
                ) else {
                    continue
                }
                spans.append(
                    ProjectNoteMentionSpan(
                        range: mention.range,
                        displayText: mention.displayText,
                        recipient: .user(id: member.id)
                    )
                )
            }
        }

        return spans.sorted { $0.range.location < $1.range.location }
    }

    private static func visibleMentions(
        in text: String,
        teamMembers: [TeamMember]
    ) -> [VisibleMention] {
        struct Pattern {
            let displayText: String
            let recipient: VisibleRecipient
        }

        let memberGroups = Dictionary(
            grouping: teamMembers.filter {
                !canonicalName($0.fullName).isEmpty
            },
            by: { visibleMentionText(for: $0).lowercased() }
        )
        var patterns = memberGroups.compactMap {
            _, members -> Pattern? in
            guard let first = members.first else { return nil }
            return Pattern(
                displayText: visibleMentionText(for: first),
                recipient: .users(members)
            )
        }
        patterns.append(
            Pattern(
                displayText: "@All Team",
                recipient: .allTeam
            )
        )
        patterns.sort {
            ($0.displayText as NSString).length
                > ($1.displayText as NSString).length
        }

        var mentions: [VisibleMention] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let atIndex = text[searchStart...].firstIndex(of: "@") {
            defer { searchStart = text.index(after: atIndex) }

            if atIndex != text.startIndex {
                let preceding = text[text.index(before: atIndex)]
                guard isMentionBoundary(preceding) else { continue }
            }

            for pattern in patterns {
                guard let range = text.range(
                    of: pattern.displayText,
                    options: [.caseInsensitive, .anchored],
                    range: atIndex..<text.endIndex
                ) else {
                    continue
                }
                if range.upperBound != text.endIndex,
                   !isMentionBoundary(text[range.upperBound]) {
                    continue
                }
                // `@All Team (person)` is always the named teammate token,
                // never the reserved group prefix.
                if case .allTeam = pattern.recipient,
                   text[range.upperBound...].lowercased().hasPrefix(
                       reservedPersonSuffix
                   ) {
                    continue
                }
                mentions.append(
                    VisibleMention(
                        range: NSRange(range, in: text),
                        displayText: String(text[range]),
                        recipient: pattern.recipient
                    )
                )
                break
            }
        }

        return mentions
    }

    private static func canonicalName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedName(_ name: String) -> String {
        canonicalName(name).lowercased()
    }

    private static func rangesOverlap(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        NSIntersectionRange(lhs, rhs).length > 0
    }

    /// Identity spans are authoritative only when the visible token remains a
    /// complete mention. Alphanumeric adjacency turns it into ordinary text,
    /// exactly matching the boundary rule used by plain mention discovery.
    static func hasCompleteMentionBoundary(
        for range: NSRange,
        in text: NSString
    ) -> Bool {
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= text.length else {
            return false
        }
        if range.location > 0 {
            let precedingRange = text.rangeOfComposedCharacterSequence(
                at: range.location - 1
            )
            let precedingText = text.substring(with: precedingRange)
            if let character = precedingText.last,
               !isMentionBoundary(character) {
                return false
            }
        }
        let end = NSMaxRange(range)
        if end < text.length {
            let followingRange = text.rangeOfComposedCharacterSequence(
                at: end
            )
            let followingText = text.substring(with: followingRange)
            if let character = followingText.first,
               !isMentionBoundary(character) {
                return false
            }
        }
        return true
    }

    static func containsPotentialMention(in text: String) -> Bool {
        !potentialMentionTokens(in: text).isEmpty
    }

    /// Finds boundary-safe `@token` prefixes that are not necessarily in the
    /// active roster. The resolver subtracts every recognized/identity-backed
    /// range, leaving only visible tokens that need an explicit picker choice.
    /// Capturing the first word is sufficient because it overlaps every valid
    /// multi-word mention without guessing where an unknown name ends.
    private static func potentialMentionTokens(
        in text: String
    ) -> [(range: NSRange, displayText: String)] {
        var tokens: [(range: NSRange, displayText: String)] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let atIndex = text[searchStart...].firstIndex(of: "@") {
            defer { searchStart = text.index(after: atIndex) }

            if atIndex != text.startIndex {
                let preceding = text[text.index(before: atIndex)]
                guard isMentionBoundary(preceding) else { continue }
            }

            let tokenStart = text.index(after: atIndex)
            guard tokenStart < text.endIndex else { continue }
            let first = text[tokenStart]
            guard first.isLetter
                    || first.isNumber
                    || first == "_"
                    || first == "[" else {
                continue
            }

            var tokenEnd = tokenStart
            while tokenEnd < text.endIndex {
                let character = text[tokenEnd]
                guard character.isLetter
                        || character.isNumber
                        || character == "_"
                        || character == "-"
                        || character == "[" else {
                    break
                }
                tokenEnd = text.index(after: tokenEnd)
            }
            let range = atIndex..<tokenEnd
            tokens.append(
                (
                    range: NSRange(range, in: text),
                    displayText: String(text[range])
                )
            )
        }
        return tokens
    }

    private static let webMentionRegex = try! NSRegularExpression(
        pattern: #"@\[([^\]\r\n]+)\]\(([^)\r\n]+)\)"#
    )

    static func isMentionBoundary(_ character: Character) -> Bool {
        !character.isLetter && !character.isNumber && character != "_"
    }
}

struct ProjectNoteMentionDispatchRequest: Codable, Equatable {
    let eventType: String
    let mentionEventId: String

    init(mentionEventId: String) {
        self.eventType = "mention_edit"
        self.mentionEventId = mentionEventId
    }
}

/// Process-wide linearization gate for queue mutations that can originate from
/// the main ModelContext or the long-lived DataActor ModelContext. SwiftData
/// transactions are context-local; this gate closes the inter-context gap while
/// each caller refreshes and commits its persisted snapshot under the same lock.
final class ProjectNoteMentionQueueCoordinator: @unchecked Sendable {
    static let shared = ProjectNoteMentionQueueCoordinator()

    private let lock = NSLock()
    /// Operations whose HTTP execution window is currently open. Persisted
    /// `inProgress` remains the durable source of truth; this process-local set
    /// closes only the gap where another ModelContext still holds a stale
    /// pre-claim snapshot. IDs are released after the execution path commits its
    /// success/failure state so a later persisted retry can be claimed again.
    private var activeClaimIds = Set<UUID>()

    private init() {}

    func withMutation<T>(
        _ body: (Set<UUID>) throws -> T
    ) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(activeClaimIds)
    }

    /// Runs recovery before releasing the same process-wide gate that protected
    /// the failed mutation. Full-state restoration cannot safely happen after
    /// unlock: a waiting context could otherwise commit legitimate queue work
    /// and then have that work overwritten by the stale recovery snapshot.
    func withMutation<T>(
        recoveringWith recovery: (Error) -> Void,
        _ body: (Set<UUID>) throws -> T
    ) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        do {
            return try body(activeClaimIds)
        } catch {
            recovery(error)
            throw error
        }
    }

    func claim(
        operationId: UUID,
        _ body: () throws -> Bool
    ) rethrows -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !activeClaimIds.contains(operationId) else {
            return false
        }
        let didClaim = try body()
        if didClaim {
            activeClaimIds.insert(operationId)
        }
        return didClaim
    }

    /// Ends the process-local execution lease. Every caller that successfully
    /// claims must release from a `defer`, covering success, retry, permanent
    /// failure, decoding failure, and cancellation alike.
    func release(operationId: UUID) {
        lock.lock()
        activeClaimIds.remove(operationId)
        lock.unlock()
    }
}

enum ProjectNoteMentionEditSync {
    static let updateOperationType = "updateProjectNoteMentions"
    static let dispatchOperationType = "dispatchProjectNoteMentionEvent"

    static let noteIdPayloadKey = "note_id"
    static let contentPayloadKey = "content"
    static let mentionedUserIdsPayloadKey = "mentioned_user_ids"
    static let eventIdPayloadKey = "mention_event_id"
    static let previousContentPayloadKey = "previous_content"
    static let previousMentionedUserIdsPayloadKey =
        "previous_mentioned_user_ids"
    static let previousNeedsSyncPayloadKey = "previous_needs_sync"
    static let previousUpdatedAtPayloadKey = "previous_updated_at"

    struct ReconciledNoteState: Equatable {
        let content: String
        let mentionedUserIds: [String]
        let needsSync: Bool
        let updatedAt: Date?
    }

    struct DiscardOperationSnapshot: Equatable {
        let id: UUID
        let entityType: String
        let entityId: String
        let operationType: String
        let payload: Data
        let changedFields: String
        let createdAt: Date
        let retryCount: Int
        let lastAttemptedAt: Date?
        let status: String
        let lastError: String?
        let previousValues: Data?
        let priority: Int
        let requiresWiFi: Bool
        let dependsOnId: String?
        let completedAt: Date?
        let serverConfirmedAt: Date?

        init(_ operation: SyncOperation) {
            id = operation.id
            entityType = operation.entityType
            entityId = operation.entityId
            operationType = operation.operationType
            payload = operation.payload
            changedFields = operation.changedFields
            createdAt = operation.createdAt
            retryCount = operation.retryCount
            lastAttemptedAt = operation.lastAttemptedAt
            status = operation.status
            lastError = operation.lastError
            previousValues = operation.previousValues
            priority = operation.priority
            requiresWiFi = operation.requiresWiFi
            dependsOnId = operation.dependsOnId
            completedAt = operation.completedAt
            serverConfirmedAt = operation.serverConfirmedAt
        }

        func restore(_ operation: SyncOperation) {
            operation.id = id
            operation.entityType = entityType
            operation.entityId = entityId
            operation.operationType = operationType
            operation.payload = payload
            operation.changedFields = changedFields
            operation.createdAt = createdAt
            operation.retryCount = retryCount
            operation.lastAttemptedAt = lastAttemptedAt
            operation.status = status
            operation.lastError = lastError
            operation.previousValues = previousValues
            operation.priority = priority
            operation.requiresWiFi = requiresWiFi
            operation.dependsOnId = dependsOnId
            operation.completedAt = completedAt
            operation.serverConfirmedAt = serverConfirmedAt
        }

        func restoredModel() -> SyncOperation {
            let operation = SyncOperation(
                entityType: entityType,
                entityId: entityId,
                operationType: operationType,
                payload: payload,
                changedFields: [],
                previousValues: previousValues,
                priority: priority,
                dependsOnId: dependsOnId
            )
            restore(operation)
            return operation
        }
    }

    struct DiscardNoteSnapshot: Equatable {
        let id: String
        let projectId: String
        let companyId: String
        let authorId: String
        let content: String
        let attachmentsJSON: String
        let mentionedUserIdsString: String
        let photoURL: String?
        let eventKind: String?
        let contentMetadataJSON: String?
        let createdAt: Date
        let updatedAt: Date?
        let deletedAt: Date?
        let lastSyncedAt: Date?
        let needsSync: Bool

        init(_ note: ProjectNote) {
            id = note.id
            projectId = note.projectId
            companyId = note.companyId
            authorId = note.authorId
            content = note.content
            attachmentsJSON = note.attachmentsJSON
            mentionedUserIdsString = note.mentionedUserIdsString
            photoURL = note.photoURL
            eventKind = note.eventKind
            contentMetadataJSON = note.contentMetadataJSON
            createdAt = note.createdAt
            updatedAt = note.updatedAt
            deletedAt = note.deletedAt
            lastSyncedAt = note.lastSyncedAt
            needsSync = note.needsSync
        }

        func restore(_ note: ProjectNote) {
            note.id = id
            note.projectId = projectId
            note.companyId = companyId
            note.authorId = authorId
            note.content = content
            note.attachmentsJSON = attachmentsJSON
            note.mentionedUserIdsString = mentionedUserIdsString
            note.photoURL = photoURL
            note.eventKind = eventKind
            note.contentMetadataJSON = contentMetadataJSON
            note.createdAt = createdAt
            note.updatedAt = updatedAt
            note.deletedAt = deletedAt
            note.lastSyncedAt = lastSyncedAt
            note.needsSync = needsSync
        }

        func restoredModel() -> ProjectNote {
            let note = ProjectNote(
                id: id,
                projectId: projectId,
                companyId: companyId,
                authorId: authorId,
                content: content,
                photoURL: photoURL,
                createdAt: createdAt
            )
            restore(note)
            return note
        }
    }

    struct DiscardStateSnapshot: Equatable {
        let operations: [DiscardOperationSnapshot]
        let note: DiscardNoteSnapshot?
    }

    struct DiscardMentionUpdateNoteSnapshot: Equatable {
        let id: String
        let content: String
        let mentionedUserIdsString: String
        let updatedAt: Date?
        let needsSync: Bool

        init(_ note: ProjectNote) {
            id = note.id
            content = note.content
            mentionedUserIdsString = note.mentionedUserIdsString
            updatedAt = note.updatedAt
            needsSync = note.needsSync
        }

        func restore(_ note: ProjectNote) {
            note.content = content
            note.mentionedUserIdsString = mentionedUserIdsString
            note.updatedAt = updatedAt
            note.needsSync = needsSync
        }
    }

    struct DiscardDeleteNoteSnapshot: Equatable {
        let id: String
        let deletedAt: Date?
        let needsSync: Bool

        init(_ note: ProjectNote) {
            id = note.id
            deletedAt = note.deletedAt
            needsSync = note.needsSync
        }

        func restore(_ note: ProjectNote) {
            note.deletedAt = deletedAt
            note.needsSync = needsSync
        }
    }

    enum DiscardNoteMutation {
        case delete
        case mentionUpdate
        case offlineCreateDeletion
    }

    enum DiscardNoteRecoverySnapshot: Equatable {
        case delete(DiscardDeleteNoteSnapshot)
        case mentionUpdate(DiscardMentionUpdateNoteSnapshot)
        case offlineCreateDeletion(DiscardNoteSnapshot)

        var id: String {
            switch self {
            case .delete(let snapshot):
                return snapshot.id
            case .mentionUpdate(let snapshot):
                return snapshot.id
            case .offlineCreateDeletion(let snapshot):
                return snapshot.id
            }
        }
    }

    struct DiscardDependencySnapshot: Equatable {
        let operationId: UUID
        let dependsOnId: String?
    }

    struct DiscardRecoverySnapshot: Equatable {
        let discardedOperations: [DiscardOperationSnapshot]
        let rewiredDependencies: [DiscardDependencySnapshot]
        let note: DiscardNoteRecoverySnapshot?
    }

    struct DiscardDependencyRewire {
        let operation: SyncOperation
        let replacementDependency: String?
    }

    /// New notes are canonical lowercase, but builds before this fix could
    /// persist default UUIDs in uppercase. Every recovery/inbound identity
    /// lookup tolerates both representations so one logical note never forks.
    static func fetchProjectNote(
        matching id: String,
        in context: ModelContext
    ) throws -> ProjectNote? {
        let canonicalId = id.lowercased()
        let uppercaseId = id.uppercased()
        let descriptor = FetchDescriptor<ProjectNote>(
            predicate: #Predicate {
                $0.id == id
                    || $0.id == canonicalId
                    || $0.id == uppercaseId
            }
        )
        return try context.fetch(descriptor).first
    }

    /// Queue rows created after canonicalization use lowercase note IDs, while
    /// rows persisted by older builds can retain uppercase UUID strings. Route
    /// every inbound protection lookup through the same tolerant identity rule
    /// as the note fetch so realtime/pull cannot clear or overwrite a local
    /// tombstone merely because the two stores disagree on UUID casing.
    static func fetchProjectNoteOperations(
        matching id: String,
        in context: ModelContext
    ) throws -> [SyncOperation] {
        let entityType = SyncEntityType.projectNote.rawValue
        let canonicalId = id.lowercased()
        let uppercaseId = id.uppercased()
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate {
                $0.entityType == entityType
                    && (
                        $0.entityId == id
                            || $0.entityId == canonicalId
                            || $0.entityId == uppercaseId
                    )
            }
        )
        return try context.fetch(descriptor)
    }

    static func bypassesGenericCoalescing(_ operation: SyncOperation) -> Bool {
        operation.entityType == SyncEntityType.projectNote.rawValue
            && (
                operation.operationType == updateOperationType
                    || operation.operationType == dispatchOperationType
            )
    }

    static func isUpdateOperation(_ operation: SyncOperation) -> Bool {
        operation.entityType == SyncEntityType.projectNote.rawValue
            && operation.operationType == updateOperationType
    }

    static func isDispatchOperation(_ operation: SyncOperation) -> Bool {
        operation.entityType == SyncEntityType.projectNote.rawValue
            && operation.operationType == dispatchOperationType
    }

    static func isProjectNoteCreateOperation(
        _ operation: SyncOperation
    ) -> Bool {
        operation.entityType == SyncEntityType.projectNote.rawValue
            && operation.operationType == "create"
    }

    static func isDependencyDrainOperation(
        _ operation: SyncOperation
    ) -> Bool {
        bypassesGenericCoalescing(operation)
            || (
                operation.entityType
                    == SyncEntityType.projectNote.rawValue
                    && operation.operationType == "delete"
                    && operation.dependsOnId?.isEmpty == false
            )
    }

    /// Both inbound implementations keep the optimistic note dirty until every
    /// same-note authoritative update has reached a terminal server-confirmed
    /// state. Pending-only checks are insufficient while a request is in flight,
    /// transiently exhausted, or parked for explicit operator resolution.
    static func hasUnresolvedUpdate(
        for noteId: String,
        in operations: [SyncOperation]
    ) -> Bool {
        let canonicalNoteId = noteId.lowercased()
        let unresolvedStatuses = Set([
            "pending",
            "inProgress",
            "failed",
            "parked",
        ])
        return operations.contains {
            isUpdateOperation($0)
                && $0.entityId.lowercased() == canonicalNoteId
                && unresolvedStatuses.contains($0.status)
        }
    }

    /// A ProjectNote remains locally authoritative while any same-note write
    /// still requires execution or explicit operator resolution. This broader
    /// guard covers create/update/delete as well as mention edits, preventing an
    /// inbound echo from clearing `needsSync` on an in-flight, failed, or parked
    /// tombstone.
    static func hasUnresolvedWrite(
        for noteId: String,
        in operations: [SyncOperation]
    ) -> Bool {
        let canonicalNoteId = noteId.lowercased()
        let unresolvedStatuses = Set([
            "pending",
            "inProgress",
            "failed",
            "parked",
        ])
        return operations.contains {
            $0.entityType == SyncEntityType.projectNote.rawValue
                && $0.entityId.lowercased() == canonicalNoteId
                && unresolvedStatuses.contains($0.status)
                && (
                    isUpdateOperation($0)
                        || ["create", "update", "delete"]
                            .contains($0.operationType)
                )
        }
    }

    /// A permanent rejection proves the RPC did not commit its edit event. If
    /// a later full-authoritative replacement is already queued behind it, the
    /// rejected update and its impossible dispatch can be retired atomically,
    /// releasing the replacement without weakening per-note ordering.
    @discardableResult
    static func supersedeParkedUpdatesReplacedByLaterEdits(
        in operations: [SyncOperation],
        completedAt: Date = Date()
    ) -> Bool {
        var didChange = false
        let liveSuccessorStatuses = Set(["pending", "inProgress", "failed"])

        for parkedUpdate in operations where
            isUpdateOperation(parkedUpdate) && parkedUpdate.status == "parked"
        {
            let parkedId = parkedUpdate.id.uuidString.lowercased()
            let noteId = parkedUpdate.entityId.lowercased()
            let hasLaterReplacement = operations.contains { candidate in
                isUpdateOperation(candidate)
                    && candidate.id != parkedUpdate.id
                    && candidate.entityId.lowercased() == noteId
                    && liveSuccessorStatuses.contains(candidate.status)
                    && candidate.dependsOnId?.lowercased() == parkedId
            }
            guard hasLaterReplacement else { continue }

            parkedUpdate.status = "completed"
            parkedUpdate.completedAt = completedAt
            didChange = true

            guard let eventId = mentionEventId(from: parkedUpdate) else {
                continue
            }
            for dispatch in operations where
                isDispatchOperation(dispatch)
                    && dispatch.entityId.lowercased() == eventId
                    && dispatch.status != "completed"
            {
                dispatch.status = "completed"
                dispatch.completedAt = completedAt
            }
        }

        return didChange
    }

    /// Prepares a mention operation for explicit discard. The discarded
    /// update's uncommitted event dispatch is removed with it, while later
    /// full-authoritative replacements inherit the discarded node's upstream
    /// dependency. No surviving operation retains a dangling UUID.
    static func prepareForDiscard(
        _ operation: SyncOperation,
        in operations: [SyncOperation]
    ) -> Set<UUID> {
        var discardedIds = Set([operation.id])
        let discardsUncreatedNote = isProjectNoteCreateOperation(operation)
        guard bypassesGenericCoalescing(operation)
                || discardsUncreatedNote else {
            return discardedIds
        }

        if discardsUncreatedNote {
            let noteId = operation.entityId.lowercased()
            for sameNoteWrite in operations where
                sameNoteWrite.id != operation.id
                    && sameNoteWrite.entityType
                        == SyncEntityType.projectNote.rawValue
                    && sameNoteWrite.entityId.lowercased() == noteId
                    && sameNoteWrite.status != "completed"
            {
                discardedIds.insert(sameNoteWrite.id)
            }
            let descendantUpdates = operations.filter {
                isUpdateOperation($0)
                    && $0.entityId.lowercased() == noteId
            }
            discardedIds.formUnion(descendantUpdates.map(\.id))
            let descendantEventIds = Set(
                descendantUpdates.compactMap {
                    mentionEventId(from: $0)
                }
            )
            for dispatch in operations where
                isDispatchOperation(dispatch)
                    && descendantEventIds.contains(
                        dispatch.entityId.lowercased()
                    )
            {
                discardedIds.insert(dispatch.id)
            }
        } else if isUpdateOperation(operation),
           let eventId = mentionEventId(from: operation) {
            for dispatch in operations where
                isDispatchOperation(dispatch)
                    && dispatch.entityId.lowercased() == eventId
            {
                discardedIds.insert(dispatch.id)
            }
        }

        return discardedIds
    }

    /// Plans every surviving dependency edge that cancellation will mutate.
    /// Keeping this plan explicit lets failed-discard recovery restore only
    /// those precise fields rather than rolling unrelated queue rows backward.
    static func dependencyRewiresForDiscard(
        discardedIds: Set<UUID>,
        in operations: [SyncOperation]
    ) -> [DiscardDependencyRewire] {
        let discardedIdStrings = Set(
            discardedIds.map { $0.uuidString.lowercased() }
        )
        let discardedById = Dictionary(
            uniqueKeysWithValues: operations.compactMap {
                candidate -> (String, SyncOperation)? in
                guard discardedIds.contains(candidate.id) else { return nil }
                return (candidate.id.uuidString.lowercased(), candidate)
            }
        )

        func survivingDependency(from dependency: String?) -> String? {
            var candidate = dependency
            var visited = Set<String>()
            while let current = candidate?.lowercased(),
                  discardedIdStrings.contains(current),
                  visited.insert(current).inserted {
                candidate = discardedById[current]?.dependsOnId
            }
            return candidate
        }

        return operations.compactMap {
            candidate -> DiscardDependencyRewire? in
            guard !discardedIds.contains(candidate.id) else {
                return nil
            }
            guard let dependency = candidate.dependsOnId?.lowercased(),
                  discardedIdStrings.contains(dependency) else {
                return nil
            }
            return DiscardDependencyRewire(
                operation: candidate,
                replacementDependency: survivingDependency(
                    from: discardedById[dependency]?.dependsOnId
                )
            )
        }
    }

    /// Applies a previously planned dependency change only after the caller has
    /// entered the same SwiftData transaction that reconciles note state and
    /// deletes the discarded operations.
    static func applyDiscardRewires(
        _ rewires: [DiscardDependencyRewire]
    ) {
        for rewire in rewires {
            rewire.operation.dependsOnId = rewire.replacementDependency
        }
    }

    /// Captures every queue field plus the complete note before cancellation
    /// mutates registered SwiftData models. This covers dependency rewires,
    /// note reconciliation/tombstones, and every object scheduled for deletion.
    static func discardStateSnapshot(
        note: ProjectNote?,
        operations: [SyncOperation]
    ) -> DiscardStateSnapshot {
        DiscardStateSnapshot(
            operations: operations
                .map(DiscardOperationSnapshot.init)
                .sorted {
                    $0.id.uuidString < $1.id.uuidString
                },
            note: note.map(DiscardNoteSnapshot.init)
        )
    }

    /// Captures only state that cancellation is about to mutate: complete rows
    /// for operations it deletes, prior dependency values for surviving rows it
    /// rewires, and the affected note. Unrelated queue lifecycle changes remain
    /// owned by their executing context.
    static func discardRecoverySnapshot(
        note: ProjectNote?,
        noteMutation: DiscardNoteMutation?,
        operations: [SyncOperation],
        discardedIds: Set<UUID>,
        dependencyRewires: [DiscardDependencyRewire]
    ) -> DiscardRecoverySnapshot {
        let noteSnapshot: DiscardNoteRecoverySnapshot?
        if let note, let noteMutation {
            switch noteMutation {
            case .delete:
                noteSnapshot = .delete(
                    DiscardDeleteNoteSnapshot(note)
                )
            case .mentionUpdate:
                noteSnapshot = .mentionUpdate(
                    DiscardMentionUpdateNoteSnapshot(note)
                )
            case .offlineCreateDeletion:
                noteSnapshot = .offlineCreateDeletion(
                    DiscardNoteSnapshot(note)
                )
            }
        } else {
            noteSnapshot = nil
        }

        return DiscardRecoverySnapshot(
            discardedOperations: operations
                .filter {
                    discardedIds.contains($0.id)
                }
                .map(DiscardOperationSnapshot.init)
                .sorted {
                    $0.id.uuidString < $1.id.uuidString
                },
            rewiredDependencies: dependencyRewires
                .map {
                    DiscardDependencySnapshot(
                        operationId: $0.operation.id,
                        dependsOnId: $0.operation.dependsOnId
                    )
                }
                .sorted {
                    $0.operationId.uuidString
                        < $1.operationId.uuidString
                },
            note: noteSnapshot
        )
    }

    /// Restores only cancellation-owned state after a thrown transaction.
    /// Rollback alone is insufficient on current SwiftData because registered
    /// values and pending deletions can survive. A surviving rewired row is
    /// never recreated if another context legitimately removed it.
    static func restoreDiscardState(
        _ snapshot: DiscardRecoverySnapshot,
        in modelContext: ModelContext
    ) throws {
        modelContext.rollback()

        var operationsById = Dictionary(
            uniqueKeysWithValues: try modelContext
                .fetch(FetchDescriptor<SyncOperation>())
                .map {
                    ($0.id, $0)
                }
        )
        for operationSnapshot in snapshot.discardedOperations {
            if let operation = operationsById[operationSnapshot.id] {
                operationSnapshot.restore(operation)
            } else {
                let restored = operationSnapshot.restoredModel()
                modelContext.insert(restored)
                operationsById[restored.id] = restored
            }
        }
        for dependencySnapshot in snapshot.rewiredDependencies {
            operationsById[dependencySnapshot.operationId]?.dependsOnId =
                dependencySnapshot.dependsOnId
        }

        if let noteSnapshot = snapshot.note {
            switch noteSnapshot {
            case .delete(let deleteSnapshot):
                if let note = try fetchProjectNote(
                    matching: deleteSnapshot.id,
                    in: modelContext
                ) {
                    deleteSnapshot.restore(note)
                }
            case .mentionUpdate(let updateSnapshot):
                if let note = try fetchProjectNote(
                    matching: updateSnapshot.id,
                    in: modelContext
                ) {
                    updateSnapshot.restore(note)
                }
            case .offlineCreateDeletion(let fullSnapshot):
                if try fetchProjectNote(
                    matching: fullSnapshot.id,
                    in: modelContext
                ) == nil {
                    modelContext.insert(fullSnapshot.restoredModel())
                }
            }
        }

        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    /// Restores the optimistic ProjectNote to the queue state that will
    /// actually reach the server after an explicit discard. A surviving later
    /// or earlier update wins; otherwise the discarded operation's persisted
    /// pre-edit snapshot becomes authoritative again.
    static func reconciledNoteStateAfterDiscard(
        _ operation: SyncOperation,
        discardedIds: Set<UUID>,
        in operations: [SyncOperation]
    ) -> ReconciledNoteState? {
        guard isUpdateOperation(operation) else { return nil }
        let noteId = operation.entityId.lowercased()
        let unresolvedStatuses = Set([
            "pending",
            "inProgress",
            "failed",
            "parked",
        ])
        let hasSurvivingSameNoteWrite = operations.contains {
            !discardedIds.contains($0.id)
                && $0.entityType == SyncEntityType.projectNote.rawValue
                && $0.entityId.lowercased() == noteId
                && unresolvedStatuses.contains($0.status)
                && (
                    isUpdateOperation($0)
                        || ["create", "update", "delete"]
                            .contains($0.operationType)
                )
        }
        let survivingUpdate = operations
            .filter {
                !discardedIds.contains($0.id)
                    && isUpdateOperation($0)
                    && $0.entityId.lowercased() == noteId
            }
            .max {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }

        if let survivingUpdate,
           let payload = payloadObject(from: survivingUpdate),
           let content = payload[contentPayloadKey] as? String,
           let mentionedUserIds =
                payload[mentionedUserIdsPayloadKey] as? [String] {
            return ReconciledNoteState(
                content: content,
                mentionedUserIds: mentionedUserIds,
                needsSync:
                    survivingUpdate.status != "completed"
                        || hasSurvivingSameNoteWrite,
                updatedAt: survivingUpdate.createdAt
            )
        }

        guard let payload = payloadObject(from: operation),
              let content = payload[previousContentPayloadKey] as? String,
              let mentionedUserIds =
                payload[previousMentionedUserIdsPayloadKey] as? [String]
        else {
            return nil
        }
        let previousUpdatedAt: Date?
        if payload.keys.contains(previousUpdatedAtPayloadKey) {
            previousUpdatedAt = date(
                from: payload[previousUpdatedAtPayloadKey]
            )
        } else {
            // Older queue rows predate the explicit nullable snapshot field.
            previousUpdatedAt = operation.createdAt
        }
        return ReconciledNoteState(
            content: content,
            mentionedUserIds: mentionedUserIds,
            needsSync:
                (payload[previousNeedsSyncPayloadKey] as? Bool ?? false)
                    || hasSurvivingSameNoteWrite,
            updatedAt: previousUpdatedAt
        )
    }

    private static func payloadObject(
        from operation: SyncOperation
    ) -> [String: Any]? {
        try? JSONSerialization.jsonObject(
            with: operation.payload
        ) as? [String: Any]
    }

    private static func date(from value: Any?) -> Date? {
        if let interval = value as? TimeInterval {
            return Date(timeIntervalSince1970: interval)
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        return nil
    }

    private static func mentionEventId(from update: SyncOperation) -> String? {
        guard isUpdateOperation(update),
              let payload = try? JSONSerialization.jsonObject(
                with: update.payload
              ) as? [String: Any],
              let eventId = payload[eventIdPayloadKey] as? String else {
            return nil
        }
        return eventId.lowercased()
    }

    /// Returns whether another dependency-ordered mention operation can run
    /// immediately. `SyncEngine.pushPending()` uses this after each outbound
    /// pass so an update completion releases its dependent update/dispatch in
    /// the same drain instead of waiting for a future sync trigger.
    static func readyPendingOperationIds(
        in operations: [SyncOperation],
        now: Date = Date()
    ) -> Set<UUID> {
        let statusById = Dictionary(
            uniqueKeysWithValues: operations.map {
                ($0.id.uuidString.lowercased(), $0.status)
            }
        )

        return Set(operations.compactMap { operation -> UUID? in
            guard operation.status == "pending",
                  isDependencyDrainOperation(operation) else {
                return nil
            }
            if operation.retryCount > 0,
               let lastAttemptedAt = operation.lastAttemptedAt,
               now < lastAttemptedAt.addingTimeInterval(operation.backoffDelay) {
                return nil
            }
            guard let dependencyId = operation.dependsOnId,
                  !dependencyId.isEmpty else {
                return operation.id
            }
            return statusById[dependencyId.lowercased()] == "completed"
                ? operation.id
                : nil
        })
    }

    /// Revalidates a previously-snapshotted mention operation immediately
    /// before execution. A later edit can retarget a dispatch while an earlier
    /// unrelated request is suspended; only the current persisted dependency
    /// graph may authorize entering `inProgress`.
    static func isReadyForExecution(
        _ operation: SyncOperation,
        in operations: [SyncOperation],
        now: Date = Date()
    ) -> Bool {
        guard isDependencyDrainOperation(operation) else { return true }
        return readyPendingOperationIds(
            in: operations,
            now: now
        ).contains(operation.id)
    }

    /// Claims one operation against a persisted owning-context snapshot while
    /// sharing the process-wide queue gate with edit/delete mutations. For the
    /// long-lived DataActor, refresh happens inside the gate immediately before
    /// the transaction, so no retarget/delete commit can land in between.
    static func claimForExecution(
        _ operation: SyncOperation,
        context: ModelContext,
        refreshFromStore: Bool,
        now: Date = Date()
    ) throws -> Bool {
        try ProjectNoteMentionQueueCoordinator.shared.claim(
            operationId: operation.id
        ) {
            if refreshFromStore {
                context.rollback()
            }
            var didClaim = false
            try context.transaction {
                let operationId = operation.id
                let descriptor = FetchDescriptor<SyncOperation>(
                    predicate: #Predicate {
                        $0.id == operationId
                    }
                )
                guard let persistedOperation =
                    try context.fetch(descriptor).first,
                    persistedOperation.status == "pending" else {
                    return
                }
                if isDependencyDrainOperation(persistedOperation) {
                    let operations = try context.fetch(
                        FetchDescriptor<SyncOperation>()
                    )
                    guard isReadyForExecution(
                        persistedOperation,
                        in: operations,
                        now: now
                    ) else {
                        return
                    }
                }
                persistedOperation.status = "inProgress"
                persistedOperation.lastAttemptedAt = now
                didClaim = true
            }
            return didClaim
        }
    }

    /// A permanently rejected create is proven absent from the server. When a
    /// delete is already queued for that local-only note, complete the entire
    /// chain locally instead of leaving the delete dependent forever.
    @discardableResult
    static func retireParkedCreateWithQueuedDelete(
        _ create: SyncOperation,
        in operations: [SyncOperation],
        completedAt: Date = Date()
    ) -> Bool {
        guard isProjectNoteCreateOperation(create),
              create.status == "parked" else {
            return false
        }
        let noteId = create.entityId.lowercased()
        let hasQueuedDelete = operations.contains {
            $0.entityType == SyncEntityType.projectNote.rawValue
                && $0.entityId.lowercased() == noteId
                && $0.operationType == "delete"
                && $0.status != "completed"
        }
        guard hasQueuedDelete else { return false }

        let updates = operations.filter {
            isUpdateOperation($0)
                && $0.entityId.lowercased() == noteId
        }
        let eventIds = Set(
            updates.compactMap { mentionEventId(from: $0) }
        )
        for operation in operations {
            let isSameNoteWrite =
                operation.entityType
                    == SyncEntityType.projectNote.rawValue
                    && operation.entityId.lowercased() == noteId
            let isSameNoteDispatch =
                isDispatchOperation(operation)
                    && eventIds.contains(
                        operation.entityId.lowercased()
                    )
            guard isSameNoteWrite || isSameNoteDispatch else { continue }
            operation.status = "completed"
            operation.completedAt = completedAt
            operation.lastError = nil
        }
        return true
    }

    static func shouldContinueDrain(
        readyBeforePass: Set<UUID>,
        readyAfterPass: Set<UUID>
    ) -> Bool {
        !readyAfterPass.isEmpty && readyAfterPass != readyBeforePass
    }

    static func executeIfHandled(
        entityType: String,
        operationType: String,
        payload: [String: Any],
        companyId: String
    ) async throws -> Bool {
        guard entityType == SyncEntityType.projectNote.rawValue else {
            return false
        }

        switch operationType {
        case updateOperationType:
            guard let noteId = payload[noteIdPayloadKey] as? String,
                  let content = payload[contentPayloadKey] as? String,
                  let mentionedUserIds = payload[mentionedUserIdsPayloadKey] as? [String],
                  let mentionEventId = payload[eventIdPayloadKey] as? String else {
                throw SyncError.encodingFailed(
                    detail: "project-note mention update payload is incomplete"
                )
            }

            try await ProjectNoteRepository(companyId: companyId).updateMentions(
                noteId,
                content: content,
                mentionedUserIds: mentionedUserIds,
                mentionEventId: mentionEventId
            )
            return true

        case dispatchOperationType:
            guard let mentionEventId = payload[eventIdPayloadKey] as? String else {
                throw SyncError.encodingFailed(
                    detail: "project-note mention dispatch payload is missing its event id"
                )
            }
            try await ProjectNoteMentionDispatchService.dispatch(
                mentionEventId: mentionEventId
            )
            return true

        default:
            return false
        }
    }
}

enum ProjectNoteMentionDispatchService {
    static func dispatch(mentionEventId: String) async throws {
        let token = try await FirebaseAuthService.shared.getIDToken()
        let endpoint = AppConfiguration.apiBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("notifications")
            .appendingPathComponent("dispatch")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ProjectNoteMentionDispatchRequest(mentionEventId: mentionEventId)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.serverError(
                statusCode: 0,
                message: "notification dispatcher returned an invalid response"
            )
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "unknown response"
            throw SyncError.serverError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }
}
