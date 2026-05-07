//
//  SettingsSearchIndex.swift
//  OPS
//
//  Bug e33aa336 — granular settings search with breadcrumbs and deep-links.
//
//  This is the single source of truth for what the in-header settings search
//  can find. Every searchable surface — top-level page, section header, or
//  individual control inside a sub-page — is registered here as a
//  `SettingsSearchEntry`. Each entry knows its breadcrumb path (e.g.
//  ["Project Settings", "Task Types"]) and a `SettingsRoute` payload that
//  tells the navigation layer which destination to open and which section to
//  scroll to once it's open.
//
//  Why a centralized index instead of letting each sub-view register itself:
//  Settings sub-views are presented via `fullScreenCover`, so they aren't in
//  the view hierarchy until tapped. We need every entry to be searchable
//  before any cover is mounted, which means the index has to exist outside
//  the views themselves. Permission-gating happens here too (build-time
//  filtering against PermissionStore) so role-restricted entries never show
//  up in results for users who can't reach them.
//
//  Two-stage navigation model:
//   1. `SettingsRoute.destination` opens the matching `fullScreenCover` —
//      same enum SettingsView already uses, no new presentation surface.
//   2. `SettingsRoute.section` (optional) is broadcast as a NotificationCenter
//      payload AFTER the cover settles. Sub-views with deep-link awareness
//      observe their own scoped notification name and use ScrollViewReader
//      to bring the matching section into view + briefly highlight it.
//
//  When a sub-view doesn't know about a section ID, the deep-link is a no-op
//  and the user just lands on the page — graceful degradation, never broken.

import SwiftUI

// MARK: - Settings Route

/// Where a tapped search result should send the user. Pairs the top-level
/// destination (one of the existing `fullScreenCover` cases in SettingsView)
/// with an optional section identifier the destination listens for.
struct SettingsRoute: Equatable {
    /// Top-level destination — matches SettingsView's `SettingsDestination`
    /// enum cases. Strings are used here (instead of importing the enum) so
    /// this file stays self-contained and the entries can be defined where
    /// the source files for sub-views can't see SettingsDestination.
    let destination: Destination

    /// Optional section identifier inside the destination. When non-nil, the
    /// destination's view scrolls to the matching anchor on appear.
    let section: String?

    enum Destination: String, Equatable {
        case profile
        case organization
        case organizationDetails
        case manageTeam
        case subscription
        case notifications
        case map
        case dataStorage
        case security
        case productsServices
        case integrations
        case projectSettings
        case taskTypes
        case schedulingType
        case allPhotos
        case myExpenses
        case reviewExpenses
        case permissions
        case laserMeter
        case inventorySettings
        case whatsNew
        case reportIssue
        case wizardManagement
        case trash
    }

    init(_ destination: Destination, section: String? = nil) {
        self.destination = destination
        self.section = section
    }
}

// MARK: - Settings Search Entry

/// A single searchable surface in settings. Replaces the legacy
/// `SearchableSettingItem` — same matching rules, but now carries a
/// breadcrumb path for display and a typed route for navigation.
struct SettingsSearchEntry: Identifiable, Equatable {
    /// Stable string ID derived from breadcrumb + title so SwiftUI's
    /// `ForEach` diffing doesn't churn between identical-looking entries.
    let id: String

    /// Final-step name shown as the row's primary label.
    /// Example: "Set Color" when breadcrumb ends in "Task Types".
    let title: String

    /// Path from the top-level page to this entry, parent-first. The row
    /// renders "PROJECT SETTINGS › TASK TYPES › SET COLOR" from this.
    /// Always at least 1 element; top-level pages are a single-element path.
    let breadcrumb: [String]

    /// SF Symbol shown in the row's icon slot. Mirrors the icon of the
    /// nearest container — the page or section the entry belongs to —
    /// so results feel anchored to a familiar visual.
    let icon: String

    /// Lowercased keyword pool for fuzzy-ish matching. The query is matched
    /// against title, breadcrumb crumbs, and these keywords.
    let keywords: [String]

    /// Where tapping the result should navigate.
    let route: SettingsRoute

    init(
        title: String,
        breadcrumb: [String],
        icon: String,
        keywords: [String],
        route: SettingsRoute
    ) {
        // Stable ID — breadcrumb path + title. Two entries with the same
        // breadcrumb + title would collide, which is intentional: the index
        // builder shouldn't be registering duplicates.
        self.id = (breadcrumb + [title]).joined(separator: "/").lowercased()
        self.title = title
        self.breadcrumb = breadcrumb
        self.icon = icon
        self.keywords = keywords
        self.route = route
    }

    /// Match a query against title, breadcrumb crumbs, and keywords. Any hit
    /// in any of those returns true. Match is case-insensitive substring.
    func matches(query: String) -> Bool {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return false }

        if title.lowercased().contains(q) { return true }
        if breadcrumb.contains(where: { $0.lowercased().contains(q) }) { return true }
        if keywords.contains(where: { $0.lowercased().contains(q) }) { return true }
        return false
    }
}

