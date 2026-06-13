//
//  ConfirmCompanyLiveBoundary.swift
//  OPS
//
//  The LIVE implementation of S5c's `ConfirmCompanyBoundary`, backed by the hardened
//  `OnboardingManager`. This is the only place the rebuilt confirm-company screen
//  touches the real crew-join op (`join_user_to_company`) and the team-preview
//  lookup — S5c itself stays dumb and testable behind the protocol.
//
//  It does NOT reinvent either op:
//    • TEAM PREVIEW — `OnboardingManager.fetchCompanyJoinDetails(code:)` owns the
//      `get_company_join_details` RPC. It takes a CODE, so this adapter only attempts
//      the enrichment when a `joinCompanyCode` is present (the picker + code-entry
//      paths both persist one). With no code it returns `nil` and the screen renders
//      its deliberate SPARSE layout. The fetch is best-effort: any throw → `nil`, so a
//      lookup failure NEVER blocks the confirm or the join.
//    • JOIN — `OnboardingManager.joinCompanyFromOnboarding(companyId:invitationId:
//      companyCode:)` owns the entire server transaction (company_id, invitation-
//      accept, role, seat grant — all server-side via the amended RPC). This adapter
//      passes the persisted form-data identity and maps a throw into the screen's
//      `.failed(message:)` surface (a thrown `OnboardingManagerError.serverError`
//      carries the "team is full" copy verbatim; any other throw collapses to a terse
//      retry-able phrase).
//
//  The identity (companyId / invitationId / companyCode) is captured from form data at
//  construction so the boundary is a pure value over a fixed company — the screen
//  passes NO ids, keeping it ignorant of the join contract.
//

import SwiftUI

@MainActor
struct ConfirmCompanyLiveBoundary: ConfirmCompanyBoundary {

    let manager: OnboardingManager

    /// The resolved company to join, captured from `formData.joinCompany*` by the
    /// gateway. `companyId` is always present; `invitationId` is set only on the
    /// picker path (drives the invite-accept write); `companyCode` is present on both
    /// paths and is what the team-preview lookup keys off.
    let companyId: String
    let invitationId: String?
    let companyCode: String?

    /// Best-effort team-preview enrichment. Only attempts the lookup when a code is
    /// present (the RPC keys off the code). Any failure → `nil` (the screen falls back
    /// to the sparse layout) — NEVER throws / blocks the join.
    func fetchTeamPreview() async -> CompanyJoinDetailsDTO? {
        guard let code = companyCode, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        do {
            return try await manager.fetchCompanyJoinDetails(code: code)
        } catch {
            print("[CONFIRM_COMPANY_BOUNDARY] fetchCompanyJoinDetails threw (sparse fallback): \(error)")
            return nil
        }
    }

    /// The live crew JOIN. Forwards the persisted identity to the manager's join op;
    /// maps a throw into the inline `.failed(message:)` surface the screen branches on.
    func join() async -> ConfirmCompanyJoinOutcome {
        do {
            try await manager.joinCompanyFromOnboarding(
                companyId: companyId,
                invitationId: invitationId,
                companyCode: companyCode
            )
            return .joined
        } catch let error as OnboardingManagerError {
            return .failed(message: Self.message(for: error))
        } catch {
            print("[CONFIRM_COMPANY_BOUNDARY] joinCompanyFromOnboarding threw: \(error)")
            return .failed(message: Self.genericMessage)
        }
    }

    // MARK: - Mapping

    /// A bare phrase for a typed join error. A `.serverError` carries server-authored
    /// user-facing copy (e.g. "team is full") — pass it through verbatim. Everything
    /// else collapses to the terse retry-able phrase. The view prefixes `// ERROR — `
    /// and uppercases. Copy locked via ops-copywriter.
    static func message(for error: OnboardingManagerError) -> String {
        switch error {
        case .serverError(let detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? genericMessage : detail
        default:
            return genericMessage
        }
    }

    /// The default terse, retry-able failure phrase (network / decode / untyped).
    static let genericMessage = "couldn't join — try again"
}
