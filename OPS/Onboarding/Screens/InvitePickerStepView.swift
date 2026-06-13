//
//  InvitePickerStepView.swift
//  OPS
//
//  Onboarding rebuild P5 — Invite picker: the CREW-path screen that lists the
//  pending team invitations the user has been invited to. They pick their crew to
//  join. A single-card picker is fine — it lets the user CONFIRM their crew before
//  joining (the step machine routes both 1 and N invites here).
//
//  Design spec §4.2. A rebuild of the legacy `InvitePickerScreen`'s strong card
//  design — company logo / initial, industries, an overlapping team-avatar stack,
//  "N members", a role tag, and "Invited by …". CRITICAL FIX vs the legacy: the
//  role tag uses a `chipRadius` (4pt) TAG, NOT a `Capsule` — the legacy used a
//  Capsule, which violates the OPS "no 999px pills except avatars" rule.
//
//  SELECTION CONTRACT — the screen owns NO flow logic and reaches NO singletons.
//  Selecting a card persists the chosen invite (company id, code, name) into form
//  data via `onSelectInvite` and advances to `.confirmCompany(source: .picker)`.
//  The secondary "Enter a different code" advances to
//  `.codeEntry(provenance: .fromPicker)`. Header Back → `coordinator.goBack()`
//  (picker.backEdge = rolePick). The gateway wires all three; tests drive the
//  closures directly — no network.
//
//  Design-system conformance (`DESIGN.md` + `mobile/MOBILE.md`):
//    • Pure-black canvas, glass + hairlines, ZERO shadows. NO accent anywhere on
//      this screen — the cards, role tag, avatars, and the secondary CTA are all
//      neutral. (Accent is reserved for a single PRIMARY CTA; this screen's action
//      is the card tap, so there is no accented control.)
//    • Cards are L1 glass surfaces: `panelRadius` (10pt), hairline border, the
//      `.glassSurface()` material. Role tag is an L3 `chipRadius` tag.
//    • Team-avatar stack + initial-circle fallbacks reuse the legacy geometry
//      (40pt logo, 28pt avatars, −8 overlap, +N overflow), retuned to tokens.
//    • One easing curve; honored only when Reduce Motion is off. Light selection
//      haptic on a card tap / the secondary action.
//  Every literal traces to an `OPSStyle` token. Copy locked via ops-copywriter.
//

import SwiftUI

struct InvitePickerStepView: View {

    /// The pending invitations to choose from. The gateway passes the invites S4c
    /// fetched and persisted into `formData` (so the picker never re-fetches).
    let invites: [PendingInviteDTO]

    /// Select an invite → persist it into form data, then advance to
    /// `.confirmCompany(source: .picker)`. The gateway wires both effects.
    let onSelectInvite: (PendingInviteDTO) -> Void

    /// "Enter a different code" → `.codeEntry(provenance: .fromPicker)`.
    let onEnterDifferentCode: () -> Void

    /// Header Back → role pick (`invitePicker.backEdge == rolePick`). The gateway
    /// wires `coordinator.goBack()`.
    let onBack: () -> Void

    // MARK: Init

    init(
        invites: [PendingInviteDTO],
        onSelectInvite: @escaping (PendingInviteDTO) -> Void,
        onEnterDifferentCode: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.invites = invites
        self.onSelectInvite = onSelectInvite
        self.onEnterDifferentCode = onEnterDifferentCode
        self.onBack = onBack
    }

    #if DEBUG
    /// Snapshot/preview seam — settles the entrance so a renderer captures the
    /// settled frame. DEBUG-only; never used by the live gateway.
    init(
        invites: [PendingInviteDTO],
        previewSettled: Bool,
        onSelectInvite: @escaping (PendingInviteDTO) -> Void = { _ in },
        onEnterDifferentCode: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {}
    ) {
        self.invites = invites
        self.onSelectInvite = onSelectInvite
        self.onEnterDifferentCode = onEnterDifferentCode
        self.onBack = onBack
        _hasAppeared = State(initialValue: previewSettled)
    }
    #endif

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            ScrollView {
                scrollContent
            }
        }
        .onAppear {
            OnboardingHaptics.prepare()
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(OPSStyle.Animation.page) { hasAppeared = true }
            }
        }
    }

    /// The full vertical stack. Extracted so the DEBUG snapshot harness can render
    /// it WITHOUT the enclosing `ScrollView` (`ImageRenderer` reports zero intrinsic
    /// size for a `ScrollView`).
    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            header

            subline
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            cardStack
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            differentCodeBlock
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

    // MARK: - Header (Back → role pick)

    private var header: some View {
        OnboardingStepHeader(
            title: "You've been invited",
            backLabel: "Role",
            onBack: onBack
        )
    }

    // MARK: - Subline

    private var subline: some View {
        Text("Pick your crew.")
            .font(OPSStyle.Typography.body) // Mohave 16pt
            .foregroundColor(OPSStyle.Colors.text2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Pick your crew")
    }

    // MARK: - Card stack

    private var cardStack: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            ForEach(invites) { invite in
                InviteCard(invite: invite) {
                    OnboardingHaptics.selection()
                    onSelectInvite(invite)
                }
            }
        }
    }

    // MARK: - Enter a different code (secondary)

    private var differentCodeBlock: some View {
        OnboardingSecondaryCTA(title: "Enter a different code") {
            onEnterDifferentCode()
        }
    }
}

// MARK: - Invite card

