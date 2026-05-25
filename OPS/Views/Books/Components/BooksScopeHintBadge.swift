//
//  BooksScopeHintBadge.swift
//  OPS
//
//  Books — Mission Deck Phase B.
//  Small badge rendered beside the carousel header label on Cards 3 + 4:
//  A/R is ALL OPEN regardless of period; Forecast is ACTIVE-only.
//
//  Spec: docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md § 4.6
//

import SwiftUI

struct BooksScopeHintBadge: View {
    enum Variant {
        case allOpen
        case active
    }

    let variant: Variant

    private var label: String {
        switch variant {
        case .allOpen: return "ALL OPEN"
        case .active:  return "ACTIVE"
        }
    }

    private var textColor: Color {
        switch variant {
        case .allOpen: return OPSStyle.Colors.roseMobile
        case .active:  return OPSStyle.Colors.primaryAccent
        }
    }

    // Background and border alphas come from HANDOFF.md § 3 — rose RGB(181,130,137)
    // and accent RGB(111,148,176) at 0.32 / 0.45 / 0.88 alpha. Resolve via the
    // semantic `rose` / `primaryAccent` tokens with literal opacities.
    private var bg: Color {
        switch variant {
        case .allOpen: return OPSStyle.Colors.rose.opacity(0.32)
        case .active:  return OPSStyle.Colors.primaryAccent.opacity(0.32)
        }
    }

    private var border: Color {
        switch variant {
        case .allOpen: return OPSStyle.Colors.rose.opacity(0.88)
        case .active:  return OPSStyle.Colors.primaryAccent.opacity(0.45)
        }
    }

    var body: some View {
        Text(label)
            .font(.custom("JetBrainsMono-Medium", size: 9).weight(.semibold))
            .tracking(1.44)  // 0.16em at 9pt
            .foregroundColor(textColor)
            .textCase(.uppercase)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .fill(bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .strokeBorder(border, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .accessibilityLabel(label.replacingOccurrences(of: "_", with: " "))
    }
}

#if DEBUG
#Preview("BooksScopeHintBadge — both variants") {
    HStack(spacing: OPSStyle.Layout.spacing2) {
        BooksScopeHintBadge(variant: .allOpen)
        BooksScopeHintBadge(variant: .active)
        Spacer()
    }
    .padding(OPSStyle.Layout.spacing3_5)
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
