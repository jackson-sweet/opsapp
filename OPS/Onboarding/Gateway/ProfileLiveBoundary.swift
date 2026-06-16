//
//  ProfileLiveBoundary.swift
//  OPS
//
//  The LIVE implementation of S6c's `ProfileBoundary`, backed by the hardened
//  `OnboardingManager`. This is the only place the rebuilt profile screen touches
//  the real avatar-upload + employee-profile-save ops — S6c itself stays dumb and
//  testable behind the protocol.
//
//  It does NOT reinvent either op:
//    • AVATAR — `OnboardingManager.uploadOnboardingAvatarThrowing(imageData:)` owns
//      the Supabase Storage upload (`profile-images`) + the `UserRepository`
//      `updateProfileImageUrl` write, and — unlike the legacy
//      `uploadAvatarDuringOnboarding`, which SWALLOWS its error and only `print`s —
//      it THROWS on failure. This adapter maps a success into `.uploaded(url:)` and a
//      throw into `.failed(message:)`, so the screen can surface a retry-able error
//      (R7 — never silent).
//    • PROFILE SAVE — `OnboardingManager.saveEmployeeProfile(...)` owns the user-row
//      update (first/last/phone here; the emergency-contact fields are S7c's job, so
//      they are passed `nil`). A throw maps into the screen's `.failed(message:)`.
//
//  The boundary is a pure value over the live manager — the screen passes NO ids and
//  reaches NO singletons, staying ignorant of storage + the save contract.
//

import Foundation

@MainActor
struct ProfileLiveBoundary: ProfileBoundary {

    let manager: OnboardingManager

    /// Upload the avatar through the manager's THROWING path so a real success/failure
    /// signal reaches the screen. A throw → `.failed(message:)` (surfaced + retry-able).
    func uploadAvatar(imageData: Data) async -> AvatarUploadOutcome {
        do {
            let url = try await manager.uploadOnboardingAvatarThrowing(imageData: imageData)
            return .uploaded(url: url)
        } catch let error as OnboardingManagerError {
            return .failed(message: Self.message(for: error))
        } catch {
            print("[PROFILE_BOUNDARY] uploadOnboardingAvatarThrowing threw: \(error)")
            return .failed(message: Self.avatarGenericMessage)
        }
    }

    /// Save the worker's name + phone (profile only — emergency contact is S7c). A
    /// throw maps into the inline `.failed(message:)` surface the screen branches on.
    func saveProfile(firstName: String, lastName: String, phone: String) async -> ProfileSaveOutcome {
        do {
            try await manager.saveEmployeeProfile(
                firstName: firstName,
                lastName: lastName,
                phone: phone.isEmpty ? nil : phone,
                emergencyContactName: nil,
                emergencyContactPhone: nil,
                emergencyContactRelationship: nil
            )
            return .saved
        } catch let error as OnboardingManagerError {
            return .failed(message: Self.message(for: error))
        } catch {
            print("[PROFILE_BOUNDARY] saveEmployeeProfile threw: \(error)")
            return .failed(message: Self.saveGenericMessage)
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
            return trimmed.isEmpty ? saveGenericMessage : detail
        default:
            return saveGenericMessage
        }
    }

    /// The default terse, retry-able avatar-upload failure phrase.
    static let avatarGenericMessage = "photo didn't upload"

    /// The default terse, retry-able profile-save failure phrase.
    static let saveGenericMessage = "couldn't save — try again"
}
