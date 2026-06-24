//
//  WelcomeStepView.swift
//  OPS
//
//  Onboarding rebuild P3 — S1 (Welcome), the root of the rebuilt flow.
//
//  Design spec §4.2 S1. Serves new AND returning users identically: a full-bleed
//  hero photo slideshow behind a LEFT-ALIGNED brand block (mark + wordmark on one
//  baseline, tagline + subline lower), a version footer, and two full-width CTAs
//  pinned in the thumb zone — GET STARTED (primary, accent) → role pick, SIGN IN
//  (ghost) → login. There is NO header back (Welcome is the root, no back-edge).
//
//  Hero slideshow (owner feedback 2026-06-23 — "the slideshow seems to have been
//  removed"; restore it): six cross-fading field photos (`hero_1…6`, the legacy
//  splash assets in Assets.xcassets/Images). Motion is an AMBIENT beat — felt, not
//  watched — so it carries NO haptic and crossfades on the single OPS easing curve,
//  advanced by a `TimelineView` schedule (the SwiftUI-sanctioned time-driven
//  animator — never a `Timer`), never a spring/bounce and never `.easeInOut`. Under
//  `accessibilityReduceMotion` the slideshow is fully STATIC: first frame only, no
//  schedule, no advance. A token scrim gradient (black overlay tokens, top→bottom)
//  keeps the left-aligned text and the bottom CTAs legible over any photo.
//
//  This is a DUMB screen: it owns no flow logic and reaches no singletons. The two
//  button actions are injected closures (the gateway wires them to the coordinator),
//  so the navigation effects are unit-testable by driving those closures directly.
//  Built on the Task 3.1 components — `OnboardingPrimaryCTA` / `OnboardingSecondaryCTA`
//  — so the buttons are never re-rolled here.
//
//  Design-system conformance (DESIGN.md + mobile/MOBILE.md):
//    • Pure-black canvas under the hero; full-bleed photo with a token scrim.
//    • LEFT-ALIGNED brand block (MOBILE.md — OPS is left-aligned, never centered).
//    • Accent (`opsAccent`) appears ONLY on the primary CTA fill (via the shared
//      component) — nowhere else on this screen.
//    • Wordmark in Cake Mono (display role); tagline in Cake Mono badge role;
//      subline in Mohave body; version in JetBrains Mono (numbers = mono).
//    • One easing curve, honored only when Reduce Motion is off; the entrance and
//      the slideshow crossfade both nil out / freeze under Reduce Motion.
//    • Zero shadows on UI chrome; 44pt+ targets (CTAs are 52pt via the component).
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

    /// Stable origin for the ambient slideshow schedule. Captured once when the
    /// view's state is created and persisted across re-appears. The active slide is
    /// DERIVED from elapsed time against this origin (see `heroSlideshow`) — there
    /// is no per-frame `@State` and no `Timer`; a `TimelineView` schedule drives the
    /// crossfade, the SwiftUI-sanctioned time-driven animator (auto-pauses
    /// off-screen, nothing to tear down).
    @State private var slideshowStart = Date()

    /// The field-photo assets, in advance order. Reuses the legacy splash slideshow
    /// imagery (Assets.xcassets/Images/hero_1…6).
    private let heroImages = ["hero_1", "hero_2", "hero_3", "hero_4", "hero_5", "hero_6"]

    var body: some View {
        ZStack {
            // L0 — pure-black canvas (also the backstop while photos decode).
            OPSStyle.Colors.background.ignoresSafeArea()

            // Hero slideshow + scrim sit BEHIND all content.
            heroSlideshow
            scrim

            VStack(alignment: .leading, spacing: 0) {
                // Brand lockup pinned to the top-left.
                brandLockup

                Spacer(minLength: OPSStyle.Layout.spacing5)

                // Brand message (tagline + subline) lives lower, above the CTAs —
                // the eye lands on the photo, then the promise, then the action.
                brandMessage

                Spacer(minLength: OPSStyle.Layout.spacing4)

                ctaStack
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5) // 20pt — §1 m-canvas-x
            .padding(.top, OPSStyle.Layout.spacing5)
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

    // MARK: - Hero slideshow (ambient — no haptic, OPS curve, static under RM)

    private var heroSlideshow: some View {
        GeometryReader { geometry in
            if reduceMotion {
                // Reduce Motion → fully static: render ONLY the first frame. No
                // TimelineView, no schedule, no crossfade — the atmosphere is
                // carried by a single strong photo with zero motion or battery cost.
                heroFrame(heroImages[0], in: geometry)
            } else {
                // Ambient crossfade driven by a `SwiftUI.TimelineView` schedule —
                // the SwiftUI-sanctioned time-driven animator (never a `Timer`).
                // Fully qualified because the app defines its OWN `TimelineView`
                // (the calendar timeline) which would otherwise shadow SwiftUI's.
                // The active slide is derived purely from elapsed time, so the
                // schedule is the single source of truth and there is no per-frame
                // state to leak. It stops ticking when the view is off-screen.
                SwiftUI.TimelineView(.periodic(from: slideshowStart, by: heroDwellDuration)) { context in
                    let active = slideIndex(at: context.date)
                    ZStack {
                        ForEach(heroImages.indices, id: \.self) { index in
                            heroFrame(heroImages[index], in: geometry)
                                // Only the active frame is visible; the rest fade
                                // out. The crossfade rides the single OPS curve at
                                // ~1s — never a spring/bounce, never `.easeInOut`.
                                .opacity(active == index ? 1 : 0)
                                .animation(OPSStyle.Animation.curve(heroCrossfadeDuration), value: active)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true) // Decorative atmosphere; the wordmark carries the label.
    }

    /// One full-bleed hero frame, clipped to the hero region.
    private func heroFrame(_ name: String, in geometry: GeometryProxy) -> some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
    }

    /// The slide showing at a given tick — derived purely from elapsed time against
    /// `slideshowStart`, wrapped by the photo count. No stored frame index; the
    /// `TimelineView` schedule is the single source of truth.
    private func slideIndex(at date: Date) -> Int {
        let elapsed = date.timeIntervalSince(slideshowStart)
        guard elapsed > 0 else { return 0 }
        return Int(elapsed / heroDwellDuration) % max(heroImages.count, 1)
    }

    /// Token scrim — top→bottom black gradient so the left-aligned text and the
    /// bottom CTAs stay legible over any photo. All stops are `Colors` overlay
    /// tokens (no hardcoded alphas); it bottoms out at the pure-black canvas so the
    /// CTAs read on solid black.
    private var scrim: some View {
        LinearGradient(
            colors: [
                OPSStyle.Colors.modalOverlay,  // black @ 0.50 — top, keeps the photo readable
                OPSStyle.Colors.overlayMedium, // black @ 0.60
                OPSStyle.Colors.overlayHeavy,  // black @ 0.85
                OPSStyle.Colors.background      // pure black — CTAs land on solid ground
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Brand lockup (top-left — mark + wordmark on one baseline)

    private var brandLockup: some View {
        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
            // OPS mark — the canonical brand glyph, monochrome `text`.
            Image("LogoWhite")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: heroMarkSize, height: heroMarkSize)
                .foregroundColor(OPSStyle.Colors.text)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - markBaselineInset }
                .accessibilityHidden(true) // Wordmark carries the label.

            // Wordmark — Cake Mono display voice, uppercase.
            Text("OPS")
                .font(OPSStyle.Typography.display) // Cake Mono Light 30pt
                .foregroundColor(OPSStyle.Colors.text)
                .tracking(2)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: (hasAppeared || reduceMotion) ? 0 : -OPSStyle.Layout.spacing2)
    }

    // MARK: - Brand message (left-aligned tagline + subline)

    private var brandMessage: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            // Tagline — the canonical brand line. Cake Mono badge role,
            // uppercase-for-authority, `text2` so it leads without shouting.
            Text("BUILT BY TRADES. FOR TRADES.")
                .font(OPSStyle.Typography.badgeCake) // Cake Mono Light 11pt
                .foregroundColor(OPSStyle.Colors.text2)
                .tracking(1.6)
                .fixedSize(horizontal: false, vertical: true)

            // Subline — the lifeline promise. Mohave body, sentence case. The
            // proven OPS line: names the gut problem (crews refuse software) in
            // the fewest possible words. (ops-copywriter — replaces the cut line.)
            Text("Job management your crew will actually use.")
                .font(OPSStyle.Typography.title) // Mohave SemiBold 28pt — display weight
                .foregroundColor(OPSStyle.Colors.text)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .opacity(hasAppeared ? 1 : 0)
        // Subtle rise on entrance; nil under Reduce Motion.
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
            // `textMute` decorative, never tappable. LEFT-aligned with the brand
            // block (MOBILE.md — OPS is left-aligned, never centered); it was the
            // one stray centered element on the screen.
            Text(AppConfiguration.AppInfo.displayVersion)
                .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                .foregroundColor(OPSStyle.Colors.textMute)
                .tracking(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, OPSStyle.Layout.spacing1)
                .accessibilityLabel("Version \(AppConfiguration.AppInfo.version)")
        }
    }

    // MARK: - Metrics

    /// Brand mark size — the lockup glyph beside the wordmark. A token-derived
    /// multiple, not a floating literal. Sized to sit on the Cake 30pt baseline.
    private var heroMarkSize: CGFloat { OPSStyle.Layout.IconSize.xl } // 32pt

    /// Nudge that drops the mark onto the wordmark's text baseline (the glyph has
    /// no descender to align to). A token-derived hairline, not a magic number.
    private var markBaselineInset: CGFloat { OPSStyle.Layout.spacing1 } // 4pt

    /// Ambient dwell — seconds a photo holds before the next crossfade begins.
    private var heroDwellDuration: TimeInterval { 4.0 }

    /// Crossfade length — seconds for one photo to dissolve into the next, on the
    /// OPS curve.
    private var heroCrossfadeDuration: Double { 1.0 }
}

// MARK: - Previews

#if DEBUG
#Preview("WelcomeStepView") {
    WelcomeStepView(onGetStarted: {}, onSignIn: {})
        .preferredColorScheme(.dark)
}
#endif
