//
//  RoleDetailView.swift
//  OPS
//
//  Edit permissions for a specific role. Groups the granular permissions by category.
//  Toggle on/off and set scope (ALL / ASSIGNED / OWN).
//

import SwiftUI

// MARK: - Search tag metadata
// Maps permission key → extra keyword aliases used for search.
// Keeps search logic colocated with the registry so there is one place to update.
private let permissionSearchTags: [String: [String]] = [
    "projects.create":              ["new project", "add project"],
    "projects.edit":                ["modify project", "update project"],
    "tasks.create":                 ["new task", "add task"],
    "tasks.edit":                   ["modify task", "update task"],
    "tasks.delete":                 ["remove task"],
    "tasks.change_status":          ["task status", "mark complete", "mark done"],
    "clients.create":               ["new client", "add client", "customer"],
    "clients.edit":                 ["modify client", "update client", "customer"],
    "estimates.create":             ["new estimate", "quote", "proposal"],
    "invoices.view":                ["invoice", "bill", "billing"],
    "invoices.create":              ["new invoice", "bill", "billing"],
    "invoices.edit":                ["modify invoice", "update invoice", "bill"],
    "invoices.send":                ["send invoice", "email invoice", "deliver"],
    "invoices.record_payment":      ["record payment", "log payment", "mark paid", "collect"],
    "invoices.delete":              ["remove invoice", "void invoice"],
    "expenses.create":              ["new expense", "add expense", "receipt"],
    "pipeline.create":              ["new lead", "add lead", "opportunity"],
    "pipeline.view":                ["funnel", "leads", "opportunity"],
    "pipeline.edit":                ["update lead", "change lead", "opportunity"],
    "pipeline.assign":              ["assign lead", "reassign", "owner"],
    "pipeline.convert":             ["convert lead", "create project", "won"],
    "pipeline.manage":              ["funnel", "leads", "opportunity"],
    "calendar.edit":                ["reschedule", "scheduling", "shift", "move event", "calendar change"],
    "catalog.view":                 ["stock", "materials", "supplies", "parts", "inventory", "catalog", "products"],
    "catalog.manage":               ["edit stock", "manage stock", "adjust quantity"],
    "catalog.products.manage":      ["edit product", "edit price", "options", "modifiers", "recipe"],
    "catalog.orders.manage":        ["draft order", "send order", "fulfill order", "supplier"],
    "team.view":                    ["crew", "staff", "members"],
    "team.manage":                  ["crew", "staff", "members", "hire", "manage people"],
    "settings.company":             ["company settings", "business", "org"],
    "settings.billing":             ["billing", "subscription", "payment", "plan"],
    "job_board.manage_sections":    ["columns", "board", "kanban", "sections"],
    "deck_builder.view":            ["designs", "proposals", "presentation"],
    "deck_builder.create":          ["new design", "new proposal"],
    "deck_builder.edit":            ["modify design", "update proposal"],
]

// MARK: - View

struct RoleDetailView: View {
    let role: AdminRoleRow
    @EnvironmentObject private var dataController: DataController
    @ObservedObject private var permissionStore = PermissionStore.shared
    @Environment(\.dismiss) private var dismiss

    // Current state from server
    @State private var currentPermissionSnapshot: [CanonicalRolePermission] = []
    @State private var desiredLevels: [String: PermissionLevel] = [:]
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var assignmentConflict: RolePermissionMutationConflict?

    // Team members assigned to this role
    @State private var roleUsers: [User] = []


    // Search + collapse
    @State private var searchQuery: String = ""
    @State private var expandedCategories: Set<String> = []

    // MARK: - Search helpers

