//
//  OnboardingGateway.swift
//  OPS
//
//  Onboarding rebuild P2 — the SwiftUI shell that hosts the rebuilt onboarding
//  flow. It owns a single `OnboardingFlowCoordinator`, maps the live user into
//  the server-state the coordinator derives resume placement from, renders the
//  screen for the current step, and performs the host-level side effects
//  (completion → enter the app, sign-out → real auth signout).
//
//  This file is DEAD until `FeatureFlags.useRebuiltOnboarding` is flipped true
//  AND ContentView routes to it. The default-false flag keeps the legacy flow
//  shipping until cutover.
//
//  SCOPE (P2): every per-step screen below is a PLACEHOLDER stub
//  (`OnboardingPlaceholderStep`) — labeled, walkable scaffolding so a debug
//  build can drive the flow end-to-end. The real, design-system-final screens
//  replace these in P3–P5; the §12 design gate applies to THOSE, not to this
//  scaffolding. Do not treat the stub styling as canonical.
//

import SwiftUI

struct OnboardingGateway: View {

    @EnvironmentObject private var dataController: DataController

    /// One coordinator for the lifetime of the gateway. Constructed with a fresh
    /// store (live `.standard` UserDefaults), a live auth-state closure, and a
    /// server-state provider that maps the current user into the facts
    /// `OnboardingResume` derives placement from. Dependencies are injected so
    /// the coordinator stays free of singleton reach and unit-testable.
    @StateObject private var coordinator: OnboardingFlowCoordinator

    init() {
        // `dataController` is not yet available here (environment objects are
        // injected after init), so the closures capture it lazily. They run only
        // after the view is in the hierarchy — `start()` is called from
        // `.onAppear`, never from init — so the environment object is present by
        // the time either closure is first invoked.
        //
        // The capture is resolved at call time via a holder the body wires up in
        // `.onAppear` (see `bind`), avoiding capturing `self` (a struct) or an
        // un-injected environment object inside the init.
        let holder = DataControllerHolder()
        _coordinator = StateObject(wrappedValue: OnboardingFlowCoordinator(
            store: OnboardingFlowStateStore(),
            isAuthenticated: { holder.controller?.isAuthenticated ?? false },
            serverStateProvider: {
                guard let user = holder.controller?.currentUser else { return nil }
                return Self.serverState(for: user)
            }
        ))
        _holder = StateObject(wrappedValue: holder)
    }

    /// Bridges the environment-injected `dataController` into the closures the
    /// coordinator captured at init. Set once in `.onAppear`, before `start()`.
    @StateObject private var holder: DataControllerHolder

    var body: some View {
        OnboardingPlaceholderStep(
            step: coordinator.currentStep,
            canGoBack: coordinator.canGoBack,
            onContinue: { handleContinue() },
            onBack: { coordinator.goBack() },
            onSignOut: { handleSignOut() }
        )
        .onAppear {
            // Wire the live controller into the coordinator's closures BEFORE
            // resolving the entry point, then start (idempotent).
            holder.controller = dataController
            coordinator.start()
        }
    }

    // MARK: - Host-level side effects

    /// Advance off the current step. P2 scaffolding: this walks the linear
    /// forward path so the flow is traversable in a debug build. The completion
    /// step is terminal — CONTINUE there finishes onboarding (host action below)
    /// rather than advancing to another step. The real per-step forward logic
    /// (branching on role, invite results, etc.) lands with the real screens in
    /// P3–P5.
    private func handleContinue() {
        if coordinator.currentStep == .completionGate {
            handleComplete()
            return
        }
        if let next = Self.placeholderNextStep(after: coordinator.currentStep) {
            coordinator.advance(to: next)
        }
    }

    /// Onboarding finished. Drop the coordinator's local optimisation blob and
    /// admit the user into the authenticated app.
    ///
    /// TODO(P4): the full completion gate — server `onboarding_completed.ios`
    /// ACK, the completion-pending sweep, and the precise admit predicate
    /// (DataController.isAppBound) — is wired in P4. For P2 scaffolding this
    /// performs the minimal correct host action: clear local flow state and flip
    /// `isAuthenticated` so the app routes to PINGatedView. It is guarded so it
    /// only admits when a user actually exists; a stub-walked flow with no signed
    /// -in user simply resets without falsely entering the app.
    private func handleComplete() {
        coordinator.complete()
        if dataController.currentUser != nil {
            dataController.isAuthenticated = true
        }
    }

    /// SIGN OUT escape. Triggers the real auth signout (which flips
    /// `isAuthenticated`, clears the user, posts `LogoutInitiated`, and wipes
    /// auth tokens) AND resets the coordinator's local flow state.
    private func handleSignOut() {
        coordinator.signOut()
        dataController.logout()
    }

    // MARK: - Server-state mapping

