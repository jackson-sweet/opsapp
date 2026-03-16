//
//  AppHeader.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import SwiftUI

struct AppHeader: View {
    enum HeaderType {
        case home
        case settings
        case schedule
        case jobBoard
        case inventory
        case pipeline
    }
    
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var appState: AppState
    @State private var showLockedMessage: String? = nil
    @State private var showLockedAlert: Bool = false
    var headerType: HeaderType
    var onSearchTapped: (() -> Void)? = nil
    var onRefreshTapped: (() -> Void)? = nil
    var onFilterTapped: (() -> Void)? = nil
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

                        // Sync ring animation — rotating arc when actively syncing
                        if dataController.syncEngine.isSyncing {
                            SyncRingView()
                                .frame(width: 52, height: 52)
                        }

                        // Pending offline badge — amber dot when operations are queued
                        if !dataController.syncEngine.isSyncing && dataController.syncEngine.pendingOperationCount > 0 {
                            Circle()
                                .fill(OPSStyle.Colors.warningStatus)
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Circle()
                                        .stroke(OPSStyle.Colors.background, lineWidth: 1.5)
                                )
                                .offset(x: 18, y: -18)
                        }

                        // Bell icon — bottom-left of avatar
                        ZStack {
                            Circle()
                                .fill(OPSStyle.Colors.background)
                                .frame(width: 22, height: 22)

                            Image(systemName: appState.unreadNotificationCount > 0 ? "bell.fill" : "bell")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(appState.unreadNotificationCount > 0 ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryText)
                        }
                        .offset(x: -14, y: 14)

                        // Unread count badge — top-right of avatar
                        if appState.unreadNotificationCount > 0 {
                            Text("\(min(appState.unreadNotificationCount, 99))")
                                .font(.system(size: 10, weight: .bold))
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
            .sheet(isPresented: $appState.showingNotifications) {
                NavigationStack {
                    NotificationListView()
                        .environmentObject(dataController)
                        .environmentObject(appState)
                }
            }
            .onAppear {
                appState.refreshUnreadCount()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pushNotificationReceived)) { _ in
                appState.refreshUnreadCount()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                appState.refreshUnreadCount()
            }

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
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
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
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                    }

                    // Universal search button (all pages except home)
                    Button(action: {
                        appState.showingUniversalSearch = true
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: 44, height: 44)
                            .background(OPSStyle.Colors.cardBackground)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }

            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .alert("Locked", isPresented: $showLockedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(showLockedMessage ?? "")
            }

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

// MARK: - Sync Ring Animation

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
