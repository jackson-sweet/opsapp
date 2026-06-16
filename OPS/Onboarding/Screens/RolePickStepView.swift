//
//  RolePickStepView.swift
//  OPS
//
//  Onboarding rebuild P3 — S2 (Role pick).
//
//  Design spec §4.2 S2. Two TAPPABLE CARDS — RUN A CREW (owner) and JOIN A CREW
//  (crew). ONE tap per card: it commits the role into the coordinator's form
//  data AND advances to create-account in a single gesture. There is no
//  segmented control + separate continue button — the card IS the action. This
//  is the design-judgment call the spec demands: an either/or role choice
//  collapses to two equal entry points, each self-explanatory and committing on
//  the first tap (no second confirmation step for a once-ever decision).
//
//  This is a DUMB screen: it owns no flow logic and reaches no singletons. The
//  per-role commit and the back/sign-out escapes are injected closures (the
//  gateway wires them to the coordinator), so the navigation + form-data effects
//  are unit-testable by driving those closures directly. The header is the
//  Task 3.1 `OnboardingStepHeader`; it is fed Back when a back-edge exists
//  (pre-auth → Welcome) and SIGN OUT when resumed post-auth (no back-edge).
//
//  Design-system conformance (DESIGN.md + mobile/MOBILE.md):
//    • Pure-black canvas. Cards are L1 glass: `panelRadius`, hairline
//      `glassBorder`, glass fill — NO shadow.
//    • Accent (`opsAccent`) appears NOWHERE on this screen — the role cards are
//      neutral surfaces (accent = primary CTA only). The card affordance
//      chevron is `text3`, never accent.
//    • Title in Cake Mono (screen-title role); role labels in Cake Mono badge
//      role; headlines in Cake Mono section role; support copy in Mohave.
//    • Light selection haptic on card tap; one easing curve, honored only when
//      Reduce Motion is off; entrance nil'd under `accessibilityReduceMotion`.
//    • 56pt+ card tap targets (well above the 44pt floor).
//  Every literal traces to an `OPSStyle` token. Copy locked via ops-copywriter.
//

import SwiftUI

struct RolePickStepView: View {

    /// Commit OWNER + advance — wired by the gateway to
    /// `coordinator.update { $0.selectedRole = .owner }` then
    /// `coordinator.advance(to: .createAccount)`.
    let onSelectOwner: () -> Void

    /// Commit CREW + advance — the `.crew` analogue of `onSelectOwner`.
    let onSelectCrew: () -> Void

    /// Whether the live flow has a back-edge here (pre-auth → Welcome). The
    /// gateway passes `coordinator.canGoBack`. When true the header shows Back;
    /// when false (post-auth resume) it shows SIGN OUT instead.
    let canGoBack: Bool

    /// Follow the back-edge — wired to `coordinator.goBack()`.
    let onBack: () -> Void

    /// SIGN OUT escape (post-auth resume, no back-edge) — wired to the gateway's
    /// sign-out handler.
    let onSignOut: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // The header carries the control row (Back / SIGN OUT) AND the
                // screen title — the question IS the title, so there is no second
                // stacked title beneath it. Only the bracketed micro-instruction
                // follows, in the body.
                header

                instruction
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing2)

                Spacer(minLength: OPSStyle.Layout.spacing4)

                VStack(spacing: OPSStyle.Layout.spacing3) {
                    RoleCard(role: .owner, index: 0, hasAppeared: hasAppeared, reduceMotion: reduceMotion) {
                        OnboardingHaptics.selection()
                        onSelectOwner()
                    }
                    RoleCard(role: .crew, index: 1, hasAppeared: hasAppeared, reduceMotion: reduceMotion) {
                        OnboardingHaptics.selection()
                        onSelectCrew()
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                Spacer(minLength: OPSStyle.Layout.spacing4)
            }
            .padding(.bottom, OPSStyle.Layout.spacing4)
        }
        .onAppear {
            OnboardingHaptics.prepare()
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(OPSStyle.Animation.page) {
                    hasAppeared = true
                }
            }
        }
    }

    // MARK: - Header (Back pre-auth, SIGN OUT post-auth resume)

    private var header: some View {
        // The Task 3.1 dumb header. The question is the title (no second stacked
        // title). Pre-auth there is a back-edge to Welcome, so feed Back;
        // post-auth resume has no edge, so feed SIGN OUT. Never both.
        Group {
            if canGoBack {
                OnboardingStepHeader(
                    title: "How will you use OPS?",
                    backLabel: "Welcome",
                    onBack: onBack
                )
            } else {
                OnboardingStepHeader(
                    title: "How will you use OPS?",
                    onSignOut: onSignOut
                )
            }
        }
    }

    // MARK: - Bracketed micro-instruction (sits under the title)

    private var instruction: some View {
        // Bracketed micro-instruction per the OPS voice (`[ … ]`).
        Text("[ PICK YOUR LANE ]")
            .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
            .foregroundColor(OPSStyle.Colors.text3)
            .tracking(1.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: (hasAppeared || reduceMotion) ? 0 : OPSStyle.Layout.spacing3)
    }
}

