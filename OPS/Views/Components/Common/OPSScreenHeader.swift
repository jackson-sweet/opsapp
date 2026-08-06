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

/// Shared, testable policy for the mobile header's trailing edge. The visual
/// spec permits no more than two actions; extra actions must move into one of
/// those slots (normally an overflow menu) rather than widening the band.
enum OPSHeaderGeometry {
    enum AccessibilityPosition: Equatable {
        case leading
        case title
        case trailing(Int)
    }

    static let maximumTrailingActionCount = 2

    static func visibleTrailingActions<Action>(from actions: [Action]) -> [Action] {
        Array(actions.prefix(maximumTrailingActionCount))
    }

    static func accessibilityOrder(
        hasLeading: Bool,
        trailingActionCount: Int
    ) -> [AccessibilityPosition] {
        var positions: [AccessibilityPosition] = hasLeading ? [.leading, .title] : [.title]
        let visibleCount = min(max(0, trailingActionCount), maximumTrailingActionCount)
        positions.append(contentsOf: (0..<visibleCount).map(AccessibilityPosition.trailing))
        return positions
    }

    static func accessibilitySortPriority(
        for position: AccessibilityPosition
    ) -> Double {
        switch position {
        case .leading:
            return Double(maximumTrailingActionCount + 1)
        case .title:
            return Double(maximumTrailingActionCount)
        case .trailing(let index):
            return Double(maximumTrailingActionCount - index - 1)
        }
    }
}

/// Makes an arbitrary custom header control glove-safe without requiring every
/// legacy caller to rebuild its button label. Empty header slots are omitted by
/// OPSScreenHeader, so root titles still begin at the canonical leading inset.
struct OPSHeaderControlSlot<Content: View>: View {
    private let position: OPSHeaderGeometry.AccessibilityPosition
    private let alignment: Alignment
    private let content: Content

    init(
        position: OPSHeaderGeometry.AccessibilityPosition,
        alignment: Alignment,
        @ViewBuilder content: () -> Content
    ) {
        self.position = position
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        content
            .frame(
                minWidth: OPSStyle.Layout.touchTargetMin,
                minHeight: OPSStyle.Layout.touchTargetMin,
                alignment: alignment
            )
            .contentShape(Rectangle())
            .accessibilitySortPriority(
                OPSHeaderGeometry.accessibilitySortPriority(for: position)
            )
    }
}

/// A source-order-preserving trailing action row that enforces the two-action
/// policy even if a future caller accidentally supplies more.
struct OPSHeaderActionStrip<Action: Identifiable, ActionContent: View>: View {
    private let actions: [Action]
    private let actionContent: (Action) -> ActionContent

    init(
        _ actions: [Action],
        @ViewBuilder actionContent: @escaping (Action) -> ActionContent
    ) {
        self.actions = actions
        self.actionContent = actionContent
    }

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            let visibleActions = OPSHeaderGeometry.visibleTrailingActions(from: actions)
            ForEach(visibleActions.indices, id: \.self) { index in
                actionContent(visibleActions[index])
                    .accessibilitySortPriority(
                        OPSHeaderGeometry.accessibilitySortPriority(
                            for: .trailing(index)
                        )
                    )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }
}

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
            leadingSlot

            Text(title)
                .font(OPSStyle.Typography.screenTitle(for: title))
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)
                .accessibilitySortPriority(
                    OPSHeaderGeometry.accessibilitySortPriority(for: .title)
                )

            trailingSlot
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .frame(
            minHeight: OPSStyle.Layout.screenHeaderBandHeight,
            alignment: .center
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var leadingSlot: some View {
        if Leading.self == EmptyView.self {
            EmptyView()
        } else {
            OPSHeaderControlSlot(position: .leading, alignment: .leading) {
                leading
            }
        }
    }

    @ViewBuilder
    private var trailingSlot: some View {
        if Trailing.self == EmptyView.self {
            EmptyView()
        } else {
            OPSHeaderControlSlot(position: .trailing(0), alignment: .trailing) {
                trailing
            }
        }
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
        .accessibilityLabel(label.map { "Back to \($0)" } ?? "Back")
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
        .accessibilityLabel("Close")
    }
}
