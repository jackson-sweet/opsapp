//
//  OnboardingFlowState.swift
//  OPS
//
//  Onboarding rebuild §5.3 — the unified v4 onboarding flow state, its store,
//  and the one-shot v3→v4 migration. Pure persistence logic; this code is dead
//  until a later phase flips a feature flag.
//
//  v4 collapses the legacy v3 system (screen enum + split user/company data +
//  phase flags) into a single versioned blob: the current step position plus a
//  flat bag of collected form values. The step is an OPTIMISATION — server-
//  derived resume (`OnboardingResume.derive`) is the authority for placement,
//  so the persisted step only avoids a same-session re-walk; a missing or
//  unreadable step is never fatal.
//
//  Wire-format stability mirrors `OnboardingFlowStep`: explicit/pinned coding
//  keys, a version tag, and fail-closed decoding. A blob whose step payload no
//  longer decodes (unknown identifier, corrupt bytes) is treated as "no saved
//  state" by the store — discarded, logged, never a crash.
//

import Foundation

// MARK: - Role choice (flow-local)

/// The onboarding path the user chose at role-pick. Uncommitted until a company
/// exists (owner) or a join completes (crew) — remembered only so a same-session
/// resume doesn't force the user to re-pick. Pinned raw values for persistence.
enum OnboardingFlowRole: String, Codable, Equatable {
    case owner = "owner"
    case crew = "crew"
}

// MARK: - Collected form data

/// Flat bag of everything the rebuilt flow collects, all optional so a partial
/// blob (early kill, or a future field addition) always decodes. Deliberately
/// minimal — only known-collected fields, no speculative extras. Avatar IMAGE
/// bytes are never persisted here (too large); at most a `hasSelectedAvatar`
/// flag survives the round-trip.
struct OnboardingFormData: Codable, Equatable {
    var selectedRole: OnboardingFlowRole?
    var firstName: String?
    var lastName: String?
    var email: String?
    var companyName: String?
    var industries: [String]?
    /// Crew path — the code the user typed to join an existing company.
    var enteredCrewCode: String?
    /// Owner path — the code returned by the create-company RPC.
    var generatedCrewCode: String?
    var phone: String?
    var emergencyContactName: String?
    var emergencyContactPhone: String?
    var emergencyContactRelationship: String?
    /// Whether the user picked an avatar. The image bytes are NOT persisted.
    var hasSelectedAvatar: Bool?

    /// Pinned wire keys — never rename or reuse. A reorder or future addition
    /// cannot corrupt persisted state because every key is explicit and every
    /// field is optional.
    private enum CodingKeys: String, CodingKey {
        case selectedRole
        case firstName
        case lastName
        case email
        case companyName
        case industries
        case enteredCrewCode
        case generatedCrewCode
        case phone
        case emergencyContactName
        case emergencyContactPhone
        case emergencyContactRelationship
        case hasSelectedAvatar
    }

    init(
        selectedRole: OnboardingFlowRole? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        companyName: String? = nil,
        industries: [String]? = nil,
        enteredCrewCode: String? = nil,
        generatedCrewCode: String? = nil,
        phone: String? = nil,
        emergencyContactName: String? = nil,
        emergencyContactPhone: String? = nil,
        emergencyContactRelationship: String? = nil,
        hasSelectedAvatar: Bool? = nil
    ) {
        self.selectedRole = selectedRole
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.companyName = companyName
        self.industries = industries
        self.enteredCrewCode = enteredCrewCode
        self.generatedCrewCode = generatedCrewCode
        self.phone = phone
        self.emergencyContactName = emergencyContactName
        self.emergencyContactPhone = emergencyContactPhone
        self.emergencyContactRelationship = emergencyContactRelationship
        self.hasSelectedAvatar = hasSelectedAvatar
    }
}

// MARK: - The v4 state blob

/// A single versioned blob = step position + collected form data, persisted
/// under `onboarding_state_v4`.
struct OnboardingFlowState: Codable, Equatable {
    /// Current schema version. Bump only with a paired migration.
    static let currentVersion = 1

    /// Persisted position. `nil` when unknown — server-derived resume places
    /// the user; the step is purely an optimisation to skip a re-walk.
    var step: OnboardingFlowStep?

    /// Collected form values, so a same-session kill/resume doesn't force
    /// re-entry.
    var data: OnboardingFormData

    /// Decoded schema version — used by the store to reject future-version blobs.
    /// Internal (not public) so the store can read it without it leaking wider.
    let version: Int

    init(step: OnboardingFlowStep?, data: OnboardingFormData) {
        self.step = step
        self.data = data
        self.version = Self.currentVersion
    }

    /// Pinned wire keys — never rename or reuse.
    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case step
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Tolerate an absent version tag (defaults to v1) so older or hand-
        // written blobs still load; the field's presence is informational.
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        // A present-but-unreadable step throws here (the step machine fails
        // closed on unknown identifiers); the store treats that as no state.
        self.step = try container.decodeIfPresent(OnboardingFlowStep.self, forKey: .step)
        self.data = try container.decodeIfPresent(OnboardingFormData.self, forKey: .data) ?? OnboardingFormData()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Always stamp the CURRENT binary's schema version, not the version the
        // blob was originally decoded with. This ensures a save cycle never
        // silently downgrade-stamps a blob that was decoded from a newer-version
        // binary and is now being re-persisted by an older one.
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encodeIfPresent(step, forKey: .step)
        try container.encode(data, forKey: .data)
    }

    static func == (lhs: OnboardingFlowState, rhs: OnboardingFlowState) -> Bool {
        // Version is an internal schema tag, not part of state identity — two
        // blobs with the same step + data are equal regardless of version.
        lhs.step == rhs.step && lhs.data == rhs.data
    }
}