// MARK: - Role model (flow-local copy, locked via ops-copywriter)

/// The two onboarding roles, with their locked card copy. Distinct from the
/// legacy `UserTypeChoice` (which drives the old segmented-control flow) — this
/// is the single-tap-card model for the rebuilt S2. Each case maps 1:1 to an
/// `OnboardingFlowRole`; the card's tap closure does the commit + advance.
private enum RolePickRole {
    case owner
    case crew

    /// Short uppercase label — Cake Mono badge voice.
    var label: String {
        switch self {
        case .owner: return "RUN A CREW"
        case .crew:  return "JOIN A CREW"
        }
    }

    /// The praised role-benefit headline (retained tone from the existing flow).
    var headline: String {
        switch self {
        case .owner: return "REGISTER YOUR COMPANY. RUN YOUR JOBS."
        case .crew:  return "SEE YOUR JOBS. GET TO WORK."
        }
    }

    /// One supporting line, sentence case (Mohave body).
    var support: String {
        switch self {
        case .owner:
            return "Create jobs, assign your crew, track progress. No training—open it and you know what to do."
        case .crew:
            return "Your schedule, job details, and directions in one place. No more digging through texts."
        }
    }

    /// SF Symbol affordance glyph. Metadata, not an action — never accent-tinted.
    var icon: String {
        switch self {
        case .owner: return "person.3.fill"        // OPSStyle.Icons.crew
        case .crew:  return "person.badge.plus"    // join affordance
        }
    }

    /// VoiceOver: the label + headline read as a single actionable card.
    var accessibilityLabel: String {
        "\(label). \(headline)"
    }
}

// MARK: - Role card (single-tap commit + advance)

private struct RoleCard: View {
    let role: RolePickRole
    let index: Int
    let hasAppeared: Bool
    let reduceMotion: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing3) {
                // Leading glyph — metadata color, never accent.
                Image(systemName: role.icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.lg, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text2)
                    .frame(width: OPSStyle.Layout.IconSize.xl, alignment: .leading)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text(role.label)
                        .font(OPSStyle.Typography.badgeCake) // Cake Mono Light 11pt
                        .foregroundColor(OPSStyle.Colors.text3)
                        .tracking(1.4)

                    Text(role.headline)
                        .font(OPSStyle.Typography.section) // Cake Mono Light 18pt
                        .foregroundColor(OPSStyle.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(role.support)
                        .font(OPSStyle.Typography.smallBody) // Mohave Light 14pt
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                // Affordance chevron — `text3`, NOT accent (accent = primary CTA).
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.text3)
                    .padding(.top, OPSStyle.Layout.spacing1)
            }
            .padding(OPSStyle.Layout.spacing3) // 16pt — §1 m-card-inset
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard) // ≥56pt tap target
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                    // Pressed → brighter interactive fill; rest → L1 glass approx.
                    .fill(isPressed ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.glassApprox)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                    .stroke(
                        isPressed ? OPSStyle.Colors.line : OPSStyle.Colors.glassBorder,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.99 : 1.0))
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(reduceMotion ? nil : OPSStyle.Animation.hover) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(role.accessibilityLabel)
        .accessibilityHint(role.support)
        .accessibilityAddTraits(.isButton)
        // Staggered entrance — second card lags one step; nil under Reduce Motion.
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: (hasAppeared || reduceMotion) ? 0 : OPSStyle.Layout.spacing3)
        .animation(
            reduceMotion ? nil
                : OPSStyle.Animation.page.delay(Double(index) * OPSStyle.Animation.durationStaggerStep),
            value: hasAppeared
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("RolePickStepView — pre-auth (Back)") {
    RolePickStepView(
        onSelectOwner: {},
        onSelectCrew: {},
        canGoBack: true,
        onBack: {},
        onSignOut: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("RolePickStepView — post-auth resume (Sign out)") {
    RolePickStepView(
        onSelectOwner: {},
        onSelectCrew: {},
        canGoBack: false,
        onBack: {},
        onSignOut: {}
    )
    .preferredColorScheme(.dark)
}
#endif
