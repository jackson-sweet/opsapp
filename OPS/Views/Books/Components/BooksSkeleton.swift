//
//  BooksSkeleton.swift
//  OPS
//
//  Books — Mission Deck Phase B.
//  Skeleton primitives for the cold-paint no-cache state on Books cards.
//
//  Spec: docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md § 4.3
//

import SwiftUI

enum BooksSkeleton {

    /// Single-line text placeholder. Height matches body line-height (~14pt).
    static func text(width: CGFloat) -> some View {
        SkeletonBlock(width: width, height: 14)
    }

    /// Full-tile placeholder matching `BooksDrillTile` dimensions slot-for-slot.
    static func tile() -> some View {
        SkeletonTile()
    }

    /// Generic bar placeholder for chart slots (sparkline, aging ramp, diverging bar).
    static func bar(width: CGFloat?, height: CGFloat) -> some View {
        SkeletonBlock(width: width, height: height)
    }
}

private struct SkeletonBlock: View {
    let width: CGFloat?
    let height: CGFloat
    var radius: CGFloat = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(reduceMotion
                  ? Color.white.opacity(0.08)
                  : Color.white.opacity(pulse ? 0.08 : 0.03))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .accessibilityHidden(true)
    }
}

private struct SkeletonTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                SkeletonBlock(width: 84, height: 9)
                Spacer(minLength: 4)
                SkeletonBlock(width: 9, height: 9)
            }
            SkeletonBlock(width: 110, height: 18)
            Spacer(minLength: 0)
            SkeletonBlock(width: 60, height: 9)
        }
        .padding(OPSStyle.Layout.spacing2_5)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: OPSStyle.Layout.Border.standard)
        )
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("BooksSkeleton — variants") {
    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
        BooksSkeleton.text(width: 140)
        BooksSkeleton.text(width: 220)
        BooksSkeleton.bar(width: nil, height: 6)
        HStack(spacing: OPSStyle.Layout.spacing2) {
            BooksSkeleton.tile()
            BooksSkeleton.tile()
        }
    }
    .padding(OPSStyle.Layout.spacing3_5)
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
