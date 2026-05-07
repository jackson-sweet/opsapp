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
        // Catalog
        PermissionDefinition(id: "catalog.view", label: "View Catalog", category: "Catalog"),
        PermissionDefinition(id: "catalog.stock.adjust", label: "Adjust Stock Quantity", category: "Catalog"),
        PermissionDefinition(id: "catalog.manage", label: "Manage Catalog", category: "Catalog"),
        PermissionDefinition(id: "catalog.import", label: "Import Catalog", category: "Catalog"),
        PermissionDefinition(id: "catalog.products.view", label: "View Products", category: "Catalog"),
        PermissionDefinition(id: "catalog.products.manage", label: "Manage Products", category: "Catalog"),
        PermissionDefinition(id: "catalog.orders.view", label: "View Orders", category: "Catalog"),
        PermissionDefinition(id: "catalog.orders.manage", label: "Manage Orders", category: "Catalog"),
        // Team
        PermissionDefinition(id: "team.view", label: "View Team", category: "Team"),
        PermissionDefinition(id: "team.manage", label: "Manage Team", category: "Team"),
        // Settings
        PermissionDefinition(id: "settings.company", label: "Company Settings", category: "Settings"),
        PermissionDefinition(id: "settings.billing", label: "Billing Settings", category: "Settings"),
        // Job Board
        PermissionDefinition(id: "job_board.manage_sections", label: "Manage Sections", category: "Job Board"),
        // Deck Builder
        PermissionDefinition(id: "deck_builder.view", label: "View Designs", category: "Deck Builder"),
        PermissionDefinition(id: "deck_builder.create", label: "Create Designs", category: "Deck Builder"),
        PermissionDefinition(id: "deck_builder.edit", label: "Edit Designs", category: "Deck Builder"),
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
        switch roleName.lowercased() {
        case "admin": return "Admin"
        case "owner": return "Owner"
        case "office": return "Office"
        case "operator": return "Operator"
        case "crew": return "Crew"
        case "unassigned": return "Unassigned"
        default: return roleName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func iconForRole(_ roleName: String) -> String {
        switch roleName.lowercased() {
        case "admin": return "shield.checkered"
        case "owner": return "crown.fill"
        case "office": return "desktopcomputer"
        case "operator": return "wrench.and.screwdriver.fill"
        case "crew": return "hammer.fill"
        case "unassigned": return "person.fill.questionmark"
        default: return "person.fill"
        }
    }

    /// Maps permission categories to their feature flag slug.
    /// Categories not in this map are always enabled.
    static let categoryFeatureFlag: [String: String] = [
        "Pipeline": "pipeline",
        "Estimates": "estimates",
        "Deck Builder": "deck_builder",
    ]

    /// Returns the feature flag slug gating a category, or nil if ungated.
    static func featureFlag(for category: String) -> String? {
        categoryFeatureFlag[category]
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
        case "Deck Builder": return "ruler.fill"
        default: return "lock.fill"
        }
    }
}

// MARK: - Permission Level

enum PermissionLevel: String, CaseIterable, Identifiable {
    case off = "off"
    case own = "own"
    case assigned = "assigned"
    case all = "all"

    var id: String { rawValue }

