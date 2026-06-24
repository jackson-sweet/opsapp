//
//  RebuiltOnboardingPreviewView.swift
//  OPS
//
//  DEBUG-ONLY developer tool — a per-screen previewer for the REBUILT onboarding
//  flow (`OPS/Onboarding/Screens/*StepView.swift`). It lets the owner inspect each
//  finished screen in isolation, full-screen, seeded with representative stub data —
//  NO network, NO auth, NO real account / company creation.
//
//  The entire file is wrapped in `#if DEBUG`, and its launch entry in
//  `DeveloperDashboard` is `#if DEBUG`-gated too, so the previewer (and everything it
//  references) is COMPILED OUT of release / production builds. It is structurally
//  unreachable when shipped.
//
//  How it works
//  ------------
//  The rebuilt screens are DUMB views: each takes an injected async boundary protocol
//  plus navigation closures, and several expose a `#if DEBUG` seed-init that pins the
//  visual `@State` so error / loading / variant frames render without an async
//  interaction. This previewer:
//    • Injects its OWN local stub boundaries (`Stub*Boundary` below) — every method
//      returns a benign outcome immediately and touches NOTHING (no Supabase, no
//      Firebase, no storage). These mirror the screens' own `private Preview*Boundary`
//      stubs, re-declared here because those are file-private to each screen.
//    • Seeds representative form values (a fake company name + crew code, sample
//      invites, a sample team) so the populated screens render filled, not blank.
//    • Wires every navigation closure to a harmless no-op or to `close` (dismiss the
//      preview) — so tapping a CTA never crashes or enters the real flow.
//
//  This tool is ADDITIVE: it does not modify any onboarding screen, boundary, the
//  gateway, the coordinator, or the flow. It reuses the screens exactly as they ship.
//

#if DEBUG

import SwiftUI

// MARK: - Previewer (the navigable list)

/// A grouped list of every rebuilt onboarding screen (and its meaningful variant
/// states). Tapping a row renders that screen full-screen over a seeded stub.
struct RebuiltOnboardingPreviewView: View {

    @Environment(\.dismiss) private var dismiss

    /// Forwarded purely as a crash-safety net for incidentally-presented secondary
    /// sheets (Login's forgot-password sheet declares `@EnvironmentObject DataController`).
    /// None of the 13 rebuilt screens read it, and the previewer's stubs touch no
    /// network — this is the already-live controller, so injection adds none either.
    @EnvironmentObject private var dataController: DataController

    /// The currently-presented screen variant (nil = the list). Drives the cover.
    @State private var selection: Variant?

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                OPSScreenHeader(
                    "Onboarding Screens",
                    leading: {
                        Button(action: { dismiss() }) {
                            Image(systemName: OPSStyle.Icons.close)
                                .font(.system(size: 20))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    }
                )
                .background(OPSStyle.Colors.background)

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        introNote
                            .padding(.horizontal)
                            .padding(.top)

                        ForEach(Self.screens) { screen in
                            screenCard(screen)
                                .padding(.horizontal)
                        }

                        Spacer(minLength: OPSStyle.Layout.spacing4)
                    }
                }
            }
        }
        .fullScreenCover(item: $selection) { variant in
            RebuiltOnboardingPreviewHost(variant: variant)
                .environmentObject(dataController)
        }
    }

    // MARK: List chrome

    private var introNote: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Label("Rebuilt onboarding — visual preview", systemImage: "eye")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("Each screen renders in isolation with stub data. No network, no auth, no real accounts or companies. CTAs are inert — close from the pill at the top of every screen.")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassSurface()
    }

    /// One card per screen: a step header + a tappable row per variant.
    private func screenCard(_ screen: Screen) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(screen.stepCode)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(screen.title.uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(Array(screen.variants.enumerated()), id: \.element.id) { index, variant in
                    Button {
                        OnboardingHaptics.selection()
                        selection = variant
                    } label: {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Text(variant.label)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: OPSStyle.Icons.chevronRight)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing2_5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < screen.variants.count - 1 {
                        Divider().overlay(OPSStyle.Colors.separator)
                    }
                }
            }
        }
        .padding()
        .nestedCard()
    }
}

// MARK: - Full-screen host (the dismiss chrome)

