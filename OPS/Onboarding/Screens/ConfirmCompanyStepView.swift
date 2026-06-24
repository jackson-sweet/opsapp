//
//  ConfirmCompanyStepView.swift
//  OPS
//
//  Onboarding rebuild P5 — S5c (Confirm company): the CREW-path COMMIT POINT. The
//  worker has resolved a company (a picked pending invite, or a looked-up code) and
//  lands here to CONFIRM their crew — branding, team preview, role — before tapping
//  the live JOIN. This is the screen that touches the real crew-join op
//  (`join_user_to_company` via `OnboardingManager.joinCompanyFromOnboarding`).
//
//  Reached from TWO origins, carried in the step's `ConfirmSource` (read by the
//  gateway off the coordinator's current step, NOT by this screen):
//    • `.picker`              — selected from the invite picker. Back → invitePicker.
//    • `.codeEntry(provenance)` — resolved from a typed code. Back → codeEntry(prov).
//  The back-edge is the coordinator's job (back map); this screen just calls onBack.
//
//  Design spec §4.2 S5c. A rebuild of the legacy `EmployeeCompanyConfirmationView`'s
//  working JOIN contract + good "JOIN CREW" / "NOT YOUR COMPANY?" copy, with the
//  legacy's design-system violations CORRECTED:
//    • Banned headline "WELCOME TO" → "CONFIRM YOUR CREW" (verify-before-commit, not
//      a premature welcome).
//    • Role tag was a `Capsule` tinted with the steel-blue ACCENT — both banned.
//      Now a neutral `chipRadius` (4pt) TAG (the same fix InvitePicker shipped).
//    • Spring entrance → the single OPS easing curve, honored only when Reduce Motion
//      is off.
//
//  RICH vs SPARSE (the deliberate fallback): when the join-details fetch returns team
//  data (avatars / member count / industries / role / invited-by) the screen renders
//  the full branded preview. When it does NOT (a legacy/code-entry company with no
//  team data, or the fetch failed), the screen renders a deliberate REDUCED layout —
//  company name + logo only — NOT a broken rich layout with empty rows. The decision
//  is the pure `ConfirmCompanyLayout` so it is unit-testable without rendering.
//
//  JOIN CONTRACT — the screen owns NO flow logic and reaches NO singletons. The join
//  is funnelled through an injected `ConfirmCompanyBoundary` returning a
//  `ConfirmCompanyJoinOutcome`; the navigation decision is the pure
//  `ConfirmCompanyOutcomeRouter`. On `.joined` → success haptic + onJoined (the
//  gateway advances to `.profile`). On `.failed` → an inline retry-able error, NO
//  nav. The boundary is also where the team-preview fetch happens (over
//  `OnboardingManager.fetchCompanyJoinDetails`), so the screen never touches an RPC.
//
//  Design-system conformance (`DESIGN.md` + `mobile/MOBILE.md`):
//    • Pure-black canvas, glass + hairlines, ZERO shadows. Accent (`opsAccent`)
//      appears ONLY on the one primary CTA (JOIN CREW). The card, role tag, avatars,
//      and the secondary CTA are all neutral.
//    • The company card is an L1 glass surface (`panelRadius`, hairline, glass
//      material). The role tag is an L3 `chipRadius` tag. Avatar stack reuses the
//      shared geometry (40pt logo, 28pt avatars, −8 overlap, +N overflow).
//    • One easing curve; honored only when Reduce Motion is off. Medium-impact haptic
//      ON TAP of JOIN; success on a completed join, error on a failure.
//  Every literal traces to an `OPSStyle` token. Copy locked via ops-copywriter
//  (NO "WELCOME TO"; role tag = chip not Capsule).
//

import SwiftUI

// MARK: - Confirm-company boundary (the testable seam)

/// The branded company + team preview the confirm screen renders. Built from the
/// persisted `formData.joinCompany*` (always present) PLUS an optional live
/// `fetchCompanyJoinDetails` enrichment (team avatars / member count / industries /
/// role / invited-by). When the enrichment is absent the screen renders the SPARSE
/// layout — name + logo only.
struct ConfirmCompanyPreview: Equatable {
    /// Always-present identity, persisted by the picker / code-entry screen.
    let companyId: String
    let companyName: String
    let companyCode: String?
    let companyLogoUrl: String?

