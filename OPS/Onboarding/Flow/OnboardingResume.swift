//
//  OnboardingResume.swift
//  OPS
//
//  Onboarding rebuild §5.3 — server-state → resume-step derivation.
//  The server-observable state is the authority; local flow state is an
//  optimization only. Rules are evaluated in strict priority order.
//

import Foundation

/// The server-observable onboarding facts the resume decision is made from.
struct OnboardingServerState: Equatable {
    /// The user row has a company affiliation.
    let hasCompany: Bool
    /// `users.role`, e.g. "owner", "crew". Uncommitted until a company exists.
    let role: String?
    /// `users.user_type`, "company"/"employee". Carried for completeness;
    /// derivation keys off `hasCompany` and `role` only.
    let userType: String?
    /// First, last, and phone all non-blank.
    let profileComplete: Bool
    /// `onboarding_completed.web == true`.
    let webComplete: Bool
}

/// Derives the step the onboarding flow resumes at from server state.
enum OnboardingResume {
    /// Rules in strict priority order (§5.3):
    /// 1. No company → role pick. Role is uncommitted regardless of stored
    ///    `userType`/`role`.
    /// 2. Company + web already complete → completion gate. Silent
    ///    auto-complete: the gate fires the iOS ACK, zero screens.
    /// 3. Company + owner → completion gate (NOT the crew-code screen).
    ///    `derive` is only reached on RESUME / cross-device — never the fresh
    ///    owner flow, which advances crewCode→completionGate via the screen CTA.
    ///    The crew code is a ONE-TIME reveal payoff (and lives in Settings
    ///    afterward); re-showing it on resume would land a returning owner with no
    ///    v4 blob on a BLANK `[ ]` (form data's `generatedCrewCode` is empty
    ///    cross-device). So a resuming owner skips straight to the gate → app.
    /// 4. Company + employee + incomplete profile → profile.
    /// 5. Company + employee + complete profile → completion gate.
    ///    Emergency contact is optional and never re-offered on resume.
    static func derive(_ state: OnboardingServerState) -> OnboardingFlowStep {
        guard state.hasCompany else {
            return .rolePick
        }
        if state.webComplete {
            return .completionGate
        }
        // Case-insensitive: legacy rows may carry title-case values e.g. "Owner".
        if state.role?.lowercased() == "owner" {
            return .completionGate
        }
        if !state.profileComplete {
            return .profile
        }
        return .completionGate
    }
}