/// Hosts one previewed screen and overlays a universal close pill at the top. The
/// pill is centered (the screens' headers are edge-aligned, so the top-center band
/// is always clear) and respects the safe area, so it never collides with a back or
/// SIGN OUT control.
private struct RebuiltOnboardingPreviewHost: View {

    @Environment(\.dismiss) private var dismiss
    let variant: RebuiltOnboardingPreviewView.Variant

    var body: some View {
        ZStack(alignment: .top) {
            // The real screen, seeded. Back / SIGN OUT closures (where the public
            // init is used) are wired to `dismiss` too, so they double as a close.
            variant.build { dismiss() }

            closePill
                .padding(.top, OPSStyle.Layout.spacing2)
        }
    }

    private var closePill: some View {
        Button { dismiss() } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.close)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                Text("\(variant.screenTitle.uppercased()) · \(variant.label.uppercased())")
                    .font(OPSStyle.Typography.miniLabel)
                    .tracking(1.2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundColor(OPSStyle.Colors.primaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(
                Capsule(style: .continuous)
                    .fill(OPSStyle.Colors.overlayHeavy)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .frame(maxWidth: 320)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close preview")
    }
}

// MARK: - Dashboard launch tile

/// The launch tile shown in `DeveloperDashboard`'s TESTING & DEBUG grid. Mirrors the
/// dashboard's `ToolCard` styling so it sits flush with the other tools. DEBUG-only.
struct RebuiltOnboardingLaunchCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                ZStack {
                    Circle()
                        .fill(Color.indigo.opacity(0.2))
                        .frame(width: 56, height: 56)

                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: OPSStyle.Layout.IconSize.lg))
                        .foregroundColor(.indigo)
                }

                Text("Onboarding Screens")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("Preview each rebuilt onboarding screen")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .nestedCard()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Catalog (screens + variants)

extension RebuiltOnboardingPreviewView {

    /// One previewable variant of a screen. `build` constructs the seeded screen,
    /// handed a `close` action it wires into whatever natural dismiss the screen has.
    struct Variant: Identifiable {
        let id: String
        let screenTitle: String
        let label: String
        let build: (_ close: @escaping () -> Void) -> AnyView
    }

    /// A screen and the set of states worth inspecting.
    struct Screen: Identifiable {
        let id: String
        let stepCode: String
        let title: String
        let variants: [Variant]
    }

