//
//  Animation+OPS.swift
//  OPS
//
//  Canonical OPS easing curve, ported from `OPSStyle.swift` motion notes:
//  `cubic-bezier(0.22, 1, 0.36, 1)` — single curve, no spring, no bounce.
//  Defined in spec 2026-05-10-lidar-dimensioned-photo-capture-design.md §5.3
//  and referenced across measurement, deck builder, and tutorial surfaces.
//
//  Three duration presets cover the OPS motion vocabulary:
//    • opsCurve200  — micro-motion (enter/exit chips, opacity ramps)
//    • opsCurve300  — stagger / multi-element entries
//    • opsCurve350  — major transitions (card flips, hero swaps)
//

import SwiftUI

public extension Animation {
    /// 200 ms — the most common entry/exit beat (mesh fade-in, helper text,
    /// shutter flash arc halves, post-capture overlay).
    static let opsCurve200 = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)

    /// 300 ms — staggered entries and slower atmospheric reveals.
    static let opsCurve300 = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.30)

    /// 350 ms — major transitions (card flips, view swaps).
    static let opsCurve350 = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.35)
}
