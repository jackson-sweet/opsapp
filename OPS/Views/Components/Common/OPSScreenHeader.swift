//
//  OPSScreenHeader.swift
//  OPS
//
//  The canonical OPS screen / nav header (MOBILE.md §2.1, §2.3, §6.3).
//
//  Use on pushed/detail screens, full-screen covers, and modal sheets that
//  roll their own header instead of (or on top of) the native nav bar. It
//  guarantees the canonical screen-title spec — Cake Mono Light 28pt (22pt for
//  long strings), UPPERCASE, LEFT-aligned, `Colors.text`, 20pt horizontal
//  padding, 52pt content height — while letting each screen keep its exact
//  leading (back/close) and trailing (action) controls.
//
//  Layout:  [leading]  SCREEN TITLE  ───spacer───  [trailing]
//
//  The title is ALWAYS left-aligned (never centered — §2.1 / §13) and always
//  uppercase. Pair with `OPSHeaderBackButton` (§2.3 chevron + previous-screen
//  label) or `OPSHeaderCloseButton` (§6.3 close ✕) for the leading control.
//

import SwiftUI

struct OPSScreenHeader<Leading: View, Trailing: View>: View {
    private let title: String
    private let leading: Leading
    private let trailing: Trailing

    init(
        _ title: String,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2_5) {
            leading
            Text(title)
                .font(OPSStyle.Typography.screenTitle(for: title))
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            Spacer(minLength: OPSStyle.Layout.spacing2)
            trailing
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5) // 20pt §2.1
        .frame(minHeight: 52, alignment: .center)         // 52pt content §2.1
    }
}

// MARK: - Leading controls

/// Back affordance for the canonical header — chevron + optional previous-screen
/// label in the tactical voice (MOBILE.md §2.3). 44×44 tap target.
struct OPSHeaderBackButton: View {
    /// Short name of the previous screen (e.g. "TODAY"). Omit for chevron-only.
    var label: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: "chevron.left")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                if let label {
                    Text(label)
                        .font(OPSStyle.Typography.miniLabel) // JetBrains Mono 10
                        .textCase(.uppercase)
                        .tracking(1.4)                       // ~0.14em
                        .lineLimit(1)
                }
            }
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .frame(minWidth: OPSStyle.Layout.touchTargetMin,
                   minHeight: OPSStyle.Layout.touchTargetMin,
                   alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Close affordance for modally-presented full sheets (MOBILE.md §6.3).
/// 44×44 tap target.
struct OPSHeaderCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: OPSStyle.Layout.touchTargetMin,
                       height: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