    /// Every rebuilt onboarding screen, in flow order, with its meaningful variants.
    static let screens: [Screen] = [

        // S1 — Welcome
        Screen(id: "welcome", stepCode: "S1", title: "Welcome", variants: [
            Variant(id: "welcome.default", screenTitle: "Welcome", label: "Default") { _ in
                AnyView(WelcomeStepView(onGetStarted: {}, onSignIn: {}))
            }
        ]),

        // S4 — Login
        Screen(id: "login", stepCode: "S4", title: "Login", variants: [
            Variant(id: "login.default", screenTitle: "Login", label: "Default") { close in
                AnyView(LoginStepView(
                    boundary: StubLoginBoundary(),
                    onUpdateFormData: { _ in },
                    onComplete: {},
                    onIncomplete: { _ in },
                    onNewIdentity: {},
                    onBack: close,
                    prefilledEmail: "you@summitbuilders.co"
                ))
            },
            Variant(id: "login.error", screenTitle: "Login", label: "Error — wrong password") { _ in
                AnyView(LoginStepView(
                    boundary: StubLoginBoundary(),
                    previewEmail: "you@summitbuilders.co",
                    previewPassword: "••••••••",
                    previewDidAttemptSubmit: true,
                    previewFailureMessage: "That password didn't match. Try again."
                ))
            }
        ]),

        // S2 — Role pick
        Screen(id: "rolePick", stepCode: "S2", title: "Role pick", variants: [
            Variant(id: "rolePick.default", screenTitle: "Role pick", label: "Default") { close in
                AnyView(RolePickStepView(
                    onSelectOwner: {},
                    onSelectCrew: {},
                    canGoBack: true,
                    onBack: close,
                    onSignOut: close
                ))
            }
        ]),

        // S3 — Create account
        Screen(id: "createAccount", stepCode: "S3", title: "Create account", variants: [
            Variant(id: "createAccount.default", screenTitle: "Create account", label: "Default (owner)") { close in
                AnyView(CreateAccountStepView(
                    selectedRole: .owner,
                    boundary: StubSignupBoundary(),
                    onUpdateFormData: { _ in },
                    onCreated: {},
                    onExistingComplete: {},
                    onExistingIncomplete: { _ in },
                    onSignIn: {},
                    onBack: close
                ))
            },
            Variant(id: "createAccount.socialName", screenTitle: "Create account", label: "Social — needs name") { _ in
                AnyView(CreateAccountStepView(
                    selectedRole: .crew,
                    boundary: StubSignupBoundary(),
                    previewEmail: "sam@icloud.com",
                    previewSocialNameEmail: "sam@icloud.com"
                ))
            }
        ]),

        // S4o — Company name
        Screen(id: "companyName", stepCode: "S4o", title: "Company name", variants: [
            Variant(id: "companyName.default", screenTitle: "Company name", label: "Default") { close in
                AnyView(CompanyNameStepView(
                    boundary: StubCompanyBoundary(),
                    onUpdateFormData: { _ in },
                    onCreated: { _ in },
                    onBack: close
                ))
            },
            Variant(id: "companyName.filled", screenTitle: "Company name", label: "Filled") { _ in
                AnyView(CompanyNameStepView(
                    boundary: StubCompanyBoundary(),
                    previewCompanyName: "Summit Builders"
                ))
            }
        ]),

        // S5o — Crew code (the owner payoff)
        Screen(id: "crewCode", stepCode: "S5o", title: "Crew code", variants: [
            Variant(id: "crewCode.default", screenTitle: "Crew code", label: "Default") { _ in
                AnyView(CrewCodeStepView(
                    crewCode: "7F3K-92QX",
                    companyName: "Summit Builders",
                    previewSettled: true
                ))
            }
        ]),

        // S4c — Invite check (the crew auto-transition)
        Screen(id: "inviteCheck", stepCode: "S4c", title: "Invite check", variants: [
            Variant(id: "inviteCheck.checking", screenTitle: "Invite check", label: "Checking") { _ in
                AnyView(InviteCheckStepView(
                    boundary: StubInviteCheckBoundary(),
                    previewPhase: .checking
                ))
            },
            Variant(id: "inviteCheck.failed", screenTitle: "Invite check", label: "Failed — retry") { _ in
                AnyView(InviteCheckStepView(
                    boundary: StubInviteCheckBoundary(),
                    previewPhase: .failed
                ))
            }
        ]),

        // Invite picker
        Screen(id: "invitePicker", stepCode: "S4c", title: "Invite picker", variants: [
            Variant(id: "invitePicker.invites", screenTitle: "Invite picker", label: "With invites") { close in
                AnyView(InvitePickerStepView(
                    invites: PreviewSeed.invites,
                    previewSettled: true,
                    onSelectInvite: { _ in },
                    onEnterDifferentCode: {},
                    onBack: close
                ))
            },
            Variant(id: "invitePicker.empty", screenTitle: "Invite picker", label: "Empty") { close in
                AnyView(InvitePickerStepView(
                    invites: [],
                    previewSettled: true,
                    onSelectInvite: { _ in },
                    onEnterDifferentCode: {},
                    onBack: close
                ))
            }
        ]),

        // S4c-code — Code entry
        Screen(id: "codeEntry", stepCode: "S4c", title: "Code entry", variants: [
            Variant(id: "codeEntry.default", screenTitle: "Code entry", label: "Default") { close in
                AnyView(CodeEntryStepView(
                    provenance: .zeroInvites,
                    boundary: StubCodeEntryBoundary(),
                    onUpdateFormData: { _ in },
                    onFound: { _ in },
                    onBack: close,
                    onSignOut: close
                ))
            },
            Variant(id: "codeEntry.notFound", screenTitle: "Code entry", label: "Not found") { _ in
                AnyView(CodeEntryStepView(
                    provenance: .zeroInvites,
                    boundary: StubCodeEntryBoundary(),
                    previewCode: "ZZ-0000",
                    previewError: "No company found for that code. Check with your boss."
                ))
            }
        ]),

        // S5c — Confirm company (the crew JOIN commit point)
        Screen(id: "confirmCompany", stepCode: "S5c", title: "Confirm company", variants: [
            Variant(id: "confirmCompany.rich", screenTitle: "Confirm company", label: "Rich — with team") { _ in
                AnyView(ConfirmCompanyStepView(
                    boundary: StubConfirmCompanyBoundary(),
                    companyName: "Summit Builders",
                    backLabel: "Invites",
                    previewState: PreviewSeed.richConfirmPreview
                ))
            },
            Variant(id: "confirmCompany.sparse", screenTitle: "Confirm company", label: "Sparse — name only") { _ in
                AnyView(ConfirmCompanyStepView(
                    boundary: StubConfirmCompanyBoundary(),
                    companyName: "Apex Electrical",
                    backLabel: "Code",
                    previewState: PreviewSeed.sparseConfirmPreview
                ))
            }
        ]),

        // S6c — Profile (crew post-join)
        Screen(id: "profile", stepCode: "S6c", title: "Profile", variants: [
            Variant(id: "profile.default", screenTitle: "Profile", label: "Default") { close in
                AnyView(ProfileStepView(
                    boundary: StubProfileBoundary(),
                    prefillFirstName: "Sam",
                    prefillLastName: "Rivera",
                    prefillPhone: "(604) 555-0148",
                    onUpdateFormData: { _ in },
                    onContinue: {},
                    onSignOut: close
                ))
            },
            Variant(id: "profile.uploading", screenTitle: "Profile", label: "Avatar uploading") { _ in
                AnyView(ProfileStepView(
                    boundary: StubProfileBoundary(),
                    previewFirstName: "Sam",
                    previewLastName: "Rivera",
                    previewPhone: "(604) 555-0148",
                    previewAvatarStatus: .uploading(image: PreviewSeed.avatarImage)
                ))
            },
            Variant(id: "profile.saveError", screenTitle: "Profile", label: "Save error") { _ in
                AnyView(ProfileStepView(
                    boundary: StubProfileBoundary(),
                    previewFirstName: "Sam",
                    previewLastName: "Rivera",
                    previewPhone: "(604) 555-0148",
                    previewDidAttemptSubmit: true,
                    previewSaveError: "Couldn't save. Check your connection and try again."
                ))
            }
        ]),

        // S7c — Emergency contact (optional + skippable)
        Screen(id: "emergencyContact", stepCode: "S7c", title: "Emergency contact", variants: [
            Variant(id: "emergencyContact.default", screenTitle: "Emergency contact", label: "Default") { close in
                AnyView(EmergencyContactStepView(
                    boundary: StubEmergencyBoundary(),
                    onUpdateFormData: { _ in },
                    onFinish: {},
                    onSkip: {},
                    onBack: close
                ))
            }
        ]),

        // Completion gate (both paths terminate here)
        Screen(id: "completionGate", stepCode: "S8", title: "Completion gate", variants: [
            Variant(id: "completionGate.syncing", screenTitle: "Completion gate", label: "Syncing") { _ in
                AnyView(CompletionGateView(
                    boundary: StubCompletionBoundary(),
                    previewPhase: .syncing
                ))
            },
            Variant(id: "completionGate.queued", screenTitle: "Completion gate", label: "Queued") { _ in
                AnyView(CompletionGateView(
                    boundary: StubCompletionBoundary(),
                    previewPhase: .queued
                ))
            }
        ])
    ]
}

