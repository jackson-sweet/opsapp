//
//  OnboardingPrimaryCTA.swift
//  OPS
//
//  The bottom action buttons for the rebuilt onboarding flow.
//
//  `OnboardingPrimaryCTA`   — the single most important action on a step.
//      Spec: `mobile/MOBILE.md` §8 (Floating CTAs / Primary).
//        • 52pt height (thumb zone), full width, `opsAccent` fill (accent = primary CTA only)
//        • Cake Mono 300 uppercase label, optional trailing `→`
//        • Medium-impact haptic on tap; success notification reserved for screens
//        • Disabled = reduced OPACITY (NOT a gray color swap)
//        • Loading = inline spinner, disables interaction
//
//  `OnboardingSecondaryCTA` — ghost / hairline-border action (SIGN IN, SKIP).
//      Spec: `DESIGN.md` §9 (Secondary button) + `mobile/MOBILE.md` §8 (Secondary CTA).
//        • Transparent fill, `buttonBorder` hairline, `text2` label. NO accent.
//
//  Both honor `accessibilityReduceMotion`. Every value traces to an `OPSStyle` token.
//

import SwiftUI

// MARK: - Primary CTA (steel-blue accent — the one accented control on the step)

struct OnboardingPrimaryCTA: View {
    let title: String
    var trailingArrow: Bool = true
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The tap is live only when enabled AND not loading. `internal` so the
    /// "disabled / loading blocks the action" contract is unit-testable.
    var isInteractive: Bool { isEnabled && !isLoading }

    /// Single tap entry point. Fires haptic + action ONLY when interactive, so a
    /// disabled or loading CTA can never invoke its action even if the underlying
    /// `Button` is somehow triggered. SwiftUI's `.disabled` is the visual gate;
    /// this is the belt-and-suspenders logical gate.
    func performTap() {
        guard isInteractive else { return }
        OnboardingHaptics.commit()
        action()
    }

    var body: some View {
        Button {
            performTap()
        } label: {
            ZStack {
                // Label — hidden (kept for layout) while loading.
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(title.uppercased())
                        .font(OPSStyle.Typography.buttonLabel) // Cake Mono 300, 14pt
                    if trailingArrow {
                        Image(systemName: OPSStyle.Icons.arrowRight)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    }
                }
                .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                        .controlSize(.small)
                }
            }
            .foregroundColor(OPSStyle.Colors.invertedText) // black-on-accent per §8
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.bottomCTAHeight) // §8 bottom-anchored CTA height (52pt)
            .background(OPSStyle.Colors.opsAccent)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)) // 5pt
        }
        .buttonStyle(PressScaleStyle(reduceMotion: reduceMotion))
        .disabled(!isInteractive)
        .opacity(isEnabled ? 1.0 : OPSStyle.Layout.Opacity.medium) // disabled = reduced opacity, NOT gray swap
        .animation(reduceMotion ? nil : OPSStyle.Animation.hover, value: isLoading)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? "Loading" : "")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Secondary CTA (ghost / hairline — SIGN IN, SKIP, etc.)

struct OnboardingSecondaryCTA: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            OnboardingHaptics.selection()
            action()
        } label: {
            Text(title.uppercased())
                .font(OPSStyle.Typography.buttonLabel) // Cake Mono 300, 14pt
                .foregroundColor(OPSStyle.Colors.text2) // ghost = text-2, never accent
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.bottomCTAHeight) // 52pt, matches primary
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .buttonStyle(PressScaleStyle(reduceMotion: reduceMotion))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : OPSStyle.Layout.Opacity.medium)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Press scale (shared, reduced-motion aware)

/// Subtle 0.98 press scale on the single OPS easing curve — no spring, no bounce.
/// Collapses to no scale under Reduce Motion.
private struct PressScaleStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.98 : 1.0))
            .animation(reduceMotion ? nil : OPSStyle.Animation.hover, value: configuration.isPressed)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("OnboardingPrimaryCTA") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        VStack(spacing: OPSStyle.Layout.spacing3) {
            OnboardingPrimaryCTA(title: "Continue", action: {})
            OnboardingPrimaryCTA(title: "Create account", isEnabled: false, action: {})
            OnboardingPrimaryCTA(title: "Joining crew", isLoading: true, action: {})
            OnboardingPrimaryCTA(title: "Get started", trailingArrow: false, action: {})
            OnboardingSecondaryCTA(title: "Sign in", action: {})
            OnboardingSecondaryCTA(title: "Skip for now", action: {})
        }
        .padding(OPSStyle.Layout.spacing4)
    }
    .preferredColorScheme(.dark)
}
#endif
