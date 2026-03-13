//
//  UserPermissionsListView.swift
//  OPS
//
//  Lists team members with their current roles and override counts.
//  Tap to open per-user permission detail.
//

import SwiftUI

struct UserPermissionsListView: View {
    @EnvironmentObject private var dataController: DataController

    @State private var teamMembers: [User] = []
    @State private var overrideCounts: [String: Int] = [:]
    @State private var isLoading = true
    @State private var selectedMember: User?

    private var company: Company? {
        dataController.getCurrentUserCompany()
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                        .scaleEffect(1.2)
                    Text("Loading team...")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if teamMembers.isEmpty {
                EmptyStateView(
                    icon: "person.3",
                    title: "No team members",
                    message: "Team members will appear here."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Section header
                        HStack(spacing: 6) {
                            Image(systemName: OPSStyle.Icons.crew)
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Text("\(teamMembers.count) TEAM MEMBER\(teamMembers.count == 1 ? "" : "S")")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.horizontal, 20)

                        // Team members card
                        VStack(spacing: 0) {
                            ForEach(teamMembers) { member in
                                memberRow(member)

                                if member.id != teamMembers.last?.id {
                                    Divider()
                                        .background(OPSStyle.Colors.cardBorder)
                                }
                            }
                        }
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 16)
                    .tabBarPadding()
                }
            }
        }
        .onAppear { loadTeamMembers() }
        .sheet(item: $selectedMember) { member in
            UserPermissionDetailView(member: member, companyId: company?.id ?? "")
                .environmentObject(dataController)
        }
    }

    // MARK: - Member Row

    private func memberRow(_ member: User) -> some View {
        Button(action: {
            selectedMember = member
        }) {
            HStack(spacing: 12) {
                UserAvatar(user: member, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(member.fullName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        // Role badge
                        Text(member.roleDisplay.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(colorForRole(member.role))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colorForRole(member.role).opacity(0.2))
                            .cornerRadius(OPSStyle.Layout.cardCornerRadius)

                        // Override count badge
                        if let count = overrideCounts[member.id], count > 0 {
                            Text("\(count) OVERRIDE\(count == 1 ? "" : "S")")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(OPSStyle.Colors.warningStatus.opacity(0.2))
                                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        }
                    }

                    if let email = member.email, !email.isEmpty {
                        Text(email)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Helpers

    private func colorForRole(_ role: UserRole) -> Color {
        switch role {
        case .admin: return OPSStyle.Colors.warningStatus
        case .owner: return OPSStyle.Colors.warningStatus
        case .office: return OPSStyle.Colors.primaryAccent
        case .operator: return OPSStyle.Colors.primaryAccent
        case .crew: return OPSStyle.Colors.secondaryText
        case .unassigned: return OPSStyle.Colors.tertiaryText
        }
    }

    // MARK: - Data Loading

    private func loadTeamMembers() {
        guard let companyId = company?.id else {
            isLoading = false
            return
        }

        let members = dataController.getTeamMembers(companyId: companyId)
            .sorted { user1, user2 in
                if user1.role.hierarchy < user2.role.hierarchy { return true }
                if user1.role.hierarchy > user2.role.hierarchy { return false }
                return user1.firstName < user2.firstName
            }

        teamMembers = members
        isLoading = false

        // Load override counts in background
        Task {
            var counts: [String: Int] = [:]
            for member in members {
                if let overrides = try? await PermissionAdminService.fetchUserOverrides(userId: member.id) {
                    counts[member.id] = overrides.count
                }
            }
            await MainActor.run {
                self.overrideCounts = counts
            }
        }
    }
}