// MARK: - Seed data (representative, fully local)

/// Static sample values so the populated screens render filled, not blank. Nothing
/// here is persisted or sent anywhere — it exists only for the previewer.
private enum PreviewSeed {

    static let team: [TeamMemberDTO] = [
        TeamMemberDTO(firstName: "Dana", lastName: "Cole", profileImageUrl: nil),
        TeamMemberDTO(firstName: "Marco", lastName: "Reyes", profileImageUrl: nil),
        TeamMemberDTO(firstName: "Jess", lastName: "Tran", profileImageUrl: nil),
        TeamMemberDTO(firstName: "Owen", lastName: "Blake", profileImageUrl: nil)
    ]

    static let invites: [PendingInviteDTO] = [
        PendingInviteDTO(
            invitationId: "inv_summit",
            companyId: "co_summit",
            companyName: "Summit Builders",
            companyCode: "7F3K-92QX",
            companyLogoUrl: nil,
            industries: ["General Contracting", "Framing"],
            roleName: "Crew",
            invitedByName: "Dana Cole",
            teamMembers: team,
            teamSize: 8,
            expiresAt: "2026-12-31T00:00:00Z"
        ),
        PendingInviteDTO(
            invitationId: "inv_apex",
            companyId: "co_apex",
            companyName: "Apex Electrical",
            companyCode: "K91M-22ZD",
            companyLogoUrl: nil,
            industries: ["Electrical"],
            roleName: "Lead",
            invitedByName: "Priya Nair",
            teamMembers: Array(team.prefix(2)),
            teamSize: 3,
            expiresAt: "2026-12-31T00:00:00Z"
        )
    ]

