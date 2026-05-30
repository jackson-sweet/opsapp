//
//  InvitePickerScreen.swift
//  OPS
//
//  Shows a list of pending team invitations when the user has multiple.
//  Each card displays company branding, team info, and role.
//  Tapping a card navigates to CompanyConfirmationScreen.
//

import SwiftUI

struct InvitePickerScreen: View {
    @ObservedObject var manager: OnboardingManager

    @StateObject private var animationCoordinator = OnboardingAnimationCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            OnboardingHeader(
                showBack: true,
                onBack: { manager.goBack() },
                onSignOut: { manager.signOut() }
            )
            .padding(.horizontal, 40)
            .padding(.top, 16)

            // Title
            PhasedOnboardingHeader(
                title: "YOU'VE BEEN INVITED",
                subtitle: "Pick your crew.",
                coordinator: animationCoordinator
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 32)

            // Invite cards
            PhasedContent(coordinator: animationCoordinator) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(manager.pendingInvites) { invite in
                            inviteCard(invite: invite)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)

            Spacer()

            // "Enter a different code" button
            PhasedPrimaryButton(
                "ENTER A DIFFERENT CODE",
                coordinator: animationCoordinator
            ) {
                manager.goToScreen(.codeEntry)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .background(OPSStyle.Colors.background)
        .onAppear {
            animationCoordinator.start()
        }
    }

    // MARK: - Invite Card

    @ViewBuilder
    private func inviteCard(invite: PendingInviteDTO) -> some View {
        Button {
            manager.selectedInvite = invite
            manager.confirmationSource = .pickerSelection
            manager.goToScreen(.companyConfirmation)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Top row: logo + company info
                HStack(spacing: 12) {
                    // Company logo (40x40)
                    cardLogoView(logoUrl: invite.companyLogoUrl, name: invite.companyName)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(invite.companyName.uppercased())
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)

                        // Industries (max 3)
                        if let industries = invite.industries, !industries.isEmpty {
                            Text(Array(industries.prefix(3)).joined(separator: " \u{2022} "))
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Chevron
                    Image("ops.chevron-right")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                // Team avatars + count
                if invite.teamSize > 0 {
                    HStack(spacing: 8) {
                        cardAvatarStack(members: invite.teamMembers, teamSize: invite.teamSize)

                        Text("\(invite.teamSize) member\(invite.teamSize == 1 ? "" : "s")")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Spacer()
                    }
                }

                // Bottom row: role badge + inviter
                HStack(spacing: 8) {
                    if let role = invite.roleName {
                        Text(role)
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(OPSStyle.Colors.primaryAccent.opacity(0.15))
                            )
                    }

                    if let inviter = invite.invitedByName {
                        Text("Invited by \(inviter)")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }

                    Spacer()
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Card Subviews

    /// Company logo for card (40x40) with initial-circle fallback
    @ViewBuilder
    private func cardLogoView(logoUrl: String?, name: String) -> some View {
        if let urlString = logoUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                default:
                    cardInitialCircle(name: name)
                }
            }
        } else {
            cardInitialCircle(name: name)
        }
    }

    /// Fallback circle with company initials (40x40)
    private func cardInitialCircle(name: String) -> some View {
        let words = name.split(separator: " ")
        let initials: String
        if words.count >= 2 {
            initials = String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else {
            initials = String(name.prefix(2)).uppercased()
        }

        return ZStack {
            Circle()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .overlay(
                    Circle()
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                )

            Text(initials)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .frame(width: 40, height: 40)
    }

    /// Stacked overlapping team member avatars for cards (28x28, max 6 + overflow)
    private func cardAvatarStack(members: [TeamMemberDTO], teamSize: Int) -> some View {
        let displayMembers = Array(members.prefix(6))
        let overflow = teamSize - displayMembers.count

        return HStack(spacing: -8) {
            ForEach(Array(displayMembers.enumerated()), id: \.offset) { index, member in
                cardMemberAvatar(member: member)
                    .zIndex(Double(displayMembers.count - index))
            }

            if overflow > 0 {
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .overlay(
                            Circle()
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )

                    Text("+\(overflow)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(width: 28, height: 28)
                .zIndex(0)
            }
        }
    }

    /// Single team member avatar for cards (28x28)
    @ViewBuilder
    private func cardMemberAvatar(member: TeamMemberDTO) -> some View {
        if let urlString = member.profileImageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(OPSStyle.Colors.cardBackgroundDark, lineWidth: 2))
                default:
                    cardMemberInitialCircle(member: member)
                }
            }
        } else {
            cardMemberInitialCircle(member: member)
        }
    }

    /// Fallback circle with member initials for cards (28x28)
    private func cardMemberInitialCircle(member: TeamMemberDTO) -> some View {
        ZStack {
            Circle()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .overlay(
                    Circle()
                        .stroke(OPSStyle.Colors.cardBackgroundDark, lineWidth: 2)
                )

            Text(member.initials)
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - Preview

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)
    manager.selectFlow(.employee)

    return InvitePickerScreen(manager: manager)
}
