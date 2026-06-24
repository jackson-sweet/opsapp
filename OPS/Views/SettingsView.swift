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
    @Environment(\.wizardStateManager) private var wizardStateManager
    @State private var showLogoutConfirmation = false
    // Bug G5 — the former sheet-based settings search has been replaced by an
    // in-header expandable input; its state lives on AppState now.
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
        case laserMeter
        case trash
        // Bug e33aa336 — granular search routes also target sub-pages that
        // weren't previously reachable from the top-level Settings list.
        // Each one maps onto an existing sub-view; the new cases just give
        // search a typed lane into them.
        case organizationDetails
        case manageTeam
        case taskTypes
        case inventorySettings
        case pipelineSettings

        var id: String { rawValue }
    }

    @State private var activeDestination: SettingsDestination?

    // Bug e33aa336 — when a search result targets a specific section inside
    // a sub-page, this value holds the section identifier until the sub-page
    // mounts. The destination view sees it via SettingsDeepLinkHost (below)
    // and broadcasts the matching `SettingsDeepLink.<destination>` notification,
    // which the sub-view observes to scroll/highlight the section.
    @State private var pendingDeepLinkSection: String? = nil

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

    // Bug e33aa336 — the legacy `allSearchableSettings` property and its
    // SearchableSettingItem entries were replaced by `SettingsSearchIndex`,
    // which carries breadcrumb paths and typed routes. Search results are
    // now built inline from the index (see `settingsSearchResults` below).

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background
                    .edgesIgnoringSafeArea(.all)

                VStack(alignment: .leading, spacing: 0) {
                    AppHeader(headerType: .settings)
                        .padding(.bottom, OPSStyle.Layout.spacing2)

                    // Bug G5 — when the header search is active, the settings
                    // list below is replaced by a live results list. The
                    // inline search button has moved into the header, so the
                    // content area is no longer pushed down by a duplicate
                    // control. The results view uses the same searchable
                    // index as the old SettingsSearchSheet.
                    if appState.isSettingsSearchActive {
                        settingsSearchResults
                            .transition(.opacity)
                    } else {
                    ScrollView {
                        VStack(spacing: OPSStyle.Layout.spacing4) {
                            // Profile card
                            profileCard
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                .padding(.top, OPSStyle.Layout.spacing3)

                            // Organization section — company identity, team, billing, permissions
                            settingsSection(title: "ORGANIZATION") {
                                settingsRow(
                                    icon: "building.2.fill",
                                    title: "Organization Details",
                                    action: { activeDestination = .organizationDetails }
                                )

                                if isAdminOrOffice {
                                    sectionDivider

                                    settingsRow(
                                        icon: "person.3.fill",
                                        title: "Manage Team",
                                        action: { activeDestination = .manageTeam }
                                    )
                                }

                                if isAdmin {
                                    sectionDivider

                                    settingsRow(
                                        icon: "creditcard",
                                        title: "Subscription",
                                        action: { activeDestination = .subscription }
                                    )

                                    sectionDivider

                                    settingsRow(
                                        icon: "person.badge.key.fill",
                                        title: "Permissions",
                                        action: { activeDestination = .permissions }
                                    )
                                }
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                            // Business section — commerce-facing config (catalog, accounting)
                            if hasPipelineAccess || isPipelineGated {
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
                                    } else {
                                        gatedSettingsRow(
                                            icon: OPSStyle.Icons.productTag,
                                            title: "Products & Services"
                                        )

                                        sectionDivider

                                        gatedSettingsRow(
                                            icon: OPSStyle.Icons.accountingChart,
                                            title: "Integrations"
                                        )
                                    }
                                }
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            }

                            // Operations section — workflow rules. Bug 4014b472 moved these out
                            // of BUSINESS: task taxonomy, scheduling, project review rules, and
                            // inventory are app-behavior config, not company identity.
                            if isAdminOrOffice || permissionStore.can("catalog.view") || permissionStore.can("pipeline.manage") {
                                settingsSection(title: "OPERATIONS") {
                                    if isAdminOrOffice {
                                        settingsRow(
                                            icon: "square.grid.2x2",
                                            title: "Task Types",
                                            action: { activeDestination = .taskTypes }
                                        )

                                        sectionDivider

                                        settingsRow(
                                            icon: "hammer.circle",
                                            title: "Project Rules",
                                            action: { activeDestination = .projectSettings }
                                        )

                                        if permissionStore.can("catalog.view") {
                                            sectionDivider
                                        }
                                    }

                                    if permissionStore.can("catalog.view") {
                                        settingsRow(
                                            icon: "shippingbox",
                                            title: "Inventory",
                                            action: { activeDestination = .inventorySettings }
                                        )
                                    }
                                    // Inventory tracking on/off now lives inside the
                                    // Inventory screen (top "TRACKING" section) and
                                    // the Catalog Setup review step — both gated to
                                    // catalog.manage. No separate top-level row.

                                    // Calls — around-call auto-log preference (154cb8a3),
                                    // gated to pipeline managers.
                                    if permissionStore.can("pipeline.manage") {
                                        if isAdminOrOffice || permissionStore.can("catalog.view") {
                                            sectionDivider
                                        }
                                        settingsRow(
                                            icon: OPSStyle.Icons.phone,
                                            title: "Calls",
                                            action: { activeDestination = .pipelineSettings }
                                        )
                                    }
                                }
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            }

                            // App section — device-level preferences (everyone)
                            settingsSection(title: "APP") {
                                settingsRow(
                                    icon: OPSStyle.Icons.bellFill,
                                    title: "Notifications",
                                    action: { activeDestination = .notifications }
                                )

                                sectionDivider

                                settingsRow(
                                    icon: OPSStyle.Icons.map,
                                    title: "Map",
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

                                sectionDivider

                                Button(action: { activeDestination = .laserMeter }) {
                                    HStack(spacing: 14) {
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                            .frame(width: 28, alignment: .center)

                                        Text("Laser Meter")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryText)

                                        Spacer()

                                        if LaserMeterService.shared.connectionState == .connected {
                                            Circle()
                                                .fill(OPSStyle.Colors.successStatus)
                                                .frame(width: 8, height: 8)
                                        }

                                        Image(systemName: OPSStyle.Icons.chevronRight)
                                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    }
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

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

                                if isAdminOrOffice {
                                    sectionDivider

                                    settingsRow(
                                        icon: "trash",
                                        title: "Trash",
                                        action: { activeDestination = .trash }
                                    )
                                }
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

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
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                            // Developer section (conditional)
                            if shouldShowDeveloperOptions {
                                settingsSection(title: "DEVELOPER") {
                                    settingsRow(
                                        icon: "hammer.circle.fill",
                                        title: "Developer Tools",
                                        action: { activeDestination = .developerDashboard }
                                    )
                                }
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            }

                            // Log out button
                            logOutButton
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                .padding(.top, OPSStyle.Layout.spacing2)

                            // App version footer
                            appVersionFooter
                                .padding(.top, OPSStyle.Layout.spacing2)
                                .padding(.bottom, OPSStyle.Layout.spacing4)
                        }
                        .padding(.bottom, 90) // Tab bar padding
                    }
                    } // end of !isSettingsSearchActive branch (Bug G5)
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
        // Bug G5 — reset the header search when Settings disappears so a return
        // trip starts clean instead of lingering in a half-focused state.
        .onChange(of: appState.isSettingsSearchActive) { _, isActive in
            if !isActive {
                appState.settingsSearchQuery = ""
            }
        }
        .alert("Log Out", isPresented: $showLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                dataController.logout()
                ToastCenter.shared.present(Feedback.Settings.loggedOut)
            }
        } message: {
            Text("Are you sure you want to log out of your account?")
        }
        // MARK: - Navigation Cover (consolidated enum-based)
        // Bug e33aa336 — when a search result targets a sub-section inside a
        // page (e.g. "Set Color" deep inside Task Types), the destination is
        // wrapped in a `SettingsDeepLinkHost` that broadcasts the pending
        // section ID once the view has had time to mount. Sub-views that opt
        // in observe `SettingsDeepLink.<destination>` and scroll to the
        // matching anchor. When `pendingDeepLinkSection` is nil, the host is
        // a no-op and the destination behaves exactly as before.
        .fullScreenCover(item: $activeDestination) { destination in
            SettingsDeepLinkHost(
                destination: destination,
                section: pendingDeepLinkSection
            ) {
                settingsDestinationView(for: destination)
                    .wizardBannerIfAvailable(stateManager: wizardStateManager)
                    .wizardOverlayIfAvailable(stateManager: wizardStateManager)
            }
        }
        .onChange(of: activeDestination) { oldValue, newValue in
            if oldValue == .developerDashboard {
                developerModeEnabled = UserDefaults.standard.bool(forKey: "developerModeEnabled")
                #if DEBUG
                if !developerModeEnabled && UserDefaults.standard.object(forKey: "developerModeEnabled") != nil {
                    developerModeExplicitlyDisabled = true
                }
                #endif
            }
            // Once the cover is dismissed, the pending section has done its
            // job (the sub-view either consumed it or didn't recognize it).
            // Clear so the next cover doesn't inherit a stale ID.
            if newValue == nil {
                pendingDeepLinkSection = nil
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
        // Bug 4014b472 — with Manage Team promoted to a top-level row, wizards can
        // target it directly instead of the two-hop dance through Organization.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SettingsOpenManageTeam"))) { _ in
            activeDestination = .manageTeam
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SettingsOpenPermissions"))) { _ in
            activeDestination = .permissions
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardDismissSettingsCovers"))) { _ in
            activeDestination = nil
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
                ProductsServicesSettingsView()
                    .environmentObject(dataController)
            }
        case .integrations:
            NavigationStack {
                IntegrationsSettingsView()
                    .environmentObject(dataController)
            }
        case .projectSettings:
            NavigationStack {
                ProjectRulesView()
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
        case .trash:
            NavigationStack {
                TrashView()
                    .environmentObject(dataController)
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
        case .laserMeter:
            NavigationStack {
                LaserMeterSettingsView()
            }
        // Bug e33aa336 — direct routes to sub-pages so search can land the
        // user one tap closer to where they were trying to go. Each one is
        // the same view a regular drill-in would mount; only the entry point
        // changed.
        case .organizationDetails:
            NavigationStack {
                OrganizationDetailsView()
                    .environmentObject(dataController)
            }
        case .manageTeam:
            NavigationStack {
                ManageTeamView()
                    .environmentObject(dataController)
                    .environmentObject(SubscriptionManager.shared)
                    .environmentObject(permissionStore)
            }
        case .taskTypes:
            NavigationStack {
                TaskSettingsView()
                    .environmentObject(dataController)
            }
        case .inventorySettings:
            NavigationStack {
                InventorySettingsView()
                    .environmentObject(dataController)
            }
        case .pipelineSettings:
            NavigationStack {
                PipelineSettingsView()
                    .environmentObject(dataController)
            }
        }
    }

    // MARK: - Settings Search Results (Bug G5 + Bug e33aa336)

    /// Live results list that replaces the settings content while the header
    /// search is focused.
    ///
    /// Bug e33aa336 — results are now drawn from `SettingsSearchIndex`, which
    /// includes deep entries like "Project Settings › Task Types › Set Color".
    /// Each row shows a breadcrumb path so it's obvious where the tap will
    /// land, and the route carries a `section` identifier so the sub-page can
    /// scroll directly to the matching control instead of dumping the user
    /// at the top of the page.
    private var settingsSearchResults: some View {
        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing2_5) {
                let query = appState.settingsSearchQuery.trimmingCharacters(in: .whitespaces)
                let entries = SettingsSearchIndex.build(permissionStore: permissionStore)
                let results = query.isEmpty
                    ? []
                    : entries.filter { $0.matches(query: query) }

                if query.isEmpty {
                    searchEmptyState
                        .padding(.top, 60)
                } else if results.isEmpty {
                    searchNoResults(query: query)
                        .padding(.top, 60)
                } else {
                    HStack {
                        Text("\(results.count) RESULT\(results.count == 1 ? "" : "S")")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .tracking(0.5)
                        Spacer()
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing3)

                    ForEach(results) { entry in
                        settingsSearchResultRow(for: entry)
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    }
                }
            }
            .padding(.bottom, 90) // Tab bar padding
        }
    }

    private var searchEmptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: OPSStyle.Icons.search)
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("SEARCH SETTINGS")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .tracking(0.5)

            Text("Find profile, organization, or app settings")
                .font(OPSStyle.Typography.smallBody)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
    }

    private func searchNoResults(query: String) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: OPSStyle.Icons.search)
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("NO RESULTS")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .tracking(0.5)

            Text("No settings match \u{201C}\(query)\u{201D}")
                .font(OPSStyle.Typography.smallBody)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
    }

    /// Single row for a `SettingsSearchEntry`. Layout:
    ///   icon  |  TITLE                           |  >
    ///         |  CRUMB › CRUMB › CRUMB           |
    /// The breadcrumb sits below the title in `secondaryText` so the user can
    /// tell at a glance how deep the result lives — "Set Color" alone could
    /// belong to anything; "Project Settings › Task Types" makes the parent
    /// hierarchy visible without consuming the title slot.
    private func settingsSearchResultRow(for entry: SettingsSearchEntry) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Close the search on commit so returning from the destination
            // leaves Settings in its default state.
            withAnimation(OPSStyle.Animation.spring) {
                appState.isSettingsSearchActive = false
                appState.settingsSearchQuery = ""
            }
            // Stash the section identifier first so the destination view can
            // pick it up the moment fullScreenCover mounts. Then flip the
            // destination — the order matters because `activeDestination`
            // changing is what triggers the cover, and the cover's content
            // closure is evaluated immediately.
            pendingDeepLinkSection = entry.route.section
            applyRoute(entry.route)
        }) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: entry.icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: 28, height: 28, alignment: .center)
                    .padding(.top, 2) // Optical alignment with first text line

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(entry.title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    breadcrumbPath(entry.breadcrumb)
                }

                Spacer(minLength: 8)

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.top, OPSStyle.Layout.spacing1) // Match icon alignment
            }
            .padding(.vertical, 14)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Breadcrumb path renderer: "PROJECT SETTINGS › TASK TYPES" with the
    /// chevron rendered in `tertiaryText` so the path reads cleanly without
    /// the separators competing with the crumbs themselves. Wraps to a
    /// second line on long paths instead of truncating — long paths are
    /// usually the most useful results.
    @ViewBuilder
    private func breadcrumbPath(_ crumbs: [String]) -> some View {
        // Non-breaking space + chevron + non-breaking space, so SwiftUI
        // breaks between crumbs (not between a crumb and its separator).
        let separator = "\u{00A0}\u{203A}\u{00A0}"
        let joined = crumbs.map { $0.uppercased() }.joined(separator: separator)
        Text(joined)
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .tracking(0.5)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Translate a `SettingsRoute` into the existing fullScreenCover system.
    /// Most cases set `activeDestination` directly. A handful (Manage Team,
    /// Org Details, Task Types, Inventory Settings) used to be reachable only
    /// by drilling through their parent page; we now have dedicated enum cases
    /// so search lands the user one tap closer.
    private func applyRoute(_ route: SettingsRoute) {
        switch route.destination {
        case .profile:               activeDestination = .profile
        case .organization:          activeDestination = .organization
        case .organizationDetails:   activeDestination = .organizationDetails
        case .manageTeam:            activeDestination = .manageTeam
        case .subscription:          activeDestination = .subscription
        case .notifications:         activeDestination = .notifications
        case .map:                   activeDestination = .map
        case .dataStorage:           activeDestination = .dataStorage
        case .security:              activeDestination = .security
        case .productsServices:      activeDestination = .productsServices
        case .integrations:          activeDestination = .integrations
        case .projectSettings:       activeDestination = .projectSettings
        case .taskTypes:             activeDestination = .taskTypes
        case .allPhotos:             activeDestination = .allPhotos
        case .myExpenses:            activeDestination = .myExpenses
        case .reviewExpenses:        activeDestination = .reviewExpenses
        case .permissions:           activeDestination = .permissions
        case .laserMeter:            activeDestination = .laserMeter
        case .inventorySettings:    activeDestination = .inventorySettings
        case .whatsNew:              activeDestination = .whatsNew
        case .reportIssue:           activeDestination = .reportIssue
        case .wizardManagement:      activeDestination = .wizardManagement
        case .trash:                 activeDestination = .trash
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        Button(action: { activeDestination = .profile }) {
            HStack(spacing: 14) {
                // Avatar
                profileAvatar

                // Name and subtitle
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text((dataController.currentUser?.fullName ?? "User").uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    HStack(spacing: OPSStyle.Layout.spacing1) {
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
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .glassSurface()
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
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Section header
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Grouped card
            VStack(spacing: 0) {
                content()
            }
            .glassSurface()
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
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Gated Row (feature-flagged)

    private func gatedSettingsRow(icon: String, title: String) -> some View {
        Button(action: { ToastCenter.shared.present(Feedback.Settings.featureInTesting) }) {
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
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(OPSStyle.Colors.tertiaryText.opacity(0.15))
                    )
            }
            .padding(.vertical, 14)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
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
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
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
