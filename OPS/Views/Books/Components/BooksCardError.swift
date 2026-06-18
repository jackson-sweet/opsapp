//
//  BooksCardError.swift
//  OPS
//
//  Books — Mission Deck Phase B.
//  Card-level error state. Replaces a single Books card's body while sibling
//  cards stay live — granular fail-soft, not a tab-wide spinner.
//
//  Spec: docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md § 4.4
//

import SwiftUI

struct BooksCardError: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("—")
                .font(.custom("Mohave-Light", size: 48))
                .foregroundColor(OPSStyle.Colors.rose)
                .accessibilityHidden(true)

            Text("// ERROR — LOAD FAILED")
                .font(.custom("JetBrainsMono-Medium", size: 10.5).weight(.semibold))
                .tracking(1.05)  // ~0.10em at 10.5pt
                .foregroundColor(OPSStyle.Colors.rose)

            Text("Couldn't fetch this period. Showing cached data above the fold; tap retry to try again.")
                .font(.custom("Mohave-Regular", size: 14))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            Button(action: onRetry) {
                Text("[RETRY →]")
                    .font(.custom("CakeMono-Light", size: 13))
                    .tracking(0.65)
                    .foregroundColor(OPSStyle.Colors.rose)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .fill(OPSStyle.Colors.rose.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .strokeBorder(OPSStyle.Colors.rose.opacity(0.30), lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry loading card")
            .accessibilityHint("Double-tap to try again")
            .padding(.top, OPSStyle.Layout.spacing1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing3)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("BooksCardError") {
    BooksCardError(onRetry: {})
        .padding(.vertical, OPSStyle.Layout.spacing4)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
}
#endif