// MARK: - Deep-Link Notifications

/// Notification names sub-views observe to scroll/highlight the section a
/// search result targets. One name per top-level destination keeps the
/// observer surface narrow on each sub-view (no global "settings deep link"
/// firehose). The userInfo carries `"section"` — a string the sub-view
/// matches against its own internal section IDs.
enum SettingsDeepLink {
    static let userInfoSectionKey = "section"

    static let profile           = Notification.Name("SettingsDeepLink.profile")
    static let organization      = Notification.Name("SettingsDeepLink.organization")
    static let manageTeam        = Notification.Name("SettingsDeepLink.manageTeam")
    static let subscription      = Notification.Name("SettingsDeepLink.subscription")
    static let notifications     = Notification.Name("SettingsDeepLink.notifications")
    static let map               = Notification.Name("SettingsDeepLink.map")
    static let dataStorage       = Notification.Name("SettingsDeepLink.dataStorage")
    static let security          = Notification.Name("SettingsDeepLink.security")
    static let projectSettings   = Notification.Name("SettingsDeepLink.projectSettings")
    static let taskTypes         = Notification.Name("SettingsDeepLink.taskTypes")
    static let permissions       = Notification.Name("SettingsDeepLink.permissions")
    static let inventorySettings = Notification.Name("SettingsDeepLink.inventorySettings")
    static let integrations      = Notification.Name("SettingsDeepLink.integrations")
    static let productsServices  = Notification.Name("SettingsDeepLink.productsServices")
    static let laserMeter        = Notification.Name("SettingsDeepLink.laserMeter")

    /// Map a destination to its corresponding notification name. Keeping
    /// this here (instead of in SettingsView) means the host wrapper doesn't
    /// need to import the SettingsDestination enum to dispatch.
    static func notificationName(for destinationRaw: String) -> Notification.Name? {
        switch destinationRaw {
        case "profile":             return profile
        case "organization":        return organization
        case "manageTeam":          return manageTeam
        case "subscription":        return subscription
        case "notifications":       return notifications
        case "map":                 return map
        case "dataStorage":         return dataStorage
        case "security":            return security
        case "projectSettings":     return projectSettings
        case "taskTypes":           return taskTypes
        case "permissions":         return permissions
        case "inventorySettings":   return inventorySettings
        case "integrations":        return integrations
        case "productsServices":    return productsServices
        case "laserMeter":          return laserMeter
        default:                    return nil
        }
    }
}

// MARK: - Deep-Link Host Wrapper

/// Wraps a settings destination view and, on appear, broadcasts the section
/// the user wanted to land on so the sub-view can scroll/highlight it. The
/// wrapper is intentionally generic — it doesn't know what the destination
/// is, only its raw value (so the notification name can be resolved) and an
/// optional section string.
///
/// Why a slight delay before posting: `fullScreenCover` mounts the content
/// view, but ScrollViewReader inside that content doesn't have its proxy
/// wired up until the view's first layout pass completes. Posting on the
/// next runloop tick gives the destination's observer a stable proxy to
/// scroll with. 250ms is conservative enough for older devices and short
/// enough that the user perceives the scroll as part of the cover landing.
struct SettingsDeepLinkHost<Content: View, Destination: RawRepresentable>: View where Destination.RawValue == String {
    let destination: Destination
    let section: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .task {
                // No section requested → behave exactly like the un-wrapped
                // destination. No notification, no delay, no surprise.
                guard let section, !section.isEmpty else { return }
                guard let name = SettingsDeepLink.notificationName(for: destination.rawValue) else { return }

                // Wait for the destination's view tree to finish its first
                // layout pass. .task already runs after onAppear, but the
                // ScrollViewReader proxy needs one additional run-loop turn
                // before scrollTo will actually find the anchor.
                try? await Task.sleep(nanoseconds: 250_000_000)

                NotificationCenter.default.post(
                    name: name,
                    object: nil,
                    userInfo: [SettingsDeepLink.userInfoSectionKey: section]
                )
            }
    }
}

// MARK: - Deep-Link Spotlight Modifier

/// View modifier that briefly highlights a settings section when a search
/// deep-link lands on it. Renders as a soft accent-colored border + tinted
/// fill that pulses up over 200ms, holds for ~1.2s, then fades out — long
/// enough for the user's eye to find it, short enough that it doesn't
/// linger and bleed visual noise into normal settings interactions.
///
/// `isActive` is owned by the destination view (driven by an internal
/// @State that the deep-link observer flips on, then off after a delay).
/// When false, the modifier is a pure no-op so unmarked sections render
/// identically to before.
struct DeepLinkSpotlightModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius + 4)
                    .stroke(
                        isActive ? OPSStyle.Colors.primaryAccent : Color.clear,
                        lineWidth: 2
                    )
                    .padding(-6) // Pulled outside the card so the glow reads as a spotlight, not a border swap
                    .opacity(isActive ? 1.0 : 0.0)
                    .allowsHitTesting(false)
            )
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                    .fill(OPSStyle.Colors.primaryAccent.opacity(isActive ? 0.08 : 0.0))
                    .padding(-2)
            )
    }
}

