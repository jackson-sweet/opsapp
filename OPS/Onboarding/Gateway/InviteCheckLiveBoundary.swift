//
//  InviteCheckLiveBoundary.swift
//  OPS
//
//  The LIVE implementation of S4c's `InviteCheckBoundary`, backed by the
//  `CompanyRepository.checkPendingInvites(email:)` SECURITY-DEFINER RPC. This is
//  the only place the rebuilt invite-check screen touches the real network — S4c
//  itself stays dumb and testable behind the protocol.
//
//  R13 — VISIBLE FAILURE, NOT SILENT ZERO. The repository's own
//  `checkPendingInvites(email:)` swallows a DECODE failure (returns `[]`), but a
//  genuine network / RPC throw propagates. `OnboardingManager.checkPendingInvites()`
//  swallows BOTH (sets `pendingInvites = []` on any error), which is exactly the
//  R13 trap — a fetch failure would masquerade as "zero invites" and silently
//  route the user to code entry. This boundary therefore calls the REPOSITORY
//  DIRECTLY and maps a thrown error to `.failed`, so the screen can surface a
//  retry-able failure state instead of a false zero.
//
//  An empty email is NOT a fetch failure — it is a legitimate "no invites to find"
//  (a social-auth user with no email on the row), so it resolves `.found([])`.
//

import Foundation

@MainActor
struct InviteCheckLiveBoundary: InviteCheckBoundary {

    /// The email to check pending invites against — the gateway passes
    /// `coordinator.formData.email` (falling back to the live user's email).
    let email: String?

    func checkInvites() async -> InviteCheckOutcome {
        let trimmed = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // No email on the row → legitimately zero invites to find (not a failure).
        // A social-auth identity may carry no email; the crew path still works via
        // the code-entry fallback the screen routes to on `.found([])`.
        guard !trimmed.isEmpty else {
            return .found([])
        }

        do {
            // Repository call DIRECTLY — bypassing OnboardingManager's swallowing
            // wrapper so a network / RPC throw is a VISIBLE failure (R13), never a
            // silent zero. A decode-only fault inside the repo still resolves to an
            // empty array there; that is acceptable (no invites parsed), and the
            // screen treats an empty result as zero invites by design.
            let invites = try await CompanyRepository().checkPendingInvites(email: trimmed)
            return .found(invites)
        } catch {
            print("[INVITE_CHECK_BOUNDARY] checkPendingInvites threw: \(error)")
            return .failed
        }
    }
}
