//
//  BooksDrillFilterChip.swift
//  OPS
//
//  Books — Mission Deck Phase B.
//  Pill shown below the segmented control when a drill applied a filter.
//  Tap the × to clear the filter and return the list to its default scope.
//
//  Spec: docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md § 4.5
//

import SwiftUI

struct BooksDrillFilterChip: View {
    let label: String
    let onClear: () -> Void

    var body: some View {
        Button(action: onClear) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.custom("JetBrainsMono-Medium", size: 10))
                    .tracking(1.4)  // 0.14em at 10pt
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .textCase(.uppercase)
                Image(OPSStyle.Icons.close)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .fill(OPSStyle.Colors.surfaceActive)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clear \(label) filter")
    }
}

#if DEBUG
#Preview("BooksDrillFilterChip") {
    HStack {
        BooksDrillFilterChip(label: "OVERDUE", onClear: {})
        BooksDrillFilterChip(label: "SENT", onClear: {})
        Spacer()
    }
    .padding(OPSStyle.Layout.spacing3_5)
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
