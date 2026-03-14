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

    @State private var notifications: [NotificationDTO] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .edgesIgnoringSafeArea(.all)

            if isLoading {
                ProgressView()
                    .tint(OPSStyle.Colors.primaryAccent)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        userInfoHeader

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
        .trackScreen("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("NOTIFICATIONS")
                    .font(OPSStyle.Typography.caption)
                    .tracking(0.5)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Text("DONE")
                        .font(OPSStyle.Typography.smallCaption)
                        .tracking(0.3)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !notifications.isEmpty {
                    Button {
                        markAllAsRead()
                    } label: {
                        Text("MARK ALL READ")
                            .font(OPSStyle.Typography.miniLabel)
                            .tracking(0.3)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
        }
        .task {
            await loadNotifications()
        }
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
                    // Avatar (uses profile image or initials)
                    UserAvatar(user: user, size: 56)

                    // Name
                    Text("\(user.firstName) \(user.lastName)")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    // Company name
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
            }
        }
    }

    // MARK: - Notification List

    private var notificationListContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(notifications) { notification in
                notificationRow(notification)

                if notification.id != notifications.last?.id {
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorderSubtle)
                        .frame(height: 1)
                        .padding(.leading, 56)
                }
            }
        }
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
            case "assignment":
                return (OPSStyle.Icons.assignmentNotification, OPSStyle.Colors.successStatus)
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

        // Deep link to project if applicable
        if let projectId = notification.projectId, !projectId.isEmpty {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                appState.viewProjectDetailsById(projectId)
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

    private func relativeTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoString) else {
                return ""
            }
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        let relFormatter = RelativeDateTimeFormatter()
        relFormatter.unitsStyle = .abbreviated
        return relFormatter.localizedString(for: date, relativeTo: Date())
    }
}