extension View {
    /// Apply a transient highlight when a settings search deep-link lands on
    /// this section. Pass an `@State` boolean owned by the destination view.
    func deepLinkSpotlight(_ isActive: Bool) -> some View {
        modifier(DeepLinkSpotlightModifier(isActive: isActive))
    }
}

// MARK: - Settings Search Index Builder

/// Builds the full searchable index for the current user. Permission gates
/// are evaluated at build time, so callers don't need to filter results
/// later — what comes out of `build(...)` is already scoped to what the
/// user can actually open.
enum SettingsSearchIndex {

    /// Build the live index. Caller passes the permission store + a flag
    /// for whether expenses are visible to the current user (since that
    /// gate is checked the same way in two places and we'd rather pass the
    /// resolved bool than re-resolve here).
    static func build(permissionStore: PermissionStore) -> [SettingsSearchEntry] {
        var entries: [SettingsSearchEntry] = []

        let isAdmin = permissionStore.can("settings.company")
        let isAdminOrOffice = permissionStore.can("team.view")
        let hasPipelineAccess = permissionStore.can("pipeline.view")
        let canViewOwnExpenses = permissionStore.can("expenses.view", requiredScope: "own")
        let canApproveExpenses = permissionStore.can("expenses.approve")
        let hasInventoryAccess = permissionStore.can("catalog.view")
        let hasFinanceView = permissionStore.can("finances.view")

        // ─── ACCOUNT ─────────────────────────────────────────────────────

        entries.append(contentsOf: profileEntries())
        entries.append(contentsOf: organizationEntries(isAdmin: isAdmin, isAdminOrOffice: isAdminOrOffice))

        if isAdmin {
            entries.append(contentsOf: subscriptionEntries())
        }

        // ─── APP ─────────────────────────────────────────────────────────

        entries.append(contentsOf: notificationEntries())
        entries.append(contentsOf: mapEntries())
        entries.append(contentsOf: dataStorageEntries())
        entries.append(contentsOf: securityEntries())
        entries.append(contentsOf: laserMeterEntries())

        // ─── DATA ────────────────────────────────────────────────────────

        entries.append(contentsOf: photosEntries())

        if canViewOwnExpenses {
            entries.append(contentsOf: myExpensesEntries())
        }

        if canApproveExpenses {
            entries.append(contentsOf: reviewExpensesEntries())
        }

        if isAdminOrOffice {
            entries.append(contentsOf: trashEntries())
        }

        // ─── BUSINESS ────────────────────────────────────────────────────

        if hasPipelineAccess {
            entries.append(contentsOf: productsAndServicesEntries())
            entries.append(contentsOf: integrationsEntries())
        }

        if isAdminOrOffice {
            entries.append(contentsOf: projectSettingsEntries(hasFinanceView: hasFinanceView))
        }

        if hasInventoryAccess {
            entries.append(contentsOf: inventorySettingsEntries())
        }

        if isAdmin {
            entries.append(contentsOf: permissionsEntries())
        }

        // ─── SUPPORT ─────────────────────────────────────────────────────

        entries.append(contentsOf: supportEntries())

        return entries
    }

    // MARK: - Profile

    private static func profileEntries() -> [SettingsSearchEntry] {
        let breadcrumb = ["Profile"]
        let icon = OPSStyle.Icons.person
        let route: (String?) -> SettingsRoute = { SettingsRoute(.profile, section: $0) }

        return [
            // Top-level page entry
            SettingsSearchEntry(
                title: "Profile",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: ["profile", "my info", "my profile", "personal", "account info"],
                route: route(nil)
            ),
            // Sub-controls
            SettingsSearchEntry(
                title: "Edit Personal Information",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: ["name", "first name", "last name", "phone", "personal information", "edit profile"],
                route: route("personal_information")
            ),
            SettingsSearchEntry(
                title: "Profile Photo",
                breadcrumb: breadcrumb,
                icon: "camera.fill",
                keywords: ["avatar", "photo", "picture", "profile photo", "headshot", "image"],
                route: route("personal_information")
            ),
            SettingsSearchEntry(
                title: "Home Address",
                breadcrumb: breadcrumb + ["Personal Information"],
                icon: "house",
                keywords: ["home address", "address", "where i live", "street", "city", "postal", "zip"],
                route: route("home_address")
            ),
            SettingsSearchEntry(
                title: "Reset Password",
                breadcrumb: breadcrumb + ["Credentials"],
                icon: "lock.rotation",
                keywords: ["password", "change password", "reset password", "login", "credentials"],
                route: route("credentials")
            ),
            SettingsSearchEntry(
                title: "Delete Account",
                breadcrumb: breadcrumb,
                icon: "trash",
                keywords: ["delete account", "delete my account", "remove account", "close account", "permanent action"],
                route: route("delete_account")
            ),
        ]
    }

