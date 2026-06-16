//
//  WelcomeStepView.swift
//  OPS
//
//  Onboarding rebuild P3 — S1 (Welcome), the root of the rebuilt flow.
//
//  Design spec §4.2 S1. Serves new AND returning users identically: a static
//  brand hero (mark + wordmark + tagline + one subline), a version footer, and
//  two CTAs — GET STARTED (primary, accent) → role pick, SIGN IN (ghost) →
//  login. There is NO header back (Welcome is the root, no back-edge) and NO
//  auto-playing slideshow — the hero is static-first per the spec.
//
//  This is a DUMB screen: it owns no flow logic and reaches no singletons. The
//  two button actions are injected closures (the gateway wires them to the
//  coordinator), so the navigation effects are unit-testable by driving those
//  closures directly. Built on the Task 3.1 components — `OnboardingPrimaryCTA`
//  / `OnboardingSecondaryCTA` — so the buttons are never re-rolled here.
//
//  Design-system conformance (DESIGN.md + mobile/MOBILE.md):
//    • Pure-black canvas, glass + hairline brand card, zero shadows.
//    • Accent (`opsAccent`) appears ONLY on the primary CTA fill (via the
//      shared component) — nowhere else on this screen.
//    • Wordmark in Cake Mono (display role); tagline in Cake Mono badge role;
//      subline in Mohave body; version in JetBrains Mono (numbers = mono).
//    • One easing curve, honored only when Reduce Motion is off; the entrance
//      is nil'd under `accessibilityReduceMotion` and the hero is fully static.
//    • 44pt+ targets (CTAs are 52pt via the shared component).
//  Every literal traces to an `OPSStyle` token. Copy locked via ops-copywriter.
//

import SwiftUI

struct WelcomeStepView: View {

    /// GET STARTED — the primary, accented action. The gateway wires this to
    /// `coordinator.advance(to: .rolePick)`.
    let onGetStarted: () -> Void

    /// SIGN IN — the ghost action for returning users. The gateway wires this to
    /// `coordinator.advance(to: .login)`.
    let onSignIn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the one-shot entrance. Starts collapsed; flips true on appear.
    /// Under Reduce Motion the view renders in its final state with no transition.
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            // L0 — pure-black canvas.
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: OPSStyle.Layout.spacing5)

                brandHero

                Spacer(minLength: OPSStyle.Layout.spacing5)

                ctaStack
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5) // 20pt — §1 m-canvas-x
            .padding(.bottom, OPSStyle.Layout.spacing4)
        }
        .onAppear {
            // Warm the haptic generators; fire a single light arrival tick.
            OnboardingHaptics.prepare()
            OnboardingHaptics.selection()

            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true // No transition — land in final state.
            } else {
                withAnimation(OPSStyle.Animation.page) {
                    hasAppeared = true
                }
            }
        }
    }

    // MARK: - Brand hero (static-first — no slideshow)

    private var brandHero: some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            // OPS mark — the canonical brand glyph, monochrome `text`.
            Image("LogoWhite")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: heroMarkSize, height: heroMarkSize)
                .foregroundColor(OPSStyle.Colors.text)
                .accessibilityHidden(true) // Wordmark below carries the label.

            VStack(spacing: OPSStyle.Layout.spacing2_5) {
                // Wordmark — Cake Mono display voice, uppercase.
                Text("OPS")
                    .font(OPSStyle.Typography.display) // Cake Mono Light 30pt
                    .foregroundColor(OPSStyle.Colors.text)
                    .tracking(2)
                    .accessibilityAddTraits(.isHeader)

                // Tagline — the canonical brand line. Cake Mono badge role,
                // uppercase-for-authority, muted to `text2` so the wordmark leads.
                Text("BUILT BY TRADES. FOR TRADES.")
                    .font(OPSStyle.Typography.badgeCake) // Cake Mono Light 11pt
                    .foregroundColor(OPSStyle.Colors.text2)
                    .tracking(1.6)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Subline — the lifeline promise. Mohave body, sentence case.
                Text("The app your crew opens and just gets.")
                    .font(OPSStyle.Typography.body) // Mohave
                    .foregroundColor(OPSStyle.Colors.text3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, OPSStyle.Layout.spacing1)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(hasAppeared ? 1 : 0)
        // Subtle rise on entrance; nil under Reduce Motion (set at call site).
        .offset(y: (hasAppeared || reduceMotion) ? 0 : OPSStyle.Layout.spacing3)
    }

    // MARK: - CTAs + version footer

    private var ctaStack: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            // PRIMARY — the single accented control on the screen.
            OnboardingPrimaryCTA(title: "Get started") {
                onGetStarted()
            }

            // SECONDARY / ghost — returning users.
            OnboardingSecondaryCTA(title: "Sign in") {
                onSignIn()
            }

            // Version footer — JetBrains Mono (numbers are always mono),
            // `textMute` decorative, never tappable.
            Text(AppConfiguration.AppInfo.displayVersion)
                .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                .foregroundColor(OPSStyle.Colors.textMute)
                .tracking(1)
                .padding(.top, OPSStyle.Layout.spacing1)
                .accessibilityLabel("Version \(AppConfiguration.AppInfo.version)")
        }
    }

    // MARK: - Metrics

    /// Brand mark size — matches the established splash/landing presentation
    /// (80pt), scaled for the onboarding hero. A token-derived multiple, not a
    /// floating literal.
    private var heroMarkSize: CGFloat { OPSStyle.Layout.IconSize.xxl * 2 } // 96pt
}

// MARK: - Previews

#if DEBUG
#Preview("WelcomeStepView") {
    WelcomeStepView(onGetStarted: {}, onSignIn: {})
        .preferredColorScheme(.dark)
}
#endif
