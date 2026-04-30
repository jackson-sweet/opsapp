//
//  RecurringEventEditScopeSheet.swift
//  OPS
//
//  Apple-Calendar-style "this / future / all" prompt that appears when a user
//  edits or deletes one occurrence of a recurring event. The prompt is the
//  ONLY UI between the user and a series-wide mutation, so the choice is
//  decisive: tap to dismiss, fire haptic, then the parent runs the mutation
//  asynchronously.
//

import SwiftUI

// MARK: - Scope

/// Which slice of a recurring series an action targets.
enum RecurringEventScope {
    /// Just the row the user tapped — detach from series, then mutate.
    case thisOnly
    /// This row + every later sibling in the series.
    case thisAndFuture
    /// Every row in the series.
    case allEvents
}

// MARK: - Sheet Mode

/// Whether the sheet is asking about an edit or a delete. Drives copy + the
/// destructive styling on the third row.
enum RecurringEventScopeMode {
    case edit
    case delete

    fileprivate var headline: String {
        switch self {
        case .edit:   return "RECURRING EVENT"
        case .delete: return "DELETE RECURRING EVENT"
        }
    }

    fileprivate var subhead: String {
        switch self {
        case .edit:   return "Apply your edit to which events?"
        case .delete: return "Remove which events from the series?"
        }
    }

    fileprivate var thisOnly: (title: String, subtitle: String) {
        switch self {
        case .edit:   return ("EDIT THIS EVENT", "Only this occurrence")
        case .delete: return ("DELETE THIS EVENT", "Only this occurrence")
        }
    }

    fileprivate var thisAndFuture: (title: String, subtitle: String) {
        switch self {
        case .edit:   return ("EDIT FUTURE EVENTS", "This event and every later one")
        case .delete: return ("DELETE FUTURE EVENTS", "This event and every later one")
        }
    }

    fileprivate var allEvents: (title: String, subtitle: String) {
        switch self {
        case .edit:   return ("EDIT ALL EVENTS", "Every occurrence in the series")
        case .delete: return ("DELETE ALL EVENTS", "Every occurrence in the series")
        }
    }

    fileprivate var isDestructive: Bool { self == .delete }
}

// MARK: - Sheet

struct RecurringEventEditScopeSheet: View {
    let mode: RecurringEventScopeMode
    let onSelect: (RecurringEventScope) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Top grip — gives the sheet a deliberate, military-tactical
            // anchor and tells the user it's dismissible by drag.
            Capsule()
                .fill(OPSStyle.Colors.tertiaryText.opacity(0.5))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, OPSStyle.Layout.spacing4)

            // Title block
            VStack(spacing: OPSStyle.Layout.spacing2) {
                Text(mode.headline)
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .tracking(1)

                Text(mode.subhead)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing4)
            .padding(.bottom, OPSStyle.Layout.spacing4)

            // Three scope rows
            VStack(spacing: OPSStyle.Layout.spacing2) {
                scopeRow(
                    title: mode.thisOnly.title,
                    subtitle: mode.thisOnly.subtitle,
                    isDestructive: false,
                    isPrimary: false
                ) {
                    select(.thisOnly)
                }

                scopeRow(
                    title: mode.thisAndFuture.title,
                    subtitle: mode.thisAndFuture.subtitle,
                    isDestructive: false,
                    isPrimary: false
                ) {
                    select(.thisAndFuture)
                }

                scopeRow(
                    title: mode.allEvents.title,
                    subtitle: mode.allEvents.subtitle,
                    isDestructive: mode.isDestructive,
                    isPrimary: true
                ) {
                    select(.allEvents)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            // Cancel
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onCancel()
                dismiss()
            } label: {
                Text("CANCEL")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing3)
            .padding(.bottom, OPSStyle.Layout.spacing4)
        }
        .frame(maxWidth: .infinity)
        .background(OPSStyle.Colors.background.ignoresSafeArea(edges: .bottom))
        .colorScheme(.dark)
    }

    // MARK: - Scope Row

    /// Tappable row. The third row receives `.primary` styling (filled
    /// emphasis) — tapping it is the "do it to everything" choice and we
    /// want it visually decisive. Destructive variant also recolours that
    /// emphasis red.
    @ViewBuilder
    private func scopeRow(
        title: String,
        subtitle: String,
        isDestructive: Bool,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(titleColor(isDestructive: isDestructive, isPrimary: isPrimary))

                    Text(subtitle)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(subtitleColor(isDestructive: isDestructive, isPrimary: isPrimary))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(titleColor(isDestructive: isDestructive, isPrimary: isPrimary).opacity(0.6))
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, 14)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)  // 60pt — primary action target
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(isDestructive: isDestructive, isPrimary: isPrimary))
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(rowBorder(isDestructive: isDestructive, isPrimary: isPrimary),
                            lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PressDimStyle())
    }

    // MARK: - Selection

    /// Fire haptic + close instantly. Mutation runs in the parent after the
    /// dismiss completes — the sheet should never block on network work.
    private func select(_ scope: RecurringEventScope) {
        // Medium impact = commitment beat (per OPSStyle haptic vocabulary).
        // The user is making a series-wide choice; the haptic confirms weight.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onSelect(scope)
        dismiss()
    }

    // MARK: - Color resolution

    private func titleColor(isDestructive: Bool, isPrimary: Bool) -> Color {
        if isPrimary && isDestructive { return OPSStyle.Colors.primaryText }
        if isPrimary { return OPSStyle.Colors.invertedText }
        if isDestructive { return OPSStyle.Colors.errorStatus }
        return OPSStyle.Colors.primaryText
    }

    private func subtitleColor(isDestructive: Bool, isPrimary: Bool) -> Color {
        if isPrimary && isDestructive { return OPSStyle.Colors.primaryText.opacity(0.7) }
        if isPrimary { return OPSStyle.Colors.invertedText.opacity(0.7) }
        return OPSStyle.Colors.secondaryText
    }

    @ViewBuilder
    private func rowBackground(isDestructive: Bool, isPrimary: Bool) -> some View {
        if isPrimary && isDestructive {
            OPSStyle.Colors.errorStatus
        } else if isPrimary {
            OPSStyle.Colors.primaryText
        } else {
            OPSStyle.Colors.cardBackgroundDark
        }
    }

    private func rowBorder(isDestructive: Bool, isPrimary: Bool) -> Color {
        if isPrimary { return Color.clear }
        if isDestructive { return OPSStyle.Colors.errorStatus.opacity(0.4) }
        return OPSStyle.Colors.cardBorder
    }
}

// MARK: - Press dim style

/// Subtle press feedback — dim + tiny scale. Avoids spring overshoot
/// (brand rule: "no bouncy/playful animations").
private struct PressDimStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
