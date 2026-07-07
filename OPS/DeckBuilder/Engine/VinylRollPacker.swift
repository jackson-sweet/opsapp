// OPS/OPS/DeckBuilder/Engine/VinylRollPacker.swift
//
// Full-roll ordering math (spec § 4.1). Given the strip lengths a cut plan
// requires and the length of one full roll, returns the FEWEST whole rolls that
// yield every strip — a single strip is cut from ONE roll and never spans two.
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

enum VinylRollPacker {

    /// Fewest rolls of `rollLengthFeet` needed to yield every strip in
    /// `stripLengthsFeet`. Each strip consumes its own length from ONE roll (no
    /// strip spans two rolls). First-fit-decreasing. A strip longer than a roll
    /// is counted in `overlengthStripCount` and excluded from the packed rolls.
    ///
    /// A non-positive `rollLengthFeet` yields no valid roll, so every strip is
    /// unproducible: `(rollCount: 0, overlengthStripCount: stripLengthsFeet.count)`.
    static func rollsNeeded(stripLengthsFeet: [Double], rollLengthFeet: Double) -> RollPackResult {
        let epsilon = 1e-6

        guard rollLengthFeet > epsilon else {
            return RollPackResult(rollCount: 0, overlengthStripCount: stripLengthsFeet.count)
        }

        var overlengthStripCount = 0
        var packable: [Double] = []
        for length in stripLengthsFeet {
            if length > rollLengthFeet + epsilon {
                overlengthStripCount += 1          // longer than any roll — cannot be produced
            } else if length > epsilon {
                packable.append(length)            // skip degenerate ≤0 strips (consume no material)
            }
        }

        // Longest-first: the FFD ordering that minimizes wasted roll capacity.
        let sorted = packable.sorted(by: >)
        var rollRemaining: [Double] = []           // remaining feet on each opened roll
        for length in sorted {
            if let index = rollRemaining.firstIndex(where: { $0 + epsilon >= length }) {
                rollRemaining[index] -= length
            } else {
                rollRemaining.append(rollLengthFeet - length)
            }
        }

        return RollPackResult(rollCount: rollRemaining.count, overlengthStripCount: overlengthStripCount)
    }
}
