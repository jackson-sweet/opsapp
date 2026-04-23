//
//  NotificationListView.swift
//  OPS
//
//  In-app notification list showing recent mentions and updates.
//

import SwiftUI

struct NotificationListView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var notifications: [NotificationDTO] = []
    @State private var isLoading = true
    @State private var showingOlder = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header — matches SettingsHeader pattern
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: OPSStyle.Icons.chevronLeft)
                            .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)

                    Spacer()

                    Text("NOTIFICATIONS")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    if !notifications.isEmpty {
                        Button(action: { markAllAsRead() }) {
                            Text("READ ALL")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        .frame(height: OPSStyle.Layout.touchTargetMin)
                    } else {
                        Spacer()
                            .frame(width: OPSStyle.Layout.touchTargetMin)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing2_5)

                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(OPSStyle.Colors.primaryAccent)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            userInfoHeader

                            // Push notification disabled warning
                            if !NotificationManager.shared.isNotificationsEnabled {
                                pushDisabledBanner
                                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                                    .padding(.bottom, 12)
                            }

                            // Sync status section — shows pending/failed operations
                            SyncStatusSection()
                                .environmentObject(dataController)

                            if notifications.isEmpty {
                                emptyState
                                    .padding(.top, 60)
                            } else {
                                notificationListContent
                            }
                        }
                    }
                }
            }
        }
        .trackScreen("Notifications")
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .task {
            await loadNotifications()
        }
    }

    // MARK: - Push Disabled Banner

    private var pushDisabledBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.warningStatus)

            VStack(alignment: .leading, spacing: 2) {
                Text("PUSH NOTIFICATIONS OFF")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("You'll only see notifications when you open the app")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            Button {
                NotificationManager.shared.openAppSettings()
            } label: {
                Text("ENABLE")
                    .font(OPSStyle.Typography.smallCaption)
                    .tracking(0.5)
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(OPSStyle.Colors.warningStatus)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
            }
        }
        .padding(12)
        .background(OPSStyle.Colors.warningStatus.opacity(0.1))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.warningStatus.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: "bell.slash")
                .font(OPSStyle.Typography.largeTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("NO NOTIFICATIONS")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("You'll see mentions and updates here")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    // MARK: - User Info Header

    private var userInfoHeader: some View {
        Group {
            if let user = dataController.currentUser {
                VStack(spacing: 12) {
                    // Avatar — prominent size so it's clearly visible on the dark background
                    UserAvatar(user: user, size: 72)
                        .overlay(
                            Circle()
                                .stroke(
                                    Color(hex: user.userColor ?? "#A49577") ?? OPSStyle.Colors.primaryAccent,
                                    lineWidth: OPSStyle.Layout.Border.thick
                                )
                                .frame(width: 76, height: 76)
                        )

                    // Name
                    Text(user.fullName.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    // Company name — fetch from user's company or UserDefaults
                    if let companyName = UserDefaults.standard.string(forKey: "Company Name"),
                       !companyName.isEmpty {
                        Text(companyName.uppercased())
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

                    // Role badge
                    Text(user.role.displayName.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .tracking(0.5)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(OPSStyle.Colors.primaryAccent.opacity(0.1))
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                        )
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                // No background fill — same background as the rest of the sheet
            }
        }
    }

    // MARK: - Notification List (Sectioned)

    /// Buckets used to group notifications in the list.
    private enum NotificationBucket {
        case today
        case thisWeek
        case lastWeek
        case older
    }

    /// Groups notifications by date bucket (today / this week / last week / older).
    /// Calendar-week semantics: "this week" = current calendar week excluding today;
    /// "last week" = the previous calendar week.
    private var groupedNotifications: (today: [NotificationDTO], thisWeek: [NotificationDTO], lastWeek: [NotificationDTO], older: [NotificationDTO]) {
        var today: [NotificationDTO] = []
        var thisWeek: [NotificationDTO] = []
        var lastWeek: [NotificationDTO] = []
        var older: [NotificationDTO] = []

        for notification in notifications {
            guard let date = parseCreatedAt(notification.createdAt) else {
                older.append(notification)
                continue
            }
            switch bucket(for: date) {
            case .today:    today.append(notification)
            case .thisWeek: thisWeek.append(notification)
            case .lastWeek: lastWeek.append(notification)
            case .older:    older.append(notification)
            }
        }
        return (today, thisWeek, lastWeek, older)
    }

    private func bucket(for date: Date) -> NotificationBucket {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return .today
        }

        // Resolve the start of the current and previous calendar weeks once.
        guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return .older
        }

        if date >= currentWeekStart {
            return .thisWeek
        }

        if let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart),
           date >= lastWeekStart {
            return .lastWeek
        }

        return .older
    }

    private var notificationListContent: some View {
        let grouped = groupedNotifications
        return LazyVStack(spacing: 0) {
            if !grouped.today.isEmpty {
                sectionHeader("TODAY", count: grouped.today.count)
                sectionRows(grouped.today)
            }

            if !grouped.thisWeek.isEmpty {
                sectionHeader("THIS WEEK", count: grouped.thisWeek.count)
                sectionRows(grouped.thisWeek)
            }

            if !grouped.lastWeek.isEmpty {
                sectionHeader("LAST WEEK", count: grouped.lastWeek.count)
                sectionRows(grouped.lastWeek)
            }

            if !grouped.older.isEmpty {
                collapsibleOlderSection(grouped.older)
            }
        }
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        // Section labels above grouped content use the canonical OPS pattern:
        // microLabel (Kosugi 11pt) + secondaryText, matching PersonalEventSheet.sectionLabel
        // and the explicit purpose comment in Fonts.swift for `microLabel`.
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text(title)
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("(\(count))")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing3_5)
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    private func sectionRows(_ items: [NotificationDTO]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, notif in
            VStack(spacing: 0) {
                notificationRow(notif)
                if index < items.count - 1 {
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorderSubtle)
                        .frame(height: OPSStyle.Layout.Border.standard)
                        .padding(.leading, 56)
                }
            }
        }
    }

    /// The expand/collapse animation. Respects the system Reduce Motion setting:
    /// when reduced, the content swaps without any spring or move transition.
    private var collapseAnimation: SwiftUI.Animation? {
        reduceMotion ? nil : OPSStyle.Animation.spring
    }

    private var collapseTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    private func collapsibleOlderSection(_ items: [NotificationDTO]) -> some View {
        VStack(spacing: 0) {
            if showingOlder {
                // Expanded: section header on left, COLLAPSE label + chevron-up on right.
                expandedOlderHeader(count: items.count)
                sectionRows(items)
                    .transition(collapseTransition)
            } else {
                // Collapsed: a clear "SEE OLDER" call-to-action button in the list area.
                seeOlderButton(count: items.count)
            }
        }
    }

    private func expandedOlderHeader(count: Int) -> some View {
        Button {
            withAnimation(collapseAnimation) {
                showingOlder = false
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text("OLDER")
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text("(\(count))")
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Spacer()

                Text("COLLAPSE")
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Image(systemName: OPSStyle.Icons.chevronUp)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func seeOlderButton(count: Int) -> some View {
        Button {
            withAnimation(collapseAnimation) {
                showingOlder = true
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text("SEE OLDER")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("(\(count))")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Image(systemName: OPSStyle.Icons.chevronDown)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.leading, OPSStyle.Layout.spacing1)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing3_5)
    }

    // MARK: - Row

    private func notificationRow(_ notification: NotificationDTO) -> some View {
        Button(action: {
            handleNotificationTap(notification)
        }) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                // Unread indicator
                Circle()
                    .fill(notification.isRead ? Color.clear : OPSStyle.Colors.primaryAccent)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                // Icon
                notificationIcon(for: notification.type)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title)
                        .font(notification.isRead ? OPSStyle.Typography.caption : OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    Text(notification.body)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(2)

                    Text(relativeTime(notification.createdAt))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                if notification.projectId != nil {
                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func notificationIcon(for type: String) -> some View {
        let (iconName, color): (String, Color) = {
            switch type {
            case "mention":
                return (OPSStyle.Icons.mention, OPSStyle.Colors.primaryAccent)
            case "project_note":
                return ("note.text", OPSStyle.Colors.primaryAccent.opacity(0.8))
            case "task_assignment":
                return ("person.badge.plus", OPSStyle.Colors.successStatus)
            case "project_assignment":
                return ("folder.badge.plus", OPSStyle.Colors.successStatus)
            case "assignment":
                return (OPSStyle.Icons.assignmentNotification, OPSStyle.Colors.successStatus)
            case "task_completion":
                return ("checkmark.circle.fill", OPSStyle.Colors.successStatus)
            case "project_completion":
                return ("flag.checkered", OPSStyle.Colors.successStatus)
            case "schedule_change":
                return ("calendar.badge.clock", OPSStyle.Colors.warningStatus)
            case "dependency_completed":
                return ("arrow.triangle.branch", OPSStyle.Colors.primaryAccent)
            case "team_join":
                return ("person.badge.plus", OPSStyle.Colors.primaryAccent)
            case "expense_submitted":
                return ("doc.text", OPSStyle.Colors.warningStatus)
            case "invoice_approved":
                return ("checkmark.seal", OPSStyle.Colors.successStatus)
            case "invoice_revisions":
                return ("exclamationmark.triangle", OPSStyle.Colors.warningStatus)
            case "role_assigned":
                return ("person.text.rectangle", OPSStyle.Colors.primaryAccent)
            case "inventory_warning":
                return ("shippingbox", OPSStyle.Colors.warningStatus)
            case "inventory_critical":
                return ("shippingbox.fill", OPSStyle.Colors.errorStatus)
            case "time_off_approved":
                return ("calendar.badge.checkmark", OPSStyle.Colors.successStatus)
            case "time_off_denied":
                return ("calendar.badge.exclamationmark", OPSStyle.Colors.errorStatus)
            case "invoice_overdue":
                return ("exclamationmark.circle", OPSStyle.Colors.errorStatus)
            case "photo_storage_limit":
                return ("externaldrive.fill.badge.exclamationmark", OPSStyle.Colors.warningStatus)
            case "update":
                return (OPSStyle.Icons.sync, OPSStyle.Colors.secondaryText)
            default:
                return (OPSStyle.Icons.bell, OPSStyle.Colors.secondaryText)
            }
        }()

        return Image(systemName: iconName)
            .font(OPSStyle.Typography.caption)
            .foregroundColor(color)
            .frame(width: 32, height: 32)
            .background(OPSStyle.Colors.subtleBackground)
            .clipShape(Circle())
    }

    // MARK: - Actions

    private func loadNotifications() async {
        guard let userId = UserDefaults.standard.string(forKey: "user_id"), !userId.isEmpty else {
            isLoading = false
            return
        }

        do {
            let repo = NotificationRepository()
            let result = try await repo.fetchRecent(userId: userId)
            await MainActor.run {
                notifications = result
                isLoading = false
            }
        } catch {
            print("[NOTIFICATIONS] Failed to load: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func handleNotificationTap(_ notification: NotificationDTO) {
        // Mark as read locally first
        if let index = notifications.firstIndex(where: { $0.id == notification.id }),
           !notifications[index].isRead {
            notifications[index].isRead = true
            appState.unreadNotificationCount = max(0, appState.unreadNotificationCount - 1)
        }

        // Mark as read on server
        Task {
            let repo = NotificationRepository()
            try? await repo.markAsRead(notification.id)
        }

        // Route by deep link type
        let deepLink = notification.deepLinkType ?? ""

        switch deepLink {
        case "subscription", "trial_expiry":
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // batchId carries the promo code for trial expiry notifications
                appState.pendingPromoCode = notification.batchId
                appState.showingPlanSelection = true
            }
        case "paymentReview":
            dismiss()
            // Switch to job board first, then post the review-open notification
            // after the JobBoardView has had time to mount its onReceive handler.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("OpenJobBoard"), object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    NotificationCenter.default.post(name: Notification.Name("OpenPaymentReview"), object: nil)
                }
            }
        case "taskReview":
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("OpenJobBoard"), object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    NotificationCenter.default.post(name: Notification.Name("OpenTaskReview"), object: nil)
                }
            }
        case "photoStorage":
            // Cap-hit from PhotoPrefetchService. Hand the baton to the
            // notification sheet's onDismiss callback (AppHeader) so the
            // photo-storage sheet only presents AFTER this sheet is fully
            // gone — avoids sheet-on-sheet deadlock.
            appState.pendingRailDeepLink = "photoStorage"
            dismiss()
        default:
            // Deep link to project if applicable
            if let projectId = notification.projectId, !projectId.isEmpty {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    appState.viewProjectDetailsById(projectId)
                }
            }
        }
    }

    private func markAllAsRead() {
        guard let userId = UserDefaults.standard.string(forKey: "user_id"), !userId.isEmpty else { return }

        Task {
            let repo = NotificationRepository()
            try? await repo.markAllAsRead(userId: userId)
            await MainActor.run {
                appState.unreadNotificationCount = 0
            }
            await loadNotifications()
        }
    }

    // MARK: - Helpers

    /// Parses an ISO8601 timestamp string from Supabase, tolerating both
    /// fractional-second and whole-second forms.
    private func parseCreatedAt(_ isoString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: isoString)
    }

    private func relativeTime(_ isoString: String) -> String {
        guard let date = parseCreatedAt(isoString) else { return "" }
        let relFormatter = RelativeDateTimeFormatter()
        relFormatter.unitsStyle = .abbreviated
        return relFormatter.localizedString(for: date, relativeTo: Date())
    }
}