    /// Optional live enrichment (nil / empty when unavailable → sparse layout).
    var industries: [String]?
    var teamMembers: [TeamMemberDTO]
    var teamSize: Int
    var roleName: String?
    var invitedByName: String?

    init(
        companyId: String,
        companyName: String,
        companyCode: String?,
        companyLogoUrl: String?,
        industries: [String]? = nil,
        teamMembers: [TeamMemberDTO] = [],
        teamSize: Int = 0,
        roleName: String? = nil,
        invitedByName: String? = nil
    ) {
        self.companyId = companyId
        self.companyName = companyName
        self.companyCode = companyCode
        self.companyLogoUrl = companyLogoUrl
        self.industries = industries
        self.teamMembers = teamMembers
        self.teamSize = teamSize
        self.roleName = roleName
        self.invitedByName = invitedByName
    }
}

/// What the live crew JOIN resolved to. The screen branches on these; the gateway
/// produces them from the live `OnboardingManager`. Never thrown — failures map to
/// a typed case so the screen always has an outcome to branch on.
enum ConfirmCompanyJoinOutcome: Equatable {
    /// The join committed (company_id / role / seat / invite-accept all written
    /// server-side). The gateway advances to `.profile`.
    case joined

    /// The join failed (network / server / no seats). Inline retry-able error; NO
    /// nav. `message` is a bare phrase the view prefixes + uppercases.
    case failed(message: String)
}

/// The async boundary S5c funnels BOTH its operations through: an OPTIONAL team-
/// preview enrichment fetch, and the live crew JOIN. Implemented live by the gateway
/// (over `OnboardingManager.fetchCompanyJoinDetails` + `joinCompanyFromOnboarding`);
/// stubbed in tests. `@MainActor` because the live manager is main-actor isolated.
@MainActor
protocol ConfirmCompanyBoundary {
    /// Best-effort fetch of the team preview (avatars / member count / industries) for
    /// the resolved company. Returns `nil` when there is nothing to enrich with (no
    /// code to look up, the lookup failed, or the company has no team data) — the
    /// screen then renders the SPARSE layout. NEVER throws / blocks the JOIN.
    func fetchTeamPreview() async -> CompanyJoinDetailsDTO?

    /// Commit the crew JOIN — the live `join_user_to_company` op. Returns `.joined`
    /// on success, `.failed(message:)` on any error (no seats / network / server).
    func join() async -> ConfirmCompanyJoinOutcome
}

// MARK: - S5c screen

struct ConfirmCompanyStepView: View {

    /// The async boundary. Injected so the screen never touches an RPC.
    let boundary: ConfirmCompanyBoundary

    /// The always-present identity persisted by the picker / code-entry screen
    /// (`formData.joinCompany*`). The screen renders this immediately and ENRICHES it
    /// with the boundary's team preview when it lands — so a slow/failed fetch never
    /// blocks the confirm.
    let companyName: String
    let companyLogoUrl: String?

    /// JOIN succeeded → the gateway advances to `.profile`.
    let onJoined: () -> Void

    /// Header Back per the back map (`.picker` → invitePicker; `.codeEntry(prov)` →
    /// codeEntry(prov)). The gateway wires `coordinator.goBack()`. The back LABEL
    /// (the previous-screen short name) is passed in so the screen stays ignorant of
    /// the source.
    let backLabel: String
    let onBack: () -> Void

    // MARK: Init

    init(
        boundary: ConfirmCompanyBoundary,
        companyName: String,
        companyLogoUrl: String?,
        backLabel: String,
        onJoined: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.boundary = boundary
        self.companyName = companyName
        self.companyLogoUrl = companyLogoUrl
        self.backLabel = backLabel
        self.onJoined = onJoined
        self.onBack = onBack
    }

