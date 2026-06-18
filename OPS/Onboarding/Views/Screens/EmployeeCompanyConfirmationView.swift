//
//  EmployeeCompanyConfirmationView.swift
//  OPS
//
//  Confirmation screen shown after employee enters crew code.
//  Shows company name/logo so they can verify they joined the right one.
//

import SwiftUI

struct EmployeeCompanyConfirmationView: View {
    let companyName: String
    let companyLogoURL: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    // Optional branded invite data
    var industries: [String]? = nil
    var teamMembers: [TeamMemberDTO]? = nil
    var teamSize: Int? = nil
    var roleName: String? = nil
    var invitedByName: String? = nil

    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with logo
                HStack(alignment: .bottom) {
                    Image("LogoWhite")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .padding(.bottom, OPSStyle.Layout.spacing2)
                    Text("OPS")
                        .font(OPSStyle.Typography.largeTitle.weight(.bold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Spacer()
                }
                .padding(.leading, OPSStyle.Layout.spacing1)
                .padding(.horizontal, 40)
                .padding(.top, 60)

                Spacer()

                // Company confirmation content
                VStack(spacing: OPSStyle.Layout.spacing3_5) {
                    // Company logo or initial
                    if let logoURL = companyLogoURL, let url = URL(string: logoURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                            default:
                                companyInitialCircle
                            }
                        }
                        .opacity(logoOpacity)
                    } else {
                        companyInitialCircle
                            .opacity(logoOpacity)
                    }

                    // Welcome text
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        Text("WELCOME TO")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .tracking(2)

                        Text(companyName.uppercased())
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(textOpacity)

                    // Industries (if branded data available)
                    if let industries = industries, !industries.isEmpty {
                        Text(industries.prefix(3).joined(separator: " \u{2022} ").uppercased())
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .tracking(1.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(textOpacity)
                    }

                    // Team avatars + size (if branded data available)
                    if let members = teamMembers, !members.isEmpty, let size = teamSize {
                        VStack(spacing: OPSStyle.Layout.spacing2) {
                            HStack(spacing: -8) {
                                ForEach(Array(members.prefix(6).enumerated()), id: \.offset) { index, member in
                                    teamMemberAvatar(member: member)
                                        .zIndex(Double(6 - index))
                                }
                                if size > 6 {
                                    ZStack {
                                        Circle()
                                            .fill(OPSStyle.Colors.cardBackgroundDark)
                                            .frame(width: 28, height: 28)
                                            .overlay(Circle().stroke(OPSStyle.Colors.background, lineWidth: 2))
                                        Text("+\(size - 6)")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(size) \(size == 1 ? "member" : "members")")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .opacity(textOpacity)
                    }

                    // Role badge (invite only)
                    if let role = roleName {
                        Text("You'll join as \(role)")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(OPSStyle.Colors.primaryAccent.opacity(0.15))
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(textOpacity)
                    }

                    // Invited by (invite only)
                    if let inviter = invitedByName {
                        Text("Invited by \(inviter)")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(textOpacity)
                    }
                }
                .padding(.horizontal, 40)

                Spacer()

                // Bottom buttons
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    Button(action: onCancel) {
                        Text("NOT YOUR COMPANY?")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(minHeight: 44)
                    }

                    Button(action: onConfirm) {
                        HStack {
                            Text("JOIN CREW")
                                .font(OPSStyle.Typography.bodyBold)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        }
                        .foregroundColor(OPSStyle.Colors.invertedText)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(OPSStyle.Colors.primaryText)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
                .opacity(buttonOpacity)
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            startAnimations()
            OnboardingSupabaseAnalytics.shared.trackStepView("confirmation")
        }
    }

    // MARK: - Team Member Avatar

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

    private func memberInitialCircle(member: TeamMemberDTO) -> some View {
        ZStack {
            Circle()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(OPSStyle.Colors.background, lineWidth: 2))
            Text(member.initials)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    private var companyInitialCircle: some View {
        ZStack {
            Circle()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            Text(String(companyName.prefix(1)).uppercased())
                .font(OPSStyle.Typography.title.weight(.bold))
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    private func startAnimations() {
        withAnimation(OPSStyle.Animation.curve(0.5).delay(0.2)) {
            logoOpacity = 1.0
        }
        withAnimation(Animation.easeIn(duration: 0.6).delay(0.5)) {
            textOpacity = 1.0
        }
        withAnimation(Animation.easeIn(duration: 0.5).delay(0.9)) {
            buttonOpacity = 1.0
        }
    }
}

// MARK: - Preview

#Preview("Employee Company Confirmation") {
    EmployeeCompanyConfirmationView(
        companyName: "Apex Roofing Co.",
        companyLogoURL: nil,
        onConfirm: {},
        onCancel: {}
    )
    .environment(\.colorScheme, .dark)
}

#Preview("Employee Company Confirmation - With Logo") {
    EmployeeCompanyConfirmationView(
        companyName: "Apex Roofing Co.",
        companyLogoURL: "https://example.com/logo.png",
        onConfirm: {},
        onCancel: {}
    )
    .environment(\.colorScheme, .dark)
}