/// A single invitation card. L1 glass surface (panelRadius, hairline, glass
/// material, ZERO shadow). Tapping it selects the crew. NO accent — every element
/// is neutral. The role TAG uses `chipRadius` (4pt), NOT a Capsule (the legacy bug).
private struct InviteCard: View {
    let invite: PendingInviteDTO
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                topRow
                if invite.teamSize > 0 { teamRow }
                bottomRow
            }
            .padding(OPSStyle.Layout.spacing3) // 16pt — §3 m-card-inset
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: OPSStyle.Layout.panelRadius)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Top row — logo + name + industries + chevron

    private var topRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            CompanyLogo(logoUrl: invite.companyLogoUrl, name: invite.companyName)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1 / 2) {
                Text(invite.companyName.uppercased())
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)

                if let industries = invite.industries, !industries.isEmpty {
                    Text(Array(industries.prefix(3)).joined(separator: " · "))
                        .font(OPSStyle.Typography.smallCaption) // JetBrains Mono 12pt
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: OPSStyle.Layout.spacing2)

            Image(systemName: OPSStyle.Icons.chevronRight)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.text3)
        }
    }

    // MARK: Team row — overlapping avatar stack + "N members"

    private var teamRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            AvatarStack(members: invite.teamMembers, teamSize: invite.teamSize)

            Text(memberCountLabel)
                .font(OPSStyle.Typography.smallCaption) // JetBrains Mono 12pt
                .foregroundColor(OPSStyle.Colors.text2)

            Spacer(minLength: 0)
        }
    }

    /// "1 member" / "N members". Mono number, pluralized.
    private var memberCountLabel: String {
        "\(invite.teamSize) member\(invite.teamSize == 1 ? "" : "s")"
    }

    // MARK: Bottom row — role tag (chipRadius, NOT a Capsule) + "Invited by …"

    private var bottomRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            if let role = invite.roleName, !role.isEmpty {
                RoleTag(role: role)
            }

            if let inviter = invite.invitedByName, !inviter.isEmpty {
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
        var parts: [String] = [invite.companyName]
        if invite.teamSize > 0 { parts.append(memberCountLabel) }
        if let role = invite.roleName, !role.isEmpty { parts.append("role \(role)") }
        if let inviter = invite.invitedByName, !inviter.isEmpty { parts.append("invited by \(inviter)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Role tag (chipRadius — the Capsule→chip fix)

/// The role badge. §4.3 / L3 tag visual: `chipRadius` (4pt), surfaceInput fill,
/// hairline border. JetBrains Mono uppercase. NO accent (the legacy used the
/// steel-blue accent on a Capsule — both are corrected here). NO 999px pill.
private struct RoleTag: View {
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
            .accessibilityLabel("Role \(role)")
    }
}

// MARK: - Company logo (40pt) with initial-circle fallback

private struct CompanyLogo: View {
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

private struct AvatarStack: View {
    let members: [TeamMemberDTO]
    let teamSize: Int

    private let side: CGFloat = 28
    private let maxShown = 5

    var body: some View {
        let shown = Array(members.prefix(maxShown))
        let overflow = teamSize - shown.count

        return HStack(spacing: -OPSStyle.Layout.spacing2) { // −8 overlap
            ForEach(Array(shown.enumerated()), id: \.offset) { index, member in
                MemberAvatar(member: member, side: side)
                    .zIndex(Double(shown.count - index))
            }
            if overflow > 0 {
                overflowBadge(overflow)
                    .zIndex(0)
            }
        }
        .accessibilityHidden(true)
    }

    private func overflowBadge(_ overflow: Int) -> some View {
        ZStack {
            Circle().fill(OPSStyle.Colors.surfaceInput)
            Circle().stroke(OPSStyle.Colors.background, lineWidth: OPSStyle.Layout.Border.thick)
            Text("+\(overflow)")
                .font(OPSStyle.Typography.microLabel) // JetBrains Mono micro
                .foregroundColor(OPSStyle.Colors.text2)
        }
        .frame(width: side, height: side)
    }
}

private struct MemberAvatar: View {
    let member: TeamMemberDTO
    let side: CGFloat

    var body: some View {
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
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay(Circle().stroke(OPSStyle.Colors.background, lineWidth: OPSStyle.Layout.Border.thick))
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

// MARK: - Previews

#if DEBUG
private extension PendingInviteDTO {
    /// A fixture invite for previews/snapshots.
    static func fixture(
        name: String = "Sweet Deck & Rail",
        industries: [String]? = ["Carpentry", "Roofing"],
        role: String? = "Crew",
        invitedBy: String? = "Jack Sweet",
        teamSize: Int = 6
    ) -> PendingInviteDTO {
        PendingInviteDTO(
            invitationId: UUID().uuidString,
            companyId: UUID().uuidString,
            companyName: name,
            companyCode: "BR8K90ZT",
            companyLogoUrl: nil,
            industries: industries,
            roleName: role,
            invitedByName: invitedBy,
            teamMembers: [
                TeamMemberDTO(firstName: "Jack", lastName: "Sweet", profileImageUrl: nil),
                TeamMemberDTO(firstName: "Mara", lastName: "Lopez", profileImageUrl: nil),
                TeamMemberDTO(firstName: "Devon", lastName: "Reed", profileImageUrl: nil)
            ],
            teamSize: teamSize,
            expiresAt: "2026-12-31T00:00:00Z"
        )
    }
}

#Preview("InvitePickerStepView — multiple") {
    InvitePickerStepView(
        invites: [
            .fixture(),
            .fixture(name: "North Ridge HVAC", industries: ["HVAC"], role: "Lead", invitedBy: "Sam Okafor", teamSize: 1)
        ],
        previewSettled: true
    )
    .preferredColorScheme(.dark)
}

#Preview("InvitePickerStepView — single") {
    InvitePickerStepView(
        invites: [.fixture()],
        previewSettled: true
    )
    .preferredColorScheme(.dark)
}
#endif