    #if DEBUG
    /// Snapshot/preview seam — seeds the resolved preview + visual `@State` (loading /
    /// error) so a renderer can capture the rich / sparse / error / loading frames a
    /// renderer can't otherwise drive. DEBUG-only; never used by the live gateway.
    init(
        boundary: ConfirmCompanyBoundary,
        companyName: String,
        companyLogoUrl: String? = nil,
        backLabel: String = "Invites",
        previewState: ConfirmCompanyPreview,
        previewIsJoining: Bool = false,
        previewError: String? = nil,
        onJoined: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {}
    ) {
        self.boundary = boundary
        self.companyName = companyName
        self.companyLogoUrl = companyLogoUrl
        self.backLabel = backLabel
        self.onJoined = onJoined
        self.onBack = onBack
        _preview = State(initialValue: previewState)
        _isJoining = State(initialValue: previewIsJoining)
        _errorMessage = State(initialValue: previewError)
        _hasAppeared = State(initialValue: true)
        _previewInert = State(initialValue: true)
    }
    #endif

    // MARK: State

    /// The branded preview the screen renders. Seeded immediately from the persisted
    /// identity (sparse), then ENRICHED in place when the boundary's team-preview
    /// fetch lands. A nil-team enrichment leaves it sparse — never a broken rich card.
    @State private var preview: ConfirmCompanyPreview?

    /// An inline error (join failure). Cleared on the next attempt.
    @State private var errorMessage: String?

    /// True while the JOIN is in flight — drives the CTA spinner + gate.
    @State private var isJoining = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    #if DEBUG
    /// When true (snapshot seam only) the view performs NO side effects on appear —
    /// no team-preview fetch — so a render captures a stable, seeded frame.
    @State private var previewInert = false
    #endif

