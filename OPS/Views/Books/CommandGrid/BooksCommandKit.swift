//
//  BooksCommandKit.swift
//  OPS
//
//  Money & Leads redesign (2026-06-30) — shared foundation for the command-grid
//  surfaces. Three primitives reused across both screens:
//    • `.commandCard()`  — the solid #141416 raised L1 card (NET PROFIT hero,
//      job-profitability, lead triage cards).
//    • `BooksFormat`     — currency / compact / signed-percent number formatting
//      (always tabular mono at the call site).
//    • `CountUpText`     — a reduce-motion-aware 0→target hero count-up on the
//      single OPS easing curve (Money profit hero, Leads forecast hero).
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
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 9)
            .onAppear {
                guard !appeared else { return }
                if reduceMotion {
                    appeared = true
                    return
                }
                withAnimation(
                    .timingCurve(0.22, 1, 0.36, 1, duration: OPSStyle.Animation.durationPanel)
                        .delay(min(Double(index) * 0.04, 0.28))
                ) {
                    appeared = true
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

// MARK: - Number formatting

/// Money-screen number formatting. Every value is formatted (never raw) and
/// rendered in JetBrains Mono / Mohave with `.monospacedDigit()` at the call
/// site (DESIGN.md §2 — numbers are always mono, tabular, slashed-zero).
enum BooksFormat {
    /// Full currency, no cents — `$18,240`. Hero numbers and lead values.
    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// Compact currency for dense tiles — `$34.8K`, `$1.2M`, `$640`. Drops a
    /// trailing `.0` so round thousands read `$34K` not `$34.0K`.
    static func compact(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        let magnitude = abs(value)
        if magnitude >= 1_000_000 {
            return "\(sign)$\(trim(magnitude / 1_000_000))M"
        }
        if magnitude >= 1_000 {
            return "\(sign)$\(trim(magnitude / 1_000))K"
        }
        return "\(sign)$\(Int(magnitude.rounded()))"
    }

    /// Signed percent — `+14%`, `-3%`, `0%`. Caller colors it olive/rose.
    static func signedPct(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded > 0 { return "+\(rounded)%" }
        return "\(rounded)%"
    }

    /// One-decimal with a stripped trailing `.0` (`34.8`, `12`, `1.2`).
    private static func trim(_ value: Double) -> String {
        let s = String(format: "%.1f", value)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}

// MARK: - Count-up hero number

/// A hero number that counts up from 0 to `target` on appear, and animates
/// between values when `target` changes (period switch). Honors Reduce Motion
/// by snapping to the final value with no interpolation. The single OPS easing
/// curve at the 800ms count-up duration (DESIGN.md §8).
struct CountUpText: View {
    let target: Double
    var format: (Double) -> String = BooksFormat.currency
    var font: Font
    var color: Color = OPSStyle.Colors.text

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        _CountUpNumber(value: shown, format: format)
            .font(font)
            .foregroundColor(color)
            .monospacedDigit()
            .onAppear {
                withAnimation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: OPSStyle.Animation.durationCountUp)) {
                    shown = target
                }
            }
            .onChange(of: target) { _, newValue in
                withAnimation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: OPSStyle.Animation.durationCountUp)) {
                    shown = newValue
                }
            }
    }
}

/// Drives the per-frame interpolation. `animatableData` lets SwiftUI tween the
/// underlying Double; `body` reformats each interpolated frame.
private struct _CountUpNumber: View, Animatable {
    var value: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
    }
}
