//
//  UserPermissionDetailView.swift
//  OPS
//
//  Per-user role assignment and permission overrides.
//  Section 1: Role (radio buttons for Field Crew / Office Crew / Admin)
//  Section 2: Permission Overrides (shows baseline from role vs overrides)
//

import SwiftUI

struct UserPermissionDetailView: View {
    let member: User
    let companyId: String

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    // Role state
    @State private var selectedRole: UserRole
    @State private var originalRole: UserRole
    @State private var isSavingRole = false

    // Override state
    @State private var rolePermissions: [String: String] = [:] // permission -> scope from role
    @State private var userOverrides: [String: OverrideState] = [:]
    @State private var isLoading = true
    @State private var isSavingOverride = false
    @State private var errorMessage: String?

    struct OverrideState {
        let granted: Bool
        let scope: String?
    }

    init(member: User, companyId: String) {
        self.member = member
        self.companyId = companyId
        self._selectedRole = State(initialValue: member.role)
        self._originalRole = State(initialValue: member.role)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Member header
                        memberHeader

                        // Error
                        if let error = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: OPSStyle.Icons.alert)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                                Text(error)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                            }
                            .padding(.horizontal, 20)
                        }

                        // Section 1: Role
                        roleSection

                        // Section 2: Permission Overrides
                        if !isLoading {
                            overridesSection
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("User Permissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        .onAppear { loadData() }
    }

    // MARK: - Member Header

    private var memberHeader: some View {
        HStack(spacing: 16) {
            UserAvatar(user: member, size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(member.fullName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                if let email = member.email {
                    Text(email)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Role Section

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.key")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text("ROLE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                roleOption(.fieldCrew, title: "Field Crew", description: "Works on job sites. Limited scheduling and client access.")
                Divider().background(OPSStyle.Colors.cardBorder)
                roleOption(.officeCrew, title: "Office Crew", description: "Full access to scheduling, clients, and project creation.")
                Divider().background(OPSStyle.Colors.cardBorder)
                roleOption(.admin, title: "Admin", description: "Full access to all features including team and billing.")
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .padding(.horizontal, 20)

            // Save role button (only when changed)
            if selectedRole != originalRole {
                Button(action: { saveRole() }) {
                    HStack {
                        if isSavingRole {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                                .scaleEffect(0.8)
                        } else {
                            Text("SAVE ROLE")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(OPSStyle.Colors.invertedText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                }
                .disabled(isSavingRole)
                .padding(.horizontal, 20)
            }
        }
    }

    private func roleOption(_ role: UserRole, title: String, description: String) -> some View {
        Button(action: { selectedRole = role }) {
            HStack(spacing: 12) {
                Image(systemName: selectedRole == role ? OPSStyle.Icons.checkmarkCircleFill : OPSStyle.Icons.circle)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(selectedRole == role ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(selectedRole == role ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)

                    Text(description)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(selectedRole == role ? OPSStyle.Colors.subtleBackground : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Overrides Section

    private var overridesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text("PERMISSION OVERRIDES")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, 20)

            Text("Override individual permissions beyond what the role grants.")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, 20)

            // Group by category
            ForEach(PermissionRegistry.categories, id: \.self) { category in
                overrideCategory(category)
            }
        }
    }

    private func overrideCategory(_ category: String) -> some View {
        let permissions = PermissionRegistry.permissions(for: category)

        return VStack(alignment: .leading, spacing: 4) {
            Text(category.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(permissions) { perm in
                    overrideRow(perm)

                    if perm.id != permissions.last?.id {
                        Divider().background(OPSStyle.Colors.cardBorder)
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
    }

    private func overrideRow(_ perm: PermissionDefinition) -> some View {
        let fromRole = rolePermissions[perm.id] != nil
        let hasOverride = userOverrides[perm.id] != nil
        let override = userOverrides[perm.id]
        let effectivelyGranted = hasOverride ? (override?.granted ?? false) : fromRole

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(perm.label)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(effectivelyGranted ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)

                HStack(spacing: 4) {
                    if fromRole {
                        Text("FROM ROLE")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.successStatus)
                    } else {
                        Text("NOT IN ROLE")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    if hasOverride {
                        Text("· OVERRIDE")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { effectivelyGranted },
                set: { newValue in
                    toggleOverride(permissionId: perm.id, fromRole: fromRole, granted: newValue)
                }
            ))
            .tint(OPSStyle.Colors.primaryAccent)
            .labelsHidden()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func toggleOverride(permissionId: String, fromRole: Bool, granted: Bool) {
        // If toggling to match the role baseline, remove the override
        if granted == fromRole {
            Task {
                do {
                    try await PermissionAdminService.removeUserOverride(userId: member.id, permission: permissionId)
                    await MainActor.run {
                        userOverrides.removeValue(forKey: permissionId)
                    }
                } catch {
                    await MainActor.run { errorMessage = "Failed to remove override" }
                }
            }
        } else {
            // Add/update override
            Task {
                do {
                    let scope = granted ? "all" : nil
                    try await PermissionAdminService.setUserOverride(
                        userId: member.id,
                        companyId: companyId,
                        permission: permissionId,
                        scope: scope,
                        granted: granted
                    )
                    await MainActor.run {
                        userOverrides[permissionId] = OverrideState(granted: granted, scope: scope)
                    }
                } catch {
                    await MainActor.run { errorMessage = "Failed to save override" }
                }
            }
        }
    }

    private func saveRole() {
        guard !isSavingRole else { return }
        isSavingRole = true
        errorMessage = nil

        Task {
            do {
                // 1. Write to user_roles
                let roleId = try await PermissionAdminService.resolveRoleId(for: selectedRole)
                try await PermissionAdminService.assignUserRole(userId: member.id, roleId: roleId)

                // 2. Write to legacy employee_type
                let employeeTypeValue: String
                switch selectedRole {
                case .fieldCrew: employeeTypeValue = "Field Crew"
                case .officeCrew: employeeTypeValue = "Office Crew"
                case .admin: employeeTypeValue = "Admin"
                }

                try await dataController.syncManager.updateUserFields(
                    userId: member.id,
                    fields: ["employee_type": .string(employeeTypeValue)]
                )

                // 3. Update local model
                await MainActor.run {
                    member.role = selectedRole
                    try? dataController.modelContext?.save()
                    originalRole = selectedRole
                    isSavingRole = false

                    // Reload role permissions since role changed
                    loadRolePermissions()

                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }

                // 4. Refresh PermissionStore if editing current user
                if member.id == dataController.currentUser?.id {
                    if let supabaseId = SupabaseService.shared.currentUserId {
                        await PermissionStore.shared.fetchPermissions(userId: supabaseId)
                    }
                }

                print("[PERMISSIONS] Updated \(member.fullName) role to \(selectedRole)")

            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save role"
                    isSavingRole = false

                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
                print("[PERMISSIONS] Error saving role: \(error)")
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        Task {
            // Load role permissions baseline
            loadRolePermissions()

            // Load user overrides
            do {
                let overrides = try await PermissionAdminService.fetchUserOverrides(userId: member.id)
                var map: [String: OverrideState] = [:]
                for o in overrides {
                    map[o.permission] = OverrideState(granted: o.granted, scope: o.scope)
                }
                await MainActor.run {
                    self.userOverrides = map
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
                print("[PERMISSIONS] Error loading user overrides: \(error)")
            }
        }
    }

    private func loadRolePermissions() {
        Task {
            do {
                let roleId = try await PermissionAdminService.resolveRoleId(for: selectedRole)
                let perms = try await PermissionAdminService.fetchRolePermissions(roleId: roleId)
                var map: [String: String] = [:]
                for p in perms {
                    map[p.permission] = p.scope
                }
                await MainActor.run {
                    self.rolePermissions = map
                }
            } catch {
                print("[PERMISSIONS] Error loading role permissions: \(error)")
            }
        }
    }
}