    /// The preview the body renders off — the resolved `@State`, falling back to a
    /// sparse preview built from the always-present identity so the FIRST frame
    /// (before the fetch lands) is already correct.
    private var resolvedPreview: ConfirmCompanyPreview {
        preview ?? ConfirmCompanyPreview(
            companyId: "",
            companyName: companyName,
            companyCode: nil,
            companyLogoUrl: companyLogoUrl
        )
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            ScrollView {
                scrollContent
            }
        }
        .onAppear {
            OnboardingHaptics.prepare()
            seedPreviewIfNeeded()
            runEntrance()
            fetchTeamPreviewIfNeeded()
        }
    }

    /// The full vertical stack. Extracted so the DEBUG snapshot harness can render it
    /// WITHOUT the enclosing `ScrollView`.
    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            header

            subline
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            companyCard
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            ctaBlock
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
        .padding(.bottom, OPSStyle.Layout.spacing5)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: (hasAppeared || reduceMotion) ? 0 : OPSStyle.Layout.spacing3)
    }

    #if DEBUG
    /// A render of the screen with no `ScrollView`, for the snapshot harness only.
    var snapshotBody: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()
            scrollContent
        }
    }
    #endif

    // MARK: - Header (Back per back map)

    private var header: some View {
        OnboardingStepHeader(
            title: "Confirm your crew",
            backLabel: backLabel,
            onBack: onBack
        )
    }

    // MARK: - Subline (rich vs sparse copy)

    private var subline: some View {
        Text(sublineText)
            .font(OPSStyle.Typography.body) // Mohave 16pt
            .foregroundColor(OPSStyle.Colors.text2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(sublineText)
    }

    /// The instruction adapts to the layout: a "crew" framing when a team preview is
    /// shown, a "company" framing when only the name + logo are known (sparse).
    private var sublineText: String {
        switch ConfirmCompanyLayout.decide(resolvedPreview) {
        case .rich:   return "Make sure this is your crew before you join."
        case .sparse: return "Make sure this is the right company before you join."
        }
    }

    // MARK: - Company card (L1 glass — rich or sparse)

    private var companyCard: some View {
        ConfirmCompanyCard(preview: resolvedPreview)
    }

    // MARK: - CTA block (primary JOIN + secondary NOT-YOUR-COMPANY + inline error)

    private var ctaBlock: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            if let errorMessage {
                Text("// ERROR — \(errorMessage.uppercased())")
                    .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                    .tracking(1.4)
                    .foregroundColor(OPSStyle.Colors.rose)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Error. \(errorMessage)")
            }

            OnboardingPrimaryCTA(
                title: "Join crew",
                isLoading: isJoining
            ) {
                attemptJoin()
            }

            OnboardingSecondaryCTA(title: "Not your company?") {
                onBack()
            }
        }
    }

    // MARK: - Entrance

    private func runEntrance() {
        guard !hasAppeared else { return }
        if reduceMotion {
            hasAppeared = true
        } else {
            withAnimation(OPSStyle.Animation.page) { hasAppeared = true }
        }
    }

    // MARK: - Team-preview fetch (best-effort enrichment — never blocks the join)

    /// Seed the sparse preview from the always-present identity so the first frame is
    /// correct before any fetch lands. Idempotent.
    private func seedPreviewIfNeeded() {
        guard preview == nil else { return }
        preview = ConfirmCompanyPreview(
            companyId: "",
            companyName: companyName,
            companyCode: nil,
            companyLogoUrl: companyLogoUrl
        )
    }

    /// Best-effort enrichment. The fetch is OPTIONAL — a nil result leaves the sparse
    /// preview untouched (the deliberate fallback). It NEVER gates the JOIN.
    private func fetchTeamPreviewIfNeeded() {
        #if DEBUG
        if previewInert { return } // snapshot seam — no side effects
        #endif

        Task { @MainActor in
            guard let details = await boundary.fetchTeamPreview() else { return }
            enrich(with: details)
        }
    }

    /// Merge the live team details into the preview, keeping the always-present
    /// identity (name / logo the user already saw) authoritative.
    private func enrich(with details: CompanyJoinDetailsDTO) {
        let merged = ConfirmCompanyPreview(
            companyId: details.companyId.isEmpty ? resolvedPreview.companyId : details.companyId,
            companyName: companyName, // keep the name the user confirmed against
            companyCode: details.companyCode ?? resolvedPreview.companyCode,
            companyLogoUrl: companyLogoUrl ?? details.companyLogoUrl,
            industries: details.industries,
            teamMembers: details.teamMembers,
            teamSize: details.teamSize,
            roleName: resolvedPreview.roleName,
            invitedByName: resolvedPreview.invitedByName
        )
        if reduceMotion {
            preview = merged
        } else {
            withAnimation(OPSStyle.Animation.standard) { preview = merged }
        }
    }

    // MARK: - Join (the live commit point)

    /// The crew JOIN. Immediate medium haptic ON TAP, loading state during the async,
    /// then branch on the outcome via the pure router: `.joined` → success haptic +
    /// onJoined (gateway advances to `.profile`); `.failed` → inline error, NO nav.
    func attemptJoin() {
        guard !isJoining else { return }
        errorMessage = nil
        isJoining = true
        OnboardingHaptics.commit() // immediate medium impact ON TAP

        Task { @MainActor in
            let outcome = await boundary.join()
            isJoining = false
            handle(outcome)
        }
    }

    /// Route a join outcome. `.joined` is the only navigation — delegated to the pure
    /// `ConfirmCompanyOutcomeRouter` so it is unit-testable; the error case sets local
    /// state here.
    func handle(_ outcome: ConfirmCompanyJoinOutcome) {
        let navigated = ConfirmCompanyOutcomeRouter.route(
            outcome,
            onJoined: {
                OnboardingHaptics.success()
                onJoined()
            }
        )
        guard !navigated else { return }

        OnboardingHaptics.error()
        if case .failed(let message) = outcome {
            errorMessage = message
        }
    }
}

// MARK: - Pure layout decision (rich vs sparse — fully unit-testable)

/// The deliberate rich-vs-sparse layout decision, factored out of the view so it is
/// unit-testable without rendering. RICH requires real team data to show; otherwise
/// the screen renders the reduced SPARSE layout (name + logo only) — never a broken
/// rich card with empty rows.
enum ConfirmCompanyLayout: Equatable {
    /// Full branded preview — at least a team member OR a member count is present.
    case rich
    /// Reduced fallback — company name + logo only.
    case sparse

