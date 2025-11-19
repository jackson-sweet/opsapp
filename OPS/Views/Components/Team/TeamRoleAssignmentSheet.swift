//
//  TeamRoleAssignmentSheet.swift
//  OPS
//
//  Sheet for assigning roles to unassigned team members
//

import SwiftUI
import SwiftData

struct TeamRoleAssignmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    let unassignedMemberIds: [String]
    let companyId: String

    @State private var teamMembers: [User] = []
    @State private var roleAssignments: [String: UserRole] = [:] // userId -> selected role
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if isLoading {
                        loadingView
                    } else if teamMembers.isEmpty {
                        emptyView
                    } else {
                        // Content
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                // Header message
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(OPSStyle.Colors.warningStatus)

                                        Text("New Team Members")
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                    }

                                    Text("The following team members need roles assigned. Select a role for each member to complete setup.")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 16)

                                // Team member list
                                ForEach(teamMembers, id: \.id) { member in
                                    TeamMemberRoleRow(
                                        member: member,
                                        selectedRole: Binding(
                                            get: { roleAssignments[member.id] ?? .fieldCrew },
                                            set: { roleAssignments[member.id] = $0 }
                                        )
                                    )
                                    .padding(.horizontal, 20)
                                }

                                // Error message if any
                                if let error = errorMessage {
                                    Text(error)
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.errorStatus)
                                        .padding(.horizontal, 20)
                                }
                            }
                            .padding(.bottom, 100) // Space for button
                        }

                        // Fixed save button at bottom
                        VStack(spacing: 0) {
                            Divider()
                                .background(Color.white.opacity(0.1))

                            Button(action: {
                                Task {
                                    await saveRoleAssignments()
                                }
                            }) {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Save Roles")
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .padding(20)
                            .disabled(isSaving)
                        }
                        .background(OPSStyle.Colors.background)
                    }
                }
            }
            .navigationTitle("Assign Team Roles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") {
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .disabled(isSaving)
                }
            }
        }
        .onAppear {
            loadTeamMembers()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                .scaleEffect(1.5)

            Text("Loading team members...")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 48))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("No unassigned members found")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Button("Close") {
                dismiss()
            }
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadTeamMembers() {
        isLoading = true

        // Fetch the unassigned users from the database
        let users = dataController.getUsers(ids: unassignedMemberIds)

        DispatchQueue.main.async {
            self.teamMembers = users

            // Initialize role assignments with Field Crew as default
            for member in users {
                roleAssignments[member.id] = .fieldCrew
            }

            isLoading = false
        }
    }

    @MainActor
    private func saveRoleAssignments() async {
        isSaving = true
        errorMessage = nil

        var successCount = 0
        var failureCount = 0

        for (userId, role) in roleAssignments {
            do {
                // Update user role locally
                if let user = teamMembers.first(where: { $0.id == userId }) {
                    user.role = role
                    user.needsSync = true
                }

                // Update via API
                let roleString = BubbleFields.EmployeeType.fromSwiftEnum(role)
                try await dataController.apiService.updateUser(
                    id: userId,
                    userData: ["employeeType": roleString]
                )

                successCount += 1
            } catch {
                print("[ROLE_ASSIGNMENT] ❌ Failed to update role for user \(userId): \(error)")
                failureCount += 1
            }
        }

        // Save changes to database
        do {
            try dataController.modelContext?.save()
        } catch {
            print("[ROLE_ASSIGNMENT] ❌ Failed to save to database: \(error)")
        }

        // Re-sync team members to update TeamMember objects
        if let company = dataController.getCompany(id: companyId) {
            await dataController.syncManager?.syncCompanyTeamMembers(company)
        }

        isSaving = false

        if failureCount > 0 {
            errorMessage = "Failed to update \(failureCount) team member(s). Please try again."
        } else {
            // All successful, dismiss
            dismiss()
        }
    }
}

/// Row for selecting a team member's role
struct TeamMemberRoleRow: View {
    let member: User
    @Binding var selectedRole: UserRole

    var body: some View {
        VStack(spacing: 12) {
            // Member info
            HStack(spacing: 12) {
                // Avatar
                UserAvatar(user: member, size: 48)

                // Name
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.fullName)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    if let email = member.email {
                        Text(email)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }

            // Role selector
            VStack(alignment: .leading, spacing: 8) {
                Text("SELECT ROLE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                HStack(spacing: 12) {
                    roleButton(.fieldCrew)
                    roleButton(.officeCrew)
                    roleButton(.admin)
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    @ViewBuilder
    private func roleButton(_ role: UserRole) -> some View {
        Button(action: {
            selectedRole = role
        }) {
            VStack(spacing: 6) {
                Image(systemName: iconForRole(role))
                    .font(.system(size: 20))
                    .foregroundColor(selectedRole == role ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)

                Text(role.displayName)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(selectedRole == role ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedRole == role ? OPSStyle.Colors.primaryAccent.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedRole == role ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func iconForRole(_ role: UserRole) -> String {
        switch role {
        case .fieldCrew:
            return "hammer.fill"
        case .officeCrew:
            return "building.2.fill"
        case .admin:
            return "star.fill"
        }
    }
}

// Helper extension for converting Swift enum back to Bubble string
extension BubbleFields.EmployeeType {
    static func fromSwiftEnum(_ role: UserRole) -> String {
        switch role {
        case .fieldCrew:
            return BubbleFields.EmployeeType.fieldCrew
        case .officeCrew:
            return BubbleFields.EmployeeType.officeCrew
        case .admin:
            return BubbleFields.EmployeeType.admin
        }
    }
}

// Helper extension for DataController
extension DataController {
    func getUsers(ids: [String]) -> [User] {
        guard let modelContext = modelContext else { return [] }

        do {
            let descriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { user in
                    ids.contains(user.id)
                }
            )
            return try modelContext.fetch(descriptor)
        } catch {
            print("[DATA_CONTROLLER] ❌ Failed to fetch users: \(error)")
            return []
        }
    }
}
