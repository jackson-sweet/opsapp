//
//  ReticleOverlay.swift
//  OPS
//
//  Pulsing reticle drawn over the AR preview when the live mesh classifier
//  reports `.openingLocked` (spec §5.1, animation row 2 of §5.3).
//
//  Visual: steel-blue stroke, 1.5 px, no fill, ~96 pt frame.
//  Motion (full): 1.6 s loop, scale 0.92→1.0→0.92 + opacity 60%→100%→60%, OPS curve.
//  Motion (reduced): static reticle with a single 200 ms fade-in on detection.
//  No haptic — ambient discovery beat (architect Never-list #4).
//

import SwiftUI

struct ReticleOverlay: View {
    /// True when an opening has been classified — drives both visibility and the pulse.
    let isLocked: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var visible = false

    var body: some View {
        ZStack {
            cornerBrackets
        }
        .frame(width: 96, height: 96)
        .scaleEffect(reduceMotion ? 1.0 : (pulse ? 1.0 : 0.92))
        .opacity(reticleOpacity)
        .allowsHitTesting(false)
        .onAppear { syncAnimation() }
        .onChange(of: isLocked) { _, _ in syncAnimation() }
    }

    // MARK: - Drawing

    /// Four L-shaped corner brackets framing the opening — easier to read on a
    /// busy AR scene than a full ring (matches DeckBuilder tactical pattern).
    private var cornerBrackets: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let arm: CGFloat = 18
            let inset: CGFloat = 0
            var path = Path()
            // Top-left
            path.move(to: CGPoint(x: inset, y: inset + arm))
            path.addLine(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: inset + arm, y: inset))
            // Top-right
            path.move(to: CGPoint(x: w - inset - arm, y: inset))
            path.addLine(to: CGPoint(x: w - inset, y: inset))
            path.addLine(to: CGPoint(x: w - inset, y: inset + arm))
            // Bottom-left
            path.move(to: CGPoint(x: inset, y: h - inset - arm))
            path.addLine(to: CGPoint(x: inset, y: h - inset))
            path.addLine(to: CGPoint(x: inset + arm, y: h - inset))
            // Bottom-right
            path.move(to: CGPoint(x: w - inset - arm, y: h - inset))
            path.addLine(to: CGPoint(x: w - inset, y: h - inset))
            path.addLine(to: CGPoint(x: w - inset, y: h - inset - arm))
            ctx.stroke(
                path,
                with: .color(OPSStyle.Colors.opsAccent),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    // MARK: - State plumbing

    /// Computed opacity. When locked: pulse 60%→100% (or 100% in reduced motion).
    /// When unlocked: hidden.
    private var reticleOpacity: Double {
        guard isLocked, visible else { return 0 }
        if reduceMotion { return 1.0 }
        return pulse ? 1.0 : 0.6
    }

    private func syncAnimation() {
        guard isLocked else {
            // Stop the loop and clear visibility — architect Never-list #8 (no orphaned animations).
            withAnimation(.opsCurve200) { visible = false }
            pulse = false
            return
        }
        // First reveal: 200 ms fade-in matching the §5.3 reduced-motion fallback timing.
        withAnimation(.opsCurve200) { visible = true }
        guard !reduceMotion else { return }
        // Start the pulse — 0.8 s each direction, autoreverse → 1.6 s loop.
        withAnimation(
            .timingCurve(0.22, 1, 0.36, 1, duration: 0.8)
                .repeatForever(autoreverses: true)
        ) {
            pulse = true
        }
    }
}
