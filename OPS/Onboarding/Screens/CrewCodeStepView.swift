//
//  CrewCodeStepView.swift
//  OPS
//
//  Onboarding rebuild P4 — S5o (Crew code): the PAYOFF screen.
//
//  Design spec §4.2 S5o. The company is created; this is the celebration + handoff.
//  The owner sees their company name confirmed and the DB-truth crew code, copies
//  it / invites their crew, then enters the app. There is NO header back
//  (`crewCode.backEdge == nil` — the company is committed, this is forward-only)
//  and NO SIGN OUT (nothing to escape from — the account + company exist).
//
//  Layout (top → bottom):
//    • Header — title only (no Back, no SIGN OUT).
//    • Confirmation subline — "<Company> is ready."
//    • Crew code — the SHARED `OnboardingCodeDisplay` (display mode): the SAME
//      bracketed JetBrains-Mono glyph the crew-ENTRY screen renders, with the
//      built-in COPY affordance (success haptic + COPIED confirm).
//    • Share line + INVITE CREW — a native share of the code so the owner can fire
//      it into a text/email to their crew. Reuses iOS's share sheet (no bespoke
//      invite UI to drift from the design system).
//    • Reassurance — "You'll find this code in Settings anytime."
//    • Primary CTA — "Enter OPS" → completion gate.
//
//  This is a DUMB screen: it owns no flow logic and reaches no singletons. The
//  code + company name are passed in (the gateway reads `coordinator.formData`),
//  and the single CTA action is an injected closure (wired to
//  `coordinator.advance(to: .completionGate)`), so the navigation is unit-testable
//  by driving that closure directly.
//
//  Design-system conformance (`DESIGN.md` + `mobile/MOBILE.md`):
//    • Pure-black canvas, glass + hairlines, ZERO shadows. Accent (`opsAccent`)
//      appears ONLY on the primary CTA (via the shared component). The code glyph,
//      COPY, and INVITE CREW are all neutral — never accent.
//    • Built on the shared `OnboardingCodeDisplay` + `OnboardingStepHeader` +
//      `OnboardingPrimaryCTA`. Nothing re-rolled.
//    • One easing curve; honored only when Reduce Motion is off.
//  Every literal traces to an `OPSStyle` token. Copy locked via ops-copywriter.
//

import SwiftUI

struct CrewCodeStepView: View {

    /// The DB-truth crew code returned by the create-company RPC. The gateway
    /// passes `coordinator.formData.generatedCrewCode`.
    let crewCode: String

    /// The company name, for the confirmation subline. The gateway passes
    /// `coordinator.formData.companyName`.
    let companyName: String

    /// ENTER OPS — the single forward action. The gateway wires this to
    /// `coordinator.advance(to: .completionGate)`.
    let onEnter: () -> Void

    // MARK: Init

    init(
        crewCode: String,
        companyName: String,
        onEnter: @escaping () -> Void
    ) {
        self.crewCode = crewCode
        self.companyName = companyName
        self.onEnter = onEnter
    }

    #if DEBUG
    /// Snapshot/preview seam — settles the entrance for snapshots. DEBUG-only.
    init(
        crewCode: String,
        companyName: String,
        previewSettled: Bool,
        onEnter: @escaping () -> Void = {}
    ) {
        self.crewCode = crewCode
        self.companyName = companyName
        self.onEnter = onEnter
        _hasAppeared = State(initialValue: previewSettled)
    }
    #endif

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    /// What gets shared via INVITE CREW — the code plus a one-line instruction so a
    /// crew member who receives it knows exactly what to do. Copy locked via
    /// ops-copywriter (terse, no emoji, no exclamation).
    private var shareMessage: String {
        "Join \(companyName) on OPS. Download the app and enter crew code: \(crewCode)"
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                scrollContent
            }
        }
        .onAppear {
            OnboardingHaptics.prepare()
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(OPSStyle.Animation.page) { hasAppeared = true }
            }
        }
    }

    /// The full vertical stack. Extracted so the DEBUG snapshot harness can render
    /// it WITHOUT the enclosing `ScrollView`.
    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            header

            confirmation
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            codeBlock
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            inviteBlock
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            reassurance
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            ctaBlock
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
        .padding(.bottom, OPSStyle.Layout.spacing5)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: (hasAppeared || reduceMotion) ? 0 : OPSStyle.Layout.spacing3)
    }

    #if DEBUG
    /// A render of the screen with no `ScrollView`, for the snapshot harness only.
    var snapshotBody: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()
            scrollContent
        }
    }
    #endif

    // MARK: - Header (title only — forward-only, no Back / SIGN OUT)

    private var header: some View {
        OnboardingStepHeader(title: "You're set up.")
    }

    // MARK: - Confirmation subline

    private var confirmation: some View {
        Text(confirmationText)
            .font(OPSStyle.Typography.body) // Mohave 16pt
            .foregroundColor(OPSStyle.Colors.text2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(confirmationText)
    }

    /// "<Company> is ready." — falls back to a company-agnostic line when the name
    /// is somehow blank (defensive; the owner always has a name by this point).
    private var confirmationText: String {
        let name = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Your company is ready." : "\(name) is ready."
    }

    // MARK: - Crew code (shared display component)

    private var codeBlock: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("// CREW CODE")
                .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                .foregroundColor(OPSStyle.Colors.text3)
                .tracking(1.4)
                .accessibilityHidden(true) // the display component carries the label

            // The SHARED renderer — identical bracketed glyph to the crew ENTRY
            // screen, with the built-in COPY (success haptic + COPIED confirm).
            OnboardingCodeDisplay(code: crewCode)
        }
    }

    // MARK: - Invite crew (native share of the code)

    private var inviteBlock: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("Send this to your crew so they can join.")
                .font(OPSStyle.Typography.smallBody) // Mohave Light 14pt
                .foregroundColor(OPSStyle.Colors.text3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Reuse iOS's share sheet — the simplest, most reliable field
            // affordance (works offline, no companyId dependency). Ghost / hairline
            // styling matching the secondary-CTA spec — NEVER accent.
            ShareLink(item: shareMessage) {
                inviteLabel
            }
            .simultaneousGesture(TapGesture().onEnded { OnboardingHaptics.selection() })
            .accessibilityLabel("Invite crew")
        }
    }

    /// The INVITE CREW button face — secondary (ghost + hairline) per `mobile/MOBILE.md`
    /// §8. Person glyph + Cake Mono label, `text2`, NO accent.
    private var inviteLabel: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.personTwo)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
            Text("INVITE CREW")
                .font(OPSStyle.Typography.buttonLabel) // Cake Mono 300, 14pt
        }
        .foregroundColor(OPSStyle.Colors.text2)
        .frame(maxWidth: .infinity)
        .frame(height: OPSStyle.Layout.bottomCTAHeight) // 52pt, matches the primary CTA
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Reassurance

    private var reassurance: some View {
        Text("You'll find this code in Settings anytime.")
            .font(OPSStyle.Typography.smallBody) // Mohave Light 14pt
            .foregroundColor(OPSStyle.Colors.textMute)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("You'll find this code in Settings anytime")
    }

    // MARK: - CTA (ENTER OPS → completion gate)

    private var ctaBlock: some View {
        OnboardingPrimaryCTA(title: "Enter OPS") {
            onEnter()
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("CrewCodeStepView") {
    CrewCodeStepView(
        crewCode: "BR8K-90ZT",
        companyName: "Sweet Deck & Rail",
        onEnter: {}
    )
    .preferredColorScheme(.dark)
}
#endif
