//
//  AppHeader.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import SwiftUI

// MARK: - App Header
//
// The header lives inline at the top of every tab's view, so when the user
// switches tabs the whole tab — header + body — slides as one unit via
// MainTabView's tab transition. Root metadata sits in the first content strip
// below the canonical title band, and every trailing action flows through the
// shared two-slot policy in OPSScreenHeader.

/// Measured height of the tab's `AppHeader`, published so app-level overlays can
/// park BENEATH the header band instead of colliding with it.
///
/// `MainTabView` floats the sync attention pill in the top-trailing corner — the
/// exact rectangle this header's trailing action cluster (search + tab-specific
/// buttons, or Home's avatar) already occupies. Both are laid out from the top
/// safe area, so they land on top of each other. Publishing the real measured
/// height lets the overlay start where the header ends, which also keeps the two
/// apart when Dynamic Type grows the title block and the header gets taller.
///
/// Reduced with `max`, which only works because inactive headers stay silent.
/// MainTabView keeps every visited tab mounted, so several headers are alive and
/// publishing at all times; a header that is not in the active tab reports
/// `defaultValue` (the reduce's own starting point, so it contributes nothing)
/// and the active tab's real height wins. Without that gate the tallest header
/// ever mounted would pin the overlay for the rest of the session.
struct AppHeaderHeightKey: PreferenceKey {
    /// Floor used before any header reports and by tabs without an AppHeader.
    static let defaultValue: CGFloat = OPSStyle.Layout.screenHeaderBandHeight

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AppHeader: View {
    enum HeaderType {
        case home
        case settings
        case schedule
        case jobBoard
        case inventory
        case pipeline
        case books
        case leads
    }

    private enum TrailingAction: String, Identifiable {
        case scheduleMenu
        case jobBoardMenu
        case inventoryInsights
        case newLead
        case search

        var id: String { rawValue }
    }

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var appState: AppState
    /// Only the header in the tab on screen may claim the band height — see
    /// `AppHeaderHeightKey`.
    @Environment(\.isActiveTab) private var isActiveTab
    @State private var showLockedMessage: String? = nil
    @State private var showLockedAlert: Bool = false
    // Bug 5d66ee80: avatar dimming during sync used to be wired via nested
    // `.animation(_, value:)` modifiers which created an animation boundary
    // and caused the avatar to skip the tab-switch slide (it rendered at its
    // final position before the transition started). We now keep the derived
    // dimming state in local @State and drive it via onChange + withAnimation,
    // so parent transitions flow through cleanly.
    @State private var avatarIsDimmed: Bool = false

    // Bug G5 — Settings-tab search: the magnifying glass icon expands in place
    // into a full-width text field. Focus state is local; the text value and
    // the active flag live on AppState so SettingsView can swap its body for
    // a search-results list while the input is focused.
    @FocusState private var settingsSearchFocused: Bool
    var headerType: HeaderType
    var onRefreshTapped: (() -> Void)? = nil
    var onFilterTapped: (() -> Void)? = nil
    var onInsightsTapped: (() -> Void)? = nil
    var onMonthTapped: (() -> Void)? = nil
    var onScopeToggled: (() -> Void)? = nil
    var onPaymentReviewTapped: (() -> Void)? = nil
    var paymentReviewBadgeCount: Int = 0
    var isPaymentReviewLocked: Bool = false
    var paymentReviewLockedMessage: String = ""
    var onTaskReviewTapped: (() -> Void)? = nil
    var taskReviewBadgeCount: Int = 0
    var isTaskReviewLocked: Bool = false
    var taskReviewLockedMessage: String = ""
    var onUnscheduledReviewTapped: (() -> Void)? = nil
    var unscheduledReviewBadgeCount: Int = 0
    var isScopeAll: Bool = true
    var hasActiveFilters: Bool = false
    var filterCount: Int = 0
    /// Leads tab — the add-lead action (`+`), shown left of universal search.
    var onAddLead: (() -> Void)? = nil
    
    private var title: String {
        switch headerType {
        case .home:
            let greeting = getGreeting().uppercased()
            return "\(greeting), \(dataController.currentUser?.firstName.uppercased() ?? "USER")"
        case .settings:
            return "SETTINGS"
        case .schedule:
            return "SCHEDULE"
        case .jobBoard:
            return "JOB BOARD"
        case .inventory:
            return "INVENTORY"
        case .pipeline:
            return "PIPELINE"
        case .books:
            return "BOOKS"
        case .leads:
            return "LEADS"
        }
    }
    
    var body: some View {
        headerContent
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: AppHeaderHeightKey.self,
                        value: isActiveTab ? proxy.size.height : AppHeaderHeightKey.defaultValue
                    )
                }
            )
            .background {
                if headerType == .home {
                    OPSStyle.Layout.Gradients.headerFade
                        .ignoresSafeArea(edges: .top)
                }
            }
            .onChange(of: showLockedAlert) { _, showing in
                guard showing else { return }
                let message = showLockedMessage ?? ""
                let label = message.isEmpty ? "// LOCKED" : "// \(message.uppercased())"
                ToastCenter.shared.present(Toast(label: label, tone: .warning))
                showLockedAlert = false
            }
    }

    private var headerContent: some View {
        VStack(spacing: 0) {
            headerBand
            contextStrip
        }
    }

    @ViewBuilder
    private var headerBand: some View {
        if headerType == .home {
            OPSScreenHeader(title, trailing: { avatarButton })
        } else if headerType == .settings && appState.isSettingsSearchActive {
            settingsSearchField
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .frame(minHeight: OPSStyle.Layout.screenHeaderBandHeight)
                .transition(.opacity)
        } else {
            OPSScreenHeader(
                title,
                trailing: {
                    OPSHeaderActionStrip(trailingActions) { action in
                        trailingAction(action)
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var contextStrip: some View {
        if headerType == .home,
           let company = dataController.getCurrentUserCompany() {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(company.name.uppercased())
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                if let status = company.subscriptionStatus,
                   let statusEnum = SubscriptionStatus(rawValue: status) {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Circle()
                            .fill(statusColor(for: statusEnum))
                            .frame(
                                width: OPSStyle.Layout.Indicator.dotSM,
                                height: OPSStyle.Layout.Indicator.dotSM
                            )

                        Text(statusText(for: statusEnum))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(statusColor(for: statusEnum))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing2)
            .accessibilityElement(children: .combine)
        } else if headerType == .schedule {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("TODAY")
                Text("·")
                Text(todayDateString)
                Spacer(minLength: 0)
            }
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing2)
            .accessibilityElement(children: .combine)
        }
    }

    private var trailingActions: [TrailingAction] {
        switch headerType {
        case .schedule:
            return hasScheduleMenuActions ? [.scheduleMenu, .search] : [.search]
        case .jobBoard:
            return hasJobBoardMenuActions ? [.jobBoardMenu, .search] : [.search]
        case .inventory:
            return onInsightsTapped == nil ? [.search] : [.inventoryInsights, .search]
        case .leads:
            return onAddLead == nil ? [.search] : [.newLead, .search]
        case .settings, .pipeline, .books:
            return [.search]
        case .home:
            return []
        }
    }

    private var hasScheduleMenuActions: Bool {
        onMonthTapped != nil || onFilterTapped != nil || onScopeToggled != nil
    }

    private var hasJobBoardMenuActions: Bool {
        onUnscheduledReviewTapped != nil
            || onTaskReviewTapped != nil
            || isTaskReviewLocked
            || onPaymentReviewTapped != nil
            || isPaymentReviewLocked
    }

    @ViewBuilder
    private func trailingAction(_ action: TrailingAction) -> some View {
        switch action {
        case .scheduleMenu:
            scheduleMenu
        case .jobBoardMenu:
            jobBoardMenu
        case .inventoryInsights:
            Button(action: { onInsightsTapped?() }) {
                headerActionIcon(symbol: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Inventory insights")
        case .newLead:
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onAddLead?()
            } label: {
                headerActionIcon(symbol: OPSStyle.Icons.plus)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New lead")
        case .search:
            UniversalSearchButton(action: openSearch)
        }
    }

    private var scheduleMenu: some View {
        Menu {
            if let onMonthTapped {
                Button(action: onMonthTapped) {
                    Label("MONTH VIEW", systemImage: OPSStyle.Icons.calendar)
                }
            }
            if let onFilterTapped {
                Button(action: onFilterTapped) {
                    Label(scheduleFilterMenuTitle, systemImage: OPSStyle.Icons.filter)
                }
            }
            if let onScopeToggled {
                Button(action: onScopeToggled) {
                    Label(
                        isScopeAll ? "MY SCHEDULE" : "ALL TEAM",
                        systemImage: isScopeAll
                            ? OPSStyle.Icons.person
                            : OPSStyle.Icons.personTwo
                    )
                }
            }
        } label: {
            headerMenuLabel(
                accessibilityLabel: "Schedule actions",
                badgeCount: hasActiveFilters ? filterCount : 0,
                showsIndicator: hasActiveFilters
            )
        }
        .buttonStyle(.plain)
        .wizardTarget("toggle_month", style: .circle)
    }

    private var jobBoardMenu: some View {
        Menu {
            if let onUnscheduledReviewTapped {
                Button(action: onUnscheduledReviewTapped) {
                    Label(
                        reviewMenuTitle("UNSCHEDULED", count: unscheduledReviewBadgeCount),
                        systemImage: OPSStyle.Icons.deadline
                    )
                }
            }
            if onTaskReviewTapped != nil || isTaskReviewLocked {
                Button(action: openTaskReview) {
                    Label(
                        reviewMenuTitle(
                            "TASK REVIEW",
                            count: taskReviewBadgeCount,
                            isLocked: isTaskReviewLocked
                        ),
                        systemImage: OPSStyle.Icons.task
                    )
                }
            }
            if onPaymentReviewTapped != nil || isPaymentReviewLocked {
                Button(action: openPaymentReview) {
                    Label(
                        reviewMenuTitle(
                            "PAYMENT REVIEW",
                            count: paymentReviewBadgeCount,
                            isLocked: isPaymentReviewLocked
                        ),
                        systemImage: "rectangle.stack.fill"
                    )
                }
            }
        } label: {
            headerMenuLabel(
                accessibilityLabel: "Review actions",
                badgeCount: jobBoardBadgeCount,
                showsIndicator: jobBoardBadgeCount > 0
            )
        }
        .buttonStyle(.plain)
        .wizardTarget(
            style: .circle,
            "open_task_review",
            "open_payment_review"
        )
    }

    private func headerActionIcon(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .frame(
                width: OPSStyle.Layout.touchTargetMin,
                height: OPSStyle.Layout.touchTargetMin
            )
            .background(OPSStyle.Colors.fillNeutral)
            .clipShape(Circle())
            .contentShape(Circle())
    }

    private func headerMenuLabel(
        accessibilityLabel: String,
        badgeCount: Int,
        showsIndicator: Bool
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            headerActionIcon(symbol: OPSStyle.Icons.ellipsis)

            if badgeCount > 0 {
                Text("\(min(badgeCount, 99))")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .padding(.horizontal, OPSStyle.Layout.spacing1)
                    .padding(.vertical, OPSStyle.Layout.spacing1 / 2)
                    .background(OPSStyle.Colors.warningStatus)
                    .clipShape(Capsule())
                    .offset(
                        x: OPSStyle.Layout.spacing1,
                        y: -OPSStyle.Layout.spacing1
                    )
            } else if showsIndicator {
                Circle()
                    .fill(OPSStyle.Colors.text)
                    .frame(
                        width: OPSStyle.Layout.Indicator.dotMD,
                        height: OPSStyle.Layout.Indicator.dotMD
                    )
                    .offset(
                        x: OPSStyle.Layout.spacing1,
                        y: -OPSStyle.Layout.spacing1
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(badgeCount > 0 ? "\(badgeCount) items" : "")
    }

    private var scheduleFilterMenuTitle: String {
        guard hasActiveFilters else { return "FILTERS" }
        return filterCount > 0 ? "FILTERS · \(filterCount)" : "FILTERS · ACTIVE"
    }

    private var jobBoardBadgeCount: Int {
        max(0, unscheduledReviewBadgeCount)
            + (isTaskReviewLocked ? 0 : max(0, taskReviewBadgeCount))
            + (isPaymentReviewLocked ? 0 : max(0, paymentReviewBadgeCount))
    }

    private func reviewMenuTitle(
        _ label: String,
        count: Int,
        isLocked: Bool = false
    ) -> String {
        if isLocked { return "\(label) · LOCKED" }
        return count > 0 ? "\(label) · \(count)" : label
    }

    private func openTaskReview() {
        if isTaskReviewLocked {
            showLockedMessage = taskReviewLockedMessage
            showLockedAlert = true
        } else {
            onTaskReviewTapped?()
        }
    }

    private func openPaymentReview() {
        if isPaymentReviewLocked {
            showLockedMessage = paymentReviewLockedMessage
            showLockedAlert = true
        } else {
            onPaymentReviewTapped?()
        }
    }

    private func openSearch() {
        if headerType == .settings {
            withAnimation(OPSStyle.Animation.standard) {
                appState.isSettingsSearchActive = true
            }
            DispatchQueue.main.async {
                settingsSearchFocused = true
            }
        } else {
            appState.showingUniversalSearch = true
        }
    }

    private var avatarButton: some View {
        Button(action: { appState.showingNotifications = true }) {
            ZStack {
                Group {
                    if let user = dataController.currentUser {
                        UserAvatar(user: user, size: OPSStyle.Layout.touchTargetMin)
                    } else {
                        UserAvatar(
                            firstName: "U",
                            lastName: "",
                            size: OPSStyle.Layout.touchTargetMin,
                            backgroundColor: OPSStyle.Colors.primaryAccent
                        )
                    }
                }
                .overlay(
                    Circle().stroke(
                        OPSStyle.Colors.primaryText,
                        lineWidth: OPSStyle.Layout.Border.thick
                    )
                )
                .opacity(
                    avatarIsDimmed
                        ? OPSStyle.Layout.Opacity.light
                        : 1
                )

                if dataController.syncEngine.pendingOperationCount > 0
                    || dataController.syncEngine.isSyncing {
                    AvatarSyncOverlay(
                        count: dataController.syncEngine.pendingOperationCount,
                        isSyncing: dataController.syncEngine.isSyncing
                    )
                }

                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.background)
                        .frame(
                            width: OPSStyle.Layout.touchTargetMin / 2,
                            height: OPSStyle.Layout.touchTargetMin / 2
                        )

                    if appState.unreadNotificationCount > 0 {
                        Text("\(min(appState.unreadNotificationCount, 99))")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    } else {
                        Image(systemName: "bell")
                            .font(.system(
                                size: OPSStyle.Layout.IconSize.xs,
                                weight: .semibold
                            ))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
                .offset(
                    x: -(OPSStyle.Layout.touchTargetMin / 3),
                    y: OPSStyle.Layout.touchTargetMin / 3
                )
            }
            .frame(
                width: OPSStyle.Layout.touchTargetMin,
                height: OPSStyle.Layout.touchTargetMin
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Notifications")
        .accessibilityValue(
            appState.unreadNotificationCount > 0
                ? "\(appState.unreadNotificationCount) unread"
                : "No unread notifications"
        )
        .sheet(isPresented: $appState.showingNotifications, onDismiss: {
            if let deepLink = appState.pendingRailDeepLink {
                appState.pendingRailDeepLink = nil
                if deepLink == "photoStorage" {
                    appState.showPhotoStorage = true
                }
            }
        }) {
            NavigationStack {
                NotificationListView()
                    .environmentObject(dataController)
                    .environmentObject(appState)
            }
        }
        .onAppear {
            appState.refreshUnreadCount()
            avatarIsDimmed = dataController.syncEngine.pendingOperationCount > 0
                || dataController.syncEngine.isSyncing
        }
        .onChange(of: dataController.syncEngine.pendingOperationCount) { _, _ in
            withAnimation(OPSStyle.Animation.standard) {
                avatarIsDimmed = dataController.syncEngine.pendingOperationCount > 0
                    || dataController.syncEngine.isSyncing
            }
        }
        .onChange(of: dataController.syncEngine.isSyncing) { _, _ in
            withAnimation(OPSStyle.Animation.standard) {
                avatarIsDimmed = dataController.syncEngine.pendingOperationCount > 0
                    || dataController.syncEngine.isSyncing
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notificationReceived)) { _ in
            appState.refreshUnreadCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushNotificationReceived)) { _ in
            appState.refreshUnreadCount()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            appState.refreshUnreadCount()
        }
    }

    // MARK: - Settings Search Field (Bug G5)

    /// Full-width text input that replaces the Settings header when
    /// `appState.isSettingsSearchActive` is true. Owned by the header so the
    /// visual transition (icon → full input) stays in one place. Canceling
    /// clears the query on AppState, lowering focus so the keyboard dismisses,
    /// and flips the active flag off — SettingsView swaps back to its
    /// content on the same animation.
    private var settingsSearchField: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: OPSStyle.Icons.search)
                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextField("Search settings…", text: $appState.settingsSearchQuery)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .focused($settingsSearchFocused)
                .autocorrectionDisabled(true)
                .autocapitalization(.none)
                .submitLabel(.search)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)

            if !appState.settingsSearchQuery.isEmpty {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    appState.settingsSearchQuery = ""
                }) {
                    Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .buttonStyle(.plain)
                .frame(
                    width: OPSStyle.Layout.touchTargetMin,
                    height: OPSStyle.Layout.touchTargetMin
                )
                .accessibilityLabel("Clear search")
            }

            Button(action: closeSettingsSearch) {
                Text("CANCEL")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .frame(
                minWidth: OPSStyle.Layout.touchTargetMin,
                minHeight: OPSStyle.Layout.touchTargetMin
            )
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .background(OPSStyle.Colors.surfaceInput)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                .stroke(
                    OPSStyle.Colors.inputFieldBorderFocus,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
    }

    private func closeSettingsSearch() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        settingsSearchFocused = false
        withAnimation(OPSStyle.Animation.standard) {
            appState.isSettingsSearchActive = false
            appState.settingsSearchQuery = ""
        }
    }

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: Date())
    }
    
    private func getGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 0..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        default:
            return "Good Evening"
        }
    }
    
    private func statusColor(for status: SubscriptionStatus) -> Color {
        switch status {
        case .trial:
            return OPSStyle.Colors.primaryAccent
        case .active:
            return OPSStyle.Colors.successStatus
        case .grace:
            return OPSStyle.Colors.warningStatus
        case .expired, .cancelled:
            return OPSStyle.Colors.errorStatus
        }
    }
    
    private func statusText(for status: SubscriptionStatus) -> String {
        switch status {
        case .trial:
            if let company = dataController.getCurrentUserCompany(),
               let trialEnd = company.trialEndDate {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                let dateString = formatter.string(from: trialEnd)

                if days > 0 {
                    return "TRIAL ENDS \(dateString)"
                } else {
                    return "TRIAL ENDING"
                }
            }
            return "TRIAL"
        case .active:
            if let company = dataController.getCurrentUserCompany(),
               let plan = company.subscriptionPlan,
               let planEnum = SubscriptionPlan(rawValue: plan) {
                return planEnum.displayName.uppercased()
            }
            return "ACTIVE"
        case .grace:
            if let company = dataController.getCurrentUserCompany(),
               let days = company.daysRemainingInGracePeriod {
                if days > 0 {
                    return "GRACE \(days) DAYS"
                } else {
                    return "GRACE ENDING"
                }
            }
            return "GRACE PERIOD"
        case .expired:
            return "EXPIRED"
        case .cancelled:
            return "CANCELLED"
        }
    }
    
    
    // MARK: - Unused (retained for legacy)
    // Version and actions view at the bottom
    private var versionAndActionsView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Divider()
                .background(OPSStyle.Colors.separator)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            
            // Feature request and logout buttons in HStack
            HStack(spacing: OPSStyle.Layout.spacing3) {
                // Feature request button (1/3 width)
                NavigationLink(destination: FeatureRequestView()) {
                    HStack {
                        Image(systemName: "lightbulb")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        
                        Text("REQUEST FEATURE")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .nestedCard()
                }
                .frame(height: 44)
                
                // Logout button (2/3 width)
                Button(action: {
                    dataController.logout()
                }) {
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
                    .nestedCard()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            
            // App version and logo
            HStack {
                Image("LogoWhite") // Placeholder for actual logo
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                
                Text("OPS APP")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
                
                Text(AppConfiguration.AppInfo.displayVersion)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing3)
        }
    }
}

// MARK: - Avatar Sync Overlay

/// Sync icon with spinning animation and count shown over the avatar
/// when operations are pending or actively syncing.
struct AvatarSyncOverlay: View {
    let count: Int
    let isSyncing: Bool
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Spinning sync icon ring
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isSyncing ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.warningStatus)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    if isSyncing {
                        withAnimation(
                            .linear(duration: 1.5)
                            .repeatForever(autoreverses: false)
                        ) {
                            rotation = 360
                        }
                    }
                }
                .onChange(of: isSyncing) { _, newValue in
                    if newValue {
                        rotation = 0
                        withAnimation(
                            .linear(duration: 1.5)
                            .repeatForever(autoreverses: false)
                        ) {
                            rotation = 360
                        }
                    }
                }

            // Count in center
            if count > 0 {
                Text("\(count)")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
        }
        .frame(width: 44, height: 44)
    }
}

// MARK: - Legacy Sync Ring (retained for other callers)

/// Rotating arc overlay shown around the avatar when sync is in progress.
struct SyncRingView: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.3)
            .stroke(
                OPSStyle.Colors.primaryAccent,
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(
                    .linear(duration: 1.2)
                    .repeatForever(autoreverses: false)
                ) {
                    rotation = 360
                }
            }
    }
}
