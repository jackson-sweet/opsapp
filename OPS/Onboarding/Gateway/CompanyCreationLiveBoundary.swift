//
//  CompanyCreationLiveBoundary.swift
//  OPS
//
//  The LIVE implementation of S4o's `CompanyCreationBoundary`, backed by the
//  hardened `OnboardingManager`. This is the only place the rebuilt company-name
//  screen touches the real `create_company_for_owner` RPC — S4o itself stays dumb
//  and testable behind the protocol.
//
//  It does NOT reinvent company creation. `OnboardingManager.createCompanyViaRPC()`
//  owns the entire server transaction (company insert, owner record, user_roles,
//  defaults init) and returns the DB-truth company code; this adapter only seeds
//  the name/industry the manager reads from its own state, invokes the method, and
//  maps its typed `CreateCompanyError` throws into the `CompanyCreationOutcome`
//  surface the screen branches on.
//
//  ERROR MAPPING (traced from `OnboardingManager.CreateCompanyError`):
//    • createCompanyViaRPC handles the IDEMPOTENT reuse case internally — an owner
//      re-running after a mid-flow kill gets the EXISTING code back (RPC
//      `already_existed: true`) as a normal success, so `.created(code:)` fires and
//      the screen advances to crewCode showing that code. No special-casing needed.
//    • `.invalidName`      → `.invalidName` (FIELD error on the name field).
//    • `.alreadyInCompany` → `.alreadyInCompany` (this account already owns a
//                            company it did not create here — no code, inline error).
//    • `.userRowMissing` / `.noUserId` / `.generic` → `.failed` (inline top-level,
//                            retry-able).
//

import SwiftUI

@MainActor
struct CompanyCreationLiveBoundary: CompanyCreationBoundary {

    let manager: OnboardingManager

    func createCompany(name: String, industries: [String]) async -> CompanyCreationOutcome {
        // Ensure the company-creator flow is selected so the manager's state is
        // configured the way createCompanyViaRPC expects (idempotent).
        manager.selectFlow(.companyCreator)

        // Seed the company data the RPC reads from the manager's own state.
        // createCompanyViaRPC takes no params — it reads `state.companyData.*`.
        manager.state.companyData.name = name
        // The manager models a SINGLE primary industry string; the optional trade
        // chip is 0/1 element, so take the first (empty = no industry).
        manager.state.companyData.industry = industries.first ?? ""

        do {
            let code = try await manager.createCompanyViaRPC()
            return .created(code: code)
        } catch let error as OnboardingManager.CreateCompanyError {
            return Self.map(error)
        } catch {
            // Any non-typed throw collapses to a generic inline failure.
            return .failed(message: Self.genericMessage(error))
        }
    }

    // MARK: - Mapping

    /// Map a typed `CreateCompanyError` to the screen's outcome surface. The bare
    /// phrases are lowercased-for-the-field; the field / inline error renders the
    /// `// ERROR — ` prefix and uppercases. Copy locked via ops-copywriter.
    static func map(_ error: OnboardingManager.CreateCompanyError) -> CompanyCreationOutcome {
        switch error {
        case .invalidName:
            return .invalidName(message: "enter a company name")
        case .alreadyInCompany:
            return .alreadyInCompany(message: "this account already belongs to a company")
        case .userRowMissing:
            return .failed(message: "couldn't finish setup — try again")
        case .noUserId:
            return .failed(message: "couldn't finish setup — try again")
        case .generic:
            return .failed(message: "couldn't create your company — try again")
        }
    }

    /// A bare phrase for a non-typed failure (network / decode). Terse, ops voice.
    static func genericMessage(_ error: Error) -> String {
        "couldn't create your company — try again"
    }
}