    private func matchesSearch(_ perm: PermissionDefinition) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        if perm.id.lowercased().contains(q) { return true }
        if perm.label.lowercased().contains(q) { return true }
        if let tags = permissionSearchTags[perm.id] {
            return tags.contains { $0.lowercased().contains(q) }
        }
        return false
    }

    private func visiblePermissions(for category: String) -> [PermissionDefinition] {
        PermissionRegistry.permissions(for: category).filter { matchesSearch($0) }
    }

    private var visibleCategories: [String] {
        PermissionRegistry.categories.filter { !visiblePermissions(for: $0).isEmpty }
    }

    private var hasPendingChanges: Bool {
        PermissionRegistry.editable.contains { definition in
            effectiveLevel(for: definition.id)
                != currentLevel(for: definition.id)
        }
    }

    /// Preset roles are immutable by canonical backend identity, not by a
    /// display name that a custom role may legitimately share.
    private var isPresetRole: Bool {
        role.isPreset
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsHeader(
                    title: PermissionRegistry.displayName(for: role.name),
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, OPSStyle.Layout.spacing2)

                if isLoading {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
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
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3_5) {
                            // Role info
                            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                                Image(systemName: PermissionRegistry.iconForRole(role.name))
                                    .font(.system(size: OPSStyle.Layout.IconSize.lg))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                Text(PermissionRegistry.displayName(for: role.name).uppercased())
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                            // Preset role banner
                            if isPresetRole {
                                HStack(spacing: OPSStyle.Layout.spacing2) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    Text("Preset roles are read-only")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            }

                            // Team members assigned to this role
                            if !roleUsers.isEmpty {
                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                    HStack(spacing: 6) {
                                        Image(systemName: OPSStyle.Icons.crew)
                                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                        Text("\(roleUsers.count) TEAM MEMBER\(roleUsers.count == 1 ? "" : "S")")
                                            .font(OPSStyle.Typography.captionBold)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                                    LazyVGrid(
                                        columns: [GridItem(.adaptive(minimum: 56, maximum: 72), spacing: OPSStyle.Layout.spacing2_5)],
                                        alignment: .leading,
                                        spacing: OPSStyle.Layout.spacing2_5
                                    ) {
                                        ForEach(roleUsers) { user in
                                            VStack(spacing: 6) {
                                                if let imageData = user.profileImageData,
                                                   let uiImage = UIImage(data: imageData) {
                                                    Image(uiImage: uiImage)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 44, height: 44)
                                                        .clipShape(Circle())
                                                } else {
                                                    Circle()
                                                        .fill(user.userColor.flatMap { Color(hex: $0) } ?? OPSStyle.Colors.primaryAccent)
                                                        .frame(width: 44, height: 44)
                                                        .overlay(
                                                            Text(user.firstName.prefix(1).uppercased())
                                                                .font(OPSStyle.Typography.bodyBold)
                                                                .foregroundColor(OPSStyle.Colors.primaryText)
                                                        )
                                                }

                                                Text(user.firstName)
                                                    .font(OPSStyle.Typography.smallCaption)
                                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }
                                            .frame(width: 56)
                                        }
                                    }
                                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                }
                            }

                            // Error
                            if let error = errorMessage {
                                HStack(spacing: OPSStyle.Layout.spacing2) {
                                    Image(systemName: OPSStyle.Icons.alert)
                                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                        .foregroundColor(OPSStyle.Colors.errorStatus)
                                    Text(error)
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.errorStatus)
                                }
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            }

                            // Search field
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                TextField("Search permissions…", text: $searchQuery)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .autocorrectionDisabled()
                                    .autocapitalization(.none)
                                if !searchQuery.isEmpty {
                                    Button(action: { searchQuery = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    }
                                }
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                            .background(OPSStyle.Colors.surfaceInput)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                            // Permission categories (collapsible)
                            ForEach(visibleCategories, id: \.self) { category in
                                if let flag = PermissionRegistry.featureFlag(for: category),
                                   !permissionStore.isFeatureEnabled(flag) {
                                    gatedCategory(category)
                                } else {
                                    collapsiblePermissionCategory(category)
                                }
                            }

                            if visibleCategories.isEmpty && !searchQuery.isEmpty {
                                Text("No permissions match \"\(searchQuery)\"")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                        .padding(.bottom, hasPendingChanges ? 80 : 0)
                        .tabBarPadding()
                    }
                }
            }

            // Floating save button (hidden for preset roles)
            if hasPendingChanges && !isPresetRole {
                VStack {
                    Spacer()
                    saveButton
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.bottom, OPSStyle.Layout.spacing5)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadPermissions()
        }
        .sheet(item: $assignmentConflict) { conflict in
            LeadResponsibilityResolutionSheet(
                conflict: conflict,
                isSaving: isSaving,
                onCancel: { assignmentConflict = nil },
                onResolve: { resolutions in
                    saveChanges(assignmentResolutions: resolutions)
                }
            )
        }
        .onDisappear {
            // Wizard: notify step 2 completion when user RETURNS to the permissions list,
            // not when they first open the detail. Prevents step 3 activating while
            // the user is still inside this fullScreenCover.
            NotificationCenter.default.post(name: Notification.Name("WizardRoleDetailViewed"), object: nil)
        }
    }

    // MARK: - Collapsible Category Card

    /// A collapsible wrapper around `permissionCategory`. Each category starts
    /// collapsed; when a search query is active every visible category auto-
    /// expands so the user can see the matching rows without extra taps.
    private func collapsiblePermissionCategory(_ category: String) -> some View {
        let isExpanded = expandedCategories.contains(category)
            || !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty

        return VStack(spacing: 0) {
            // Header — always visible, tapping toggles expanded state
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(OPSStyle.Animation.panel) {
                    if expandedCategories.contains(category) {
                        expandedCategories.remove(category)
                    } else {
                        expandedCategories.insert(category)
                    }
                }
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: PermissionRegistry.iconForCategory(category))
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text(category.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    let permCount = visiblePermissions(for: category).count
                    let enabledCount = visiblePermissions(for: category).filter { effectiveLevel(for: $0.id) != .off }.count
                    if enabledCount > 0 {
                        Text("\(enabledCount)/\(permCount)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }

                    Image(systemName: isExpanded ? OPSStyle.Icons.chevronUp : OPSStyle.Icons.chevronDown)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                Rectangle()
                    .fill(OPSStyle.Colors.cardBorderSubtle)
                    .frame(height: 1)

                permissionCategoryRows(category)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassSurface()
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .frame(maxWidth: .infinity)
    }

    /// Renders just the rows + bulk picker for a category (used inside collapsible body).
    private func permissionCategoryRows(_ category: String) -> some View {
        let permissions = visiblePermissions(for: category)
        let catLevel = categoryLevel(for: permissions)
        let isMixed = catLevel == nil

        return VStack(spacing: 0) {
            // Bulk scope picker
            VStack(alignment: .leading, spacing: 6) {
                if isMixed {
                    Text("MIXED")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                permissionScopePicker(
                    selection: catLevel ?? .off,
                    levels: PermissionEditorPolicy.commonLevels(for: permissions),
                    isMixed: isMixed,
                    isReadOnly: isPresetRole,
                    onChange: { level in setPermissionLevels(permissions, to: level) }
                )
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .frame(maxWidth: .infinity)
            .background(OPSStyle.Colors.surfaceHover)

            // Individual permission rows
            ForEach(permissions) { perm in
                Rectangle()
                    .fill(OPSStyle.Colors.cardBorderSubtle)
                    .frame(height: 1)
                permissionRow(perm)
            }
        }
    }

    // MARK: - Category Card (non-collapsible, retained for reference)

    private func permissionCategory(_ category: String) -> some View {
        let permissions = PermissionRegistry.permissions(for: category)
        let catLevel = categoryLevel(for: category)
        let isMixed = catLevel == nil

        return VStack(spacing: 0) {
            // Top row: icon + title + bulk picker (lighter background)
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
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

                permissionScopePicker(
                    selection: catLevel ?? .off,
                    levels: PermissionEditorPolicy.commonLevels(for: permissions),
                    isMixed: isMixed,
                    isReadOnly: isPresetRole,
                    onChange: { level in
                        setCategoryLevel(category, to: level)
                    }
                )
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, 14)
            .background(OPSStyle.Colors.surfaceHover)

            // Individual permission rows (darker)
            ForEach(permissions) { perm in
                Rectangle()
                    .fill(OPSStyle.Colors.cardBorderSubtle)
                    .frame(height: 1)

                permissionRow(perm)
            }
        }
        .glassSurface()
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    // MARK: - Gated Category (feature-flagged, not yet available)

    private func gatedCategory(_ category: String) -> some View {
        Button(action: {
            ToastCenter.shared.present(Feedback.Settings.featureInTesting)
        }) {
            HStack(spacing: 6) {
                Image(systemName: PermissionRegistry.iconForCategory(category))
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(category.uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Spacer()

                Text("IN TESTING")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(OPSStyle.Colors.surfaceInput)
                    )
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, 14)
        }
        .buttonStyle(PlainButtonStyle())
        .glassSurface()
        .opacity(0.4)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    // MARK: - Permission Row

    private func permissionRow(_ perm: PermissionDefinition) -> some View {
        let level = effectiveLevel(for: perm.id)

        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(perm.label)
                .font(OPSStyle.Typography.body)
                .foregroundColor(level != .off ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            permissionScopePicker(
                selection: level,
                levels: perm.allowedLevels,
                isMixed: false,
                isReadOnly: isPresetRole,
                onChange: { newLevel in
                    desiredLevels = PermissionEditorPolicy.applying(
                        newLevel,
                        to: perm.id,
                        in: desiredLevels
                    )
                }
            )
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Scope Picker

    private func permissionScopePicker(
        selection: PermissionLevel,
        levels: [PermissionLevel],
        isMixed: Bool,
        isReadOnly: Bool = false,
        onChange: @escaping (PermissionLevel) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(levels) { level in
                Button(action: {
                    guard !isReadOnly else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onChange(level)
                }) {
                    Text(level.displayName)
                        .font(OPSStyle.Typography.smallCaption)
                        .tracking(0.3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundColor(
                            !isMixed && selection == level
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.tertiaryText
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .fill(
                                    !isMixed && selection == level
                                        ? OPSStyle.Colors.surfaceActive
                                        : Color.clear
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorderSubtle, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .opacity(isMixed ? 0.4 : 1.0)
        .allowsHitTesting(!isReadOnly)
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
            .padding(.vertical, OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.primaryAccent)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
        }
        .disabled(isSaving)
    }

    // MARK: - Effective State

    private func effectiveLevel(for permissionId: String) -> PermissionLevel {
        desiredLevels[permissionId] ?? .off
    }

    private func currentLevel(for permissionId: String) -> PermissionLevel {
        guard let row = currentPermissionSnapshot.first(where: {
            $0.permission == permissionId
        }),
        let level = PermissionLevel(rawValue: row.scope),
        PermissionRegistry.definition(for: permissionId)?.scopes.contains(level) == true else {
            return .off
        }
        return level
    }

    /// Returns the uniform level for all permissions in a category, or nil if mixed.
    private func categoryLevel(for category: String) -> PermissionLevel? {
        categoryLevel(for: PermissionRegistry.permissions(for: category))
    }

    private func categoryLevel(
        for perms: [PermissionDefinition]
    ) -> PermissionLevel? {
        guard let first = perms.first else { return nil }
        let firstLevel = effectiveLevel(for: first.id)
        for perm in perms.dropFirst() {
            if effectiveLevel(for: perm.id) != firstLevel {
                return nil
            }
        }
        return firstLevel
    }

    /// Bulk-set all permissions in a category to the given level.
    private func setCategoryLevel(_ category: String, to level: PermissionLevel) {
        setPermissionLevels(PermissionRegistry.permissions(for: category), to: level)
    }

    private func setPermissionLevels(
        _ perms: [PermissionDefinition],
        to level: PermissionLevel
    ) {
        var updated = desiredLevels
        for perm in perms {
            guard perm.allowedLevels.contains(level) else { continue }
            updated[perm.id] = level
        }
        desiredLevels = PermissionEditorPolicy.normalized(updated)
    }

    // MARK: - Data

    private func loadPermissions() {
        Task {
            do {
                let perms = try await PermissionAdminService.fetchRolePermissions(roleId: role.id)
                let snapshot = perms
                    .map { CanonicalRolePermission(permission: $0.permission, scope: $0.scope) }
                    .sorted { $0.permission < $1.permission }

                // Fetch users assigned to this role
                let userIds = try await PermissionAdminService.fetchUserIdsForRole(roleId: role.id)
                let companyId = dataController.getCurrentUserCompany()?.id
                var matchedUsers: [User] = []
                if let companyId = companyId, !userIds.isEmpty {
                    let allTeam = dataController.getTeamMembers(companyId: companyId)
                    matchedUsers = allTeam.filter { userIds.contains($0.id) }
                }

                await MainActor.run {
                    self.currentPermissionSnapshot = snapshot
                    self.desiredLevels = PermissionEditorPolicy.desiredLevels(from: snapshot)
                    self.roleUsers = matchedUsers
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

    private func saveChanges(
        assignmentResolutions: [RolePermissionAssignmentResolution] = []
    ) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                let request = try RolePermissionMutationRequest(
                    expectedPermissions: currentPermissionSnapshot,
                    desiredLevels: desiredLevels,
                    assignmentResolutions: assignmentResolutions
                )
                let result = try await PermissionAdminService.replaceRolePermissions(
                    roleId: role.id,
                    request: request
                )

                await MainActor.run {
                    currentPermissionSnapshot = result.permissions
                    desiredLevels = PermissionEditorPolicy.desiredLevels(
                        from: result.permissions
                    )
                    assignmentConflict = nil
                    isSaving = false

                    ToastCenter.shared.present(Feedback.Settings.permissionsSaved)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }

                print("[PERMISSIONS] Replaced role permissions for \(role.name)")

            } catch {
                await MainActor.run {
                    isSaving = false

                    if let adminError = error as? PermissionAdminService.PermissionAdminError {
                        switch adminError {
                        case .assignmentResolutionRequired(let conflict):
                            assignmentConflict = conflict
                            errorMessage = nil
                        case .assignmentResolutionChanged:
                            assignmentConflict = nil
                            errorMessage = nil
                            // Re-run without stale resolutions. The guarded
                            // endpoint will either commit (nothing is stranded
                            // now) or return a fresh authoritative prompt.
                            DispatchQueue.main.async { saveChanges() }
                        case .snapshotChanged(let current):
                            currentPermissionSnapshot = current.sorted { $0.permission < $1.permission }
                            desiredLevels = PermissionEditorPolicy.desiredLevels(from: current)
                            assignmentConflict = nil
                            errorMessage = adminError.localizedDescription
                        default:
                            errorMessage = adminError.localizedDescription
                        }
                    } else {
                        errorMessage = error.localizedDescription
                    }

                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
                print("[PERMISSIONS] Error saving permissions: \(error)")
            }
        }
    }

}

struct LeadResponsibilityResolutionSheet: View {
    private static let unassignedChoice = "__unassigned__"

    let conflict: RolePermissionMutationConflict
    let isSaving: Bool
    let onCancel: () -> Void
    let onResolve: ([RolePermissionAssignmentResolution]) -> Void

    @State private var choices: [String: String] = [:]

    private var canResolve: Bool {
        conflict.stranded.allSatisfy { lead in
            guard let choice = choices[lead.opportunityId] else { return false }
            return !choice.isEmpty
        }
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    SheetTitleLabel(title: "REASSIGN ACTIVE LEADS", size: .full)
                    SheetCloseButton(action: onCancel)
                        .disabled(isSaving)
                }
                .padding(.leading, OPSStyle.Layout.spacing3_5)
                .padding(.trailing, OPSStyle.Layout.spacing1)
                .padding(.vertical, OPSStyle.Layout.spacing2)

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        Text("This access change would leave active leads with no responsible operator. Choose a new assignee or leave each lead unassigned before saving.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(conflict.stranded) { lead in
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                Text(lead.title.isEmpty ? "Untitled lead" : lead.title)
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .lineLimit(2)

                                Picker(
                                    "New assignee",
                                    selection: Binding(
                                        get: { choices[lead.opportunityId] ?? "" },
                                        set: { choices[lead.opportunityId] = $0 }
                                    )
                                ) {
                                    Text("Choose assignee").tag("")
                                    Text("Unassigned").tag(Self.unassignedChoice)
                                    ForEach(conflict.eligibleAssignees) { assignee in
                                        Text(assignee.displayName.isEmpty ? "Team member" : assignee.displayName)
                                            .tag(assignee.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(OPSStyle.Colors.primaryText)
                                .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetStandard, alignment: .leading)
                                .padding(.horizontal, OPSStyle.Layout.spacing2)
                                .background(OPSStyle.Colors.surfaceInput)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(
                                            OPSStyle.Colors.inputFieldBorder,
                                            lineWidth: OPSStyle.Layout.Border.standard
                                        )
                                )
                            }
                            .padding(OPSStyle.Layout.spacing3)
                            .glassSurface()
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.bottom, OPSStyle.Layout.spacing5)
                }

                Button(action: resolve) {
                    Group {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(
                                    CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText)
                                )
                        } else {
                            Text("SAVE ACCESS CHANGE")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(OPSStyle.Colors.invertedText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(
                        canResolve
                            ? OPSStyle.Colors.primaryAccent
                            : OPSStyle.Colors.surfaceHover
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canResolve || isSaving)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.vertical, OPSStyle.Layout.spacing3)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isSaving)
    }

    private func resolve() {
        guard canResolve else { return }
        let resolutions = conflict.stranded.map { lead in
            let choice = choices[lead.opportunityId]
            return RolePermissionAssignmentResolution(
                opportunityId: lead.opportunityId,
                expectedAssignedTo: lead.assignedTo,
                expectedAssignmentVersion: lead.assignmentVersion,
                newAssignedTo: choice == Self.unassignedChoice ? nil : choice
            )
        }
        onResolve(resolutions)
    }
}
