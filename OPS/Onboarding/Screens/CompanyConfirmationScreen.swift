//
//  CompanyConfirmationScreen.swift
//  OPS
//
//  Confirms the company before the user joins during onboarding.
//  Shows branded company info (logo, name, industries, team avatars, role).
//  Supports both invite-based and manual code entry sources.
//

import SwiftUI

struct CompanyConfirmationScreen: View {
    @ObservedObject var manager: OnboardingManager

    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var logoAppeared = false

    @StateObject private var animationCoordinator = OnboardingAnimationCoordinator()

    // MARK: - Resolved Data

    /// The company name to display, resolved from either invite or manual details.
    private var companyName: String {
        switch manager.confirmationSource {
        case .singleInvite, .pickerSelection:
            return manager.selectedInvite?.companyName ?? ""
        case .manualCodeEntry:
            return manager.companyJoinDetails?.companyName ?? ""
        }
    }

    private var companyLogoUrl: String? {
        switch manager.confirmationSource {
        case .singleInvite, .pickerSelection:
            return manager.selectedInvite?.companyLogoUrl
        case .manualCodeEntry:
            return manager.companyJoinDetails?.companyLogoUrl
        }
    }

    private var industries: [String] {
        let raw: [String]?
        switch manager.confirmationSource {
        case .singleInvite, .pickerSelection:
            raw = manager.selectedInvite?.industries
        case .manualCodeEntry:
            raw = manager.companyJoinDetails?.industries
        }
        return Array((raw ?? []).prefix(3))
    }

    private var teamMembers: [TeamMemberDTO] {
        switch manager.confirmationSource {
        case .singleInvite, .pickerSelection:
            return manager.selectedInvite?.teamMembers ?? []
        case .manualCodeEntry:
            return manager.companyJoinDetails?.teamMembers ?? []
        }
    }

    private var teamSize: Int {
        switch manager.confirmationSource {
        case .singleInvite, .pickerSelection:
            return manager.selectedInvite?.teamSize ?? 0
        case .manualCodeEntry:
            return manager.companyJoinDetails?.teamSize ?? 0
        }
    }

    private var companyId: String {
        switch manager.confirmationSource {
        case .singleInvite, .pickerSelection:
            return manager.selectedInvite?.companyId ?? ""
        case .manualCodeEntry:
            return manager.companyJoinDetails?.companyId ?? ""
        }
    }

    private var invitationId: String? {
        switch manager.confirmationSource {
        case .singleInvite, .pickerSelection:
            return manager.selectedInvite?.invitationId
        case .manualCodeEntry:
            return nil
        }
    }

    private var roleName: String? {
        switch manager.confirmationSource {
        case .singleInvite, .pickerSelection:
            return manager.selectedInvite?.roleName
        case .manualCodeEntry:
            return nil
        }
    }

    private var inviterName: String? {
        switch manager.confirmationSource {
        case .singleInvite, .pickerSelection:
            return manager.selectedInvite?.invitedByName
        case .manualCodeEntry:
            return nil
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            OnboardingHeader(
                showBack: true,
                onBack: { handleBack() },
                onSignOut: { manager.signOut() }
            )
            .padding(.horizontal, 40)
            .padding(.top, 16)

            Spacer()

            // Company card content
            PhasedContent(coordinator: animationCoordinator) {
                VStack(spacing: 24) {
                    // Company logo
                    companyLogoView
                        .scaleEffect(logoAppeared ? 1.0 : 0.3)
                        .opacity(logoAppeared ? 1.0 : 0.0)

                    // Company name
                    Text(companyName.uppercased())
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .multilineTextAlignment(.center)

                    // Industries
                    if !industries.isEmpty {
                        Text(industries.joined(separator: " \u{2022} "))
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    // Team avatars + size
                    if teamSize > 0 {
                        VStack(spacing: 8) {
                            teamAvatarStack

                            Text("\(teamSize) member\(teamSize == 1 ? "" : "s")")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }

                    // Role badge (invite only)
                    if let role = roleName {
                        roleBadgeView(role: role)
                    }

                    // Inviter name (invite only)
                    if let inviter = inviterName {
                        Text("Invited by \(inviter)")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Bottom buttons
            VStack(spacing: 16) {
                // "Not your company?" back link
                Button {
                    handleBack()
                } label: {
                    Text("Not your company?")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                // JOIN CREW button
                PhasedPrimaryButton(
                    "JOIN CREW",
                    isEnabled: !companyId.isEmpty,
                    isLoading: isJoining,
                    loadingText: "Joining...",
                    coordinator: animationCoordinator
                ) {
                    joinCrew()
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .background(OPSStyle.Colors.background)
        .onAppear {
            animationCoordinator.start()
            // Spring bounce-in for logo after content fades in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    logoAppeared = true
                }
            }
        }
    }

    // MARK: - Subviews

    /// Company logo with initial-circle fallback
    @ViewBuilder
    private var companyLogoView: some View {
        if let urlString = companyLogoUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                case .failure:
                    initialCircle
                default:
                    initialCircle
                        .opacity(0.5)
                }
            }
        } else {
            initialCircle
        }
    }

    /// Fallback circle with company initials
    private var initialCircle: some View {
        ZStack {
            Circle()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .overlay(
                    Circle()
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                )

            Text(companyInitials)
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .frame(width: 80, height: 80)
    }

    /// First letter(s) of the company name
    private var companyInitials: String {
        let words = companyName.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(companyName.prefix(2)).uppercased()
    }

    /// Stacked overlapping team member avatars (max 6 + overflow badge)
    private var teamAvatarStack: some View {
        let displayMembers = Array(teamMembers.prefix(6))
        let overflow = teamSize - displayMembers.count

        return HStack(spacing: -8) {
            ForEach(Array(displayMembers.enumerated()), id: \.offset) { index, member in
                teamMemberAvatar(member: member)
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

    /// Single team member avatar (28x28)
    @ViewBuilder
    private func teamMemberAvatar(member: TeamMemberDTO) -> some View {
        if let urlString = member.profileImageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(OPSStyle.Colors.background, lineWidth: 2))
                default:
                    memberInitialCircle(member: member)
                }
            }
        } else {
            memberInitialCircle(member: member)
        }
    }

    /// Fallback circle with member initials (28x28)
    private func memberInitialCircle(member: TeamMemberDTO) -> some View {
        ZStack {
            Circle()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .overlay(
                    Circle()
                        .stroke(OPSStyle.Colors.background, lineWidth: 2)
                )

            Text(member.initials)
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(width: 28, height: 28)
    }

    /// Role badge pill
    private func roleBadgeView(role: String) -> some View {
        Text("You'll join as \(role)")
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(OPSStyle.Colors.primaryAccent.opacity(0.15))
            )
    }

    // MARK: - Actions

    private func joinCrew() {
        guard !companyId.isEmpty else { return }

        isJoining = true
        errorMessage = nil

        Task {
            do {
                try await manager.joinCompanyFromOnboarding(
                    companyId: companyId,
                    invitationId: invitationId
                )

                await MainActor.run {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    isJoining = false
                    manager.goForward()
                }
            } catch {
                await MainActor.run {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    isJoining = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleBack() {
        switch manager.confirmationSource {
        case .singleInvite, .manualCodeEntry:
            manager.goToScreen(.codeEntry, direction: .backward)
        case .pickerSelection:
            manager.goToScreen(.invitePicker, direction: .backward)
        }
    }
}

// MARK: - Preview

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)
    manager.selectFlow(.employee)

    return CompanyConfirmationScreen(manager: manager)
}
