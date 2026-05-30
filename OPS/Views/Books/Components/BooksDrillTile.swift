//
//  BooksDrillTile.swift
//  OPS
//
//  Books — Mission Deck Phase B.
//  L2 drill tile shared by every card in the Books hero carousel.
//  Replaces the ad-hoc `tile` / `tileContent` helpers each card used to roll.
//
//  Spec: docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md § 4.1
//

import SwiftUI

struct BooksDrillTile: View {
    let label: String
    let value: String
    var sub: String? = nil
    var valueColor: Color = OPSStyle.Colors.primaryText
    var accent: Bool = false
    var onTap: (() -> Void)? = nil
    var accessibilityHint: String? = nil
    /// Full § 8.2 VoiceOver label. When set, it replaces the composed
    /// label-plus-value announcement and suppresses the separate value, so the
    /// tile reads exactly the spec's per-tile copy.
    var accessibilityLabelOverride: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { content }
                    .buttonStyle(BooksDrillTileButtonStyle(accent: accent, reduceMotion: reduceMotion))
            } else {
                content.modifier(BooksDrillTileChrome(accent: accent, isPressed: false, reduceMotion: reduceMotion))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelOverride ?? label)
        .modifier(OptionalAccessibilityValue(value: accessibilityLabelOverride == nil ? value : nil))
        .modifier(OptionalAccessibilityHint(hint: accessibilityHint))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .top, spacing: 0) {
                Text(label)
                    .font(.custom("JetBrainsMono-Medium", size: 9.5))
                    .tracking(1.7)  // 0.18em at 9.5pt
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)  // § 8.4 — tile label clamped
                Spacer(minLength: 4)
                if onTap != nil {
                    Image("ops.arrow-right")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .accessibilityHidden(true)
                }
            }

            Text(value)
                .font(.custom("JetBrainsMono-Medium", size: 18))
                .tracking(-0.18)  // -0.01em at 18pt — per design prototype
                .foregroundColor(valueColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let sub {
                Text(sub)
                    .font(.custom("JetBrainsMono-Regular", size: 9.5))
                    .tracking(1.33)  // 0.14em at 9.5pt
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .textCase(.uppercase)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)  // § 8.4 — tile sub-label clamped
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    @ViewBuilder
    func booksNumericContentTransition(reduceMotion: Bool) -> some View {
        if reduceMotion {
            self
        } else {
            self.contentTransition(.numericText())
        }
    }

    @ViewBuilder
    func booksOpacityContentTransition(reduceMotion: Bool) -> some View {
        if reduceMotion {
            self
        } else {
            self.contentTransition(.opacity)
        }
    }
}

private struct BooksDrillTileChrome: ViewModifier {
    let accent: Bool
    let isPressed: Bool
    let reduceMotion: Bool

    private var bg: Color {
        if isPressed { return Color.white.opacity(0.08) }
        return accent ? OPSStyle.Colors.primaryAccent.opacity(0.15) : Color.white.opacity(0.04)
    }

    private var border: Color {
        if isPressed { return Color.white.opacity(0.18) }
        return accent ? Color.white.opacity(0.25) : Color.white.opacity(0.08)
    }

    func body(content: Content) -> some View {
        content
            .padding(OPSStyle.Layout.spacing2_5)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius)
                    .fill(bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius)
                    .strokeBorder(border, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .animation(reduceMotion ? nil : OPSStyle.Animation.hover, value: isPressed)
    }
}

private struct BooksDrillTileButtonStyle: ButtonStyle {
    let accent: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(BooksDrillTileChrome(accent: accent, isPressed: configuration.isPressed, reduceMotion: reduceMotion))
    }
}

private struct OptionalAccessibilityHint: ViewModifier {
    let hint: String?
    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}

private struct OptionalAccessibilityValue: ViewModifier {
    let value: String?
    func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(value)
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("BooksDrillTile — outstanding") {
    HStack(spacing: OPSStyle.Layout.spacing2) {
        BooksDrillTile(
            label: "OUTSTANDING",
            value: "$12,640",
            sub: "4 ITEMS",
            valueColor: OPSStyle.Colors.errorStatus,
            onTap: {}
        )
        BooksDrillTile(
            label: "FORECAST",
            value: "$38,900",
            sub: "7 ITEMS",
            valueColor: OPSStyle.Colors.primaryAccent,
            accent: true,
            onTap: {}
        )
    }
    .padding(OPSStyle.Layout.spacing3_5)
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}

#Preview("BooksDrillTile — read-only") {
    HStack(spacing: OPSStyle.Layout.spacing2) {
        BooksDrillTile(label: "AVG MARGIN", value: "32%", sub: "MEAN")
        BooksDrillTile(label: "PROFITABLE", value: "9", sub: "JOBS", valueColor: OPSStyle.Colors.successStatus, onTap: {})
    }
    .padding(OPSStyle.Layout.spacing3_5)
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
