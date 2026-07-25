// OPS/OPS/DeckBuilder/Engine/VinylRollPacker.swift
//
// Full-roll ordering math (spec § 4.1). Given the strip lengths a cut plan
// requires and the length of one full roll, returns a deterministic whole-roll
// packing — a single strip is cut from ONE roll and never spans two.
//
// First-fit-decreasing bin-packing: sort strips longest-first, drop each into
// the first roll that still has room, else open a new roll. FFD is the standard
// near-optimal heuristic for 1-D bin packing and is deterministic (stable order),
// so the same design always packs to the same roll count.
//
// A strip longer than a whole roll cannot be produced at this roll length; it is
// reported via `overlengthStripCount` (never silently dropped) so the UI can warn
// CUT LONGER THAN ROLL. Sticks and glue are unaffected by roll packing — this is
// purely how the vinyl membrane is purchased.

import Foundation

/// Result of packing strips into full rolls: the roll count to order and how many
/// requested strips exceed a single roll's length (which cannot be produced at
/// this roll length and are excluded from the packed count).
struct RollPackResult: Equatable {
    let rollCount: Int
    let overlengthStripCount: Int
}

/// One opened roll and the strips assigned to it by first-fit-decreasing.
struct VinylPackedRoll: Equatable {
    let capacityFeet: Double
    let stripLengthsFeet: [Double]

    var usedFeet: Double {
        stripLengthsFeet.reduce(0, +)
    }

    var leftoverFeet: Double {
        max(0, capacityFeet - usedFeet)
    }
}

/// The complete deterministic packing result, including material usage for each
/// opened roll and every strip that cannot be produced at the requested length.
struct VinylRollPackingPlan: Equatable {
    let rolls: [VinylPackedRoll]
    let overlengthStripLengthsFeet: [Double]

    var summary: RollPackResult {
        RollPackResult(
            rollCount: rolls.count,
            overlengthStripCount: overlengthStripLengthsFeet.count
        )
    }
}

enum VinylRollPacker {
    private static let epsilon = 1e-6

    /// First-fit-decreasing roll count for every producible strip in
    /// `stripLengthsFeet`. Each strip consumes its own length from ONE roll and
    /// never spans two. A strip longer than a roll is counted in
    /// `overlengthStripCount` and excluded from the packed rolls.
    ///
    /// A non-positive `rollLengthFeet` yields no valid roll, so every strip is
    /// unproducible: `(rollCount: 0, overlengthStripCount: stripLengthsFeet.count)`.
    static func rollsNeeded(stripLengthsFeet: [Double], rollLengthFeet: Double) -> RollPackResult {
        packingPlan(
            stripLengthsFeet: stripLengthsFeet,
            rollLengthFeet: rollLengthFeet
        ).summary
    }

    /// Deterministic first-fit-decreasing assignments with the used and
    /// remaining material retained for each opened roll.
    static func packingPlan(
        stripLengthsFeet: [Double],
        rollLengthFeet: Double
    ) -> VinylRollPackingPlan {
        guard rollLengthFeet > epsilon else {
            return VinylRollPackingPlan(
                rolls: [],
                overlengthStripLengthsFeet: stripLengthsFeet.sorted(by: >)
            )
        }

        var overlengthStripLengthsFeet: [Double] = []
        var packable: [Double] = []
        for length in stripLengthsFeet {
            if length > rollLengthFeet + epsilon {
                overlengthStripLengthsFeet.append(length)
            } else if length > epsilon {
                packable.append(length)
            }
        }

        // Longest-first: the FFD ordering that minimizes wasted roll capacity.
        let sorted = packable.sorted(by: >)
        var rollStripLengths: [[Double]] = []
        var rollRemaining: [Double] = []

        for length in sorted {
            if let index = rollRemaining.firstIndex(where: { $0 + epsilon >= length }) {
                rollStripLengths[index].append(length)
                rollRemaining[index] -= length
            } else {
                rollStripLengths.append([length])
                rollRemaining.append(rollLengthFeet - length)
            }
        }

        let rolls = rollStripLengths.map { lengths in
            return VinylPackedRoll(
                capacityFeet: rollLengthFeet,
                stripLengthsFeet: lengths
            )
        }

        return VinylRollPackingPlan(
            rolls: rolls,
            overlengthStripLengthsFeet: overlengthStripLengthsFeet.sorted(by: >)
        )
    }
}
