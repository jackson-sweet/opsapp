// OPS/OPS/DeckBuilder/Services/VinylOrderActivityNote.swift
//
// Builds the project-activity entry for a completed vinyl disposition.
//
// WHY A PROJECT NOTE: the project Activity tab is a `ProjectNote` feed with a
// system-event discriminator (`event_kind`) — that is how site-visit packets and
// web status changes already land there. Reusing it means the vinyl record shows
// up chronologically among the photos and notes the operator is already reading,
// syncs to web for free, and needs no schema change: `project_notes.event_kind`
// (text) and `content_metadata` (jsonb) both exist today.
//
// `content` carries the plain-text record in the exact shape Jackson sketched —
// so web, older iOS builds, and anything that only knows `content` still read a
// complete, honest entry. `content_metadata` carries the same record structured,
// which is what the rich iOS feed card renders from.
//
// Pure string/JSON assembly: no SwiftUI, no SwiftData, no I/O.

import Foundation

enum VinylOrderActivityNote {
    /// `project_notes.event_kind` for this entry. Bare strings are the existing
    /// convention (`site_visit`, `status_change`) — there is no shared enum.
    static let eventKind = "vinyl_order"

    /// One built entry, ready to insert as a `ProjectNote`.
    struct Built: Equatable {
        var content: String
        var metadataJSON: String?
    }

    /// The record for one job.
    ///
    /// `vinylLines` are the purchased vinyl lines (`2 @ 9'6"`, or the whole-roll
    /// line). `consumables` are the purchased tube/bucket lines, each carrying
    /// the other jobs it was split across.
    struct Record: Equatable {
        var disposition: VinylOrderDisposition
        var color: String?
        var po: String?
        var vinylLines: [String]
        var consumables: [VinylSharedConsumable]
        var orderedAt: Date

        init(
            disposition: VinylOrderDisposition,
            color: String? = nil,
            po: String? = nil,
            vinylLines: [String],
            consumables: [VinylSharedConsumable],
            orderedAt: Date
        ) {
            self.disposition = disposition
            self.color = Self.normalized(color)
            self.po = Self.normalized(po)
            self.vinylLines = vinylLines
            self.consumables = consumables
            self.orderedAt = orderedAt
        }

        /// The record implied by a frozen snapshot — the single source every
        /// entry point builds from, so the feed can never disagree with the
        /// ordered card.
        init(snapshot: DeckMaterialsSnapshot) {
            self.init(
                disposition: snapshot.disposition,
                color: snapshot.vinylColor,
                po: snapshot.po,
                vinylLines: snapshot.orderedVinylLines,
                consumables: snapshot.orderedConsumables,
                orderedAt: snapshot.orderedAt
            )
        }

        private static func normalized(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        /// True when the disposition was recorded but nothing was actually
        /// obtained — a shop pull of material already on hand, or a marker-only
        /// job with no resolvable materials.
        var isEmpty: Bool { vinylLines.isEmpty && consumables.isEmpty }
    }

    /// Assemble the entry. Returns nil only when there is nothing at all to
    /// say — never write an empty feed row.
    ///
    /// Shape (sentence case: this is content, not a label):
    ///
    ///     Vinyl ordered:
    ///     - 2 @ 9'6"
    ///     - 3 @ 10'6"
    ///     - 3 tubes 90 flash (shared with 12 Oak St, Maple Rd)
    ///     - 1 bucket glue (shared with 12 Oak St, Maple Rd)
    static func build(_ record: Record) -> Built? {
        var lines: [String] = [record.disposition.activityLead]

        if let color = record.color {
            lines.append("- \(color)")
        }
        lines.append(contentsOf: record.vinylLines.map { "- \($0)" })
        lines.append(contentsOf: record.consumables.map { "- \($0.activityLine)" })

        if record.isEmpty {
            // Nothing was obtained. The disposition is still worth recording —
            // "we used what was on the rack" is the answer to "did anyone order
            // this?" — but it gets a plain sentence, not an empty bullet list.
            lines = [
                record.disposition == .shop
                    ? "Vinyl pulled from shop. Nothing ordered."
                    : "Vinyl marked ordered."
            ]
            if let color = record.color { lines.append("- \(color)") }
        }

        if let po = record.po {
            lines.append("PO \(po)")
        }

        let content = lines.joined(separator: "\n")
        guard !content.isEmpty else { return nil }
        return Built(content: content, metadataJSON: metadataJSON(record))
    }

    /// Structured mirror of the same record for `content_metadata`. Keys are a
    /// stable contract shared with web — snake_case, matching the column style.
    static func metadataJSON(_ record: Record) -> String? {
        var object: [String: Any] = [
            "disposition": record.disposition.rawValue,
            "ordered_at": ISO8601DateFormatter().string(from: record.orderedAt),
            "vinyl_lines": record.vinylLines,
            "consumables": record.consumables.map { consumable -> [String: Any] in
                var entry: [String: Any] = [
                    "kind": consumable.kind.rawValue,
                    "count": consumable.count,
                    "label": consumable.kind.displayLabel,
                    "value": consumable.recordValue
                ]
                if consumable.isShared {
                    entry["shared_with"] = consumable.sharedWith
                }
                return entry
            }
        ]
        if let color = record.color { object["color"] = color }
        if let po = record.po { object["po"] = po }

        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }
}

/// The decoded `content_metadata` of a `vinyl_order` note — what the feed card
/// renders. Tolerant by construction: a note written by a newer build, or one
/// carrying only `content`, degrades to nil and the feed falls back to the
/// plain-text body rather than dropping the entry.
struct VinylOrderActivityMetadata: Equatable {
    struct Consumable: Equatable {
        var label: String
        var value: String
        var sharedWith: [String]

        var sharedSupportLine: String? {
            guard !sharedWith.isEmpty else { return nil }
            return "SHARED WITH \(sharedWith.joined(separator: ", ").uppercased())"
        }
    }

    var disposition: VinylOrderDisposition
    var color: String?
    var po: String?
    var vinylLines: [String]
    var consumables: [Consumable]

    init?(json: String?) {
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        self.disposition = VinylOrderDisposition(
            rawValue: (object["disposition"] as? String) ?? ""
        ) ?? .supplier
        self.color = (object["color"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.po = (object["po"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.vinylLines = (object["vinyl_lines"] as? [String]) ?? []
        self.consumables = ((object["consumables"] as? [[String: Any]]) ?? []).compactMap { entry in
            guard let label = entry["label"] as? String,
                  let value = entry["value"] as? String else { return nil }
            return Consumable(
                label: label,
                value: value,
                sharedWith: (entry["shared_with"] as? [String]) ?? []
            )
        }
    }
}
