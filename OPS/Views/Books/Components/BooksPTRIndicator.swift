//
//  BooksPTRIndicator.swift
//  OPS
//
//  Books — Mission Deck Phase B.
//  Custom pull-to-refresh chrome for the Books tab. OPS mark + spinning arc
//  + tactical SYNCING label. Renders the active "syncing" state; transition to
//  a "synced" success state is owned by the consumer in Phase F.
//
//  Spec: docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md § 4.7
//

import SwiftUI
import UIKit

struct BooksPTRIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            opsMark
            arc
            label
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Syncing")
    }

    @ViewBuilder
    private var opsMark: some View {
        // When the OPS mark asset ships into Assets.xcassets it is picked up
        // automatically; until then the dotted-ring SF Symbol stands in.
        if UIImage(named: "OPSMark") != nil {
            Image("OPSMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        } else {
            Image(OPSStyle.Icons.loading)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    private var arc: some View {
        ZStack {
            Circle()
                .stroke(OPSStyle.Colors.line, lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(
                    OPSStyle.Colors.secondaryText,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }

    private var label: some View {
        Text("SYNCING")
            .font(.custom("JetBrainsMono-Medium", size: 10))
            .tracking(1.8)  // 0.18em at 10pt
            .foregroundColor(OPSStyle.Colors.tertiaryText)
    }
}

#if DEBUG
#Preview("BooksPTRIndicator") {
    BooksPTRIndicator()
        .padding(OPSStyle.Layout.spacing3_5)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
}
#endif