    // MARK: - Organization

    private static func organizationEntries(isAdmin: Bool, isAdminOrOffice: Bool) -> [SettingsSearchEntry] {
        let breadcrumb = ["Organization"]
        let icon = "building.2.fill"
        let route: (String?) -> SettingsRoute = { SettingsRoute(.organization, section: $0) }

        var items: [SettingsSearchEntry] = [
            SettingsSearchEntry(
                title: "Organization",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: ["company", "business", "organization", "org", "company info"],
                route: route(nil)
            ),
            SettingsSearchEntry(
                title: "Company Details",
                breadcrumb: breadcrumb + ["Organization Details"],
                icon: icon,
                keywords: ["company name", "company logo", "logo", "company details", "company phone", "company email", "company address", "website", "tax id"],
                route: SettingsRoute(.organizationDetails)
            ),
        ]

        if isAdmin || isAdminOrOffice {
            items.append(
                SettingsSearchEntry(
                    title: "Manage Team",
                    breadcrumb: breadcrumb,
                    icon: "person.3.fill",
                    keywords: [
                        "team", "members", "employees", "crew", "staff", "people",
                        "team management", "manage crew", "remove member", "fire",
                        "edit role", "assign role", "change role"
                    ],
                    route: SettingsRoute(.manageTeam)
                )
            )
            items.append(
                SettingsSearchEntry(
                    title: "Invite Team Member",
                    breadcrumb: breadcrumb + ["Manage Team"],
                    icon: "person.crop.circle.badge.plus",
                    keywords: [
                        "invite", "invite team", "invite member", "invite employee",
                        "add member", "add employee", "add crew", "hire", "onboard",
                        "send invite"
                    ],
                    route: SettingsRoute(.manageTeam, section: "invite")
                )
            )
            items.append(
                SettingsSearchEntry(
                    title: "Crew Code",
                    breadcrumb: breadcrumb + ["Manage Team"],
                    icon: "qrcode",
                    keywords: ["crew code", "join code", "company code", "invite code", "share code"],
                    route: SettingsRoute(.manageTeam, section: "crew_code")
                )
            )
            items.append(
                SettingsSearchEntry(
                    title: "Manage Seats",
                    breadcrumb: breadcrumb + ["Manage Team"],
                    icon: "person.2.badge.gearshape",
                    keywords: ["seats", "seat count", "available seats", "seat management", "buy seats"],
                    route: SettingsRoute(.manageTeam, section: "seats")
                )
            )
        }

        return items
    }

    // MARK: - Subscription

    private static func subscriptionEntries() -> [SettingsSearchEntry] {
        let breadcrumb = ["Subscription"]
        let icon = "creditcard"
        let route: (String?) -> SettingsRoute = { SettingsRoute(.subscription, section: $0) }

        return [
            SettingsSearchEntry(
                title: "Subscription",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: ["subscription", "plan", "billing", "payment", "renewal", "trial", "pricing"],
                route: route(nil)
            ),
            SettingsSearchEntry(
                title: "Change Plan",
                breadcrumb: breadcrumb,
                icon: "arrow.up.arrow.down.circle",
                keywords: ["change plan", "upgrade", "downgrade", "switch plan", "different plan"],
                route: route("change_plan")
            ),
            SettingsSearchEntry(
                title: "Cancel Subscription",
                breadcrumb: breadcrumb,
                icon: "xmark.circle",
                keywords: ["cancel", "cancel subscription", "stop billing", "end subscription"],
                route: route("cancel")
            ),
            SettingsSearchEntry(
                title: "Billing History",
                breadcrumb: breadcrumb,
                icon: "doc.text",
                keywords: ["billing", "invoices", "receipts", "billing history", "past charges", "payment history"],
                route: route("billing_history")
            ),
        ]
    }

    // MARK: - Notifications

