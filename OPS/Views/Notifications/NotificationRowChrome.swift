//
//  NotificationRowChrome.swift
//  OPS
//
//  The rail card every notification row wears: glass surface, leading unread
//  dot + icon column, title / timestamp line, one-line body that opens on
//  expand, and a chevron. Extracted from `NotificationListView` so the
//  synthetic inbox group (bug 589e3b1e) is the same object as a server row
//  rather than a lookalike, and so both can be rendered — and snapshotted —
//  without the whole list's environment.
//
//  The body arrives as a fully styled `Text` because some rows compose it from
//  parts: a count in JetBrains Mono followed by Mohave prose (numbers are
//  always mono — DESIGN.md §4). The chrome therefore sets no font on it.
//

import SwiftUI

struct NotificationRowChrome<Icon: View, Detail: View>: View {
    let title: String
    /// Fully styled. The chrome only bounds it (one line collapsed, free when
    /// expanded) — it never restyles what the caller composed.
    let bodyText: Text
    /// Flat string of the same body, for VoiceOver.
    let bodyAccessibilityLabel: String
    /// Right-aligned relative time, already formatted.
    let timestamp: String
    let isRead: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var detail: () -> Detail

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2_5) {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(isRead ? Color.clear : OPSStyle.Colors.primaryAccent)
                            .frame(
                                width: OPSStyle.Layout.Indicator.dotSM,
                                height: OPSStyle.Layout.Indicator.dotSM
                            )

                        icon()
                    }
                    .padding(.top, 2)

                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                            Text(title.uppercased())
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(
                                    isRead
                                        ? OPSStyle.Colors.secondaryText
                                        : OPSStyle.Colors.primaryText
                                )
                                .tracking(0.5)
                                .lineLimit(1)

                            Spacer(minLength: OPSStyle.Layout.spacing2)

                            Text(timestamp)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        bodyText
                            .lineLimit(isExpanded ? nil : 1)
                            .truncationMode(.tail)
                            .accessibilityLabel(bodyAccessibilityLabel)
                    }

                    Image(systemName: isExpanded ? OPSStyle.Icons.chevronUp : OPSStyle.Icons.chevronDown)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.top, OPSStyle.Layout.spacing1)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                detail()
                    .transition(transition)
            }
        }
        .glassSurface(
            borderColor: isExpanded
                ? OPSStyle.Colors.primaryAccent.opacity(0.25)
                : OPSStyle.Colors.glassBorder
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing1)
    }
}

// MARK: - Icon

/// A rail row's glyph: monochrome SF Symbol on a neutral disc. The tone is the
/// row's semantics (olive done, tan attention, rose failed) — never decoration.
struct NotificationIconBadge: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(tint)
            .frame(width: 28, height: 28)
            .background(OPSStyle.Colors.fillNeutral)
            .clipShape(Circle())
    }
}

// MARK: - Detail furniture

/// The hairline that separates a row's collapsed header from its detail.
struct NotificationDetailDivider: View {
    var body: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorderSubtle)
            .frame(height: OPSStyle.Layout.Border.standard)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
    }
}

/// The one accent element on a rail row: its action. Steel blue is CTA-only
/// (DESIGN.md §3), which is exactly what this is.
struct NotificationActionButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    init(
        label: String,
        systemImage: String = "arrow.right.circle",
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: systemImage)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                Text(label)
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.5)
            }
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }
}
