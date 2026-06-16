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
    @State private var logoOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var buttonOpacity: Double = 0

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

    private var companyCode: String? {
        switch manager.confirmationSource {
        case .singleInvite, .pickerSelection:
            return manager.selectedInvite?.companyCode
        case .manualCodeEntry:
            return manager.companyJoinDetails?.companyCode ?? manager.state.companyData.companyCode
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
            .padding(.top, OPSStyle.Layout.spacing3)

            Spacer()

            // Company card content
            VStack(spacing: OPSStyle.Layout.spacing4) {
                // Company logo
                companyLogoView
                    .opacity(logoOpacity)

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
                    VStack(spacing: OPSStyle.Layout.spacing2) {
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
                        .padding(.top, OPSStyle.Layout.spacing1)
                }
            }
            .opacity(contentOpacity)
            .padding(.horizontal, 40)

            Spacer()

            // Bottom buttons
            VStack(spacing: OPSStyle.Layout.spacing3) {
                Button {
                    handleBack()
                } label: {
                    Text("Not your company?")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Button {
                    joinCrew()
                } label: {
                    ZStack {
                        if isJoining {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                        } else {
                            HStack {
                                Text("JOIN CREW")
                                    .font(OPSStyle.Typography.bodyBold)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                            }
                        }
                    }
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(!companyId.isEmpty ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .disabled(companyId.isEmpty || isJoining)
            }
            .opacity(buttonOpacity)
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .background(OPSStyle.Colors.background)
        .onAppear {
            withAnimation(OPSStyle.Animation.curve(0.5).delay(0.2)) {
                logoOpacity = 1.0
            }
            withAnimation(Animation.easeIn(duration: 0.6).delay(0.5)) {
                contentOpacity = 1.0
            }
            withAnimation(Animation.easeIn(duration: 0.5).delay(0.9)) {
                buttonOpacity = 1.0
            }
        }
        .errorToast($errorMessage, label: Feedback.Err.joinFailed)
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
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
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
                    invitationId: invitationId,
                    companyCode: companyCode
                )

                await MainActor.run {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    isJoining = false
                    ToastCenter.shared.present(Feedback.Onboarding.joinedCrew)
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