    private static func notificationEntries() -> [SettingsSearchEntry] {
        let breadcrumb = ["Notifications"]
        let icon = OPSStyle.Icons.bellFill
        let route: (String?) -> SettingsRoute = { SettingsRoute(.notifications, section: $0) }

        return [
            SettingsSearchEntry(
                title: "Notifications",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: ["notifications", "alerts", "push", "reminders", "sounds", "badges"],
                route: route(nil)
            ),
            SettingsSearchEntry(
                title: "Project Notifications",
                breadcrumb: breadcrumb,
                icon: "briefcase.fill",
                keywords: [
                    "project notifications", "task assigned", "task completed",
                    "schedule changes", "project updates", "team mentions",
                    "project alerts", "task alerts"
                ],
                route: route("project_notifications")
            ),
            SettingsSearchEntry(
                title: "Financial Notifications",
                breadcrumb: breadcrumb,
                icon: "dollarsign.circle",
                keywords: [
                    "financial notifications", "expense submitted", "expense approved",
                    "invoice sent", "payment received", "money alerts", "billing alerts"
                ],
                route: route("financial_notifications")
            ),
            SettingsSearchEntry(
                title: "Daily Digest",
                breadcrumb: breadcrumb + ["Other"],
                icon: "sun.max",
                keywords: ["daily digest", "morning summary", "daily summary", "digest"],
                route: route("other_notifications")
            ),
            SettingsSearchEntry(
                title: "Quiet Hours",
                breadcrumb: breadcrumb,
                icon: "moon.zzz",
                keywords: ["quiet hours", "do not disturb", "dnd", "mute hours", "night mode notifications"],
                route: route("quiet_hours")
            ),
            SettingsSearchEntry(
                title: "Advance Reminders",
                breadcrumb: breadcrumb,
                icon: "clock.badge",
                keywords: ["advance reminders", "advance notice", "reminder days before", "early reminders", "heads up"],
                route: route("advance_reminders")
            ),
            SettingsSearchEntry(
                title: "Test Notification",
                breadcrumb: breadcrumb,
                icon: "bell.badge",
                keywords: ["test notification", "test push", "send test", "try notification"],
                route: route("test_notifications")
            ),
            SettingsSearchEntry(
                title: "Temporary Mute",
                breadcrumb: breadcrumb,
                icon: "speaker.slash",
                keywords: ["mute", "temporary mute", "silence", "pause notifications", "mute for hour"],
                route: route("temporary_mute")
            ),
        ]
    }

    // MARK: - Map

    private static func mapEntries() -> [SettingsSearchEntry] {
        let breadcrumb = ["Map Settings"]
        let icon = OPSStyle.Icons.map
        let route: (String?) -> SettingsRoute = { SettingsRoute(.map, section: $0) }

        return [
            SettingsSearchEntry(
                title: "Map Settings",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: ["map", "navigation", "gps", "directions", "location"],
                route: route(nil)
            ),
            SettingsSearchEntry(
                title: "3D Buildings",
                breadcrumb: breadcrumb + ["Map Appearance"],
                icon: "building.2.crop.circle",
                keywords: ["3d", "buildings", "3d buildings", "tilt", "map appearance", "satellite", "map style"],
                route: route("map_appearance")
            ),
            SettingsSearchEntry(
                title: "Default Filter",
                breadcrumb: breadcrumb + ["Default View"],
                icon: "line.3.horizontal.decrease.circle",
                keywords: ["default filter", "default view", "today active", "all projects on map"],
                route: route("default_view")
            ),
            SettingsSearchEntry(
                title: "Default Orientation",
                breadcrumb: breadcrumb + ["Camera"],
                icon: "compass.drawing",
                keywords: ["orientation", "north up", "track up", "course up", "rotation", "compass"],
                route: route("camera")
            ),
            SettingsSearchEntry(
                title: "Auto Center",
                breadcrumb: breadcrumb + ["Camera"],
                icon: "scope",
                keywords: ["auto center", "recenter", "re-center", "center map", "auto camera"],
                route: route("camera")
            ),
            SettingsSearchEntry(
                title: "Auto Zoom",
                breadcrumb: breadcrumb + ["Camera"],
                icon: "plus.magnifyingglass",
                keywords: ["zoom", "auto zoom", "zoom level", "default zoom"],
                route: route("camera")
            ),
            SettingsSearchEntry(
                title: "Speed-Based Zoom",
                breadcrumb: breadcrumb + ["Navigation"],
                icon: "speedometer",
                keywords: ["speed zoom", "highway zoom", "speed-based", "auto zoom highway", "navigation zoom"],
                route: route("navigation")
            ),
        ]
    }

    // MARK: - Data & Storage

    private static func dataStorageEntries() -> [SettingsSearchEntry] {
        let breadcrumb = ["Data & Storage"]
        let icon = "externaldrive"
        let route: (String?) -> SettingsRoute = { SettingsRoute(.dataStorage, section: $0) }

        return [
            SettingsSearchEntry(
                title: "Data & Storage",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: ["data", "storage", "cache", "offline", "sync", "disk"],
                route: route(nil)
            ),
            SettingsSearchEntry(
                title: "Sync on App Launch",
                breadcrumb: breadcrumb + ["Synchronization"],
                icon: "arrow.triangle.2.circlepath",
                keywords: ["sync on launch", "auto sync", "launch sync", "startup sync"],
                route: route("synchronization")
            ),
            SettingsSearchEntry(
                title: "Background Sync",
                breadcrumb: breadcrumb + ["Synchronization"],
                icon: "arrow.clockwise.circle",
                keywords: ["background sync", "sync in background", "auto sync", "sync when closed"],
                route: route("synchronization")
            ),
            SettingsSearchEntry(
                title: "Historical Data Range",
                breadcrumb: breadcrumb + ["Synchronization"],
                icon: "calendar.badge.clock",
                keywords: ["historical data", "data range", "how far back", "history", "months of data"],
                route: route("synchronization")
            ),
            SettingsSearchEntry(
                title: "Photo Storage",
                breadcrumb: breadcrumb,
                icon: OPSStyle.Icons.photo,
                keywords: ["photo storage", "photo budget", "photo limit", "storage cap", "photos"],
                route: route("photo_storage")
            ),
            SettingsSearchEntry(
                title: "Auto-Download Photos",
                breadcrumb: breadcrumb + ["Auto-Download"],
                icon: "icloud.and.arrow.down",
                keywords: ["auto download", "prefetch photos", "download photos", "photo prefetch"],
                route: route("auto_download")
            ),
            SettingsSearchEntry(
                title: "Clear Image Cache",
                breadcrumb: breadcrumb + ["Data Management"],
                icon: OPSStyle.Icons.photo,
                keywords: ["clear cache", "clear image cache", "free space", "delete cache", "reset cache"],
                route: route("data_management")
            ),
        ]
    }

