//
//  OnboardingFlowStep.swift
//  OPS
//
//  Onboarding rebuild §5.2 — the step machine.
//  Pure value types: the step enum, its provenance types, and the
//  data-driven back-edge map. Steps persist across app kills inside the
//  onboarding state blob, so the Codable wire format is pinned to explicit
//  string identifiers — a future case reorder or rename cannot corrupt
//  persisted state, and unknown/corrupt payloads fail to decode (throw)
//  rather than misdecode.
//

import Foundation

/// How the user reached the crew-code entry screen. Back from code entry
/// returns to where the user actually came from.
enum CodeEntryProvenance: String, Codable, Equatable {
    case zeroInvites = "zeroInvites"
    case fromPicker = "fromPicker"
}

/// Where the user came from before the confirm-company screen. Confirm's
/// back-edge returns to the actual origin, preserving code-entry provenance.
enum ConfirmSource: Codable, Equatable {
    case picker
    case codeEntry(CodeEntryProvenance)

    private enum CodingKeys: String, CodingKey {
        case kind = "kind"
        case provenance = "provenance"
    }

    /// Stable persisted discriminators — never rename or reuse a value.
    private enum Kind: String, Codable {
        case picker = "picker"
        case codeEntry = "codeEntry"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .picker:
            self = .picker
        case .codeEntry:
            self = .codeEntry(try container.decode(CodeEntryProvenance.self, forKey: .provenance))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .picker:
            try container.encode(Kind.picker, forKey: .kind)
        case .codeEntry(let provenance):
            try container.encode(Kind.codeEntry, forKey: .kind)
            try container.encode(provenance, forKey: .provenance)
        }
    }
}

/// Every screen position in the rebuilt onboarding flow.
enum OnboardingFlowStep: Codable, Equatable {
    case welcome
    case login
    case rolePick
    case createAccount
    case companyName
    case crewCode
    case inviteCheck
    case invitePicker
    case codeEntry(provenance: CodeEntryProvenance)
    case confirmCompany(source: ConfirmSource)
    case profile
    case emergencyContact
    case completionGate

    // MARK: - Back map (§5.2 — single source of truth)

    /// Auth phase the flow is running in. Post-auth resume drops the
    /// pre-auth-only escape edges (SIGN OUT takes over as the escape).
    enum BackContext: Equatable {
        case preAuth
        case postAuth
    }

    /// The step Back navigates to, or nil when no back-edge exists. The
    /// header renders Back only when an edge exists, so a no-op Back is
    /// structurally impossible; nil rows rely on SIGN OUT where an escape
    /// is needed.
    func backEdge(context: BackContext) -> OnboardingFlowStep? {
        switch self {
        case .welcome:
            return nil
        case .login:
            return .welcome
        case .rolePick:
            // Pre-auth, Back returns to Welcome. Resumed post-auth there is
            // nothing behind role pick — SIGN OUT is the escape.
            return context == .preAuth ? .welcome : nil
        case .createAccount:
            // createAccount only exists pre-auth; rolePick in both contexts
            // is harmless.
            return .rolePick
        case .companyName:
            // Role is UNCOMMITTED until a company exists — this back-edge is
            // the wrong-role escape, post-auth included.
            return .rolePick
        case .crewCode:
            // Company committed — no way back.
            return nil
        case .inviteCheck:
            // Auto transition; its failure state has its own retry affordances.
            return nil
        case .invitePicker:
            return .rolePick
        case .codeEntry(let provenance):
            switch provenance {
            case .zeroInvites:
                return .rolePick
            case .fromPicker:
                return .invitePicker
            }
        case .confirmCompany(let source):
            switch source {
            case .picker:
                return .invitePicker
            case .codeEntry(let provenance):
                return .codeEntry(provenance: provenance)
            }
        case .profile:
            // Join committed — SIGN OUT is the escape.
            return nil
        case .emergencyContact:
            return .profile
        case .completionGate:
            return nil
        }
    }

    // MARK: - Codable (pinned wire format)

    private enum CodingKeys: String, CodingKey {
        case step = "step"
        case provenance = "provenance"
        case source = "source"
    }

    /// Stable persisted identifiers — never rename or reuse a value.
    private enum StepIdentifier: String, Codable {
        case welcome = "welcome"
        case login = "login"
        case rolePick = "rolePick"
        case createAccount = "createAccount"
        case companyName = "companyName"
        case crewCode = "crewCode"
        case inviteCheck = "inviteCheck"
        case invitePicker = "invitePicker"
        case codeEntry = "codeEntry"
        case confirmCompany = "confirmCompany"
        case profile = "profile"
        case emergencyContact = "emergencyContact"
        case completionGate = "completionGate"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(StepIdentifier.self, forKey: .step) {
        case .welcome:
            self = .welcome
        case .login:
            self = .login
        case .rolePick:
            self = .rolePick
        case .createAccount:
            self = .createAccount
        case .companyName:
            self = .companyName
        case .crewCode:
            self = .crewCode
        case .inviteCheck:
            self = .inviteCheck
        case .invitePicker:
            self = .invitePicker
        case .codeEntry:
            self = .codeEntry(provenance: try container.decode(CodeEntryProvenance.self, forKey: .provenance))
        case .confirmCompany:
            self = .confirmCompany(source: try container.decode(ConfirmSource.self, forKey: .source))
        case .profile:
            self = .profile
        case .emergencyContact:
            self = .emergencyContact
        case .completionGate:
            self = .completionGate
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .welcome:
            try container.encode(StepIdentifier.welcome, forKey: .step)
        case .login:
            try container.encode(StepIdentifier.login, forKey: .step)
        case .rolePick:
            try container.encode(StepIdentifier.rolePick, forKey: .step)
        case .createAccount:
            try container.encode(StepIdentifier.createAccount, forKey: .step)
        case .companyName:
            try container.encode(StepIdentifier.companyName, forKey: .step)
        case .crewCode:
            try container.encode(StepIdentifier.crewCode, forKey: .step)
        case .inviteCheck:
            try container.encode(StepIdentifier.inviteCheck, forKey: .step)
        case .invitePicker:
            try container.encode(StepIdentifier.invitePicker, forKey: .step)
        case .codeEntry(let provenance):
            try container.encode(StepIdentifier.codeEntry, forKey: .step)
            try container.encode(provenance, forKey: .provenance)
        case .confirmCompany(let source):
            try container.encode(StepIdentifier.confirmCompany, forKey: .step)
            try container.encode(source, forKey: .source)
        case .profile:
            try container.encode(StepIdentifier.profile, forKey: .step)
        case .emergencyContact:
            try container.encode(StepIdentifier.emergencyContact, forKey: .step)
        case .completionGate:
            try container.encode(StepIdentifier.completionGate, forKey: .step)
        }
    }
}
