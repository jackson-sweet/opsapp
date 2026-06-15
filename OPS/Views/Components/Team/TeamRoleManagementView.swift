//
//  TeamRoleManagementView.swift
//  OPS
//
//  Component for managing team member roles (admin only)
//

import SwiftUI
import Supabase

struct TeamRoleManagementView: View {
    let company: Company
    @EnvironmentObject private var dataController: DataController

    @State private var showingFullManagementSheet = false

    var body: some View {
        Button(action: {
            showingFullManagementSheet = true
        }) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                // NOTE: person.2.badge.gearshape does not have a semantic icon - using legacy
                Image(systemName: "person.2.badge.gearshape")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("Manage Roles")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("Change team member roles and permissions")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .sheet(isPresented: $showingFullManagementSheet) {
            TeamRoleManagementSheet(company: company)
                .environmentObject(dataController)
        }
    }
}

/// Full sheet for managing all team member roles
struct TeamRoleManagementSheet: View {
    let company: Company
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @State private var teamMembers: [User] = []
    @State private var roleChanges: [String: UserRole] = [:] // userId -> new role
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var searchText = ""
    @State private var errorMessage: String?

    var filteredMembers: [User] {
        if searchText.isEmpty {
            return teamMembers
        } else {
            return teamMembers.filter { member in
                member.fullName.localizedCaseInsensitiveContains(searchText) ||
                member.email?.localizedCaseInsensitiveContains(searchText) == true ||
                member.role.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var hasChanges: Bool {
        !roleChanges.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if isLoading {
                        loadingView
                    } else {
                        // Search bar
                        HStack {
                            Image(systemName: OPSStyle.Icons.search)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            TextField("Search team members", text: $searchText)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        .padding()
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.largeCornerRadius)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.top, OPSStyle.Layout.spacing2_5)
                        .padding(.bottom, OPSStyle.Layout.spacing3)

                        // Team members list
                        ScrollView {
                            VStack(spacing: OPSStyle.Layout.spacing2_5) {
                                ForEach(filteredMembers, id: \.id) { member in
                                    TeamMemberRoleEditRow(
                                        member: member,
                                        currentRole: roleChanges[member.id] ?? member.role,
                                        hasChanged: roleChanges[member.id] != nil,
                                        onRoleSelected: { newRole in
                                            if newRole != member.role {
                                                roleChanges[member.id] = newRole
                                            } else {
                                                roleChanges.removeValue(forKey: member.id)
                                            }
                                        }
                                    )
                                }

                                if filteredMembers.isEmpty {
                                    emptySearchView
                                }
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.bottom, hasChanges ? 100 : 40)
                        }

                        // Save button (only show if there are changes)
                        if hasChanges {
                            VStack(spacing: 0) {
                                Divider()
                                    .background(OPSStyle.Colors.separator)

                                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                                    // Cancel changes button
                                    Button(action: {
                                        roleChanges.removeAll()
                                    }) {
                                        Text("Reset")
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 56)
                                            .background(Color.clear)
                                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                            )
                                    }
                                    .disabled(isSaving)

                                    // Save button
                                    Button(action: {
                                        Task {
                                            await saveChanges()
                                        }
                                    }) {
                                        if isSaving {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                                        } else {
                                            Text("Save \(roleChanges.count) Change\(roleChanges.count == 1 ? "" : "s")")
                                                .font(OPSStyle.Typography.bodyBold)
                                                .foregroundColor(OPSStyle.Colors.primaryText)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(OPSStyle.Colors.primaryAccent)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .disabled(isSaving)
                                }
                                .padding(OPSStyle.Layout.spacing3_5)
                            }
                            .background(OPSStyle.Colors.background)
                        }

                        // Error message if any
                        if let error = errorMessage {
                            Text(error)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                                .padding()
                        }
                    }
                }
            }
            .navigationTitle("Manage Team Roles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
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

    private var emptySearchView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: OPSStyle.Icons.search)
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("No team members matching '\(searchText)'")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)

            Button("Clear Search") {
                searchText = ""
            }
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
        }
        .padding(.vertical, 40)
    }

    private func loadTeamMembers() {
        isLoading = true

        // Fetch all users for this company
        let users = dataController.getTeamMembers(companyId: company.id)

        DispatchQueue.main.async {
            self.teamMembers = users.sorted { $0.fullName < $1.fullName }
            isLoading = false
        }
    }

    @MainActor
    private func saveChanges() async {
        isSaving = true
        errorMessage = nil

        var successCount = 0
        var failureCount = 0

        for (userId, newRole) in roleChanges {
            do {
                // Update user role locally
                if let user = teamMembers.first(where: { $0.id == userId }) {
                    user.role = newRole
                    user.needsSync = true
                }

                // Update via Supabase
                let roleString = newRole.displayName
                try await dataController.updateUserFields(
                    userId: userId,
                    fields: ["employee_type": .string(roleString)]
                )

                successCount += 1
            } catch {
                print("[ROLE_MANAGEMENT] ❌ Failed to update role for user \(userId): \(error)")
                failureCount += 1
            }
        }

        // Save changes to database
        do {
            try dataController.modelContext?.save()
        } catch {
            print("[ROLE_MANAGEMENT] ❌ Failed to save to database: \(error)")
        }

        // Re-sync team members to update TeamMember objects
        await dataController.triggerTeamMembersSync(companyId: company.id)

        isSaving = false

        if failureCount > 0 {
            errorMessage = "Failed to update \(failureCount) team member(s). Please try again."
        } else {
            // All successful, clear changes and reload
            roleChanges.removeAll()
            loadTeamMembers()
        }
    }
}

