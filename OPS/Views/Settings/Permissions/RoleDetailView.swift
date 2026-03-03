//
//  RoleDetailView.swift
//  OPS
//
//  Edit permissions for a specific role. Groups 19 permissions by category.
//  Toggle on/off and set scope (ALL / ASSIGNED / OWN).
//

import SwiftUI

// MARK: - Permission Registry

struct PermissionDefinition: Identifiable {
    let id: String // permission key, e.g. "projects.create"
    let label: String
    let category: String
}

enum PermissionRegistry {
    static let all: [PermissionDefinition] = [
        // Projects
        PermissionDefinition(id: "projects.create", label: "Create Projects", category: "Projects"),
        PermissionDefinition(id: "projects.edit", label: "Edit Projects", category: "Projects"),
        // Tasks
        PermissionDefinition(id: "tasks.create", label: "Create Tasks", category: "Tasks"),
        PermissionDefinition(id: "tasks.edit", label: "Edit Tasks", category: "Tasks"),
        PermissionDefinition(id: "tasks.delete", label: "Delete Tasks", category: "Tasks"),
        PermissionDefinition(id: "tasks.change_status", label: "Change Task Status", category: "Tasks"),
        // Clients
        PermissionDefinition(id: "clients.create", label: "Create Clients", category: "Clients"),
        PermissionDefinition(id: "clients.edit", label: "Edit Clients", category: "Clients"),
        // Estimates
        PermissionDefinition(id: "estimates.create", label: "Create Estimates", category: "Estimates"),
        // Expenses
        PermissionDefinition(id: "expenses.create", label: "Create Expenses", category: "Expenses"),
        // Pipeline
        PermissionDefinition(id: "pipeline.view", label: "View Pipeline", category: "Pipeline"),
        PermissionDefinition(id: "pipeline.manage", label: "Manage Pipeline", category: "Pipeline"),
        // Calendar
        PermissionDefinition(id: "calendar.edit", label: "Edit Calendar", category: "Calendar"),
        // Inventory
        PermissionDefinition(id: "inventory.view", label: "View Inventory", category: "Inventory"),
        // Team
        PermissionDefinition(id: "team.view", label: "View Team", category: "Team"),
        PermissionDefinition(id: "team.manage", label: "Manage Team", category: "Team"),
        // Settings
        PermissionDefinition(id: "settings.company", label: "Company Settings", category: "Settings"),
        PermissionDefinition(id: "settings.billing", label: "Billing Settings", category: "Settings"),
        // Job Board
        PermissionDefinition(id: "job_board.manage_sections", label: "Manage Sections", category: "Job Board"),
    ]

    static var categories: [String] {
        var seen: Set<String> = []
        return all.compactMap { def in
            if seen.contains(def.category) { return nil }
            seen.insert(def.category)
            return def.category
        }
    }

    static func permissions(for category: String) -> [PermissionDefinition] {
        all.filter { $0.category == category }
    }

    // MARK: - Shared Helpers

