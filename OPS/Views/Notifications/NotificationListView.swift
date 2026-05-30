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

    enum NotificationFilter: String, CaseIterable {
        case unread = "Unread"
        case all    = "All"
    }

    @State private var notifications: [NotificationDTO] = []
    @State private var isLoading = true
    @State private var showingOlder = false
    @State private var filter: NotificationFilter = .unread
    @State private var expandedId: String? = nil

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header — matches SettingsHeader pattern
                HStack {
                    Button(action: { dismiss() }) {
                        Image(OPSStyle.Icons.chevronLeft)
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

                // All / Unread filter — Bug c5860693: replaced default
                // .pickerStyle(.segmented) (UIKit-rendered, off-brand on the
                // dark canvas) with the OPS-native SettingsSegmentedPicker.
                // Subtle fill on the active segment, tertiaryText on inactive,
                // matches every other in-app filter (settings notifications,
                // permissions tabs, etc.).
                SettingsSegmentedPicker(
                    selection: filter,
                    options: [
                        (NotificationFilter.unread, "UNREAD"),
                        (NotificationFilter.all, "ALL")
                    ],
                    onChange: { filter = $0 }
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing2)

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

                            if filteredNotifications.isEmpty {
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
            Image("ops.notification-muted")
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
            Image("ops.notification-muted")
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

    /// Notifications after applying the current filter (All / Unread).
    /// Bug 5a19b120 — when a row is expanded we mark it read locally so the
    /// unread dot/badge update, but the row must stay visible until the user
    /// collapses it. Otherwise the moment they tap to expand, the notification
    /// disappears from the Unread list before they can read its body.
    /// Allowing the currently-expanded id to bypass the unread filter keeps
    /// the row anchored while the user reads it; it falls out only after
    /// they collapse the row (or the next list reload).
    private var filteredNotifications: [NotificationDTO] {
        switch filter {
        case .all:    return notifications
        case .unread: return notifications.filter { !$0.isRead || $0.id == expandedId }
        }
    }

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

        for notification in filteredNotifications {
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
        // Bug G2 — each row is now a glass surface card with its own border,
        // so the inter-row dividers have been removed; the row's internal
        // horizontal padding handles edge breathing room.
        ForEach(items, id: \.id) { notif in
            notificationRow(notif)
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

                Image(OPSStyle.Icons.chevronUp)
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

                Image(OPSStyle.Icons.chevronDown)
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
        let isExpanded = expandedId == notification.id

        return VStack(alignment: .leading, spacing: 0) {
            // Collapsed header — always visible
            Button(action: {
                withAnimation(collapseAnimation) {
                    if isExpanded {
                        expandedId = nil
                    } else {
                        expandedId = notification.id
                        // Mark as read on expand
                        markAsRead(notification)
                    }
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }) {
                HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2_5) {
                    // Leading accent column: unread dot + icon
                    VStack(spacing: 6) {
                        Circle()
                            .fill(notification.isRead ? Color.clear : OPSStyle.Colors.primaryAccent)
                            .frame(width: 6, height: 6)

                        notificationIcon(for: notification.type)
                    }
                    .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                            Text(notification.title.uppercased())
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(
                                    notification.isRead
                                        ? OPSStyle.Colors.secondaryText
                                        : OPSStyle.Colors.primaryText
                                )
                                .tracking(0.5)
                                .lineLimit(1)

                            Spacer(minLength: OPSStyle.Layout.spacing2)

                            Text(relativeTime(notification.createdAt))
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        Text(notification.body)
                            .font(OPSStyle.Typography.smallBody)
                            .foregroundColor(
                                notification.isRead
                                    ? OPSStyle.Colors.tertiaryText
                                    : OPSStyle.Colors.secondaryText
                            )
                            .lineLimit(isExpanded ? nil : 1)
                            .truncationMode(.tail)
                    }

                    Image(isExpanded ? OPSStyle.Icons.chevronUp : OPSStyle.Icons.chevronDown)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.top, 4)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded detail — full body + deep-link action button
            if isExpanded {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorderSubtle)
                        .frame(height: 1)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)

                    Text(notification.body)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.top, OPSStyle.Layout.spacing2)

                    // Deep-link action if applicable. Expense / invoice
                    // notifications with no explicit deep_link_type still
                    // route by `notification.type` (Bug bb63c37e fallback)
                    // so we surface the button for those legacy rows too.
                    let typeImpliesDeepLink: Bool = {
                        switch notification.type {
                        case "expense_submitted", "expense_approved", "expense_rejected",
                             "invoice_approved", "invoice_revisions", "invoice_overdue":
                            return true
                        default: return false
                        }
                    }()
                    let hasDeepLink = (notification.projectId != nil && !(notification.projectId?.isEmpty ?? true))
                        || (notification.deepLinkType != nil && !(notification.deepLinkType?.isEmpty ?? true))
                        || typeImpliesDeepLink
                    if hasDeepLink {
                        let actionLabel: String = {
                            // When deep_link_type is set, use the type-specific
                            // label (handled below). Project-id-only rows show
                            // VIEW PROJECT.
                            if (notification.deepLinkType ?? "").isEmpty,
                               let projectId = notification.projectId, !projectId.isEmpty {
                                return "VIEW PROJECT"
                            }
                            // Legacy type-based fallback labels.
                            if (notification.deepLinkType ?? "").isEmpty {
                                switch notification.type {
                                case "expense_submitted", "expense_approved", "expense_rejected":
                                    return "VIEW EXPENSES"
                                case "invoice_approved", "invoice_revisions", "invoice_overdue":
                                    return "VIEW INVOICES"
                                default:
                                    return "OPEN"
                                }
                            }
                            switch notification.deepLinkType ?? "" {
                            case "subscription", "trial_expiry":   return "VIEW PLAN"
                            case "paymentReview":                  return "REVIEW PAYMENTS"
                            case "taskReview":                     return "REVIEW TASKS"
                            case "unscheduledReview":              return "REVIEW SCHEDULE"
                            case "photoStorage":                   return "MANAGE PHOTOS"
                            case "catalogOrders":                  return notification.actionLabel ?? "REVIEW"
                            case "expense", "expenses",
                                 "expenseReview", "invoice_detail": return "VIEW EXPENSES"
                            case "invoice", "invoices":            return "VIEW INVOICES"
                            case "projectsNeedingTasks":           return "PLAN THE WORK"
                            case "inbox", "email_sync_complete":   return "VIEW DETAILS"
                            case "cashflow":                       return notification.actionLabel ?? "REVIEW FORECAST"
                            default:                               return notification.actionLabel ?? "OPEN"
                            }
                        }()

                        Button(action: {
                            handleNotificationTap(notification)
                        }) {
                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                Image("ops.arrow-right")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                Text(actionLabel)
                                    .font(OPSStyle.Typography.captionBold)
                                    .tracking(0.5)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }

                    Spacer().frame(height: OPSStyle.Layout.spacing2)
                }
                .transition(collapseTransition)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                .fill(OPSStyle.Colors.cardBackgroundDark.opacity(isExpanded ? 0.9 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                .stroke(
                    isExpanded ? OPSStyle.Colors.primaryAccent.opacity(0.25) : OPSStyle.Colors.cardBorderSubtle,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, 4)
    }

    /// Mark a notification as read in local state and sync to server.
    private func markAsRead(_ notification: NotificationDTO) {
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }),
              !notifications[index].isRead else { return }
        notifications[index].isRead = true
        appState.unreadNotificationCount = max(0, appState.unreadNotificationCount - 1)
        Task {
            let repo = NotificationRepository()
            try? await repo.markAsRead(notification.id)
        }
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
            case "threshold_alert":
                return ("exclamationmark.triangle.fill", OPSStyle.Colors.warningStatus)
            case "catalog_order_drafted":
                return ("shippingbox.fill", OPSStyle.Colors.successStatus)
            case "time_off_requested":
                return ("calendar.badge.clock", OPSStyle.Colors.warningStatus)
            case "time_off_approved":
                return ("calendar.badge.checkmark", OPSStyle.Colors.successStatus)
            case "time_off_denied":
                return ("calendar.badge.exclamationmark", OPSStyle.Colors.errorStatus)
            case "invoice_overdue":
                return ("exclamationmark.circle", OPSStyle.Colors.errorStatus)
            case "task_review_stack":
                return ("tray.full", OPSStyle.Colors.warningStatus)
            case "payment_review_stack":
                return ("dollarsign.circle", OPSStyle.Colors.warningStatus)
            case "unscheduled_review_stack":
                return ("calendar.badge.exclamationmark", OPSStyle.Colors.warningStatus)
            case "photo_storage_limit":
                return ("externaldrive.fill.badge.exclamationmark", OPSStyle.Colors.warningStatus)
            case "projects_needing_tasks":
                return ("folder.badge.plus", OPSStyle.Colors.warningStatus)
            case "email_sync_complete":
                return ("envelope.badge", OPSStyle.Colors.primaryAccent)
            case "stale_estimate_review":
                return ("clock.arrow.circlepath", OPSStyle.Colors.warningStatus)
            case "expense_approved":
                return ("checkmark.seal", OPSStyle.Colors.successStatus)
            case "expense_rejected":
                return ("xmark.seal", OPSStyle.Colors.errorStatus)
            // LiDAR Dimensioned Photo Capture — spec §6 / Phase G.
            // `ruler` matches the MEASURE entry on `ProjectActionBar` so the
            // user can trace a rail card back to the originating capture flow.
            case "measurement_captured":
                return ("ruler", OPSStyle.Colors.successStatus)
            case "measurement_pending_sync":
                return ("ruler.fill", OPSStyle.Colors.warningStatus)
            case "measurement_sync_failed":
                return ("ruler", OPSStyle.Colors.errorStatus)
            case "update":
                return (OPSStyle.Icons.sync, OPSStyle.Colors.secondaryText)
            default:
                return (OPSStyle.Icons.bell, OPSStyle.Colors.secondaryText)
            }
        }()

        return Image(systemName: iconName)
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(color)
            .frame(width: 28, height: 28)
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
        // Light impact earns its place here — this is a meaningful navigation
        // commit (opens a detail surface), matches the app-wide pattern used
        // for list-row taps that transition the user somewhere.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

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
        case "unscheduledReview":
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("OpenJobBoard"), object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    NotificationCenter.default.post(name: Notification.Name("OpenUnscheduledReview"), object: nil)
                }
            }
        case "photoStorage":
            // Cap-hit from PhotoPrefetchService. Hand the baton to the
            // notification sheet's onDismiss callback (AppHeader) so the
            // photo-storage sheet only presents AFTER this sheet is fully
            // gone — avoids sheet-on-sheet deadlock.
            appState.pendingRailDeepLink = "photoStorage"
            dismiss()
        case "catalogOrders":
            // Threshold rail entry. Switch to the catalog tab, then ask
            // CatalogView to present OrdersSheet at the right sub-segment.
            // The query string on `actionUrl` carries the tab name so the
            // same notification can land on suggested / draft / sent.
            let subSegment = subSegmentFromActionUrl(notification.actionUrl) ?? "SUGGESTED"
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("OpenCatalog"), object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    NotificationCenter.default.post(
                        name: Notification.Name("OpenCatalogOrders"),
                        object: nil,
                        userInfo: ["subSegment": subSegment]
                    )
                }
            }
        case "expense", "expenses", "expenseReview":
            // Bug 8ed0d2ed — expense notifications previously fell through to
            // `default` which only handled projectId, leaving the deep link
            // dead. Route to the Expenses list (admin) or My Expenses (crew)
            // via OpenExpenses; MainTabView handles the permission split and
            // tab switch.
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("OpenExpenses"), object: nil)
            }
        case "invoice", "invoices":
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("OpenInvoices"), object: nil)
            }
        case "projectsNeedingTasks":
            // Bug 78309d78 — rail notification for accepted projects with
            // zero tasks. Mounted as a sheet at MainTabView so it survives
            // the notification rail dismissal.
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appState.showProjectsNeedingTasksReview = true
            }
        case "inbox", "email_sync_complete":
            // Email-sync notifications come from the web sync engine. iOS
            // has no inbox surface yet — route to the project if the matched
            // email was attached to one (`projectId` set). Otherwise fall
            // back to JobBoard so the user lands on actionable surface
            // rather than a dead tap.
            if let projectId = notification.projectId, !projectId.isEmpty {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    appState.viewProjectDetailsById(projectId)
                }
            } else {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: Notification.Name("OpenJobBoard"), object: nil)
                }
            }
        case "invoice_detail":
            // Legacy alias — old expense_submitted rows landed here by mistake.
            // Treated identically to "expense" so existing rail entries route
            // correctly without backfill.
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("OpenExpenses"), object: nil)
            }
        case "cashflow":
            // Cashflow forecast dip / cleared notification. Switch to Books,
            // then post OpenCashflowForecast so BooksTabView presents the
            // forecast screen after the tab swap has settled.
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: Notification.Name("OpenBooks"), object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    NotificationCenter.default.post(name: Notification.Name("OpenCashflowForecast"), object: nil)
                }
            }
        default:
            // Bug bb63c37e — when deep_link_type is missing, fall back to the
            // notification's `type` so legacy rows still route correctly. Old
            // expense_submitted / invoice_* notifications were inserted before
            // the deep_link_type column existed, so the only routing signal
            // they carry is their `type`.
            switch notification.type {
            case "expense_submitted",
                 "expense_approved",
                 "expense_rejected":
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: Notification.Name("OpenExpenses"), object: nil)
                }
            case "invoice_approved",
                 "invoice_revisions",
                 "invoice_overdue":
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: Notification.Name("OpenInvoices"), object: nil)
                }
            default:
                // Final fallback — deep link to project if available.
                if let projectId = notification.projectId, !projectId.isEmpty {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        appState.viewProjectDetailsById(projectId)
                    }
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

    /// Parses the `tab=<value>` query parameter from `ops://catalog/orders?tab=...`
    /// and maps it to the OrdersSubSegment rawValue used by OrdersSheet.
    /// Returns nil when the URL is missing, malformed, or carries an unknown
    /// tab value — caller defaults to SUGGESTED in that case.
    private func subSegmentFromActionUrl(_ urlString: String?) -> String? {
        guard let urlString = urlString,
              let comps = URLComponents(string: urlString),
              let tab = comps.queryItems?.first(where: { $0.name == "tab" })?.value else {
            return nil
        }
        switch tab.lowercased() {
        case "suggested": return "SUGGESTED"
        case "draft", "drafts": return "DRAFT"
        case "sent":      return "SENT"
        default:          return nil
        }
    }
}
