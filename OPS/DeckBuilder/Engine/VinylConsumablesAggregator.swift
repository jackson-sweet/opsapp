// OPS/OPS/DeckBuilder/Engine/VinylConsumablesAggregator.swift
//
// Cross-job consumables math for the bulk vinyl order (spec § 7): sticks are
// summed across every job FIRST, then one ceil per flashing type converts the
// total to tubes — that is the economics of batching (4 jobs × 8 drip sticks
// = 32 sticks = 2 tubes of 30, not 4 over-ordered singles). Glue sums each
// job's area/coverage ratio (per-design coverage respected), one final
// round-up to buckets. Pure — no SwiftUI, no SwiftData.

import Foundation

/// One job's contribution to the shared consumables order, read from its
/// resolved `DeckMaterialsList` + per-design `DeckMaterialsSettings`.
struct VinylConsumableNeed: Equatable {
    var dripSticks: Int
    var ninetySticks: Int
    var clipSticks: Int
    var glueAreaSqFt: Double
    var glueCoverageSqFt: Double
}

/// The suggested order: tube/bucket counts plus the raw totals that back the
/// support copy (`NEED 14 STICKS` / `NEED 6.2 BUCKETS`).
struct VinylConsumablesSuggestion: Equatable {
    var dripTubes: Int
    var ninetyTubes: Int
    var clipTubes: Int
    var glueBuckets: Int
    var totalDripSticks: Int
    var totalNinetySticks: Int
    var totalClipSticks: Int
    var exactGlueBuckets: Double
}

enum VinylConsumablesAggregator {

    static func suggest(
        needs: [VinylConsumableNeed],
        clipPerTube: Int,
        flashingPerTube: Int
    ) -> VinylConsumablesSuggestion {
        let clipCapacity = max(1, clipPerTube)
        let flashingCapacity = max(1, flashingPerTube)

        let dripSticks = needs.reduce(0) { $0 + max(0, $1.dripSticks) }
        let ninetySticks = needs.reduce(0) { $0 + max(0, $1.ninetySticks) }
        let clipSticks = needs.reduce(0) { $0 + max(0, $1.clipSticks) }

        // Zero/negative coverage rows contribute nothing rather than poisoning
        // the sum with a division blow-up.
        let exactGlue = needs.reduce(0.0) { total, need in
            guard need.glueCoverageSqFt > 0, need.glueAreaSqFt > 0 else { return total }
            return total + (need.glueAreaSqFt / need.glueCoverageSqFt)
        }

        return VinylConsumablesSuggestion(
            dripTubes: tubes(for: dripSticks, perTube: flashingCapacity),
            ninetyTubes: tubes(for: ninetySticks, perTube: flashingCapacity),
            clipTubes: tubes(for: clipSticks, perTube: clipCapacity),
            glueBuckets: exactGlue > 0 ? Int(ceil(exactGlue)) : 0,
            totalDripSticks: dripSticks,
            totalNinetySticks: ninetySticks,
            totalClipSticks: clipSticks,
            exactGlueBuckets: exactGlue
        )
    }

    private static func tubes(for sticks: Int, perTube: Int) -> Int {
        guard sticks > 0 else { return 0 }
        return Int(ceil(Double(sticks) / Double(perTube)))
    }
}