    // MARK: - Security & Privacy

    private static func securityEntries() -> [SettingsSearchEntry] {
        let breadcrumb = ["Security & Privacy"]
        let icon = "lock"
        let route: (String?) -> SettingsRoute = { SettingsRoute(.security, section: $0) }

        return [
            SettingsSearchEntry(
                title: "Security & Privacy",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: ["security", "privacy", "lock", "pin", "password", "biometric", "authentication"],
                route: route(nil)
            ),
            SettingsSearchEntry(
                title: "Require PIN on Launch",
                breadcrumb: breadcrumb + ["App Access"],
                icon: "lock.shield",
                keywords: [
                    "pin", "lock app", "require pin", "passcode", "app lock",
                    "lock it down", "secure app", "lock on launch"
                ],
                route: route("app_access")
            ),
            SettingsSearchEntry(
                title: "Change PIN",
                breadcrumb: breadcrumb + ["App Access"],
                icon: "lock.rotation",
                keywords: ["change pin", "update pin", "new pin", "reset pin"],
                route: route("app_access")
            ),
            SettingsSearchEntry(
                title: "Reset Password",
                breadcrumb: breadcrumb + ["Account Security"],
                icon: "lock.shield",
                keywords: ["reset password", "change password", "forgot password", "update password"],
                route: route("account_security")
            ),
        ]
    }

    // MARK: - Laser Meter

    private static func laserMeterEntries() -> [SettingsSearchEntry] {
        let breadcrumb = ["Laser Meter"]
        let icon = "antenna.radiowaves.left.and.right"
        let route: (String?) -> SettingsRoute = { SettingsRoute(.laserMeter, section: $0) }

        return [
            SettingsSearchEntry(
                title: "Laser Meter",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: [
                    "laser", "laser meter", "bluetooth", "ble", "bosch", "leica",
                    "disto", "glm", "distance", "measure", "tape measure", "rangefinder"
                ],
                route: route(nil)
            ),
            SettingsSearchEntry(
                title: "Pair Laser Meter",
                breadcrumb: breadcrumb,
                icon: "dot.radiowaves.left.and.right",
                keywords: ["pair", "connect", "bluetooth pair", "pair device", "connect laser"],
                route: route("pair")
            ),
        ]
    }

    // MARK: - Photos

    private static func photosEntries() -> [SettingsSearchEntry] {
        let breadcrumb = ["Photos"]
        let icon = "photo.on.rectangle.angled"

        return [
            SettingsSearchEntry(
                title: "Photos",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: ["photos", "images", "pictures", "gallery", "all photos", "photo gallery", "browse photos"],
                route: SettingsRoute(.allPhotos)
            ),
        ]
    }

    private static func myExpensesEntries() -> [SettingsSearchEntry] {
        let breadcrumb = ["My Expenses"]
        let icon = "dollarsign.circle"

        return [
            SettingsSearchEntry(
                title: "My Expenses",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: [
                    "expenses", "my expenses", "receipts", "spending",
                    "expense report", "submit expense", "reimbursement", "mileage"
                ],
                route: SettingsRoute(.myExpenses)
            ),
        ]
    }

    private static func reviewExpensesEntries() -> [SettingsSearchEntry] {
        let breadcrumb = ["Review Expenses"]
        let icon = "doc.text.magnifyingglass"

        return [
            SettingsSearchEntry(
                title: "Review Expenses",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: [
                    "review expenses", "approve expenses", "expense approval",
                    "pending expenses", "reject expense", "submitted expenses"
                ],
                route: SettingsRoute(.reviewExpenses)
            ),
        ]
    }

    private static func trashEntries() -> [SettingsSearchEntry] {
        return [
            SettingsSearchEntry(
                title: "Trash",
                breadcrumb: ["Trash"],
                icon: "trash",
                keywords: ["trash", "deleted", "recycle bin", "recover", "restore", "deleted projects", "deleted tasks"],
                route: SettingsRoute(.trash)
            ),
        ]
    }

    // MARK: - Products & Services

