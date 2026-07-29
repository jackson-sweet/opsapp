//
//  BooksCommandKit.swift
//  OPS
//
//  Money & Leads redesign (2026-06-30) — shared foundation for the command-grid
//  surfaces. Two primitives reused across both screens:
//    • `.commandCard()`  — the solid #141416 raised L1 card (NET PROFIT hero,
//      job-profitability, lead triage cards).
//    • `CountUpText`     — a reduce-motion-aware 0→target hero count-up on the
//      single OPS easing curve (Money profit hero, Leads forecast hero).
//  (`BooksFormat` began here and is now the app-wide en_US-pinned money
//   formatter — see Utilities/BooksFormat.swift.)
//

import SwiftUI

// MARK: - Command card surface

extension View {
    /// The solid raised command surface — `surfaceRaised` (#141416) fill +
    /// `glassBorder` (white@0.09) hairline + `panelRadius` (10). The opaque
    /// counterpart to `.glassSurface()` used by the Money/Leads command cards:
    /// over the pure-black canvas a solid panel reads crisper in sunlight and
    /// avoids stacking blur passes (MOBILE.md §3). Pass a tone to tint the fill
    /// + border for the attention surfaces (RUNWAY watch tile, etc.).
    func commandCard(
        tone: Color? = nil,
        cornerRadius: CGFloat = OPSStyle.Layout.panelRadius
    ) -> some View {
        let fill: Color = tone.map { $0.opacity(0.07) } ?? OPSStyle.Colors.surfaceRaised
        let border: Color = tone.map { $0.opacity(0.30) } ?? OPSStyle.Colors.glassBorder
        return self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }
}

// MARK: - Entrance stagger

/// The `cardIn` entrance — a tile rises 9pt + fades in on first appear, with a
/// per-index delay so a grid of tiles lands in a quick cascade (the design's
/// `cardIn .3s` stagger). One OPS curve, no spring; Reduce Motion shows the
/// final state immediately with no movement.
private struct BooksCardIn: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // nil until the entrance runs; `isShown` defaults to true so a static render
    // (ImageRenderer snapshot, reduce-motion, first frame) shows the final state
    // rather than an invisible (opacity-0) tile.
    @State private var entered: Bool? = nil

    private var isShown: Bool { entered ?? true }

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown ? 0 : 9)
            .onAppear {
                guard entered == nil else { return }
                if reduceMotion {
                    entered = true
                    return
                }
                entered = false
                withAnimation(
                    .timingCurve(0.22, 1, 0.36, 1, duration: OPSStyle.Animation.durationPanel)
                        .delay(min(Double(index) * 0.04, 0.28))
                ) {
                    entered = true
                }
            }
    }
}

extension View {
    /// Applies the `cardIn` entrance stagger at `index` (delay capped at 280ms).
    func booksCardIn(index: Int) -> some View {
        modifier(BooksCardIn(index: index))
    }
}

// MARK: - Count-up hero number

/// A large hero number. Renders the formatted value directly (always correct —
/// in the app, in reduce-motion, and in static ImageRenderer snapshots) and
/// uses a numeric content transition so the digits roll when the value changes
/// (e.g. a period switch). Entrance motion is carried by the card's `cardIn`
/// stagger, not a 0→target count-up — an `Animatable` count-up renders at frame
/// 0 under ImageRenderer, which is why it's deliberately avoided here.
struct CountUpText: View {
    let target: Double
    var format: (Double) -> String = BooksFormat.currency
    var font: Font
    var color: Color = OPSStyle.Colors.text

    var body: some View {
        Text(format(target))
            .font(font)
            .foregroundColor(color)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(OPSStyle.Animation.panel, value: target)
    }
}
