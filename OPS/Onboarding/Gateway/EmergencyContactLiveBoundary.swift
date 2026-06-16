//
//  EmergencyContactLiveBoundary.swift
//  OPS
//
//  The LIVE implementation of S7c's `EmergencyContactBoundary`, backed by the
//  hardened `OnboardingManager`. This is the only place the rebuilt emergency-contact
//  screen touches the real user-row save — S7c itself stays dumb and testable behind
//  the protocol.
//
//  It does NOT reinvent the save. `OnboardingManager.saveEmployeeProfile(...)` owns
//  the user-row update. That method writes first/last/phone AND the emergency fields
//  in one call (and overwrites first/last from its arguments), so this adapter sources
//  the already-committed name/phone from the manager's own state (S6c persisted them
//  there on its save) and layers the emergency fields on top — the profile identity is
//  preserved while the emergency contact is added.
//
//  The SKIP path never reaches this boundary — the screen advances to the completion
//  gate without saving. Only FINISH calls `saveEmergencyContact`.
//

import Foundation

@MainActor
struct EmergencyContactLiveBoundary: EmergencyContactBoundary {

    let manager: OnboardingManager

    /// Save the emergency fields, carrying the name/phone S6c already persisted into
    /// the manager's state so `saveEmployeeProfile` (which overwrites first/last from
    /// its args) preserves the profile identity. A throw maps into the inline
    /// `.failed(message:)` surface the screen branches on.
    func saveEmergencyContact(name: String, phone: String, relationship: String) async -> EmergencyContactSaveOutcome {
        // The profile identity S6c committed lives in the manager's state. Carry it so
        // the save doesn't blank first/last (saveEmployeeProfile takes them as args).
        let firstName = manager.state.userData.firstName
        let lastName = manager.state.userData.lastName
        let existingPhone = manager.state.userData.phone
        let phoneToWrite = existingPhone.isEmpty ? nil : existingPhone

        do {
            try await manager.saveEmployeeProfile(
                firstName: firstName,
                lastName: lastName,
                phone: phoneToWrite,
                emergencyContactName: name.isEmpty ? nil : name,
                emergencyContactPhone: phone.isEmpty ? nil : phone,
                emergencyContactRelationship: relationship.isEmpty ? nil : relationship
            )
            return .saved
        } catch let error as OnboardingManagerError {
            return .failed(message: Self.message(for: error))
        } catch {
            print("[EMERGENCY_CONTACT_BOUNDARY] saveEmployeeProfile threw: \(error)")
            return .failed(message: Self.genericMessage)
        }
    }

    // MARK: - Mapping

    /// A bare phrase for a typed manager error. A `.serverError` carries server-authored
    /// user-facing copy — pass it through verbatim; everything else collapses to the
    /// terse retry-able phrase. The view prefixes `// ERROR — ` and uppercases. Copy
    /// locked via ops-copywriter.
    static func message(for error: OnboardingManagerError) -> String {
        switch error {
        case .serverError(let detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? genericMessage : detail
        default:
            return genericMessage
        }
    }

    /// The default terse, retry-able failure phrase.
    static let genericMessage = "couldn't save — try again"
}