    static func displayName(for roleName: String) -> String {
        switch roleName {
        case "field_crew": return "Field Crew"
        case "office_crew": return "Office Crew"
        case "admin": return "Admin"
        default: return roleName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func iconForRole(_ roleName: String) -> String {
        switch roleName {
        case "field_crew": return "hammer.fill"
        case "office_crew": return "desktopcomputer"
        case "admin": return "shield.checkered"
        default: return "person.fill"
        }
    }

    static func iconForCategory(_ category: String) -> String {
        switch category {
        case "Projects": return OPSStyle.Icons.project
        case "Tasks": return OPSStyle.Icons.task
        case "Clients": return OPSStyle.Icons.subClient
        case "Estimates": return OPSStyle.Icons.estimateDoc
        case "Expenses": return OPSStyle.Icons.expense
        case "Pipeline": return OPSStyle.Icons.accountingChart
        case "Calendar": return OPSStyle.Icons.calendar
        case "Inventory": return "shippingbox.fill"
        case "Team": return OPSStyle.Icons.crew
        case "Settings": return "gearshape.fill"
        case "Job Board": return "rectangle.stack.fill"
        default: return "lock.fill"
        }
    }
}

// MARK: - View

struct RoleDetailView: View {
    let role: AdminRoleRow
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    // Current state from server
    @State private var currentPermissions: [String: String] = [:] // permission -> scope
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Pending changes
    @State private var pendingChanges: [String: PermissionChange] = [:]

    enum PermissionChange: Equatable {
        case enable(scope: String)
        case disable
    }

    private var hasPendingChanges: Bool {
        !pendingChanges.isEmpty
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsHeader(
                    title: PermissionRegistry.displayName(for: role.name),
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 8)

                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                            .scaleEffect(1.2)
                        Text("Loading permissions...")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Role info
                            HStack(spacing: 12) {
                                Image(systemName: PermissionRegistry.iconForRole(role.name))
                                    .font(.system(size: OPSStyle.Layout.IconSize.lg))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(PermissionRegistry.displayName(for: role.name).uppercased())
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)

                                    Text("Hierarchy level: \(role.hierarchy)")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                            }
                            .padding(.horizontal, 20)

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

                            // Permission categories
                            ForEach(PermissionRegistry.categories, id: \.self) { category in
                                permissionCategory(category)
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.bottom, hasPendingChanges ? 80 : 0)
                        .tabBarPadding()
                    }
                }
            }

            // Floating save button
            if hasPendingChanges {
                VStack {
                    Spacer()
                    saveButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear { loadPermissions() }
    }

    // MARK: - Category Card

    private func permissionCategory(_ category: String) -> some View {
        let permissions = PermissionRegistry.permissions(for: category)

        return VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: PermissionRegistry.iconForCategory(category))
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(category.uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, 20)

            // Permissions card
            VStack(spacing: 0) {
                ForEach(permissions) { perm in
                    permissionRow(perm)

                    if perm.id != permissions.last?.id {
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
    }

    // MARK: - Permission Row

    private func permissionRow(_ perm: PermissionDefinition) -> some View {
        let isEnabled = effectiveEnabled(for: perm.id)
        let currentScope = effectiveScope(for: perm.id)

        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(perm.label)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(isEnabled ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)

                    if isEnabled {
                        Text("Scope: \(currentScope.uppercased())")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        if newValue {
                            let scope = currentPermissions[perm.id] ?? "all"
                            pendingChanges[perm.id] = .enable(scope: scope)
                        } else {
                            pendingChanges[perm.id] = .disable
                        }
                    }
                ))
                .tint(OPSStyle.Colors.primaryAccent)
                .labelsHidden()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)

            // Scope picker when enabled
            if isEnabled {
                HStack(spacing: 8) {
                    ForEach(["all", "assigned", "own"], id: \.self) { scope in
                        scopeButton(scope: scope, permissionId: perm.id, currentScope: currentScope)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Scope Button

    private func scopeButton(scope: String, permissionId: String, currentScope: String) -> some View {
        let isSelected = currentScope == scope

        return Button(action: {
            pendingChanges[permissionId] = .enable(scope: scope)
        }) {
            Text(scope.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? OPSStyle.Colors.subtleBackground : Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button(action: { saveChanges() }) {
            HStack {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                        .scaleEffect(0.8)
                } else {
                    Text("SAVE CHANGES")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.invertedText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(OPSStyle.Colors.primaryAccent)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
        }
        .disabled(isSaving)
    }

    // MARK: - Effective State

    private func effectiveEnabled(for permissionId: String) -> Bool {
        if let change = pendingChanges[permissionId] {
            switch change {
            case .enable: return true
            case .disable: return false
            }
        }
        return currentPermissions[permissionId] != nil
    }

    private func effectiveScope(for permissionId: String) -> String {
        if let change = pendingChanges[permissionId] {
            switch change {
            case .enable(let scope): return scope
            case .disable: return "all"
            }
        }
        return currentPermissions[permissionId] ?? "all"
    }

    // MARK: - Data

    private func loadPermissions() {
        Task {
            do {
                let perms = try await PermissionAdminService.fetchRolePermissions(roleId: role.id)
                var map: [String: String] = [:]
                for perm in perms {
                    map[perm.permission] = perm.scope
                }
                await MainActor.run {
                    self.currentPermissions = map
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load permissions"
                    self.isLoading = false
                }
                print("[PERMISSIONS] Error loading role permissions: \(error)")
            }
        }
    }

    private func saveChanges() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                for (permissionId, change) in pendingChanges {
                    switch change {
                    case .enable(let scope):
                        try await PermissionAdminService.setRolePermission(roleId: role.id, permission: permissionId, scope: scope)
                        await MainActor.run {
                            currentPermissions[permissionId] = scope
                        }
                    case .disable:
                        try await PermissionAdminService.removeRolePermission(roleId: role.id, permission: permissionId)
                        await MainActor.run {
                            currentPermissions.removeValue(forKey: permissionId)
                        }
                    }
                }

                await MainActor.run {
                    pendingChanges = [:]
                    isSaving = false

                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }

                print("[PERMISSIONS] Saved \(pendingChanges.count) permission changes for role \(role.name)")

            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save changes"
                    isSaving = false

                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
                print("[PERMISSIONS] Error saving permissions: \(error)")
            }
        }
    }

}
