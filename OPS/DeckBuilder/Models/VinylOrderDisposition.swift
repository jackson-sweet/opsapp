// OPS/OPS/DeckBuilder/Models/VinylOrderDisposition.swift
//
// WHERE a job's vinyl material came from. Both dispositions end the same way —
// the job's material is handled and it leaves the VINYL ORDERS board — so this
// is a property of one act, not two features:
//   • `.supplier` — an order was placed with a supplier.
//   • `.shop`     — the material was pulled off the shop rack; nothing ordered.
//
// The project row's `vinyl_order_status` stays `ordered` for BOTH (its CHECK
// constraint allows only `not_ordered`/`ordered`, and a shipped build that has
// never heard of a third value would read it back as NOT ORDERED and re-surface
// a handled job on the board). The disposition rides in the frozen design
// snapshot and, additively, in `projects.vinyl_source` — see
// `ProjectVinylOrderFields.source`.
//
// Raw values are a stable JSON + column contract. Never rename a case without a
// decode fallback.

import Foundation

enum VinylOrderDisposition: String, Codable, CaseIterable {
    case supplier
    case shop

    /// Segmented-control option label (UPPERCASE authority).
    var sourceLabel: String {
        switch self {
        case .supplier: return "ORDERED"
        case .shop: return "FROM SHOP"
        }
    }

    /// The commit button. `.shop` is the wording Jackson asked for on the MARK
    /// ORDERED form — the act is real, it just was not an order.
    var commitLabel: String {
        switch self {
        case .supplier: return "CONFIRM ORDERED"
        case .shop: return "USE SHOP MATERIAL"
        }
    }

    /// Status value on a record card (`ORDER STATUS` / the ordered-card footer).
    var statusLabel: String {
        switch self {
        case .supplier: return "ORDERED"
        case .shop: return "FROM SHOP"
        }
    }

    /// Past-tense verb for the dated meta line: `ORDERED 14 JUL` / `PULLED 14 JUL`.
    var datePrefix: String {
        switch self {
        case .supplier: return "ORDERED"
        case .shop: return "PULLED"
        }
    }

    /// Activity-feed headline (UPPERCASE authority on the card).
    var activityTitle: String {
        switch self {
        case .supplier: return "VINYL ORDERED"
        case .shop: return "VINYL FROM SHOP"
        }
    }

    /// Lead-in for the plain-text activity body (sentence case — it is content,
    /// not a label). Mirrors the shape Jackson sketched: `Vinyl ordered:`.
    var activityLead: String {
        switch self {
        case .supplier: return "Vinyl ordered:"
        case .shop: return "Vinyl pulled from shop:"
        }
    }

    /// Confirm-sheet hint under the header.
    var confirmHint: String {
        switch self {
        case .supplier: return "Adjust any line to what you actually ordered."
        case .shop: return "Adjust any line to what you actually pulled."
        }
    }

    /// `projects.vinyl_source` value. Kept distinct from the enum's own raw value
    /// so the column contract can never drift silently with a Swift rename.
    var columnValue: String { rawValue }

    static func fromColumnValue(_ raw: String?) -> VinylOrderDisposition {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let value = VinylOrderDisposition(rawValue: raw) else { return .supplier }
        return value
    }
}

/// A consumable bought once and split across several jobs — the whole economics
/// of the bulk order board (4 jobs × 8 drip sticks = 32 sticks = 2 tubes of 30,
/// not 4 over-ordered singles).
///
/// The count stored here is the SHARED count, not this job's fraction. Three
/// tubes bought across four jobs is three tubes; splitting it into 0.75 each
/// would invent a quantity nobody ordered and no one can act on. Every job that
/// took part records the same count plus `sharedWith` — the OTHER jobs' titles —
/// so the record reads honestly from any one of them:
///
///     3 tubes 90 flash (shared with 12 Oak St, Maple Rd)
///
/// `sharedWith` empty ⇒ the line was not shared (single-job order); it renders
/// without the parenthetical.
struct VinylSharedConsumable: Codable, Equatable, Identifiable {
    /// Stable line identity — also the display label source.
    enum Kind: String, Codable, CaseIterable {
        case dripEdge
        case ninetyFlash
        case clip
        case glue

        /// Unit noun used in the activity body: `3 tubes 90 flash`.
        var unit: String {
            switch self {
            case .glue: return "bucket"
            default: return "tube"
            }
        }

        /// Sentence-case material name for the activity body.
        var materialName: String {
            switch self {
            case .dripEdge: return "drip edge"
            case .ninetyFlash: return "90 flash"
            case .clip: return "clip"
            case .glue: return "glue"
            }
        }

        /// UPPERCASE label for record cards.
        var displayLabel: String {
            switch self {
            case .dripEdge: return "DRIP EDGE"
            case .ninetyFlash: return "90 FLASH"
            case .clip: return "CLIP"
            case .glue: return "GLUE"
            }
        }
    }

    var kind: Kind
    /// The shared count as purchased — never a per-job fraction.
    var count: Int
    /// Titles of the OTHER jobs this line was split with. Empty ⇒ not shared.
    var sharedWith: [String]

    var id: String { kind.rawValue }

    init(kind: Kind, count: Int, sharedWith: [String] = []) {
        self.kind = kind
        self.count = count
        self.sharedWith = sharedWith
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case count
        case sharedWith
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .glue
        self.count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        self.sharedWith = try c.decodeIfPresent([String].self, forKey: .sharedWith) ?? []
    }

    var isShared: Bool { !sharedWith.isEmpty }

    /// `3 tubes 90 flash (shared with 12 Oak St, Maple Rd)` — the activity-body
    /// line, in the exact shape Jackson sketched. Sentence case: this is content.
    var activityLine: String {
        let noun = count == 1 ? kind.unit : "\(kind.unit)s"
        var line = "\(count) \(noun) \(kind.materialName)"
        if isShared {
            line += " (shared with \(sharedWith.joined(separator: ", ")))"
        }
        return line
    }

    /// `3 TUBES` — the value column on a record card. The sharing partners ride
    /// on their own support line so the scan column stays a clean number.
    var recordValue: String {
        let noun = count == 1 ? kind.unit.uppercased() : "\(kind.unit.uppercased())S"
        return "\(count) \(noun)"
    }

    /// `SHARED WITH 12 OAK ST, MAPLE RD`, or nil when this line was not split.
    var sharedSupportLine: String? {
        guard isShared else { return nil }
        return "SHARED WITH \(sharedWith.joined(separator: ", ").uppercased())"
    }
}
