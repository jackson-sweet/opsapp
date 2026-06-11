//
//  RoleListView.swift
//  OPS
//
//  Lists all roles grouped into Preset and Custom sections.
//  Preset roles are read-only. Custom roles can be edited, renamed, duplicated, deleted.
//

import SwiftUI

struct RoleListView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.wizardStateManager) private var wizardStateManager

    @State private var roles: [AdminRoleRow] = []
    @State private var rolePermissionCounts: [String: Int] = [:]
    @State private var roleUserCounts: [String: Int] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedRole: AdminRoleRow?

    // Create / Rename
    @State private var showingRoleForm = false
    @State private var roleFormMode: RoleFormMode = .create
    @State private var roleFormName = ""
    @State private var isSavingRole = false

    // Delete
    @State private var roleToDelete: AdminRoleRow?
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false

    enum RoleFormMode {
        case create
        case rename(AdminRoleRow)
    }

    private static let presetNames = ["admin", "owner", "office", "operator", "crew", "unassigned"]

    /// Preset roles sorted: Owner first, then by hierarchy, Unassigned last.
    private var presetRoles: [AdminRoleRow] {
        roles.filter { Self.presetNames.contains($0.name.lowercased()) }
            .sorted { r1, r2 in
                let n1 = r1.name.lowercased()
                let n2 = r2.name.lowercased()
                // Owner always first
                if n1 == "owner" { return true }
                if n2 == "owner" { return false }
                // Unassigned always last
                if n1 == "unassigned" { return false }
                if n2 == "unassigned" { return true }
                // Everything else by hierarchy ascending
                return r1.hierarchy < r2.hierarchy
            }
    }

    private var customRoles: [AdminRoleRow] {
        roles.filter { !Self.presetNames.contains($0.name.lowercased()) }
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                        .scaleEffect(1.2)
                    Text("Loading roles...")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: OPSStyle.Icons.alert)
                        .font(.system(size: OPSStyle.Layout.IconSize.xl))
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                    Text(error)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: 20) {
                            // Preset roles section
                            if !presetRoles.isEmpty {
                                roleSection(title: "PRESET ROLES", icon: "shield.fill", roles: presetRoles, isPreset: true)
                            }

                            // Custom roles section
                            if !customRoles.isEmpty {
                                roleSection(title: "CUSTOM ROLES", icon: "person.badge.key.fill", roles: customRoles, isPreset: false)
                            }

                            // New role button
                            Button(action: {
                                roleFormMode = .create
                                roleFormName = ""
                                showingRoleForm = true
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus")
                                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                                    Text("NEW ROLE")
                                        .font(OPSStyle.Typography.captionBold)
                                }
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 20)
                        }
                        // Bug e6004ed0: cap the scroll content to the viewport
                        // width so no descendant row can report an intrinsic
                        // width wider than the screen and reintroduce sideways
                        // scroll. Belt-and-suspenders on top of per-row
                        // truncation (be2b9e23 / 45a9c534).
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                        .tabBarPadding()
                        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardScrollToTarget"))) { notification in
                            if let stepId = notification.userInfo?["stepId"] as? String {
                                withAnimation {
                                    proxy.scrollTo("wizard_active_\(stepId)", anchor: .top)
                                }
                            }
                        }
                    }
                }
                .wizardTarget("view_roles")
            }
        }
        .onAppear { loadRoles() }
        .fullScreenCover(item: $selectedRole) { role in
            NavigationStack {
                RoleDetailView(role: role)
                    .environmentObject(dataController)
            }
            .wizardBannerIfAvailable(stateManager: wizardStateManager)
            .wizardOverlayIfAvailable(stateManager: wizardStateManager)
        }
        .sheet(isPresented: $showingRoleForm) {
            roleFormSheet
        }
        .confirmationDialog(
            "Delete Role",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let role = roleToDelete {
                    deleteRole(role)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let role = roleToDelete {
                Text("Delete \"\(role.name)\"? Users assigned to this role will lose their permissions.")
            }
        }
    }

    // MARK: - Role Section

    private func roleSection(title: String, icon: String, roles: [AdminRoleRow], isPreset: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(title)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(roles) { role in
                    roleRow(role, isPreset: isPreset)

                    if role.id != roles.last?.id {
                        Rectangle()
                            .fill(OPSStyle.Colors.cardBorder)
                            .frame(height: 1)
                            .padding(.horizontal, 16)
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

    // MARK: - Role Row

    private func roleRow(_ role: AdminRoleRow, isPreset: Bool) -> some View {
        Button(action: {
            selectedRole = role
        }) {
            HStack(spacing: 14) {
                Image(systemName: PermissionRegistry.iconForRole(role.name))
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 28, alignment: .center)

                // Bug be2b9e23: long custom role names + the PRESET badge used
                // to push the row past device width. The role name now
                // truncates instead of forcing horizontal overflow, and the
                // VStack claims the full available width so Spacer has room
                // to compress instead of pushing the chevron off-screen.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(PermissionRegistry.displayName(for: role.name).uppercased())
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if isPreset {
                            Text("PRESET")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(OPSStyle.Colors.subtleBackground)
                                )
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }

                    HStack(spacing: 8) {
                        let permCount = rolePermissionCounts[role.id] ?? 0
                        Text("\(permCount) permission\(permCount == 1 ? "" : "s")")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)

                        let userCount = roleUserCounts[role.id] ?? 0
                        if userCount > 0 {
                            Text("·  \(userCount) user\(userCount == 1 ? "" : "s")")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            // Duplicate (available for all roles)
            Button(action: { duplicateRole(role) }) {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            if !isPreset {
                // Rename (custom only)
                Button(action: {
                    roleFormMode = .rename(role)
                    roleFormName = role.name
                    showingRoleForm = true
                }) {
                    Label("Rename", systemImage: "pencil")
                }

                // Delete (custom only)
                Button(role: .destructive, action: {
                    roleToDelete = role
                    showingDeleteConfirmation = true
                }) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .wizardTarget("view_role_detail")
    }

    // MARK: - Role Form Sheet

    private var roleFormSheet: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ROLE NAME")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        TextField("Enter role name", text: $roleFormName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle(roleFormTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showingRoleForm = false }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveRoleForm() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(roleFormName.trimmingCharacters(in: .whitespaces).isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                        .disabled(roleFormName.trimmingCharacters(in: .whitespaces).isEmpty || isSavingRole)
                }
            }
        }
    }

    private var roleFormTitle: String {
        switch roleFormMode {
        case .create: return "New Role"
        case .rename: return "Rename Role"
        }
    }

    // MARK: - Actions

    private func saveRoleForm() {
        let name = roleFormName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSavingRole = true

        Task {
            do {
                switch roleFormMode {
                case .create:
                    let maxHierarchy = roles.map(\.hierarchy).max() ?? 5
                    _ = try await PermissionAdminService.createRole(name: name, hierarchy: maxHierarchy + 1)
                case .rename(let role):
                    try await PermissionAdminService.renameRole(roleId: role.id, name: name)
                }

                await MainActor.run {
                    isSavingRole = false
                    showingRoleForm = false
                    loadRoles()

                    switch roleFormMode {
                    case .create:
                        ToastCenter.shared.present(Feedback.Settings.roleCreated)
                    case .rename:
                        ToastCenter.shared.present(Feedback.Settings.roleRenamed)
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    isSavingRole = false
                    errorMessage = "Failed to save role"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func duplicateRole(_ role: AdminRoleRow) {
        Task {
            do {
                let newName = "\(role.name) (Copy)"
                let maxHierarchy = roles.map(\.hierarchy).max() ?? 5
                let newRole = try await PermissionAdminService.duplicateRole(
                    sourceRoleId: role.id,
                    newName: newName,
                    hierarchy: maxHierarchy + 1
                )

                await MainActor.run {
                    loadRoles()
                    ToastCenter.shared.present(Feedback.Settings.roleDuplicated)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)

                    // Open the new role for editing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        selectedRole = newRole
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to duplicate role"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func deleteRole(_ role: AdminRoleRow) {
        isDeleting = true
        Task {
            do {
                try await PermissionAdminService.deleteRole(roleId: role.id)
                await MainActor.run {
                    isDeleting = false
                    roleToDelete = nil
                    loadRoles()
                    ToastCenter.shared.present(Feedback.Settings.roleDeleted)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = "Failed to delete role"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadRoles() {
        Task {
            do {
                let fetchedRoles = try await PermissionAdminService.fetchAllRoles()

                // Show roles immediately — counts load in background
                await MainActor.run {
                    self.roles = fetchedRoles
                    self.isLoading = false
                }

                // Load permission counts and user counts in parallel
                let companyId = dataController.getCurrentUserCompany()?.id
                let companyUserIds: Set<String>
                if let companyId = companyId {
                    companyUserIds = Set(dataController.getTeamMembers(companyId: companyId).map(\.id))
                } else {
                    companyUserIds = []
                }

                await withTaskGroup(of: (String, Int, Int).self) { group in
                    for role in fetchedRoles {
                        group.addTask {
                            let permCount = (try? await PermissionAdminService.fetchRolePermissions(roleId: role.id).count) ?? 0
                            let allUserIds = (try? await PermissionAdminService.fetchUserIdsForRole(roleId: role.id)) ?? []
                            let userCount = allUserIds.filter { companyUserIds.contains($0) }.count
                            return (role.id, permCount, userCount)
                        }
                    }

                    for await (roleId, permCount, userCount) in group {
                        await MainActor.run {
                            self.rolePermissionCounts[roleId] = permCount
                            self.roleUserCounts[roleId] = userCount
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load roles: \(error.localizedDescription)"
                    self.isLoading = false
                }
                print("[PERMISSIONS] Error loading roles: \(error)")
            }
        }
    }
}
