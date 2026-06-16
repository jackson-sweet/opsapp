//
//  CodeEntryLiveBoundary.swift
//  OPS
//
//  The LIVE implementation of S4c-code's `CodeEntryBoundary`, backed by the
//  hardened `OnboardingManager.lookupCompanyByCode(_:)`. This is the only place the
//  rebuilt crew code-entry screen touches the real `lookup_company_by_code` RPC —
//  the screen itself stays dumb and testable behind the protocol.
//
//  It does NOT reinvent the lookup. `OnboardingManager.lookupCompanyByCode(_:)`
//  owns the sanitisation (strip whitespace / invisible Unicode, uppercase) and the
//  RPC, and stores the validated code in its own state for the later join. This
//  adapter only invokes it and maps the result into the `CodeEntryOutcome` surface
//  the screen branches on.
//
//  NO CLIENT FORMAT REJECTION — legacy `PREFIX-XXXXXX` codes must be accepted.
//  Validation is server lookup-only; the screen passes whatever the user typed and
//  this boundary decides found / not-found from the RPC.
//
//  ERROR MAPPING (traced from `OnboardingManagerError`):
//    • `.invalidCompanyCode` → `.notFound` (no company matched — inline "check with
//      your boss" error; the user can re-type).
//    • any other throw       → `.failed` (network / server — retry-able inline
//      error, distinct from not-found so the copy is honest).
//

import SwiftUI

@MainActor
struct CodeEntryLiveBoundary: CodeEntryBoundary {

    let manager: OnboardingManager

    func lookUpCompany(code: String) async -> CodeEntryOutcome {
        do {
            let company = try await manager.lookupCompanyByCode(code)
            return .found(
                FoundCompany(
                    companyId: company.id,
                    companyName: company.name,
                    companyCode: company.companyCode,
                    companyLogoUrl: company.logoUrl
                )
            )
        } catch let error as OnboardingManagerError {
            switch error {
            case .invalidCompanyCode:
                return .notFound
            default:
                return .failed
            }
        } catch {
            print("[CODE_ENTRY_BOUNDARY] lookupCompanyByCode threw: \(error)")
            return .failed
        }
    }
}