    /// Decide from the resolved preview. The screen is RICH when there is real team
    /// data to render: a non-empty team-member list OR a positive member count (the
    /// avatar stack + "N members" row). Industries / role / invited-by are additive
    /// detail ON a rich card — they do not, alone, justify the rich layout (a card
    /// with industries but no crew still reads as sparse to the worker).
    static func decide(_ preview: ConfirmCompanyPreview) -> ConfirmCompanyLayout {
        let hasTeam = !preview.teamMembers.isEmpty || preview.teamSize > 0
        return hasTeam ? .rich : .sparse
    }
}

// MARK: - Pure outcome routing (no SwiftUI, fully unit-testable)

/// Routes the ONE host-navigating outcome (`.joined`) and reports whether it handled
/// the outcome. The error case is local-state-only and returns `false` so the caller
/// applies it to `@State`. Extracted so the navigation branch is testable without
/// rendering (the house pattern — see `CodeEntryOutcomeRouter`).
enum ConfirmCompanyOutcomeRouter {
    /// - Returns: `true` when the outcome was the host-navigation effect (and the
    ///   `onJoined` closure was invoked); `false` for the local-state-only error case.
    @discardableResult
    static func route(
        _ outcome: ConfirmCompanyJoinOutcome,
        onJoined: () -> Void
    ) -> Bool {
        switch outcome {
        case .joined:
            onJoined()
            return true
        case .failed:
            return false
        }
    }
}

// MARK: - Company card (L1 glass — renders rich OR sparse off the pure decision)

/// The confirm card. An L1 glass surface (`panelRadius`, hairline, glass material,
/// ZERO shadow). Renders the full branded preview when `ConfirmCompanyLayout` decides
/// `.rich`, or the reduced name + logo when `.sparse`. NO accent — every element is
/// neutral. The role TAG uses `chipRadius` (4pt), NOT a Capsule (the legacy bug).
private struct ConfirmCompanyCard: View {
    let preview: ConfirmCompanyPreview

