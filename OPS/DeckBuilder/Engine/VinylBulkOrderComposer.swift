// OPS/OPS/DeckBuilder/Engine/VinylBulkOrderComposer.swift
//
// Assembles the combined supplier text for a bulk vinyl order (spec § 7):
// one section per job in wizard order — PO line, color line, cut lines (or
// the full-roll line) — blank line between sections, consumables tail last.
// Pure string assembly; cut lines arrive pre-rendered through the user's
// existing cut template + separator preferences, so this composer never
// re-derives geometry.

import Foundation

/// One job's confirmed section, in wizard order.
struct VinylBulkOrderSection: Equatable {
    var po: String
    /// Empty renders as `FIELD CONFIRM` — order now, confirm color later.
    var color: String
    /// Pre-rendered cut lines (`-9 @ 9'`). Empty for color+PO-only jobs.
    var cutLines: [String]
    /// Full-roll jobs: the rolls line rendered in place of cut lines.
    var rollsLine: String?
}

enum VinylBulkOrderComposer {
    static let defaultSectionTemplate = "PO [project]\nColor: [color]\n[cuts]"
    static let sectionTemplateStorageKey = "deckBuilder.vinylOrder.bulkSectionTemplate"
    static let clipPerTubeStorageKey = "deckBuilder.vinylOrder.clipPerTube"
    static let flashingPerTubeStorageKey = "deckBuilder.vinylOrder.flashingPerTube"
    static let defaultClipPerTube = 50
    static let defaultFlashingPerTube = 30

    /// Assemble the full message. `consumables` nil or all-zero ⇒ no tail.
    static func compose(
        sections: [VinylBulkOrderSection],
        consumables: VinylConsumablesSuggestion?,
        sectionTemplate: String = defaultSectionTemplate,
        cutSeparator: VinylCutListSeparator = .lines
    ) -> String {
        let trimmedTemplate = sectionTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = trimmedTemplate.isEmpty ? defaultSectionTemplate : sectionTemplate

        var blocks = sections
            .map { renderSection($0, template: template, cutSeparator: cutSeparator) }
            .filter { !$0.isEmpty }

        if let tail = consumablesTail(consumables) {
            blocks.append(tail)
        }
        return blocks.joined(separator: "\n\n")
    }

    /// The consumables lines alone (`-2 tubes drip edge` …), or nil when every
    /// count is zero. Tube lines carry NO stick lengths (spec § 12.6).
    static func consumablesTail(_ suggestion: VinylConsumablesSuggestion?) -> String? {
        guard let s = suggestion else { return nil }
        var lines: [String] = []
        if s.dripTubes > 0 { lines.append("-\(s.dripTubes) tube\(s.dripTubes == 1 ? "" : "s") drip edge") }
        if s.ninetyTubes > 0 { lines.append("-\(s.ninetyTubes) tube\(s.ninetyTubes == 1 ? "" : "s") 90 flash") }
        if s.clipTubes > 0 { lines.append("-\(s.clipTubes) tube\(s.clipTubes == 1 ? "" : "s") clip") }
        if s.glueBuckets > 0 { lines.append("-\(s.glueBuckets) bucket\(s.glueBuckets == 1 ? "" : "s") glue") }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func renderSection(
        _ section: VinylBulkOrderSection,
        template: String,
        cutSeparator: VinylCutListSeparator
    ) -> String {
        let color = section.color.isEmpty ? "FIELD CONFIRM" : section.color
        let cuts = section.rollsLine ?? section.cutLines.joined(separator: cutSeparator.separator)

        var rendered = VinylCutListTextTemplate.replacingTokens(
            in: template,
            replacements: [
                "project": section.po.trimmingCharacters(in: .whitespacesAndNewlines),
                "color": color,
                "cuts": cuts
            ]
        )

        if cuts.isEmpty {
            // Color+PO-only job: the empty [cuts] token leaves its line blank —
            // drop blank lines so the section ends clean, no dangling artifact.
            rendered = rendered
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: "\n")
        }
        return rendered.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
