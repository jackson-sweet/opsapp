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
// MainTabView's tab transition. Every right-side action button (search,
// filter, scope, month, review, insights) is part of this same trailing
// HStack, so they share one baseline, stay vertically aligned, and animate
// identically. (Earlier builds lifted the search button into a separate
// fixed overlay to keep it stationary across tab swaps — that desynced it
// from the other buttons and left it misaligned on tabs with a taller title
// block. The overlay is gone; the search button is a normal sibling again.)

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

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var appState: AppState
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
        
        if headerType == .home {
            
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    HStack(spacing: 8) {
                        if let company = dataController.getCurrentUserCompany() {
                            Text(company.name.uppercased())
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            // Show subscription badge if relevant
                            if let status = company.subscriptionStatus,
                               let statusEnum = SubscriptionStatus(rawValue: status) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(statusColor(for: statusEnum))
                                        .frame(width: 6, height: 6)

                                    Text(statusText(for: statusEnum))
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(statusColor(for: statusEnum))
                                }
                            }
                        }
                    }
                }
                
                Spacer()

                // User avatar with sync indicator and notification bell overlay
                Button(action: {
                    appState.showingNotifications = true
                }) {
                    ZStack {
                        // Avatar — dimmed when sync operations are pending/active.
                        // Opacity is driven by local @State (avatarIsDimmed), not
                        // the live published values, so tab-switch transitions
                        // render the avatar's final opacity up front and the slide
                        // animates uniformly with the rest of the header.
                        Group {
                            if let user = dataController.currentUser {
                                UserAvatar(user: user, size: 44)
                                    .overlay(
                                        Circle()
                                            .stroke(OPSStyle.Colors.primaryText, lineWidth: OPSStyle.Layout.Border.thick)
                                    )
                            } else {
                                UserAvatar(
                                    firstName: "U",
                                    lastName: "",
                                    size: 44,
                                    backgroundColor: OPSStyle.Colors.primaryAccent
                                )
                                .overlay(
                                    Circle()
                                        .stroke(OPSStyle.Colors.primaryText, lineWidth: OPSStyle.Layout.Border.thick)
                                    )
                            }
                        }
                        .opacity(avatarIsDimmed ? 0.35 : 1.0)

                        // Sync overlay — spinning icon with count in center
                        if dataController.syncEngine.pendingOperationCount > 0 || dataController.syncEngine.isSyncing {
                            AvatarSyncOverlay(
                                count: dataController.syncEngine.pendingOperationCount,
                                isSyncing: dataController.syncEngine.isSyncing
                            )
                        }

                        // Notification indicator — bottom-left of avatar
                        // Shows bell when no unread; shows count replacing bell when unread
                        ZStack {
                            Circle()
                                .fill(OPSStyle.Colors.background)
                                .frame(width: 22, height: 22)

                            if appState.unreadNotificationCount > 0 {
                                Text("\(min(appState.unreadNotificationCount, 99))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            } else {
                                Image(systemName: "bell")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                        }
                        .offset(x: -14, y: 14)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [
                        OPSStyle.Colors.background,
                        OPSStyle.Colors.background.opacity(0.85),
                        OPSStyle.Colors.background.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .sheet(isPresented: $appState.showingNotifications, onDismiss: {
                // Process any deep-link baton left by a notification row tap.
                // Fires AFTER this sheet is fully gone, so the target sheet
                // can present without a sheet-on-sheet race.
                if let deepLink = appState.pendingRailDeepLink {
                    appState.pendingRailDeepLink = nil
                    switch deepLink {
                    case "photoStorage":
                        appState.showPhotoStorage = true
                    default:
                        break
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
                // Seed dim state without animation so tab-enter renders the
                // final opacity immediately — the tab-slide carries the avatar.
                avatarIsDimmed = dataController.syncEngine.pendingOperationCount > 0 || dataController.syncEngine.isSyncing
            }
            .onChange(of: dataController.syncEngine.pendingOperationCount) { _, _ in
                withAnimation(OPSStyle.Animation.standard) {
                    avatarIsDimmed = dataController.syncEngine.pendingOperationCount > 0 || dataController.syncEngine.isSyncing
                }
            }
            .onChange(of: dataController.syncEngine.isSyncing) { _, _ in
                withAnimation(OPSStyle.Animation.standard) {
                    avatarIsDimmed = dataController.syncEngine.pendingOperationCount > 0 || dataController.syncEngine.isSyncing
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .notificationReceived)) { _ in
                appState.refreshUnreadCount()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pushNotificationReceived)) { _ in
                appState.refreshUnreadCount()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                appState.refreshUnreadCount()
            }

        } else if headerType == .settings && appState.isSettingsSearchActive {
            // Bug G5 — expanded search state for Settings tab. The title and
            // trailing actions collapse; the full row becomes a single input
            // with a leading magnifier, inline clear button, and trailing
            // CANCEL action. Animation is spring-driven via OPSStyle tokens.
            settingsSearchField
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .transition(.opacity)
        } else {

            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    // Show date subtitle for schedule view
                    if headerType == .schedule {
                        HStack(spacing: 8) {
                            Text("TODAY")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            Text("|")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            Text(todayDateString)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                }
                
                Spacer()
                
                // Action buttons — schedule and job board
                HStack(spacing: 8) {
                    // Calendar/month toggle button (schedule only)
                    if headerType == .schedule, let onMonthTapped = onMonthTapped {
                        Button(action: onMonthTapped) {
                            Image(systemName: "calendar")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .frame(width: 44, height: 44)
                                .background(OPSStyle.Colors.cardBackground)
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .wizardTarget("toggle_month", style: .circle)
                    }

                    // Filter button (schedule only)
                    if headerType == .schedule, let onFilterTapped = onFilterTapped {
                        Button(action: onFilterTapped) {
                            ZStack {
                                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(hasActiveFilters ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryText)
                                    .frame(width: 44, height: 44)
                                    .background(OPSStyle.Colors.cardBackground)
                                    .clipShape(Circle())

                                // Show filter count badge if filters are active
                                if hasActiveFilters && filterCount > 0 {
                                    Text("\(filterCount)")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .padding(4)
                                        .background(OPSStyle.Colors.primaryAccent)
                                        .clipShape(Circle())
                                        .offset(x: 14, y: -14)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // ALL/MINE scope toggle (schedule only)
                    if headerType == .schedule, let onScopeToggled = onScopeToggled {
                        Button(action: onScopeToggled) {
                            ZStack {
                                Image(systemName: isScopeAll ? "person.2" : "person")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(isScopeAll ? OPSStyle.Colors.primaryText : OPSStyle.Colors.primaryAccent)
                                    .frame(width: 44, height: 44)
                                    .background(OPSStyle.Colors.cardBackground)
                                    .clipShape(Circle())

                                // Indicator dot when MINE is selected
                                if !isScopeAll {
                                    Circle()
                                        .fill(OPSStyle.Colors.primaryAccent)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 14, y: -14)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    if headerType == .jobBoard {
                        // Unscheduled task review button
                        if let onUnscheduledReviewTapped {
                            Button(action: { onUnscheduledReviewTapped() }) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "calendar.badge.exclamationmark")
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .frame(width: 44, height: 44)
                                        .background(OPSStyle.Colors.cardBackground)
                                        .clipShape(Circle())

                                    if unscheduledReviewBadgeCount > 0 {
                                        Text("\(unscheduledReviewBadgeCount)")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.invertedText)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(OPSStyle.Colors.warningStatus)
                                            .clipShape(Capsule())
                                            .offset(x: 6, y: -4)
                                            // Explicit entry animation so the
                                            // count visibly lands when the tab
                                            // slide completes — without this
                                            // the badge renders at its offset
                                            // instantly and reads as "already
                                            // in place" (bug 5d66ee80).
                                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // Task review button
                        if onTaskReviewTapped != nil || isTaskReviewLocked {
                            Button(action: {
                                if isTaskReviewLocked {
                                    showLockedMessage = taskReviewLockedMessage
                                    showLockedAlert = true
                                } else {
                                    onTaskReviewTapped?()
                                }
                            }) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "checklist")
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(isTaskReviewLocked ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                                        .frame(width: 44, height: 44)
                                        .background(OPSStyle.Colors.cardBackground)
                                        .clipShape(Circle())

                                    if !isTaskReviewLocked && taskReviewBadgeCount > 0 {
                                        Text("\(taskReviewBadgeCount)")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.invertedText)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(OPSStyle.Colors.warningStatus)
                                            .clipShape(Capsule())
                                            .offset(x: 6, y: -4)
                                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .wizardTarget("open_task_review")
                        }

                        // Payment review button
                        if onPaymentReviewTapped != nil || isPaymentReviewLocked {
                            Button(action: {
                                if isPaymentReviewLocked {
                                    showLockedMessage = paymentReviewLockedMessage
                                    showLockedAlert = true
                                } else {
                                    onPaymentReviewTapped?()
                                }
                            }) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "rectangle.stack.fill")
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(isPaymentReviewLocked ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                                        .frame(width: 44, height: 44)
                                        .background(OPSStyle.Colors.cardBackground)
                                        .clipShape(Circle())

                                    if !isPaymentReviewLocked && paymentReviewBadgeCount > 0 {
                                        Text("\(paymentReviewBadgeCount)")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.invertedText)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(OPSStyle.Colors.warningStatus)
                                            .clipShape(Capsule())
                                            .offset(x: 6, y: -4)
                                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .wizardTarget("open_payment_review")
                        }

                    }

                    // Insights button (inventory only)
                    if headerType == .inventory, let onInsightsTapped = onInsightsTapped {
                        Button(action: onInsightsTapped) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .frame(width: 44, height: 44)
                                .background(OPSStyle.Colors.cardBackground)
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Universal search button — rightmost in the trailing
                    // cluster on every tab except home. It's a normal sibling
                    // of the tab-specific buttons, so it shares their baseline
                    // and slides with the rest of the header on a tab switch.
                    //
                    // Bug G5 — Settings tab uses an expanding-in-place input;
                    // tapping the icon flips appState.isSettingsSearchActive
                    // so the header re-renders as the full-width input (see
                    // the `.settings && isSettingsSearchActive` branch above).
                    Button(action: {
                        if headerType == .settings {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(OPSStyle.Animation.spring) {
                                appState.isSettingsSearchActive = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                settingsSearchFocused = true
                            }
                        } else {
                            appState.showingUniversalSearch = true
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: 44, height: 44)
                            .background(OPSStyle.Colors.cardBackground)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Search")
                }

            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .onChange(of: showLockedAlert) { _, showing in
                guard showing else { return }
                let message = showLockedMessage ?? ""
                let label = message.isEmpty ? "// LOCKED" : "// \(message.uppercased())"
                ToastCenter.shared.present(Toast(label: label, tone: .warning))
                showLockedAlert = false
            }

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
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
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
                .frame(minHeight: 32)

            if !appState.settingsSearchQuery.isEmpty {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    appState.settingsSearchQuery = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 32, height: 32)
            }

            Button(action: closeSettingsSearch) {
                Text("CANCEL")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(OPSStyle.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func closeSettingsSearch() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        settingsSearchFocused = false
        withAnimation(OPSStyle.Animation.spring) {
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
        VStack(spacing: 16) {
            Divider()
                .background(OPSStyle.Colors.separator)
                .padding(.horizontal, 20)
            
            // Feature request and logout buttons in HStack
            HStack(spacing: 16) {
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
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.largeCornerRadius)
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
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.largeCornerRadius)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            
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
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
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
                    .font(.system(size: 10, weight: .bold, design: .rounded))
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
