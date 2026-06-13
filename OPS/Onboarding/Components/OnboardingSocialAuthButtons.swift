//
//  OnboardingSocialAuthButtons.swift
//  OPS
//
//  Shared Apple + Google sign-in buttons for the rebuilt onboarding flow.
//  Create-account (S3) uses them above the email form; Login (S4) reuses the
//  same component below — they are NOT re-rolled per screen.
//
//  DUMB + PRESENTATIONAL: each button takes an action closure and a shared
//  `isLoading` flag (the screen owns the async work). A tap fires a light
//  selection haptic then the closure — no auth logic, no singleton reach, so
//  the buttons are trivially testable by driving the closures.
//
//  Design-system conformance (`DESIGN.md` + `mobile/MOBILE.md` §9 / §8):
//    • OPS treatment, NOT Apple's default button chrome — both buttons are the
//      same ghost/hairline surface (transparent fill, `buttonBorder` hairline),
//      matching the secondary-CTA pattern. Accent appears NOWHERE (accent =
//      primary CTA only). Glyphs + labels are `text` (the brand monochrome).
//    • 52pt height (thumb-zone CTA), `buttonRadius` (5pt), Cake Mono button
//      label. While loading, the tapped button shows an inline spinner and the
//      pair is disabled.
//    • One easing curve via the shared press-scale; honored only when Reduce
//      Motion is off. 44pt+ (52pt) targets.
//  Every literal traces to an `OPSStyle` token.
//

import SwiftUI

/// Which social provider a button drives. Carries its label + glyph so the
/// button body stays declarative and the two providers can't drift apart.
enum OnboardingSocialProvider: CaseIterable {
    case apple
    case google

    /// Button label — sentence case content per the OPS voice (ops-copywriter).
    var label: String {
        switch self {
        case .apple:  return "Continue with Apple"
        case .google: return "Continue with Google"
        }
    }

    /// SF Symbol for Apple; the bundled mark asset for Google (Google's brand
    /// guidelines require their multicolor "G", so it is NOT a template glyph).
    var usesSFSymbol: Bool { self == .apple }

    var sfSymbol: String { "apple.logo" }       // Apple-provided SF Symbol
    var assetName: String { "google_logo" }     // bundled Google "G" mark

    var accessibilityLabel: String {
        switch self {
        case .apple:  return "Continue with Apple"
        case .google: return "Continue with Google"
        }
    }
}

/// The Apple + Google sign-in pair. Presentational only.
struct OnboardingSocialAuthButtons: View {

    /// Tapped Apple — the screen wires this to its Apple signup path.
    let onApple: () -> Void
    /// Tapped Google — the screen wires this to its Google signup path.
    let onGoogle: () -> Void

    /// While true the pair is non-interactive and the in-flight provider shows a
    /// spinner. The screen owns the async work and flips this.
    var isLoading: Bool = false

    /// Which provider is mid-request, so only THAT button shows the spinner (the
    /// other stays a calm disabled ghost). `nil` = no request in flight.
    var loadingProvider: OnboardingSocialProvider?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) { // 12pt between the two
            providerButton(.apple, action: onApple)
            providerButton(.google, action: onGoogle)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sign up with Apple or Google")
    }

    // MARK: - Single provider button (ghost / hairline — OPS treatment)

    private func providerButton(
        _ provider: OnboardingSocialProvider,
        action: @escaping () -> Void
    ) -> some View {
        let showsSpinner = isLoading && loadingProvider == provider

        return Button {
            guard !isLoading else { return }
            OnboardingHaptics.selection()
            action()
        } label: {
            ZStack {
                HStack(spacing: OPSStyle.Layout.spacing2_5) { // 12pt glyph→label
                    glyph(for: provider)
                    Text(provider.label)
                        .font(OPSStyle.Typography.buttonLabel) // Cake Mono Light 14pt
                        .foregroundColor(OPSStyle.Colors.text)
                }
                .opacity(showsSpinner ? 0 : 1) // hidden (kept for layout) while loading

                if showsSpinner {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.text))
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.bottomCTAHeight) // 52pt — matches the primary CTA
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(SocialPressScaleStyle(reduceMotion: reduceMotion))
        .disabled(isLoading)
        // Dim the whole pair while a request is in flight (the spinner marks the
        // active one). Reduced opacity, never a gray color swap.
        .opacity(isLoading ? OPSStyle.Layout.Opacity.strong : 1.0)
        .accessibilityLabel(provider.accessibilityLabel)
        .accessibilityValue(showsSpinner ? "Loading" : "")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Provider glyph

    @ViewBuilder
    private func glyph(for provider: OnboardingSocialProvider) -> some View {
        if provider.usesSFSymbol {
            Image(systemName: provider.sfSymbol)
                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium)) // 20pt
                .foregroundColor(OPSStyle.Colors.text)
                .accessibilityHidden(true)
        } else {
            // Google's multicolor mark — its brand guidelines forbid recoloring,
            // so it is rendered as-is (not a monochrome template).
            Image(provider.assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: OPSStyle.Layout.IconSize.lg, height: OPSStyle.Layout.IconSize.lg) // 24pt
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Press scale (reduced-motion aware, matches the CTA components)

/// Subtle 0.98 press scale on the single OPS easing curve — no spring, no
/// bounce. Collapses to no scale under Reduce Motion. Mirrors the private style
/// in `OnboardingPrimaryCTA`; kept local so this component is self-contained.
private struct SocialPressScaleStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.98 : 1.0))
            .animation(reduceMotion ? nil : OPSStyle.Animation.hover, value: configuration.isPressed)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("OnboardingSocialAuthButtons") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        VStack(spacing: OPSStyle.Layout.spacing5) {
            OnboardingSocialAuthButtons(onApple: {}, onGoogle: {})
            OnboardingSocialAuthButtons(
                onApple: {}, onGoogle: {},
                isLoading: true, loadingProvider: .apple
            )
            OnboardingSocialAuthButtons(
                onApple: {}, onGoogle: {},
                isLoading: true, loadingProvider: .google
            )
        }
        .padding(OPSStyle.Layout.spacing4)
    }
    .preferredColorScheme(.dark)
}
#endif