    private static func productsAndServicesEntries() -> [SettingsSearchEntry] {
        let breadcrumb = ["Products & Services"]
        let icon = OPSStyle.Icons.productTag

        return [
            SettingsSearchEntry(
                title: "Products & Services",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: [
                    "products", "services", "catalog", "pricing", "labor", "material",
                    "line items", "price list", "service list"
                ],
                route: SettingsRoute(.productsServices)
            ),
            SettingsSearchEntry(
                title: "Add Product",
                breadcrumb: breadcrumb,
                icon: "plus.circle",
                keywords: ["add product", "create product", "new product", "add service", "create service"],
                route: SettingsRoute(.productsServices, section: "add_product")
            ),
        ]
    }

    // MARK: - Integrations

    private static func integrationsEntries() -> [SettingsSearchEntry] {
        let breadcrumb = ["Integrations"]
        let icon = OPSStyle.Icons.accountingChart

        return [
            SettingsSearchEntry(
                title: "Integrations",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: [
                    "integrations", "accounting", "third party", "api", "connect",
                    "external", "bookkeeping", "export", "import"
                ],
                route: SettingsRoute(.integrations)
            ),
            SettingsSearchEntry(
                title: "QuickBooks Online",
                breadcrumb: breadcrumb + ["Accounting"],
                icon: "building.columns.fill",
                keywords: ["quickbooks", "qbo", "intuit", "quickbooks online", "qb online"],
                route: SettingsRoute(.integrations, section: "accounting")
            ),
            SettingsSearchEntry(
                title: "Sage",
                breadcrumb: breadcrumb + ["Accounting"],
                icon: "leaf.fill",
                keywords: ["sage", "sage accounting", "sage 50"],
                route: SettingsRoute(.integrations, section: "accounting")
            ),
        ]
    }

    // MARK: - Project Settings

    private static func projectSettingsEntries(hasFinanceView: Bool) -> [SettingsSearchEntry] {
        let breadcrumb = ["Project Settings"]
        let icon = "hammer.circle"
        let route: (String?) -> SettingsRoute = { SettingsRoute(.projectSettings, section: $0) }

        var items: [SettingsSearchEntry] = [
            SettingsSearchEntry(
                title: "Project Settings",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: ["project", "project defaults", "project configuration", "workflow"],
                route: route(nil)
            ),
            SettingsSearchEntry(
                title: "Task Types",
                breadcrumb: breadcrumb,
                icon: "square.grid.2x2",
                keywords: [
                    "task types", "task category", "task kind", "categorize tasks",
                    "task labels", "task tags", "types of tasks"
                ],
                route: SettingsRoute(.taskTypes)
            ),
            // The headline example from the bug — "Set Color" deep into Task Types
            SettingsSearchEntry(
                title: "Set Color",
                breadcrumb: breadcrumb + ["Task Types"],
                icon: "paintpalette",
                keywords: [
                    "color", "set color", "task color", "task type color",
                    "category color", "change color", "pick color", "edit color"
                ],
                route: SettingsRoute(.taskTypes, section: "edit_color")
            ),
            SettingsSearchEntry(
                title: "Add Task Type",
                breadcrumb: breadcrumb + ["Task Types"],
                icon: "plus.circle",
                keywords: ["add task type", "new task type", "create task type", "custom task type"],
                route: SettingsRoute(.taskTypes, section: "add_type")
            ),
            SettingsSearchEntry(
                title: "Rename Task Type",
                breadcrumb: breadcrumb + ["Task Types"],
                icon: "pencil",
                keywords: ["rename", "rename task type", "edit task type", "change task type name"],
                route: SettingsRoute(.taskTypes, section: "rename_type")
            ),
            SettingsSearchEntry(
                title: "Delete Task Type",
                breadcrumb: breadcrumb + ["Task Types"],
                icon: "trash",
                keywords: ["delete task type", "remove task type", "merge task type"],
                route: SettingsRoute(.taskTypes, section: "delete_type")
            ),
            SettingsSearchEntry(
                title: "Scheduling Type",
                breadcrumb: breadcrumb,
                icon: "calendar.badge.clock",
                keywords: [
                    "scheduling", "scheduling type", "schedule mode",
                    "appointment", "block", "schedule style"
                ],
                route: SettingsRoute(.schedulingType)
            ),
            SettingsSearchEntry(
                title: "Overdue Threshold",
                breadcrumb: breadcrumb + ["Project Review"],
                icon: "clock.badge.exclamationmark",
                keywords: [
                    "overdue", "overdue threshold", "overdue days", "review threshold",
                    "stale projects", "old projects flag"
                ],
                route: route("project_review")
            ),
            SettingsSearchEntry(
                title: "Reminder Frequency",
                breadcrumb: breadcrumb + ["Project Review"],
                icon: "bell.badge",
                keywords: [
                    "reminder frequency", "reminder days", "renotify",
                    "reminder cadence", "remind me about overdue"
                ],
                route: route("project_review")
            ),
        ]

        if hasFinanceView {
            items.append(
                SettingsSearchEntry(
                    title: "Match Invoice Payment Terms",
                    breadcrumb: breadcrumb + ["Project Review"],
                    icon: "doc.badge.gearshape",
                    keywords: [
                        "invoice terms", "net terms", "payment terms",
                        "match invoice", "use invoice terms"
                    ],
                    route: route("project_review")
                )
            )
        }

        return items
    }

