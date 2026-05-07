//
//  ComponentEmitter.swift
//  OPS
//
//  Projects a DeckDrawingData into the catalog adapter's `components`
//  vocabulary — one row per visible component (railing, deck_board,
//  stair_set, gate, post_set) with metadata keys the adapter consumes.
//
//  Pure projection — no source-of-truth duplication. Recomputed from
//  geometry on every save via DeckDrawingData.toJSON().
//
//  Spec: docs/superpowers/specs/2026-05-07-deck-builder-catalog-integration-design.md
//  Adapter contract: OPS/Services/DesignToEstimateAdapter.swift
//

import Foundation

enum ComponentEmitter {
    /// Returns the `components` array as Codable rows, ready for inclusion
    /// in DeckDrawingData's JSON. Pure function — no I/O, no side effects.
    /// Multi-level designs flatten components across levels with a
    /// `level_id` metadata key for downstream traceability.
    ///
    /// Phase 1 ships the scaffolding (data model + file location) so the
    /// build-side contract is established. Phase 2 fills in the per-type
    /// projection logic.
    static func emit(_ data: DeckDrawingData) -> [DesignComponentRow] {
        return []
    }
}

/// One row in `DeckDrawingData.components` — the projection
/// `DesignToEstimateAdapter` consumes. `componentType` matches the
/// catalog's `DesignComponentType` raw values (`railing`, `deck_board`,
/// `stair_set`, `gate`, `post_set`). Adding component_type strings is
/// fine; renaming is a contract break.
struct DesignComponentRow: Codable, Equatable {
    let componentType: String
    let metadata: [String: AnyCodable]

    enum CodingKeys: String, CodingKey {
        case componentType = "component_type"
        case metadata
    }

    init(componentType: String, metadata: [String: AnyCodable]) {
        self.componentType = componentType
        self.metadata = metadata
    }
}

/// Thin Codable wrapper that round-trips Int / Double / String / Bool
/// through JSONEncoder/JSONDecoder. Kept narrow on purpose: the
/// components projection only needs scalar metadata values.
///
/// Also used by `ProductConfigurationResolver.Resolution.serializedOptions`
/// for line_item snapshot serialization (encode-only path).
struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ v: Any) { self.value = v }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self.value = NSNull()
        } else if let b = try? c.decode(Bool.self) {
            self.value = b
        } else if let i = try? c.decode(Int.self) {
            self.value = i
        } else if let d = try? c.decode(Double.self) {
            self.value = d
        } else if let s = try? c.decode(String.self) {
            self.value = s
        } else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Unsupported AnyCodable scalar type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let s as String: try c.encode(s)
        case let b as Bool:   try c.encode(b)
        case let i as Int:    try c.encode(i)
        case let d as Double: try c.encode(d)
        case is NSNull:       try c.encodeNil()
        default:              try c.encodeNil()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (let l as String, let r as String): return l == r
        case (let l as Bool, let r as Bool):     return l == r
        case (let l as Int, let r as Int):       return l == r
        case (let l as Double, let r as Double): return l == r
        case (is NSNull, is NSNull):             return true
        default: return false
        }
    }
}