// MARK: - Store

/// Persistence boundary for the v4 flow state. UserDefaults is injectable so
/// tests run on an isolated suite and never pollute `.standard`.
struct OnboardingFlowStateStore {

    /// Live v4 blob key.
    static let v4Key = "onboarding_state_v4"
    /// Legacy v3 blob key (see `OnboardingStorageKeys.stateV3`).
    static let legacyV3Key = "onboarding_state_v3"
    /// Legacy A/B-test coordinator step key.
    static let legacyABTestStepKey = "ab_test_flow_step"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Load / Save / Clear

    /// Returns the persisted v4 state, or `nil` if absent or undecodable.
    /// A corrupt blob is discarded (key cleared) so it can never wedge resume.
    /// A future-version blob (version > currentVersion) is treated identically
    /// to a corrupt blob — this build cannot safely interpret it, so it is
    /// discarded rather than partially applied.
    func load() -> OnboardingFlowState? {
        guard let data = defaults.data(forKey: Self.v4Key) else { return nil }
        do {
            let state = try JSONDecoder().decode(OnboardingFlowState.self, from: data)
            guard state.version <= OnboardingFlowState.currentVersion else {
                print("[ONBOARDING_FLOW_STATE] v4 blob version \(state.version) exceeds current \(OnboardingFlowState.currentVersion), discarding")
                defaults.removeObject(forKey: Self.v4Key)
                return nil
            }
            return state
        } catch {
            print("[ONBOARDING_FLOW_STATE] v4 blob unreadable, discarding: \(error)")
            defaults.removeObject(forKey: Self.v4Key)
            return nil
        }
    }

    /// Encodes and persists the v4 state under `onboarding_state_v4`.
    func save(_ state: OnboardingFlowState) {
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: Self.v4Key)
        } catch {
            print("[ONBOARDING_FLOW_STATE] Failed to encode v4 state: \(error)")
        }
    }

    /// Removes the v4 blob (used on completion / sign-out).
    func clear() {
        defaults.removeObject(forKey: Self.v4Key)
    }

    // MARK: Migration

    /// One-shot, idempotent v3→v4 migration.
    ///
    /// 1. If a v4 blob already exists → leave it untouched (don't clobber).
    /// 2. Else if a legacy v3 blob exists and decodes → best-effort map its
    ///    collected form fields into a fresh v4 blob (step left `nil`; server-
    ///    derived resume places the user) and save it.
    /// 3. Always remove the legacy `onboarding_state_v3` and `ab_test_flow_step`
    ///    keys afterward (cleanup), regardless of what was found.
    /// 4. A corrupt/undecodable v3 blob is discarded cleanly — no v4 created,
    ///    no crash.
    ///
    /// - Important: Call exactly once at app launch, on the main actor, BEFORE
    ///   any onboarding coordinator is instantiated. The legacy `OnboardingState`
    ///   writes `UserDefaults.standard` directly; calling this method after a
    ///   legacy write has occurred could clear a freshly written v3 key and
    ///   discard user data. The method is deliberately not `@MainActor`-annotated
    ///   (UserDefaults is thread-safe), but the launch-ordering constraint is
    ///   essential — enforce it at the call site, not here.
    func migrateV3IfNeeded() {
        defer { removeLegacyKeys() }

        // (1) Never clobber an existing v4 blob.
        guard defaults.data(forKey: Self.v4Key) == nil else { return }

        // (2/4) Best-effort decode of the legacy blob.
        guard let legacyData = defaults.data(forKey: Self.legacyV3Key) else { return }
        guard let legacy = try? JSONDecoder().decode(OnboardingState.self, from: legacyData) else {
            print("[ONBOARDING_FLOW_STATE] Legacy v3 blob unreadable, discarding without migration")
            return
        }

        save(OnboardingFlowState(step: nil, data: Self.mapV3(legacy)))
    }

    /// Strips the legacy keys. Idempotent.
    private func removeLegacyKeys() {
        defaults.removeObject(forKey: Self.legacyV3Key)
        defaults.removeObject(forKey: Self.legacyABTestStepKey)
    }

    /// Maps a decoded v3 state into a v4 form-data bag. Only fields with a clean
    /// v3 equivalent are carried; empty strings collapse to `nil` so v4 stays
    /// minimal. The legacy step/screen enum is NOT mapped (different machine) —
    /// resume derivation owns placement.
    static func mapV3(_ legacy: OnboardingState) -> OnboardingFormData {
        let role: OnboardingFlowRole? = {
            switch legacy.flow {
            case .companyCreator: return .owner
            case .employee: return .crew
            case nil: return nil
            }
        }()

        // Owner-created companies surface a company code; that IS the crew code
        // the owner's team will use. The employee path never has one.
        let generatedCrewCode = role == .owner ? legacy.companyData.companyCode?.nilIfBlank : nil

        let industries = legacy.companyData.industry.nilIfBlank.map { [$0] }

        return OnboardingFormData(
            selectedRole: role,
            firstName: legacy.userData.firstName.nilIfBlank,
            lastName: legacy.userData.lastName.nilIfBlank,
            email: legacy.userData.email.nilIfBlank,
            companyName: legacy.companyData.name.nilIfBlank,
            industries: industries,
            enteredCrewCode: nil,
            generatedCrewCode: generatedCrewCode,
            phone: legacy.userData.phone.nilIfBlank,
            emergencyContactName: nil,
            emergencyContactPhone: nil,
            emergencyContactRelationship: nil,
            hasSelectedAvatar: nil
        )
    }
}

// MARK: - Helpers

private extension String {
    /// Trimmed value, or `nil` when empty/whitespace — keeps migrated v4 blobs
    /// free of the v3 defaults (`""`).
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