    private var layout: ConfirmCompanyLayout { ConfirmCompanyLayout.decide(preview) }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            topRow
            if layout == .rich {
                if preview.teamSize > 0 || !preview.teamMembers.isEmpty { teamRow }
                bottomRow
            }
        }
        .padding(OPSStyle.Layout.spacing3) // 16pt — §3 m-card-inset
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: OPSStyle.Layout.panelRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Top row — logo + name + industries (industries shown only when present)

    private var topRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            ConfirmCompanyLogo(logoUrl: preview.companyLogoUrl, name: preview.companyName)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1 / 2) {
                Text(preview.companyName.uppercased())
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                if let industries = preview.industries, !industries.isEmpty {
                    Text(Array(industries.prefix(3)).joined(separator: " · "))
                        .font(OPSStyle.Typography.smallCaption) // JetBrains Mono 12pt
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Team row — overlapping avatar stack + "N members"

    private var teamRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ConfirmAvatarStack(members: preview.teamMembers, teamSize: preview.teamSize)

            Text(memberCountLabel)
                .font(OPSStyle.Typography.smallCaption) // JetBrains Mono 12pt
                .foregroundColor(OPSStyle.Colors.text2)

            Spacer(minLength: 0)
        }
    }

    /// "1 member" / "N members". Mono number, pluralized.
    private var memberCountLabel: String {
        "\(preview.teamSize) member\(preview.teamSize == 1 ? "" : "s")"
    }

    // MARK: Bottom row — role tag (chipRadius, NOT a Capsule) + "Invited by …"

    private var bottomRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            if let role = preview.roleName, !role.isEmpty {
                ConfirmRoleTag(role: role)
            }

            if let inviter = preview.invitedByName, !inviter.isEmpty {
                Text("Invited by \(inviter)")
                    .font(OPSStyle.Typography.smallCaption) // JetBrains Mono 12pt
                    .foregroundColor(OPSStyle.Colors.text3)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    /// One-line VoiceOver summary of the whole card.
    private var accessibilitySummary: String {
        var parts: [String] = [preview.companyName]
        if preview.teamSize > 0 { parts.append(memberCountLabel) }
        if let role = preview.roleName, !role.isEmpty { parts.append("you'll join as \(role)") }
        if let inviter = preview.invitedByName, !inviter.isEmpty { parts.append("invited by \(inviter)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Role tag (chipRadius — the Capsule→chip + accent→neutral fix)

/// The role badge. §4.3 / L3 tag visual: `chipRadius` (4pt), surfaceInput fill,
/// hairline border. JetBrains Mono uppercase. NO accent (the legacy used the steel-
/// blue accent on a Capsule — both are corrected here). NO 999px pill.
private struct ConfirmRoleTag: View {
    let role: String

    var body: some View {
        Text(role.uppercased())
            .font(OPSStyle.Typography.tagLabel) // JetBrains Mono micro label
            .tracking(1.0)
            .foregroundColor(OPSStyle.Colors.text2)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .accessibilityLabel("You'll join as \(role)")
    }
}

// MARK: - Company logo (40pt) with initial-circle fallback

private struct ConfirmCompanyLogo: View {
    let logoUrl: String?
    let name: String

    private let side: CGFloat = 40

    var body: some View {
        Group {
            if let urlString = logoUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        initialCircle
                    }
                }
            } else {
                initialCircle
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .accessibilityHidden(true)
    }

    private var initialCircle: some View {
        ZStack {
            OPSStyle.Colors.surfaceInput
            Text(Self.initials(from: name))
                .font(OPSStyle.Typography.cardSubtitle) // JetBrains Mono 15pt
                .foregroundColor(OPSStyle.Colors.text)
        }
    }

    /// Two-letter company initials (first letters of the first two words, else the
    /// first two chars).
    static func initials(from name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Avatar stack (28pt, −8 overlap, +N overflow)

/// The overlapping team-avatar stack. Reads as CLEAN STACKED CIRCLES, not intersecting
/// "Olympic rings": each circle carries a canvas-colored separator BAND on its outer
/// edge (`stackedCircleBand`), and consistent front-to-back Z-ORDER (first member on
/// top, each subsequent one behind, the +N badge at the very back) means the disc in
/// front cuts a clean crescent out of the one behind it. The −8 overlap, 28pt side, and
/// 2pt band all trace to `OPSStyle` tokens.
private struct ConfirmAvatarStack: View {
    let members: [TeamMemberDTO]
    let teamSize: Int

    private let side: CGFloat = 28
    private let maxShown = 5
    /// Width of the canvas-colored separator band (the crescent the front circle cuts).
    private let ringWidth: CGFloat = OPSStyle.Layout.Border.thick // 2pt

    var body: some View {
        let shown = Array(members.prefix(maxShown))
        let overflow = teamSize - shown.count

        return HStack(spacing: -OPSStyle.Layout.spacing2) { // −8 overlap
            ForEach(Array(shown.enumerated()), id: \.offset) { index, member in
                ConfirmMemberAvatar(member: member, side: side, ringWidth: ringWidth)
                    // First member draws on top; each subsequent one falls behind so the
                    // overlaps nest in a single clear front-to-back order.
                    .zIndex(Double(shown.count - index))
            }
            if overflow > 0 {
                overflowBadge(overflow)
                    .zIndex(0) // the +N badge sits at the very back of the stack
            }
        }
        .accessibilityHidden(true)
    }

    private func overflowBadge(_ overflow: Int) -> some View {
        ZStack {
            OPSStyle.Colors.surfaceInput
            Text("+\(overflow)")
                .font(OPSStyle.Typography.microLabel) // JetBrains Mono micro
                .foregroundColor(OPSStyle.Colors.text2)
        }
        .stackedCircleBand(side: side, ringWidth: ringWidth)
    }
}

private struct ConfirmMemberAvatar: View {
    let member: TeamMemberDTO
    let side: CGFloat
    /// Width of the canvas-colored separator band on the outer edge.
    var ringWidth: CGFloat = OPSStyle.Layout.Border.thick

    var body: some View {
        avatar
            .stackedCircleBand(side: side, ringWidth: ringWidth)
    }

    private var avatar: some View {
        Group {
            if let urlString = member.profileImageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        initialCircle
                    }
                }
            } else {
                initialCircle
            }
        }
    }

    private var initialCircle: some View {
        ZStack {
            OPSStyle.Colors.surfaceInput
            Text(member.initials)
                .font(OPSStyle.Typography.microLabel) // JetBrains Mono micro
                .foregroundColor(OPSStyle.Colors.text2)
        }
    }
}

// MARK: - Stacked-circle separator band (clean crescents, not Olympic rings)

/// Wraps circular avatar/badge content in a canvas-colored separator BAND so that, when
/// overlapped in a stack, the element in front cuts a clean crescent out of the one
/// behind — stacked circles, never intersecting "Olympic rings". The content fills the
/// inner circle (`side − 2·ringWidth`); the outer `ringWidth` of the `side`-wide
/// footprint is filled with the canvas/background color and clipped to a circle. Because
/// the front element's full `side` disc (band included) draws on top, it occludes the
/// element behind it cleanly. The footprint stays `side`, so the stack's overlap math is
/// unchanged. ZERO shadows — pure occlusion. (NOT a centered stroke, which straddles the
/// edge and leaves both outlines showing.)
private struct StackedCircleBand: ViewModifier {
    let side: CGFloat
    let ringWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: side - ringWidth * 2, height: side - ringWidth * 2)
            .clipShape(Circle())
            .padding(ringWidth)
            .background(OPSStyle.Colors.background) // the separator band (canvas color)
            .clipShape(Circle())
            .frame(width: side, height: side)
    }
}

