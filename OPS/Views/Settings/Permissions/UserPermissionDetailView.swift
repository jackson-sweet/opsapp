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
                ForEach(UserRole.allCases.sorted(by: { $0.hierarchy < $1.hierarchy }), id: \.rawValue) { role in
                    if role != UserRole.allCases.sorted(by: { $0.hierarchy < $1.hierarchy }).first {
                        Divider().background(OPSStyle.Colors.cardBorder)
                    }
                    roleOption(role, title: role.displayName, description: role.roleDescription)
                }
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

            ForEach(PermissionRegistry.categories, id: \.self) { category in
                overrideCategory(category)
            }
        }
    }

    private func overrideCategory(_ category: String) -> some View {
        let permissions = PermissionRegistry.permissions(for: category)
        let catLevel = overrideCategoryLevel(for: category)
        let isMixed = catLevel == nil

        return VStack(spacing: 0) {
            // Top row: icon + title + bulk picker (lighter background)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: PermissionRegistry.iconForCategory(category))
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text(category.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    if isMixed {
                        Text("MIXED")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }

                overrideScopePicker(
                    selection: catLevel ?? .off,
                    isMixed: isMixed,
                    onChange: { level in
                        setOverrideCategoryLevel(category, to: level)
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.04))

            // Individual permission rows (darker)
            ForEach(permissions) { perm in
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)

                overrideRow(perm)
            }
        }
        .background(OPSStyle.Colors.background)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, 20)
    }

    private func overrideRow(_ perm: PermissionDefinition) -> some View {
        let level = effectiveOverrideLevel(for: perm.id)
        let baseline = roleBaselineLevel(for: perm.id)
        let hasOverride = level != baseline

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(perm.label)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(level != .off ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                Spacer()
                if hasOverride {
                    Text("OVERRIDE")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                } else {
                    Text("FROM ROLE")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.successStatus)
                }
            }

            overrideScopePicker(
                selection: level,
                isMixed: false,
                onChange: { newLevel in
                    setOverrideLevel(permissionId: perm.id, level: newLevel)
                }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Override Scope Picker

    private func overrideScopePicker(
        selection: PermissionLevel,
        isMixed: Bool,
        onChange: @escaping (PermissionLevel) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(PermissionLevel.allCases) { level in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onChange(level)
                }) {
                    Text(level.displayName)
                        .font(OPSStyle.Typography.smallCaption)
                        .tracking(0.3)
                        .foregroundColor(
                            !isMixed && selection == level
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.tertiaryText
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    !isMixed && selection == level
                                        ? Color.white.opacity(0.12)
                                        : Color.clear
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .opacity(isMixed ? 0.4 : 1.0)
    }

    // MARK: - Override Helpers

    private func effectiveOverrideLevel(for permissionId: String) -> PermissionLevel {
        if let override = userOverrides[permissionId] {
            if override.granted, let scope = override.scope {
                return PermissionLevel(rawValue: scope) ?? .all
            }
            return .off
        }
        return roleBaselineLevel(for: permissionId)
    }

    private func roleBaselineLevel(for permissionId: String) -> PermissionLevel {
        if let scope = rolePermissions[permissionId] {
            return PermissionLevel(rawValue: scope) ?? .all
        }
        return .off
    }

    private func overrideCategoryLevel(for category: String) -> PermissionLevel? {
        let perms = PermissionRegistry.permissions(for: category)
        guard let first = perms.first else { return nil }
        let firstLevel = effectiveOverrideLevel(for: first.id)
        for perm in perms.dropFirst() {
            if effectiveOverrideLevel(for: perm.id) != firstLevel {
                return nil
            }
        }
        return firstLevel
    }

    private func setOverrideCategoryLevel(_ category: String, to level: PermissionLevel) {
        let perms = PermissionRegistry.permissions(for: category)
        for perm in perms {
            setOverrideLevel(permissionId: perm.id, level: level)
        }
    }

    private func setOverrideLevel(permissionId: String, level: PermissionLevel) {
        let baseline = roleBaselineLevel(for: permissionId)
        if level == baseline {
            // Matches role baseline — remove override
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
        } else if level == .off {
            // Revoking permission
            Task {
                do {
                    try await PermissionAdminService.setUserOverride(
                        userId: member.id,
                        companyId: companyId,
                        permission: permissionId,
                        scope: nil,
                        granted: false
                    )
                    await MainActor.run {
                        userOverrides[permissionId] = OverrideState(granted: false, scope: nil)
                    }
                } catch {
                    await MainActor.run { errorMessage = "Failed to save override" }
                }
            }
        } else {
            // Granting with specific scope
            Task {
                do {
                    try await PermissionAdminService.setUserOverride(
                        userId: member.id,
                        companyId: companyId,
                        permission: permissionId,
                        scope: level.rawValue,
                        granted: true
                    )
                    await MainActor.run {
                        userOverrides[permissionId] = OverrideState(granted: true, scope: level.rawValue)
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
                let employeeTypeValue = selectedRole.displayName

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
                    if let userId = dataController.currentUser?.id {
                        await PermissionStore.shared.fetchPermissions(userId: userId)
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