    var displayName: String {
        rawValue.uppercased()
    }
}

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
    "expenses.create":              ["new expense", "add expense", "receipt"],
    "pipeline.view":                ["funnel", "leads", "opportunity"],
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
    @State private var currentPermissions: [String: String] = [:] // permission -> scope
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Team members assigned to this role
    @State private var roleUsers: [User] = []

    // Feature gate alert
    @State private var showFeatureGateAlert = false

    // Pending changes
    @State private var pendingChanges: [String: PermissionChange] = [:]

    // Search + collapse
    @State private var searchQuery: String = ""
    @State private var expandedCategories: Set<String> = []

    enum PermissionChange: Equatable {
        case enable(scope: String)
        case disable
    }

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
        !pendingChanges.isEmpty
    }

    /// Preset roles (the 5 built-in roles) cannot be edited.
    private var isPresetRole: Bool {
        let presetNames = ["admin", "owner", "office", "operator", "crew", "unassigned"]
        return presetNames.contains(role.name.lowercased())
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

                            // Preset role banner
                            if isPresetRole {
                                HStack(spacing: 8) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    Text("Preset roles are read-only")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                                .padding(.horizontal, 20)
                            }

                            // Team members assigned to this role
                            if !roleUsers.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Image(systemName: OPSStyle.Icons.crew)
                                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                        Text("\(roleUsers.count) TEAM MEMBER\(roleUsers.count == 1 ? "" : "S")")
                                            .font(OPSStyle.Typography.captionBold)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                    .padding(.horizontal, 20)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
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
                                                }
                                                .frame(width: 56)
                                            }
                                        }
                                        .padding(.horizontal, 20)
                                    }
                                }
                            }

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
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                            .padding(.horizontal, 20)

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
                                    .padding(.horizontal, 20)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
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
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadPermissions()
        }
        .onDisappear {
            // Wizard: notify step 2 completion when user RETURNS to the permissions list,
            // not when they first open the detail. Prevents step 3 activating while
            // the user is still inside this fullScreenCover.
            NotificationCenter.default.post(name: Notification.Name("WizardRoleDetailViewed"), object: nil)
        }
        .alert("In Testing", isPresented: $showFeatureGateAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This feature is currently in testing. Reach out if you'd like to be added to the testing group.")
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
                withAnimation(OPSStyle.Animation.spring) {
                    if expandedCategories.contains(category) {
                        expandedCategories.remove(category)
                    } else {
                        expandedCategories.insert(category)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: PermissionRegistry.iconForCategory(category))
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text(category.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

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
                .padding(.horizontal, 16)
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
        .background(OPSStyle.Colors.background)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    /// Renders just the rows + bulk picker for a category (used inside collapsible body).
    private func permissionCategoryRows(_ category: String) -> some View {
        let permissions = visiblePermissions(for: category)
        let catLevel = categoryLevel(for: category)
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
                    isMixed: isMixed,
                    isReadOnly: isPresetRole,
                    onChange: { level in setCategoryLevel(category, to: level) }
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(OPSStyle.Colors.subtleBackground)

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

                permissionScopePicker(
                    selection: catLevel ?? .off,
                    isMixed: isMixed,
                    isReadOnly: isPresetRole,
                    onChange: { level in
                        setCategoryLevel(category, to: level)
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(OPSStyle.Colors.subtleBackground)

            // Individual permission rows (darker)
            ForEach(permissions) { perm in
                Rectangle()
                    .fill(OPSStyle.Colors.cardBorderSubtle)
                    .frame(height: 1)

                permissionRow(perm)
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

    // MARK: - Gated Category (feature-flagged, not yet available)

    private func gatedCategory(_ category: String) -> some View {
        Button(action: {
            showFeatureGateAlert = true
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(OPSStyle.Colors.subtleBackground)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(PlainButtonStyle())
        .background(OPSStyle.Colors.background)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .opacity(0.4)
        .padding(.horizontal, 20)
    }

    // MARK: - Permission Row

    private func permissionRow(_ perm: PermissionDefinition) -> some View {
        let level = effectiveLevel(for: perm.id)

        return VStack(alignment: .leading, spacing: 8) {
            Text(perm.label)
                .font(OPSStyle.Typography.body)
                .foregroundColor(level != .off ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)

            permissionScopePicker(
                selection: level,
                isMixed: false,
                isReadOnly: isPresetRole,
                onChange: { newLevel in
                    if newLevel == .off {
                        pendingChanges[perm.id] = .disable
                    } else {
                        pendingChanges[perm.id] = .enable(scope: newLevel.rawValue)
                    }
                }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Scope Picker

    private func permissionScopePicker(
        selection: PermissionLevel,
        isMixed: Bool,
        isReadOnly: Bool = false,
        onChange: @escaping (PermissionLevel) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(PermissionLevel.allCases) { level in
                Button(action: {
                    guard !isReadOnly else { return }
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
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .fill(
                                    !isMixed && selection == level
                                        ? OPSStyle.Colors.subtleBackground
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
                .fill(OPSStyle.Colors.subtleBackground)
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
            .padding(.vertical, 16)
            .background(OPSStyle.Colors.primaryAccent)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
        }
        .disabled(isSaving)
    }

    // MARK: - Effective State

    private func effectiveLevel(for permissionId: String) -> PermissionLevel {
        if let change = pendingChanges[permissionId] {
            switch change {
            case .enable(let scope): return PermissionLevel(rawValue: scope) ?? .all
            case .disable: return .off
            }
        }
        if let scope = currentPermissions[permissionId] {
            return PermissionLevel(rawValue: scope) ?? .all
        }
        return .off
    }

    /// Returns the uniform level for all permissions in a category, or nil if mixed.
    private func categoryLevel(for category: String) -> PermissionLevel? {
        let perms = PermissionRegistry.permissions(for: category)
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
        let perms = PermissionRegistry.permissions(for: category)
        for perm in perms {
            if level == .off {
                pendingChanges[perm.id] = .disable
            } else {
                pendingChanges[perm.id] = .enable(scope: level.rawValue)
            }
        }
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

                // Fetch users assigned to this role
                let userIds = try await PermissionAdminService.fetchUserIdsForRole(roleId: role.id)
                let companyId = dataController.getCurrentUserCompany()?.id
                var matchedUsers: [User] = []
                if let companyId = companyId, !userIds.isEmpty {
                    let allTeam = dataController.getTeamMembers(companyId: companyId)
                    matchedUsers = allTeam.filter { userIds.contains($0.id) }
                }

                await MainActor.run {
                    self.currentPermissions = map
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
