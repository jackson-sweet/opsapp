// OPS/OPS/DeckBuilder/Models/VinylOrderMode.swift
//
// How vinyl membrane is purchased for a deck job:
//   • `.cutList`   — buy the exact itemized strips the cut plan produces.
//   • `.fullRolls` — buy whole rolls; the required strips are packed into the
//     fewest full rolls (see `VinylRollPacker`). The itemized cut list stays
//     visible as the on-site cutting guide.
//
// Persisted per-design inside `DeckMaterialsSettings` (which rides in
// `DeckDrawingData` JSON). Raw values are the stable JSON contract — never
// rename a case without a decode fallback. Sticks and glue are unaffected by
// this choice; only how the membrane is ordered changes.

import Foundation

enum VinylOrderMode: String, Codable, CaseIterable {
    case cutList
    case fullRolls
}