    // MARK: - Inventory Settings

    private static func inventorySettingsEntries() -> [SettingsSearchEntry] {
        let breadcrumb = ["Inventory Settings"]
        let icon = "shippingbox.fill"
        let route: (String?) -> SettingsRoute = { SettingsRoute(.inventorySettings, section: $0) }

        return [
            SettingsSearchEntry(
                title: "Inventory Settings",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: [
                    "inventory", "stock", "warehouse", "materials", "supplies",
                    "inventory management", "quantity"
                ],
                route: route(nil)
            ),
            SettingsSearchEntry(
                title: "Inventory Snapshots",
                breadcrumb: breadcrumb + ["Snapshots"],
                icon: "camera.viewfinder",
                keywords: [
                    "snapshots", "inventory snapshots", "stock snapshot",
                    "point in time", "history snapshot"
                ],
                route: route("snapshots")
            ),
            SettingsSearchEntry(
                title: "Import Inventory",
                breadcrumb: breadcrumb + ["Import"],
                icon: "square.and.arrow.down",
                keywords: ["import", "import inventory", "csv import", "upload inventory", "bulk add"],
                route: route("import")
            ),
            SettingsSearchEntry(
                title: "Inventory Units",
                breadcrumb: breadcrumb + ["Units"],
                icon: "ruler",
                keywords: [
                    "units", "inventory units", "unit of measure", "uom",
                    "each", "feet", "meters", "custom units"
                ],
                route: route("units")
            ),
            SettingsSearchEntry(
                title: "Inventory Tags",
                breadcrumb: breadcrumb + ["Tags"],
                icon: "tag",
                keywords: [
                    "tags", "inventory tags", "labels", "categories",
                    "organize inventory", "filter inventory"
                ],
                route: route("tags")
            ),
            SettingsSearchEntry(
                title: "Quick Adjust",
                breadcrumb: breadcrumb + ["Quick Adjust"],
                icon: "slider.horizontal.3",
                keywords: ["quick adjust", "fast adjust", "rapid count", "fast count", "adjust amount"],
                route: route("quick_adjust")
            ),
        ]
    }

    // MARK: - Permissions

    private static func permissionsEntries() -> [SettingsSearchEntry] {
        let breadcrumb = ["Permissions"]
        let icon = "person.badge.key.fill"
        let route: (String?) -> SettingsRoute = { SettingsRoute(.permissions, section: $0) }

        return [
            SettingsSearchEntry(
                title: "Permissions",
                breadcrumb: breadcrumb,
                icon: icon,
                keywords: [
                    "permissions", "rbac", "access control", "who can",
                    "allow", "deny", "grant", "restrict"
                ],
                route: route(nil)
            ),
            SettingsSearchEntry(
                title: "Roles",
                breadcrumb: breadcrumb + ["Roles"],
                icon: "person.fill.badge.plus",
                keywords: [
                    "roles", "role list", "manage roles", "edit roles",
                    "admin role", "office role", "crew role", "custom role"
                ],
                route: route("roles")
            ),
            SettingsSearchEntry(
                title: "Add Custom Role",
                breadcrumb: breadcrumb + ["Roles"],
                icon: "plus.circle",
                keywords: ["add role", "new role", "create role", "custom role", "add custom role"],
                route: route("add_role")
            ),
            SettingsSearchEntry(
                title: "Team Permissions",
                breadcrumb: breadcrumb + ["Team"],
                icon: "person.3",
                keywords: [
                    "team permissions", "user permissions", "member permissions",
                    "individual permissions", "person overrides", "user overrides"
                ],
                route: route("team")
            ),
        ]
    }

    // MARK: - Support

    private static func supportEntries() -> [SettingsSearchEntry] {
        return [
            SettingsSearchEntry(
                title: "What's New",
                breadcrumb: ["What's New"],
                icon: "sparkles",
                keywords: [
                    "what's new", "whats new", "updates", "release notes",
                    "changelog", "new features", "version", "latest"
                ],
                route: SettingsRoute(.whatsNew)
            ),
            SettingsSearchEntry(
                title: "Report Issue",
                breadcrumb: ["Report Issue"],
                icon: OPSStyle.Icons.alert,
                keywords: [
                    "report", "report issue", "bug", "feedback", "help",
                    "support", "contact", "broken", "not working", "crash"
                ],
                route: SettingsRoute(.reportIssue)
            ),
            SettingsSearchEntry(
                title: "Setup",
                breadcrumb: ["Setup"],
                icon: "paperplane.fill",
                keywords: [
                    "setup", "tour", "guides", "wizard", "checklist",
                    "onboarding", "getting started"
                ],
                route: SettingsRoute(.wizardManagement)
            ),
        ]
    }
}