/// Row for editing a team member's role
struct TeamMemberRoleEditRow: View {
    let member: User
    let currentRole: UserRole
    let hasChanged: Bool
    let onRoleSelected: (UserRole) -> Void

    @State private var showingRolePicker = false

    var body: some View {
        Button(action: {
            showingRolePicker = true
        }) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                // Avatar
                UserAvatar(user: member, size: 48)

                // Name and current role
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.fullName)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    HStack(spacing: 6) {
                        Image(systemName: iconForRole(currentRole))
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(hasChanged ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)

                        Text(currentRole.displayName)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(hasChanged ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)

                        if hasChanged {
                            Text("(CHANGED)")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(OPSStyle.Layout.spacing2_5)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(hasChanged ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingRolePicker) {
            RolePickerSheet(
                memberName: member.fullName,
                currentRole: currentRole,
                onRoleSelected: { newRole in
                    onRoleSelected(newRole)
                    showingRolePicker = false
                }
            )
        }
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

/// Sheet for selecting a role
struct RolePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let memberName: String
    let currentRole: UserRole
    let onRoleSelected: (UserRole) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: OPSStyle.Layout.spacing4) {
                    // Header
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        Text("Select Role")
                            .font(OPSStyle.Typography.pageTitle)
                            .textCase(.uppercase)
                            .foregroundColor(OPSStyle.Colors.text)

                        Text(memberName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.top, OPSStyle.Layout.spacing4)

                    // Role options
                    VStack(spacing: OPSStyle.Layout.spacing2_5) {
                        ForEach(UserRole.allCases.sorted(by: { $0.hierarchy < $1.hierarchy }), id: \.rawValue) { role in
                            roleOption(role)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func roleOption(_ role: UserRole) -> some View {
        Button(action: {
            onRoleSelected(role)
        }) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Image(systemName: iconForRole(role))
                    .font(.system(size: OPSStyle.Layout.IconSize.lg))
                    .foregroundColor(currentRole == role ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryText)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(role.displayName)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(currentRole == role ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryText)

                    Text(descriptionForRole(role))
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()

                if currentRole == role {
                    Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.lg))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(currentRole == role ? OPSStyle.Colors.primaryAccent.opacity(0.1) : OPSStyle.Colors.cardBackgroundDark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(currentRole == role ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
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

    private func descriptionForRole(_ role: UserRole) -> String {
        role.roleDescription
    }
}
