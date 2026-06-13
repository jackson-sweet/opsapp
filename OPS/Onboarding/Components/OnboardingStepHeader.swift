//
//  OnboardingStepHeader.swift
//  OPS
//
//  The top bar for every rebuilt onboarding screen. A DUMB component: it renders
//  whatever controls the screen hands it and nothing more. The screen decides,
//  per step, which edge controls to pass:
//
//    • Back-edge step      → pass `backLabel` + `onBack`  (renders the Back control)
//    • No-back, escapable  → pass `onSignOut`             (renders the SIGN OUT control)
//    • Neither             → title-only
//
//  Spec: `ops-design-system/project/mobile/MOBILE.md` §2.1 (Navigation bar).
//    • Back: `←` chevron + PREVIOUS-SCREEN label, JetBrains Mono 10–11pt, `text2`,
//      uppercase, 0.14em tracking — shows the previous screen's short name, not "Back".
//    • Title: Cake Mono 300, uppercase, left-aligned, `text`. 28pt, drops to 22pt if long.
//    • Action controls: right-aligned. Here, the SIGN OUT escape hatch.
//    • Height: 52pt content area.
//
//  "SIGN OUT" literal is UPPERCASE-for-authority per the OPS voice (ops-copywriter).
//  Every color / radius / font / spacing value traces to an `OPSStyle` token.
//

import SwiftUI

struct OnboardingStepHeader: View {

    /// The screen title. Always rendered uppercase in Cake Mono.
    let title: String

    /// Previous-screen short name for the Back control (e.g. "IDENTITY", not "Back").
    /// The Back control renders ONLY when both `backLabel` and `onBack` are provided.
    var backLabel: String?
    var onBack: (() -> Void)?

    /// When provided, a SIGN OUT escape-hatch control renders top-right. Used on
    /// no-back-edge steps that the user must still be able to bail out of.
    var onSignOut: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// MOBILE.md §2.1: title drops from 28pt to 22pt past ~14 chars.
    private var titleFont: Font {
        title.count > 14
            ? OPSStyle.Typography.screenTitleCompact // Cake Mono Light 22pt
            : OPSStyle.Typography.screenTitle        // Cake Mono Light 28pt
    }

    /// Back control renders ONLY when both a label and a handler are supplied.
    /// `internal` so the component contract is unit-testable without rendering.
    var showsBack: Bool { backLabel != nil && onBack != nil }

    /// SIGN OUT control renders only when a handler is supplied.
    var showsSignOut: Bool { onSignOut != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Edge-control row — Back (leading) and/or SIGN OUT (trailing).
            // Reserve the row whenever either control exists so the title sits
            // at a consistent y across steps.
            if showsBack || showsSignOut {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    if showsBack {
                        backControl
                    }
                    Spacer(minLength: 0)
                    if showsSignOut {
                        signOutControl
                    }
                }
                .frame(minHeight: OPSStyle.Layout.touchTargetMin) // 44pt — controls stay tappable
            }

            // Title — Cake Mono uppercase, left-aligned (§2.1: never centered).
            Text(title.uppercased())
                .font(titleFont)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true) // Dynamic Type: wrap, don't clip
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5) // 20pt — §1 m-canvas-x
        .padding(.top, OPSStyle.Layout.spacing2)
    }

    // MARK: Back control (§2.1)

    private var backControl: some View {
        Button {
            OnboardingHaptics.selection()
            onBack?()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1 + 2) { // 6pt
                Image(systemName: OPSStyle.Icons.chevronLeft)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold)) // 1.5px-feel stroke
                Text((backLabel ?? "").uppercased())
                    .font(OPSStyle.Typography.miniLabel) // JetBrains Mono 10pt
                    .tracking(1.4)                       // ≈0.14em
            }
            .foregroundColor(OPSStyle.Colors.text2) // §2.1 back = text-2, NEVER accent
            .frame(minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(backLabel ?? "")")
    }

    // MARK: Sign out control (escape hatch)

    private var signOutControl: some View {
        Button {
            OnboardingHaptics.selection()
            onSignOut?()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1 + 2) { // 6pt
                Text("SIGN OUT")
                    .font(OPSStyle.Typography.miniLabel) // JetBrains Mono 10pt
                    .tracking(1.4)                       // ≈0.14em
                Image(systemName: OPSStyle.Icons.lockFill)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
            }
            .foregroundColor(OPSStyle.Colors.text2) // metadata control, never accent
            .frame(minHeight: OPSStyle.Layout.touchTargetMin, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sign out")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("OnboardingStepHeader") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        VStack(spacing: OPSStyle.Layout.spacing5) {
            // Back-edge step
            OnboardingStepHeader(
                title: "Your details",
                backLabel: "Identity",
                onBack: {}
            )
            // No-back, escapable step
            OnboardingStepHeader(
                title: "Build your crew",
                onSignOut: {}
            )
            // Title-only
            OnboardingStepHeader(title: "Welcome")
            // Long title (drops to 22pt)
            OnboardingStepHeader(
                title: "Connect your accounting",
                backLabel: "Crew",
                onBack: {},
                onSignOut: {}
            )
            Spacer()
        }
        .padding(.vertical, OPSStyle.Layout.spacing4)
    }
    .preferredColorScheme(.dark)
}
#endif