    /// Maps the live user row into the server-observable facts
    /// `OnboardingResume.derive` keys off. Returns `nil` when there is no current
    /// user (facts unknown) so the coordinator falls back to `.welcome`.
    ///
    /// Field sources (verified against `User` / `DataController`):
    ///   - `hasCompany`        ← `companyId` non-nil & non-blank
    ///   - `role`              ← `role.rawValue` (UserRole; derive is case-insensitive)
    ///   - `userType`          ← `userType?.rawValue` (UserType?)
    ///   - `profileComplete`   ← firstName & lastName & phone all non-blank
    ///   - `webComplete`       ← NOT EXPOSED on the local model — see TODO below.
    private static func serverState(for user: User) -> OnboardingServerState {
        let hasCompany = !(user.companyId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let firstOK = !user.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let lastOK = !user.lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let phoneOK = !(user.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let profileComplete = firstOK && lastOK && phoneOK

        // TODO(P4): `onboarding_completed.web` is NOT exposed on the local `User`
        // model or the user DTO — the iOS client only tracks the app/iOS ACK
        // (`hasCompletedAppOnboarding`), never the web flag. Surfacing the web
        // flag requires a server/DTO/model change that is out of P2 scope and
        // must not be invented here. Until it lands, `webComplete` is reported
        // `false`. Consequence (per OnboardingResume.derive): a returning user
        // who finished onboarding on WEB but not on iOS is NOT silently
        // auto-completed to the completion gate — they are routed by company +
        // role + profile instead (owner → crewCode, employee → profile/gate).
        // This is the SAFE default: it never skips required local steps. The
        // exact web-driven silent auto-complete is finished in P4 once the flag
        // is available on the model.
        let webComplete = false

        return OnboardingServerState(
            hasCompany: hasCompany,
            role: user.role.rawValue,
            userType: user.userType?.rawValue,
            profileComplete: profileComplete,
            webComplete: webComplete
        )
    }

    // MARK: - P2 placeholder forward path

    /// The next step in the LINEAR scaffolding walk. This is NOT the real flow
    /// graph — it exists only so the P2 stub can advance through every step in a
    /// debug build. Branching steps (rolePick → owner/crew, inviteCheck →
    /// picker/code, etc.) are linearised here; the real branching logic ships
    /// with the real screens in P3–P5.
    private static func placeholderNextStep(after step: OnboardingFlowStep) -> OnboardingFlowStep? {
        switch step {
        case .welcome:           return .rolePick
        case .login:             return .rolePick
        case .rolePick:          return .createAccount
        case .createAccount:     return .companyName
        case .companyName:       return .crewCode
        case .crewCode:          return .completionGate
        case .inviteCheck:       return .invitePicker
        case .invitePicker:      return .codeEntry(provenance: .fromPicker)
        case .codeEntry(let p):  return .confirmCompany(source: .codeEntry(p))
        case .confirmCompany:    return .profile
        case .profile:           return .emergencyContact
        case .emergencyContact:  return .completionGate
        case .completionGate:    return nil // terminal — CONTINUE completes
        }
    }
}

// MARK: - DataController holder

/// A tiny reference box so `OnboardingGateway.init` can hand the coordinator's
/// closures a forward reference to the environment-injected `dataController`
/// without capturing an un-injected value. The body sets `controller` in
/// `.onAppear` before any closure fires. `ObservableObject` only so it can live
/// in a `@StateObject` and survive view re-creation alongside the coordinator;
/// it publishes nothing.
private final class DataControllerHolder: ObservableObject {
    weak var controller: DataController?
}

// MARK: - P2 placeholder step

/// TEMPORARY P2 scaffolding — NOT a design-system-final screen. A single labeled
/// view that renders the current step's identifier and the navigation
/// affordances available at that step (CONTINUE always; BACK when the coordinator
/// reports a back-edge; SIGN OUT when there is no back-edge, i.e. the step's only
/// escape is signing out). It exists solely to make the flow walkable in a debug
/// build while the real screens are built in P3–P5. Styling uses OPSStyle tokens
/// to avoid hardcoded values, but the layout/copy are placeholders and the §12
/// design gate does NOT apply to this view.
private struct OnboardingPlaceholderStep: View {
    let step: OnboardingFlowStep
    let canGoBack: Bool
    let onContinue: () -> Void
    let onBack: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: OPSStyle.Layout.spacing4) {
                Spacer()

                VStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("// ONBOARDING — P2 SCAFFOLDING")
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text(stepIdentifier)
                        .font(OPSStyle.Typography.display)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Button(action: onContinue) {
                        Text(step == .completionGate ? "FINISH" : "CONTINUE")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(OPSStyle.Colors.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetLarge)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                    }

                    if canGoBack {
                        Button(action: onBack) {
                            Text("BACK")
                                .font(OPSStyle.Typography.buttonLabel)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: OPSStyle.Layout.touchTargetStandard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                        .stroke(OPSStyle.Colors.secondaryText, lineWidth: 1)
                                )
                        }
                    } else {
                        // No back-edge at this step → SIGN OUT is the escape.
                        Button(action: onSignOut) {
                            Text("SIGN OUT")
                                .font(OPSStyle.Typography.buttonLabel)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: OPSStyle.Layout.touchTargetStandard)
                        }
                    }
                }
            }
            .padding(OPSStyle.Layout.contentPadding)
        }
    }

    /// Human-readable step identifier for the scaffolding label, including
    /// provenance/source for the parameterised steps so the walk is legible.
    private var stepIdentifier: String {
        switch step {
        case .welcome:                  return "WELCOME"
        case .login:                    return "LOGIN"
        case .rolePick:                 return "ROLE PICK"
        case .createAccount:            return "CREATE ACCOUNT"
        case .companyName:              return "COMPANY NAME"
        case .crewCode:                 return "CREW CODE"
        case .inviteCheck:              return "INVITE CHECK"
        case .invitePicker:             return "INVITE PICKER"
        case .codeEntry(let p):         return "CODE ENTRY (\(p.rawValue))"
        case .confirmCompany(let s):    return "CONFIRM COMPANY (\(confirmSourceLabel(s)))"
        case .profile:                  return "PROFILE"
        case .emergencyContact:         return "EMERGENCY CONTACT"
        case .completionGate:           return "COMPLETION GATE"
        }
    }

    private func confirmSourceLabel(_ source: ConfirmSource) -> String {
        switch source {
        case .picker:                   return "picker"
        case .codeEntry(let p):         return "codeEntry/\(p.rawValue)"
        }
    }
}