private extension View {
    /// Apply the stacked-circle separator band (see `StackedCircleBand`).
    func stackedCircleBand(side: CGFloat, ringWidth: CGFloat) -> some View {
        modifier(StackedCircleBand(side: side, ringWidth: ringWidth))
    }
}

// MARK: - Previews

#if DEBUG
/// A preview/stub boundary — no network. Returns a fixed team preview + join outcome.
private struct PreviewConfirmCompanyBoundary: ConfirmCompanyBoundary {
    var details: CompanyJoinDetailsDTO?
    var outcome: ConfirmCompanyJoinOutcome = .joined
    func fetchTeamPreview() async -> CompanyJoinDetailsDTO? { details }
    func join() async -> ConfirmCompanyJoinOutcome { outcome }
}

private extension ConfirmCompanyPreview {
    static func richFixture() -> ConfirmCompanyPreview {
        ConfirmCompanyPreview(
            companyId: "co-1",
            companyName: "Sweet Deck & Rail",
            companyCode: "BR8K90ZT",
            companyLogoUrl: nil,
            industries: ["Carpentry", "Roofing"],
            teamMembers: [
                TeamMemberDTO(firstName: "Jack", lastName: "Sweet", profileImageUrl: nil),
                TeamMemberDTO(firstName: "Mara", lastName: "Lopez", profileImageUrl: nil),
                TeamMemberDTO(firstName: "Devon", lastName: "Reed", profileImageUrl: nil)
            ],
            teamSize: 6,
            roleName: "Crew",
            invitedByName: "Jack Sweet"
        )
    }

    static func sparseFixture() -> ConfirmCompanyPreview {
        ConfirmCompanyPreview(
            companyId: "co-2",
            companyName: "North Ridge HVAC",
            companyCode: "NR4G99AB",
            companyLogoUrl: nil
        )
    }
}

#Preview("ConfirmCompanyStepView — rich") {
    ConfirmCompanyStepView(
        boundary: PreviewConfirmCompanyBoundary(),
        companyName: "Sweet Deck & Rail",
        previewState: .richFixture()
    )
    .preferredColorScheme(.dark)
}

#Preview("ConfirmCompanyStepView — sparse") {
    ConfirmCompanyStepView(
        boundary: PreviewConfirmCompanyBoundary(),
        companyName: "North Ridge HVAC",
        previewState: .sparseFixture()
    )
    .preferredColorScheme(.dark)
}

#Preview("ConfirmCompanyStepView — error") {
    ConfirmCompanyStepView(
        boundary: PreviewConfirmCompanyBoundary(),
        companyName: "Sweet Deck & Rail",
        previewState: .richFixture(),
        previewError: "couldn't join — try again"
    )
    .preferredColorScheme(.dark)
}
#endif
