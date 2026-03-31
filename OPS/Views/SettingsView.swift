//
//  SettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//

import SwiftUI
import UIKit
import Foundation

struct SettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissionStore: PermissionStore
    @State private var showLogoutConfirmation = false
    @State private var showingSearchSheet = false
    @State private var isRestartingTutorial = false

    // Developer mode state
    @State private var developerModeEnabled: Bool = false
    @State private var developerModeExplicitlyDisabled: Bool = false

    // MARK: - Navigation Destination Enum

    private enum SettingsDestination: String, Identifiable {
        case profile, organization, subscription
        case notifications, map, dataStorage, security
        case productsServices, integrations, projectSettings
        case whatsNew, reportIssue, developerDashboard
        case allPhotos, myExpenses, reviewExpenses
        case permissions
        case tutorialExperience, tutorialV2
        case wizardManagement

        var id: String { rawValue }
    }

    @State private var activeDestination: SettingsDestination?
    @State private var showFeatureGateAlert = false

    // Role checks
    private var isAdmin: Bool {
        permissionStore.can("settings.company")
    }

    private var isAdminOrOffice: Bool {
        permissionStore.can("team.view")
    }

    private var hasPipelineAccess: Bool {
        permissionStore.can("pipeline.view")
    }

    private var isPipelineGated: Bool {
        !permissionStore.isFeatureEnabled("pipeline")
    }

    private var shouldShowDeveloperOptions: Bool {
        if developerModeExplicitlyDisabled { return false }
        #if DEBUG
        return true
        #else
        return developerModeEnabled
        #endif
    }

    // All searchable settings
    private var allSearchableSettings: [SearchableSettingItem] {
        var items: [SearchableSettingItem] = []

        // Account items
        items.append(contentsOf: [
            SearchableSettingItem(
                title: "Profile Information",
                categoryTitle: "Account",
                categoryIcon: OPSStyle.Icons.person,
                keywords: [
                    "name", "first name", "last name", "contact", "personal", "information",
                    "profile", "phone", "email", "address", "home address", "avatar",
                    "photo", "picture", "edit profile", "my info", "my profile",
                    "password", "reset password", "change password", "delete account"
                ],
                destination: AnyView(ProfileSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Organization",
                categoryTitle: "Account",
                categoryIcon: "building.2",
                keywords: [
                    "company", "business", "organization", "org", "company details",
                    "company name", "company logo", "logo", "company code",
                    "company phone", "company email", "company address", "website"
                ],
                destination: AnyView(OrganizationSettingsView().environmentObject(dataController))
            )
        ])

        // Manage Team — separate entry for discoverability
        if isAdmin {
            items.append(
                SearchableSettingItem(
                    title: "Manage Team",
                    categoryTitle: "Account",
                    categoryIcon: "person.3.fill",
                    keywords: [
                        "team", "members", "employees", "crew", "staff", "people",
                        "add team", "invite team", "invite member", "invite employee",
                        "add member", "add employee", "add crew", "add people",
                        "remove member", "remove employee", "fire", "delete member",
                        "edit role", "change role", "assign role", "team management",
                        "hire", "onboard", "seats", "seat management"
                    ],
                    destination: AnyView(ManageTeamView().environmentObject(dataController).environmentObject(SubscriptionManager.shared).environmentObject(permissionStore))
                )
            )

            items.append(
                SearchableSettingItem(
                    title: "Subscription",
                    categoryTitle: "Account",
                    categoryIcon: "creditcard",
                    keywords: [
                        "subscription", "plan", "billing", "seats", "payment",
                        "upgrade", "downgrade", "cancel", "pricing", "cost",
                        "renewal", "trial", "free", "pro", "premium"
                    ],
                    destination: AnyView(ManageSubscriptionView().environmentObject(dataController).environmentObject(SubscriptionManager.shared))
                )
            )
        }

        // App items
        items.append(contentsOf: [
            SearchableSettingItem(
                title: "Notifications",
                categoryTitle: "App",
                categoryIcon: OPSStyle.Icons.bellFill,
                keywords: [
                    "notifications", "alerts", "reminders", "quiet", "mute",
                    "push notifications", "do not disturb", "quiet hours",
                    "notification settings", "advance notice", "priority",
                    "sounds", "badges", "banner"
                ],
                destination: AnyView(NotificationSettingsView().environmentObject(dataController).environmentObject(NotificationManager.shared))
            ),
            SearchableSettingItem(
                title: "Map Settings",
                categoryTitle: "App",
                categoryIcon: OPSStyle.Icons.map,
                keywords: [
                    "map", "navigation", "display", "zoom", "location",
                    "gps", "directions", "map style", "satellite", "traffic",
                    "geofence", "map type"
                ],
                destination: AnyView(MapSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Data & Storage",
                categoryTitle: "App",
                categoryIcon: "externaldrive",
                keywords: [
                    "data", "sync", "storage", "cache", "clear cache",
                    "offline", "download", "upload", "refresh", "reset",
                    "clear data", "free space", "disk", "memory"
                ],
                destination: AnyView(DataStorageSettingsView().environmentObject(dataController))
            ),
            SearchableSettingItem(
                title: "Security & Privacy",
                categoryTitle: "App",
                categoryIcon: "lock",
                keywords: [
                    "security", "privacy", "pin", "biometric", "protection",
                    "face id", "touch id", "lock", "unlock", "passcode",
                    "app lock", "authentication", "secure"
                ],
                destination: AnyView(SecuritySettingsView().environmentObject(dataController))
            )
        ])

        // Data items
        items.append(
            SearchableSettingItem(
                title: "Photos",
                categoryTitle: "Data",
                categoryIcon: "photo.on.rectangle.angled",
                keywords: [
                    "photos", "images", "pictures", "gallery", "project photos",
                    "camera", "media", "attachments", "all photos", "photo gallery",
                    "browse photos", "view photos"
                ],
                destination: AnyView(AllPhotosGalleryView().environmentObject(dataController).environmentObject(appState))
            )
        )

        if permissionStore.can("expenses.view", requiredScope: "own") {
            items.append(
                SearchableSettingItem(
                    title: "My Expenses",
                    categoryTitle: "Data",
                    categoryIcon: "dollarsign.circle",
                    keywords: [
                        "expenses", "receipts", "spending", "money",
                        "my expenses", "expense report", "submit expense",
                        "reimbursement", "mileage", "cost"
                    ],
                    destination: AnyView(MyExpensesView().environmentObject(dataController))
                )
            )
        }

        if permissionStore.can("expenses.approve") {
            items.append(
                SearchableSettingItem(
                    title: "Review Expenses",
                    categoryTitle: "Data",
                    categoryIcon: "doc.text.magnifyingglass",
                    keywords: [
                        "review expenses", "approve expenses", "expense approval",
                        "pending expenses", "expense review", "reject expense",
                        "expense management", "submitted expenses"
                    ],
                    destination: AnyView(ExpensesListView().environmentObject(dataController))
                )
            )
        }

        // Business items (pipeline permission-gated)
        if hasPipelineAccess {
            items.append(contentsOf: [
                SearchableSettingItem(
                    title: "Products & Services",
                    categoryTitle: "Business",
                    categoryIcon: OPSStyle.Icons.productTag,
                    keywords: [
                        "products", "services", "catalog", "pricing", "labor", "material",
                        "line items", "price list", "service list", "add product",
                        "create product", "manage products"
                    ],
                    destination: AnyView(ProductsListView())
                ),
                SearchableSettingItem(
                    title: "Integrations",
                    categoryTitle: "Business",
                    categoryIcon: OPSStyle.Icons.accountingChart,
                    keywords: [
                        "integrations", "quickbooks", "sage", "accounting", "sync",
                        "connect", "xero", "bookkeeping", "export", "import",
                        "third party", "api"
                    ],
                    destination: AnyView(IntegrationsSettingsView())
                )
            ])
        }

        if isAdminOrOffice {
            items.append(
                SearchableSettingItem(
                    title: "Project Settings",
                    categoryTitle: "Business",
                    categoryIcon: "hammer.circle",
                    keywords: [
                        "task", "types", "project", "defaults", "scheduling",
                        "task types", "project defaults", "overdue", "threshold",
                        "reminder", "project configuration", "status", "workflow"
                    ],
                    destination: AnyView(ProjectSettingsView().environmentObject(dataController).environmentObject(permissionStore))
                )
            )
        }

        // Inventory settings
        if permissionStore.can("inventory.view") {
            items.append(
                SearchableSettingItem(
                    title: "Inventory Settings",
                    categoryTitle: "Business",
                    categoryIcon: "shippingbox.fill",
                    keywords: [
                        "inventory", "stock", "units", "tags", "snapshots",
                        "inventory units", "inventory tags", "warehouse",
                        "materials", "supplies", "quantity", "threshold",
                        "inventory management", "adjustment"
                    ],
                    destination: AnyView(InventorySettingsView().environmentObject(dataController))
                )
            )
        }

        if isAdmin {
            items.append(
                SearchableSettingItem(
                    title: "Permissions",
                    categoryTitle: "Business",
                    categoryIcon: "person.badge.key.fill",
                    keywords: [
                        "permissions", "roles", "access", "rbac", "admin", "override",
                        "role management", "user permissions", "access control",
                        "who can", "restrict", "allow", "deny", "grant"
                    ],
                    destination: AnyView(PermissionsManagementView().environmentObject(dataController).environmentObject(permissionStore))
                )
            )
        }

        // Support items
        items.append(contentsOf: [
            SearchableSettingItem(
                title: "What's New",
                categoryTitle: "Support",
                categoryIcon: "sparkles",
                keywords: [
                    "new", "updates", "features", "changelog", "release",
                    "version", "what changed", "latest", "recent", "news"
                ],
                destination: AnyView(WhatsNewView())
            ),
            SearchableSettingItem(
                title: "Report Issue",
                categoryTitle: "Support",
                categoryIcon: OPSStyle.Icons.alert,
                keywords: [
                    "report", "issue", "bug", "problem", "help",
                    "feedback", "support", "contact", "broken", "error",
                    "not working", "crash", "fix"
                ],
                destination: AnyView(ReportIssueView())
            )
        ])

        return items
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)

                VStack(alignment: .leading, spacing: 0) {
                    AppHeader(headerType: .settings)
                        .padding(.bottom, 8)

                    ScrollView {
                        VStack(spacing: OPSStyle.Layout.spacing4) {
                            // Search bar
                            searchButton
                                .padding(.horizontal, 20)
                                .padding(.top, 16)

                            // Profile card
                            profileCard
                                .padding(.horizontal, 20)

                            // Account section
                            settingsSection(title: "ACCOUNT") {
                                settingsRow(
                                    icon: "building.2",
                                    title: "Organization",
                                    action: { activeDestination = .organization }
                                )

                                if isAdmin {
                                    sectionDivider

                                    settingsRow(
                                        icon: "creditcard",
                                        title: "Subscription",
                                        action: { activeDestination = .subscription }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)

                            // App section
                            settingsSection(title: "APP") {
                                settingsRow(
                                    icon: OPSStyle.Icons.bellFill,
                                    title: "Notifications",
                                    action: { activeDestination = .notifications }
                                )

                                sectionDivider

                                settingsRow(
                                    icon: OPSStyle.Icons.map,
                                    title: "Map Settings",
                                    action: { activeDestination = .map }
                                )

                                sectionDivider

                                settingsRow(
                                    icon: "externaldrive",
                                    title: "Data & Storage",
                                    action: { activeDestination = .dataStorage }
                                )

                                sectionDivider

                                settingsRow(
                                    icon: "lock",
                                    title: "Security & Privacy",
                                    action: { activeDestination = .security }
                                )
                            }
                            .padding(.horizontal, 20)

                            // Data section
                            settingsSection(title: "DATA") {
                                settingsRow(
                                    icon: "photo.on.rectangle.angled",
                                    title: "Photos",
                                    action: { activeDestination = .allPhotos }
                                )

                                if permissionStore.can("expenses.view", requiredScope: "own") {
                                    sectionDivider

                                    settingsRow(
                                        icon: "dollarsign.circle",
                                        title: "My Expenses",
                                        action: { activeDestination = .myExpenses }
                                    )
                                }

                                if permissionStore.can("expenses.approve") {
                                    sectionDivider

                                    settingsRow(
                                        icon: "doc.text.magnifyingglass",
                                        title: "Review Expenses",
                                        action: { activeDestination = .reviewExpenses }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)

                            // Business section (admin/office crew, or pipeline permission holders)
                            if isAdminOrOffice || hasPipelineAccess || isPipelineGated {
                                settingsSection(title: "BUSINESS") {
                                    if hasPipelineAccess {
                                        settingsRow(
                                            icon: OPSStyle.Icons.productTag,
                                            title: "Products & Services",
                                            action: { activeDestination = .productsServices }
                                        )

                                        sectionDivider

                                        settingsRow(
                                            icon: OPSStyle.Icons.accountingChart,
                                            title: "Integrations",
                                            action: { activeDestination = .integrations }
                                        )

                                        if isAdminOrOffice || isAdmin {
                                            sectionDivider
                                        }
                                    } else if isPipelineGated {
                                        gatedSettingsRow(
                                            icon: OPSStyle.Icons.productTag,
                                            title: "Products & Services"
                                        )

                                        sectionDivider

                                        gatedSettingsRow(
                                            icon: OPSStyle.Icons.accountingChart,
                                            title: "Integrations"
                                        )

                                        if isAdminOrOffice || isAdmin {
                                            sectionDivider
                                        }
                                    }

                                    if isAdminOrOffice {
                                        settingsRow(
                                            icon: "hammer.circle",
                                            title: "Project Settings",
                                            action: { activeDestination = .projectSettings }
                                        )
                                    }

                                    if isAdmin {
                                        sectionDivider

                                        settingsRow(
                                            icon: "person.badge.key.fill",
                                            title: "Permissions",
                                            action: { activeDestination = .permissions }
                                        )
                                    }
                                }
                                .padding(.horizontal, 20)
                            }

                            // Support section
                            settingsSection(title: "SUPPORT") {
                                settingsRow(
                                    icon: "paperplane.fill",
                                    title: "Setup",
                                    action: { activeDestination = .wizardManagement }
                                )

                                sectionDivider

                                settingsRow(
                                    icon: "sparkles",
                                    title: "What's New",
                                    action: { activeDestination = .whatsNew }
                                )

                                sectionDivider

                                settingsRow(
                                    icon: OPSStyle.Icons.alert,
                                    title: "Report Issue",
                                    action: { activeDestination = .reportIssue }
                                )

                                sectionDivider

                                settingsRow(
                                    icon: "graduationcap.fill",
                                    title: "Restart Tutorial",
                                    action: { activeDestination = .tutorialV2 }
                                )
                            }
                            .padding(.horizontal, 20)

                            // Developer section (conditional)
                            if shouldShowDeveloperOptions {
                                settingsSection(title: "DEVELOPER") {
                                    settingsRow(
                                        icon: "hammer.circle.fill",
                                        title: "Developer Tools",
                                        action: { activeDestination = .developerDashboard }
                                    )
                                }
                                .padding(.horizontal, 20)
                            }

                            // Log out button
                            logOutButton
                                .padding(.horizontal, 20)
                                .padding(.top, 8)

                            // App version footer
                            appVersionFooter
                                .padding(.top, 8)
                                .padding(.bottom, 24)
                        }
                        .padding(.bottom, 90) // Tab bar padding
                    }
                }
            }
        }
        .trackScreen("Settings")
        .onAppear {
            AnalyticsManager.shared.trackScreenView(screenName: .settings, screenClass: "SettingsView")
            AnalyticsService.shared.trackScreenView(screenName: "settings")
            developerModeEnabled = UserDefaults.standard.bool(forKey: "developerModeEnabled")
            #if DEBUG
            if !developerModeEnabled && UserDefaults.standard.object(forKey: "developerModeEnabled") != nil {
                developerModeExplicitlyDisabled = true
            }
            #endif
        }
        .onDisappear {
            AnalyticsService.shared.endScreenView(screenName: "settings")
        }
        .sheet(isPresented: $showingSearchSheet) {
            SettingsSearchSheet(allSearchableSettings: allSearchableSettings)
                .environmentObject(dataController)
        }
        .alert("Log Out", isPresented: $showLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                dataController.logout()
            }
        } message: {
            Text("Are you sure you want to log out of your account?")
        }
        .alert("In Testing", isPresented: $showFeatureGateAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This feature is currently in testing. Reach out if you'd like to be added to the testing group.")
        }
        // MARK: - Navigation Cover (consolidated enum-based)
        .fullScreenCover(item: $activeDestination) { destination in
            settingsDestinationView(for: destination)
        }
        .onChange(of: activeDestination) { oldValue, _ in
            if oldValue == .developerDashboard {
                developerModeEnabled = UserDefaults.standard.bool(forKey: "developerModeEnabled")
                #if DEBUG
                if !developerModeEnabled && UserDefaults.standard.object(forKey: "developerModeEnabled") != nil {
                    developerModeExplicitlyDisabled = true
                }
                #endif
            }
        }
        // MARK: - Wizard Deep Navigation Receivers
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SettingsOpenSecurity"))) { _ in
            activeDestination = .security
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SettingsOpenNotifications"))) { _ in
            activeDestination = .notifications
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SettingsOpenOrganization"))) { _ in
            activeDestination = .organization
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SettingsOpenPermissions"))) { _ in
            activeDestination = .permissions
        }
    }

    // MARK: - Destination View Builder

    @ViewBuilder
    private func settingsDestinationView(for destination: SettingsDestination) -> some View {
        switch destination {
        case .profile:
            NavigationStack {
                ProfileSettingsView()
                    .environmentObject(dataController)
            }
        case .organization:
            NavigationStack {
                OrganizationSettingsView()
                    .environmentObject(dataController)
            }
        case .subscription:
            NavigationStack {
                ManageSubscriptionView()
                    .environmentObject(dataController)
                    .environmentObject(SubscriptionManager.shared)
            }
        case .notifications:
            NavigationStack {
                NotificationSettingsView()
                    .environmentObject(dataController)
                    .environmentObject(NotificationManager.shared)
            }
        case .map:
            NavigationStack {
                MapSettingsView()
                    .environmentObject(dataController)
            }
        case .dataStorage:
            NavigationStack {
                DataStorageSettingsView()
                    .environmentObject(dataController)
            }
        case .security:
            NavigationStack {
                SecuritySettingsView()
                    .environmentObject(dataController)
            }
        case .productsServices:
            NavigationStack {
                ProductsListView()
                    .environmentObject(dataController)
            }
        case .integrations:
            NavigationStack {
                IntegrationsSettingsView()
                    .environmentObject(dataController)
            }
        case .projectSettings:
            NavigationStack {
                ProjectSettingsView()
                    .environmentObject(dataController)
                    .environmentObject(permissionStore)
            }
        case .whatsNew:
            NavigationStack {
                WhatsNewView()
            }
        case .reportIssue:
            NavigationStack {
                ReportIssueView()
            }
        case .developerDashboard:
            NavigationStack {
                DeveloperDashboard()
                    .environmentObject(dataController)
            }
        case .allPhotos:
            NavigationStack {
                AllPhotosGalleryView()
                    .environmentObject(dataController)
                    .environmentObject(appState)
            }
        case .myExpenses:
            NavigationStack {
                MyExpensesView()
                    .environmentObject(dataController)
            }
        case .reviewExpenses:
            NavigationStack {
                ExpensesListView()
                    .environmentObject(dataController)
            }
        case .permissions:
            NavigationStack {
                PermissionsManagementView()
                    .environmentObject(dataController)
                    .environmentObject(permissionStore)
            }
        case .tutorialExperience:
            TutorialFlowView {
                activeDestination = nil
            }
        case .tutorialV2:
            TutorialFlowViewV2 {
                activeDestination = nil
            }
        case .wizardManagement:
            NavigationStack {
                WizardManagementView()
                    .environmentObject(dataController)
                    .environmentObject(permissionStore)
            }
        }
    }

    // MARK: - Search Button

    private var searchButton: some View {
        Button(action: { showingSearchSheet = true }) {
            HStack(spacing: 12) {
                Image(systemName: OPSStyle.Icons.search)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text("Search settings...")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        Button(action: { activeDestination = .profile }) {
            HStack(spacing: 14) {
                // Avatar
                profileAvatar

                // Name and subtitle
                VStack(alignment: .leading, spacing: 4) {
                    Text((dataController.currentUser?.fullName ?? "User").uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if let role = dataController.currentUser?.role {
                            Text(role.displayName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }

                        if let email = dataController.currentUser?.email, !email.isEmpty {
                            Text("·")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text(email)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Profile Avatar

    /// Normalizes a profile image URL (handles // prefix from legacy storage).
    private func normalizedProfileURL(_ urlString: String) -> URL? {
        var fixed = urlString
        if fixed.hasPrefix("//") {
            fixed = "https:" + fixed
        }
        return URL(string: fixed)
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let user = dataController.currentUser {
            if let imageData = user.profileImageData,
               let uiImage = UIImage(data: imageData) {
                // Local image data available
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
            } else if let urlString = user.profileImageURL,
                      !urlString.isEmpty,
                      let url = normalizedProfileURL(urlString) {
                // Load from URL
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    default:
                        initialsAvatar(user: user)
                    }
                }
            } else {
                initialsAvatar(user: user)
            }
        } else {
            Circle()
                .fill(OPSStyle.Colors.primaryAccent)
                .frame(width: 48, height: 48)
                .overlay(
                    Text("U")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                )
        }
    }

    private func initialsAvatar(user: User) -> some View {
        Circle()
            .fill(Color(hex: user.userColor ?? "#59779F") ?? OPSStyle.Colors.primaryAccent)
            .frame(width: 48, height: 48)
            .overlay(
                Text("\(user.firstName.prefix(1))\(user.lastName.prefix(1))")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            )
    }

    // MARK: - Grouped Section Builder

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Grouped card
            VStack(spacing: 0) {
                content()
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    // MARK: - Row Component

    private func settingsRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 28, alignment: .center)

                Text(title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Gated Row (feature-flagged)

    private func gatedSettingsRow(icon: String, title: String) -> some View {
        Button(action: { showFeatureGateAlert = true }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: 28, alignment: .center)

                Text(title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Spacer()

                Text("IN TESTING")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(OPSStyle.Colors.tertiaryText.opacity(0.15))
                    )
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .opacity(0.4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Divider

    private var sectionDivider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorder)
            .frame(height: 1)
            .padding(.leading, 58) // Inset past icon area
    }

    // MARK: - Log Out

    private var logOutButton: some View {
        Button(action: { showLogoutConfirmation = true }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.errorStatus)

                Text("LOG OUT")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.errorStatus, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - App Version Footer

    private var appVersionFooter: some View {
        HStack(spacing: 12) {
            Image("LogoWhite")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            Text("OPS v\(AppConfiguration.AppInfo.version)")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("·")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("© 2025 OPS")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tutorial Restart

    private func restartTutorial() {
        guard dataController.currentUser != nil else { return }
        activeDestination = .tutorialExperience
    }
}

#Preview {
    SettingsView()
        .environmentObject(DataController())
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
