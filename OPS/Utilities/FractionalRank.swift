//
//  FractionalRank.swift
//  OPS
//
//  Pure fractional-index math for drag-to-reorder priority ranks. A moved item
//  gets a value strictly between its neighbors so one move dirties one row.
//  Re-spaced by `normalize` when neighbor gaps approach Double precision limits.
//

import Foundation

enum FractionalRank {
    /// Default spacing used when (re)assigning a fresh ordered sequence.
    static let step: Double = 1024

    /// Below this neighbor gap, fractional inserts risk precision loss — normalize.
    static let minGap: Double = 1e-6

    /// A rank strictly between `lower` and `upper`.
    static func between(_ lower: Double?, _ upper: Double?) -> Double {
        switch (lower, upper) {
        case (nil, nil):                 return 0
        case (nil, let u?):              return u - 1
        case (let l?, nil):              return l + 1
        case (let l?, let u?):           return (l + u) / 2
        }
    }

    /// True when the gap between two adjacent ranks is too small to safely bisect.
    static func needsNormalization(between lower: Double, and upper: Double) -> Bool {
        abs(upper - lower) < minGap
    }

    /// Evenly spaced ranks (step, 2*step, …) for an ordered id list, order preserved.
    static func normalize(orderedIds: [String]) -> [String: Double] {
        var result: [String: Double] = [:]
        for (i, id) in orderedIds.enumerated() {
            result[id] = Double(i + 1) * step
        }
        return result
    }
}
