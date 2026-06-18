//
//  TeamRoleAssignmentSheet.swift
//  OPS
//
//  Sheet for assigning roles to unassigned team members
//

import SwiftUI
import SwiftData
import Supabase

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
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if isLoading {
                        loadingView
                    } else if teamMembers.isEmpty {
                        emptyView
                    } else {
                        // Content
                        ScrollView {
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                                // Header message
                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                    HStack(spacing: OPSStyle.Layout.spacing2) {
                                        Image(systemName: OPSStyle.Icons.alert)
                                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                                            .foregroundColor(OPSStyle.Colors.warningStatus)

                                        Text("New Team Members")
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                    }

                                    Text("The following team members need roles assigned. Select a role for each member to complete setup.")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                .padding(.top, OPSStyle.Layout.spacing3)

                                // Team member list
                                ForEach(teamMembers, id: \.id) { member in
                                    TeamMemberRoleRow(
                                        member: member,
                                        selectedRole: Binding(
                                            get: { roleAssignments[member.id] ?? .crew },
                                            set: { roleAssignments[member.id] = $0 }
                                        )
                                    )
                                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                }

                                // Error message if any
                                if let error = errorMessage {
                                    Text(error)
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.errorStatus)
                                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                }
                            }
                            .padding(.bottom, 100) // Space for button
                        }

                        // Fixed save button at bottom
                        VStack(spacing: 0) {
                            Divider()
                                .background(OPSStyle.Colors.separator)

                            Button(action: {
                                Task {
                                    await saveRoleAssignments()
                                }
                            }) {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                                } else {
                                    Text("Save Roles")
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .padding(OPSStyle.Layout.spacing3_5)
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
        VStack(spacing: OPSStyle.Layout.spacing3) {
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
        VStack(spacing: OPSStyle.Layout.spacing3) {
            // NOTE: person.3.sequence.fill does not have a semantic icon - using legacy
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("No unassigned members found")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Button("Close") {
                dismiss()
            }
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .padding(.top, OPSStyle.Layout.spacing2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadTeamMembers() {
        isLoading = true

        // Fetch the unassigned users from the database
        let users = dataController.getUsers(ids: unassignedMemberIds)

        DispatchQueue.main.async {
            self.teamMembers = users

            // Initialize role assignments with Crew as default
            for member in users {
                roleAssignments[member.id] = .crew
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

                // Update via Supabase
                let roleString = role.displayName
                try await dataController.updateUserFields(
                    userId: userId,
                    fields: ["employee_type": .string(roleString)]
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
        await dataController.triggerTeamMembersSync(companyId: companyId)

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
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            // Member info
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
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
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("SELECT ROLE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    ForEach(UserRole.allCases.sorted(by: { $0.hierarchy < $1.hierarchy }), id: \.rawValue) { role in
                        roleButton(role)
                    }
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    @ViewBuilder
    private func roleButton(_ role: UserRole) -> some View {
        Button(action: {
            selectedRole = role
        }) {
            VStack(spacing: 6) {
                Image(systemName: iconForRole(role))
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(selectedRole == role ? OPSStyle.Colors.text : OPSStyle.Colors.tertiaryText)

                Text(role.displayName)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(selectedRole == role ? OPSStyle.Colors.text : OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .fill(selectedRole == role ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(selectedRole == role ? OPSStyle.Colors.text : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func iconForRole(_ role: UserRole) -> String {
        switch role {
        case .admin:
            return "shield.checkered"
        case .owner:
            return "crown.fill"
        case .office:
            return "building.2.fill"
        case .operator:
            return "wrench.and.screwdriver.fill"
        case .crew:
            return "hammer.fill"
        case .unassigned:
            return "person.badge.clock"
        }
    }
}

// Helper extension for converting Swift enum to Supabase string
extension UserRole {
    var supabaseEmployeeType: String {
        displayName
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
