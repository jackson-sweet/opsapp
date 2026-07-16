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
    @ObservedObject private var permissionStore = PermissionStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wizardStateManager) private var wizardStateManager

    // Role state
    @State private var selectedRole: UserRole
    @State private var originalRole: UserRole
    @State private var currentRoleId: String?
    @State private var isSavingRole = false

    // Override state
    @State private var rolePermissions: [String: String] = [:]
    @State private var currentOverrideSnapshot: [CanonicalUserPermissionOverride] = []
    @State private var desiredOverrideLevels: [String: PermissionLevel] = [:]
    @State private var isLoading = true
    @State private var isSavingOverrides = false
    @State private var errorMessage: String?
    @State private var assignmentConflict: RolePermissionMutationConflict?
    @State private var pendingMutation: PendingAccessMutation?


    /// Whether this member is the company creator (account holder) — their role cannot be changed
    private var isCompanyCreator: Bool {
        guard let company = dataController.getCompany(id: companyId) else { return false }
        return company.accountHolderId == member.id
    }

    private enum PendingAccessMutation {
        case role
        case overrides
    }

    init(member: User, companyId: String) {
        self.member = member
        self.companyId = companyId
        self._selectedRole = State(initialValue: member.role)
        self._originalRole = State(initialValue: member.role)
    }

    @State private var showRoleListSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // OPS-style header
                    SettingsHeader(
                        title: "Permissions",
                        onBackTapped: { dismiss() }
                    )
                    .padding(.bottom, OPSStyle.Layout.spacing2)

                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                            // Member header
                            memberHeader

                            // Wizard context hint
                            if let mgr = wizardStateManager, mgr.isActive,
                               mgr.activeWizard?.wizardId == "permissions_roles" {
                                HStack(spacing: 10) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(OPSStyle.Colors.wizardAccent)
                                    Text("Assign a role below, or scroll down for per-person permission overrides.")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
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

                            // Section 1: Role
                            roleSection

                            // Section 2: Permission Overrides
                            if !isLoading {
                                overridesSection
                            }
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tabBarPadding()
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            loadData()
            NotificationCenter.default.post(name: Notification.Name("WizardMemberOverrideViewed"), object: nil)
        }
        .sheet(isPresented: $showRoleListSheet) {
            NavigationStack {
                RoleListView()
                    .environmentObject(dataController)
            }
        }
        .sheet(item: $assignmentConflict) { conflict in
            LeadResponsibilityResolutionSheet(
                conflict: conflict,
                isSaving: isSavingRole || isSavingOverrides,
                onCancel: {
                    assignmentConflict = nil
                    pendingMutation = nil
                },
                onResolve: { resolutions in
                    switch pendingMutation {
                    case .role:
                        saveRole(assignmentResolutions: resolutions)
                    case .overrides:
                        saveOverrides(assignmentResolutions: resolutions)
                    case nil:
                        assignmentConflict = nil
                    }
                }
            )
        }
    }

    // MARK: - Member Header

    private var memberHeader: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            UserAvatar(user: member, size: 56)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(member.fullName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let email = member.email {
                    Text(email)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    // MARK: - Role Section

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.key")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text("ROLE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            if isCompanyCreator {
                // Creator lock — cannot change the account holder's role
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedRole.displayName.uppercased())
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("Account holder. Role cannot be changed.")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .glassSurface()
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            } else {
                VStack(spacing: 0) {
                    ForEach(UserRole.allCases.sorted(by: { $0.hierarchy < $1.hierarchy }), id: \.rawValue) { role in
                        if role != UserRole.allCases.sorted(by: { $0.hierarchy < $1.hierarchy }).first {
                            Divider().background(OPSStyle.Colors.cardBorder)
                        }
                        roleOption(role, title: role.displayName, description: role.roleDescription)
                    }
                }
                .glassSurface()
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

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
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                    }
                    .disabled(isSavingRole)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                }

                // Edit roles link
                Button(action: { showRoleListSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.and.list.clipboard")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        Text("Edit & manage roles")
                            .font(OPSStyle.Typography.caption)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }
        }
    }

    private func roleOption(_ role: UserRole, title: String, description: String) -> some View {
        Button(action: { selectedRole = role }) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: selectedRole == role ? OPSStyle.Icons.checkmarkCircleFill : OPSStyle.Icons.circle)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(selectedRole == role ? OPSStyle.Colors.text : OPSStyle.Colors.tertiaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(selectedRole == role ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)

                    Text(description)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .background(selectedRole == role ? OPSStyle.Colors.surfaceActive : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Overrides Section

    private var overridesSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text("PERMISSION OVERRIDES")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            Text("Override individual permissions beyond what the role grants.")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            ForEach(PermissionRegistry.categories, id: \.self) { category in
                if let flag = PermissionRegistry.featureFlag(for: category),
                   !permissionStore.isFeatureEnabled(flag) {
                    gatedOverrideCategory(category)
                } else {
                    overrideCategory(category)
                }
            }

            if hasPendingOverrideChanges {
                Button(action: { saveOverrides() }) {
                    HStack {
                        if isSavingOverrides {
                            ProgressView()
                                .progressViewStyle(
                                    CircularProgressViewStyle(
                                        tint: OPSStyle.Colors.invertedText
                                    )
                                )
                                .scaleEffect(0.8)
                        } else {
                            Text("SAVE ACCESS CHANGES")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(OPSStyle.Colors.invertedText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                }
                .disabled(isSavingOverrides)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }
        }
    }

    // MARK: - Gated Override Category (feature-flagged, not yet available)

    private func gatedOverrideCategory(_ category: String) -> some View {
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
                    .lineLimit(1)
                    .truncationMode(.tail)

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

    private func overrideCategory(_ category: String) -> some View {
        let permissions = PermissionRegistry.permissions(for: category)
        let catLevel = overrideCategoryLevel(for: category)
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
                        .lineLimit(1)
                        .truncationMode(.tail)

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
                    levels: PermissionEditorPolicy.commonLevels(for: permissions),
                    onChange: { level in
                        setOverrideCategoryLevel(category, to: level)
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

                overrideRow(perm)
            }
        }
        .glassSurface()
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    private func overrideRow(_ perm: PermissionDefinition) -> some View {
        let level = effectiveOverrideLevel(for: perm.id)
        let baseline = roleBaselineLevel(for: perm.id)
        let hasOverride = level != baseline

        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text(perm.label)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(level != .off ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if hasOverride {
                    Text("OVERRIDE")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Text("FROM ROLE")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.successStatus)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            overrideScopePicker(
                selection: level,
                isMixed: false,
                levels: perm.allowedLevels,
                onChange: { newLevel in
                    setOverrideLevel(permissionId: perm.id, level: newLevel)
                }
            )
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
    }

    // MARK: - Override Scope Picker (uses shared SettingsSegmentedPicker)

    private func overrideScopePicker(
        selection: PermissionLevel,
        isMixed: Bool,
        levels: [PermissionLevel],
        onChange: @escaping (PermissionLevel) -> Void
    ) -> some View {
        SettingsSegmentedPicker(
            selection: selection,
            options: levels.map { ($0, $0.displayName) },
            isMixed: isMixed,
            onChange: onChange
        )
    }

    // MARK: - Override Helpers

    private var hasPendingOverrideChanges: Bool {
        let current = currentEffectiveOverrideLevels
        return PermissionRegistry.editable.contains { definition in
            (desiredOverrideLevels[definition.id] ?? .off)
                != (current[definition.id] ?? .off)
        }
    }

    private var currentEffectiveOverrideLevels: [String: PermissionLevel] {
        effectiveLevels(
            baseline: roleBaselineLevels(from: rolePermissions),
            overrides: currentOverrideSnapshot
        )
    }

    private func effectiveOverrideLevel(for permissionId: String) -> PermissionLevel {
        desiredOverrideLevels[permissionId] ?? .off
    }

    private func roleBaselineLevel(for permissionId: String) -> PermissionLevel {
        roleBaselineLevels(from: rolePermissions)[permissionId] ?? .off
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
        guard PermissionEditorPolicy.commonLevels(for: perms).contains(level) else { return }
        var updated = desiredOverrideLevels
        for perm in perms {
            updated[perm.id] = level
        }
        desiredOverrideLevels = PermissionEditorPolicy.normalized(updated)
    }

    private func setOverrideLevel(permissionId: String, level: PermissionLevel) {
        desiredOverrideLevels = PermissionEditorPolicy.applying(
            level,
            to: permissionId,
            in: desiredOverrideLevels
        )
    }

    private func roleBaselineLevels(
        from permissions: [String: String]
    ) -> [String: PermissionLevel] {
        var result = Dictionary(
            uniqueKeysWithValues: PermissionRegistry.editable.map {
                ($0.id, PermissionLevel.off)
            }
        )
        for definition in PermissionRegistry.editable {
            guard let scope = permissions[definition.id],
                  let level = PermissionLevel(rawValue: scope),
                  definition.scopes.contains(level) else { continue }
            result[definition.id] = level
        }
        return PermissionEditorPolicy.normalized(result)
    }

    private func effectiveLevels(
        baseline: [String: PermissionLevel],
        overrides: [CanonicalUserPermissionOverride]
    ) -> [String: PermissionLevel] {
        var result = baseline
        for override in overrides {
            guard let definition = PermissionRegistry.definition(for: override.permission),
                  !definition.hiddenFromEditor else { continue }
            guard override.granted else {
                result[override.permission] = .off
                continue
            }
            guard let scope = override.scope,
                  let level = PermissionLevel(rawValue: scope),
                  definition.scopes.contains(level) else { continue }
            result[override.permission] = level
        }
        return PermissionEditorPolicy.normalized(result)
    }

    private func saveOverrides(
        assignmentResolutions: [RolePermissionAssignmentResolution] = []
    ) {
        guard !isSavingOverrides,
              hasPendingOverrideChanges || !assignmentResolutions.isEmpty else { return }
        isSavingOverrides = true
        errorMessage = nil

        Task {
            do {
                let baseline = roleBaselineLevels(from: rolePermissions)
                let request = try UserPermissionOverrideMutationRequest(
                    expectedOverrides: currentOverrideSnapshot,
                    roleBaseline: baseline,
                    desiredLevels: desiredOverrideLevels,
                    assignmentResolutions: assignmentResolutions
                )
                let result = try await PermissionAdminService.replaceUserPermissionOverrides(
                    userId: member.id,
                    request: request
                )

                await MainActor.run {
                    currentOverrideSnapshot = result.overrides
                    desiredOverrideLevels = effectiveLevels(
                        baseline: baseline,
                        overrides: result.overrides
                    )
                    assignmentConflict = nil
                    pendingMutation = nil
                    isSavingOverrides = false
                    ToastCenter.shared.present(Feedback.Settings.permissionsSaved)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }

                if member.id == dataController.currentUser?.id {
                    await PermissionStore.shared.fetchPermissions(userId: member.id)
                }
            } catch {
                await MainActor.run {
                    isSavingOverrides = false
                    handlePermissionAdminError(error, mutation: .overrides)
                }
            }
        }
    }

    private func saveRole(
        assignmentResolutions: [RolePermissionAssignmentResolution] = []
    ) {
        guard !isSavingRole else { return }
        guard selectedRole != originalRole || !assignmentResolutions.isEmpty else { return }
        isSavingRole = true
        errorMessage = nil

        Task {
            do {
                let roleId = try await PermissionAdminService.resolveRoleId(for: selectedRole)
                let nextPermissions = try await PermissionAdminService.fetchRolePermissions(
                    roleId: roleId
                )
                let request = try UserRoleMutationRequest(
                    expectedRoleId: currentRoleId,
                    newRoleId: roleId,
                    assignmentResolutions: assignmentResolutions
                )
                let result = try await PermissionAdminService.replaceUserRole(
                    userId: member.id,
                    request: request
                )
                guard result.roleId == roleId else {
                    throw PermissionAdminService.PermissionAdminError.invalidResponse
                }

                let committedRole = UserRole(rawValue: result.legacyRole.lowercased())
                    ?? selectedRole
                let permissionMap = Dictionary(
                    uniqueKeysWithValues: nextPermissions.map { ($0.permission, $0.scope) }
                )
                let baseline = roleBaselineLevels(from: permissionMap)

                await MainActor.run {
                    currentRoleId = result.roleId
                    member.role = committedRole
                    selectedRole = committedRole
                    originalRole = committedRole
                    rolePermissions = permissionMap
                    desiredOverrideLevels = effectiveLevels(
                        baseline: baseline,
                        overrides: currentOverrideSnapshot
                    )
                    assignmentConflict = nil
                    pendingMutation = nil
                    isSavingRole = false
                    ToastCenter.shared.present(Feedback.Settings.roleUpdated)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }

                do {
                    try dataController.modelContext?.save()
                } catch {
                    print("[PERMISSIONS] Role committed; local cache save deferred: \(error)")
                }

                if member.id == dataController.currentUser?.id {
                    await PermissionStore.shared.fetchPermissions(userId: member.id)
                }
            } catch {
                await MainActor.run {
                    isSavingRole = false
                    handlePermissionAdminError(error, mutation: .role)
                }
            }
        }
    }

    private func handlePermissionAdminError(
        _ error: Error,
        mutation: PendingAccessMutation
    ) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        guard let adminError = error as? PermissionAdminService.PermissionAdminError else {
            errorMessage = error.localizedDescription
            return
        }

        switch adminError {
        case .assignmentResolutionRequired(let conflict):
            pendingMutation = mutation
            assignmentConflict = conflict
            errorMessage = nil

        case .assignmentResolutionChanged:
            let retryMutation = pendingMutation ?? mutation
            assignmentConflict = nil
            pendingMutation = retryMutation
            DispatchQueue.main.async {
                switch retryMutation {
                case .role:
                    saveRole()
                case .overrides:
                    saveOverrides()
                }
            }

        case .userOverrideSnapshotChanged(let current):
            currentOverrideSnapshot = current
            desiredOverrideLevels = effectiveLevels(
                baseline: roleBaselineLevels(from: rolePermissions),
                overrides: current
            )
            assignmentConflict = nil
            pendingMutation = nil
            errorMessage = adminError.localizedDescription

        case .userRoleSnapshotChanged:
            assignmentConflict = nil
            pendingMutation = nil
            loadData(message: adminError.localizedDescription)

        default:
            errorMessage = adminError.localizedDescription
        }
    }

    // MARK: - Data Loading

    private func loadData(message: String? = nil) {
        isLoading = true
        let memberId = member.id
        Task {
            do {
                async let rolesRequest = PermissionAdminService.fetchAllRoles()
                async let userRoleRequest = PermissionAdminService.fetchUserRole(userId: memberId)
                async let overridesRequest = PermissionAdminService.fetchUserOverrides(userId: memberId)
                let (roles, userRole, overrideRows) = try await (
                    rolesRequest,
                    userRoleRequest,
                    overridesRequest
                )

                let authoritativeRoleId = userRole?.role_id
                let permissionRows: [AdminRolePermissionRow]
                if let authoritativeRoleId {
                    permissionRows = try await PermissionAdminService.fetchRolePermissions(
                        roleId: authoritativeRoleId
                    )
                } else {
                    permissionRows = []
                }

                let permissionMap = Dictionary(
                    uniqueKeysWithValues: permissionRows.map { ($0.permission, $0.scope) }
                )
                let baseline = roleBaselineLevels(from: permissionMap)
                let snapshot = overrideRows.map {
                    CanonicalUserPermissionOverride(
                        permission: $0.permission,
                        scope: $0.scope,
                        granted: $0.granted
                    )
                }.sorted { $0.permission < $1.permission }
                let roleName = roles.first(where: { $0.id == authoritativeRoleId })?.name
                let authoritativeRole = roleName.flatMap {
                    UserRole(rawValue: $0.lowercased())
                } ?? .unassigned

                await MainActor.run {
                    currentRoleId = authoritativeRoleId
                    selectedRole = authoritativeRole
                    originalRole = authoritativeRole
                    rolePermissions = permissionMap
                    currentOverrideSnapshot = snapshot
                    desiredOverrideLevels = effectiveLevels(
                        baseline: baseline,
                        overrides: snapshot
                    )
                    member.role = authoritativeRole
                    assignmentConflict = nil
                    pendingMutation = nil
                    errorMessage = message
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