    static let richConfirmPreview = ConfirmCompanyPreview(
        companyId: "co_summit",
        companyName: "Summit Builders",
        companyCode: "7F3K-92QX",
        companyLogoUrl: nil,
        industries: ["General Contracting", "Framing"],
        teamMembers: team,
        teamSize: 8,
        roleName: "Crew",
        invitedByName: "Dana Cole"
    )

    static let sparseConfirmPreview = ConfirmCompanyPreview(
        companyId: "co_apex",
        companyName: "Apex Electrical",
        companyCode: nil,
        companyLogoUrl: nil
    )

    /// A stand-in avatar for the "uploading" state (no real photo picked).
    static let avatarImage: UIImage = UIImage(systemName: "person.crop.circle.fill") ?? UIImage()
}

// MARK: - Stub boundaries (no network, no auth)

/// Each stub conforms to the screen's injected boundary protocol and returns a benign
/// outcome immediately. They reach NOTHING — no Supabase, no Firebase, no storage —
/// so the previewer can never create a real account / company or hit the network.
/// They re-declare the screens' file-private `Preview*Boundary` stubs (which are not
/// visible outside their own files).

@MainActor private struct StubLoginBoundary: LoginBoundary {
    func logInEmail(email: String, password: String) async -> LoginOutcome { .complete }
    func logInApple() async -> LoginOutcome { .complete }
    func logInGoogle() async -> LoginOutcome { .complete }
}

@MainActor private struct StubSignupBoundary: CreateAccountSignupBoundary {
    func signUpEmail(firstName: String, lastName: String, email: String, password: String) async -> CreateAccountOutcome { .created }
    func signUpApple() async -> CreateAccountOutcome { .created }
    func signUpGoogle() async -> CreateAccountOutcome { .created }
    func completeSocialName(firstName: String, lastName: String, email: String) async -> CreateAccountOutcome { .created }
}

@MainActor private struct StubCompanyBoundary: CompanyCreationBoundary {
    func createCompany(name: String, industries: [String]) async -> CompanyCreationOutcome { .created(code: "7F3K-92QX") }
}

@MainActor private struct StubInviteCheckBoundary: InviteCheckBoundary {
    func checkInvites() async -> InviteCheckOutcome { .found([]) }
}

@MainActor private struct StubCodeEntryBoundary: CodeEntryBoundary {
    func lookUpCompany(code: String) async -> CodeEntryOutcome { .notFound }
}

@MainActor private struct StubConfirmCompanyBoundary: ConfirmCompanyBoundary {
    func fetchTeamPreview() async -> CompanyJoinDetailsDTO? { nil }
    func join() async -> ConfirmCompanyJoinOutcome { .joined }
}

@MainActor private struct StubProfileBoundary: ProfileBoundary {
    func uploadAvatar(imageData: Data) async -> AvatarUploadOutcome { .uploaded(url: "") }
    func saveProfile(firstName: String, lastName: String, phone: String) async -> ProfileSaveOutcome { .saved }
}

@MainActor private struct StubEmergencyBoundary: EmergencyContactBoundary {
    func saveEmergencyContact(name: String, phone: String, relationship: String) async -> EmergencyContactSaveOutcome { .saved }
}

@MainActor private struct StubCompletionBoundary: CompletionBoundary {
    func complete() async -> OnboardingManager.CompletionOutcome { .acknowledged }
}

// MARK: - Preview

#Preview("RebuiltOnboardingPreviewView") {
    RebuiltOnboardingPreviewView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}

#endif
