//
//  NotificationSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-12.
//

import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    // MARK: - Supabase-Backed State

    @State private var preferences: NotificationPreferencesDTO?
    @State private var isLoading = true
    @State private var loadError: String?

    // MARK: - Local-Only Settings (remain in @AppStorage)

    // Advance notice settings — iOS-only local UNNotification scheduling
    @AppStorage("notifyAdvanceNotice") private var notifyProjectAdvance = true
    @AppStorage("advanceNoticeDays1") private var advanceNoticeDays1 = 1
    @AppStorage("advanceNoticeDays2") private var advanceNoticeDays2 = 0
    @AppStorage("advanceNoticeDays3") private var advanceNoticeDays3 = 0
    @AppStorage("advanceNoticeHour") private var advanceNoticeHour = 8
    @AppStorage("advanceNoticeMinute") private var advanceNoticeMinute = 0

    // Temporary mute — device-only concept
    @AppStorage("isMuted") private var isMuted = false
    @AppStorage("muteUntil") private var muteUntil: Double = 0
    @State private var muteHours: Int = 1

    // Priority filter — local display filter
    @AppStorage("notificationPriority") private var notificationPriority = "all"

    // MARK: - Repository

    private let repository = NotificationPreferencesRepository()

    // Computed property for the notification time
    private var notificationTime: Date {
        get {
            var components = DateComponents()
            components.hour = advanceNoticeHour
            components.minute = advanceNoticeMinute
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            advanceNoticeHour = components.hour ?? 8
            advanceNoticeMinute = components.minute ?? 0
        }
    }

    // Computed property for reminder summary text
    private var reminderSummaryText: String {
        var activeDays: [Int] = []
        activeDays.append(advanceNoticeDays1)
        if advanceNoticeDays2 > 0 { activeDays.append(advanceNoticeDays2) }
        if advanceNoticeDays3 > 0 { activeDays.append(advanceNoticeDays3) }

        let dayText: String
        switch activeDays.count {
        case 1:
            dayText = "\(activeDays[0]) day\(activeDays[0] == 1 ? "" : "s") before"
        case 2:
            dayText = "\(activeDays[0]) & \(activeDays[1]) days before"
        case 3:
            dayText = "\(activeDays[0]), \(activeDays[1]) & \(activeDays[2]) days before"
        default:
            dayText = "No reminders set"
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeString = formatter.string(from: notificationTime)
        return "\(dayText) at \(timeString)"
    }

    // MARK: - Event Type Grouping

    /// Event types grouped by section for the UI
    private let projectEventTypes: [NotificationEventType] = [
        .taskAssigned, .taskCompleted, .scheduleChanges, .projectUpdates, .teamMentions
    ]

    private let financialEventTypes: [NotificationEventType] = [
        .expenseSubmitted, .expenseApproved, .invoiceSent, .paymentReceived
    ]

    private let otherEventTypes: [NotificationEventType] = [
        .dailyDigest
    ]

    // Bug e33aa336 — anchor IDs for ScrollViewReader. One per section in
    // the UI; a settings-search deep-link with a matching `section` value
    // scrolls to and pulses the corresponding section.
    private enum AnchorID {
        static let projectNotifications = "project_notifications"
        static let financialNotifications = "financial_notifications"
        static let otherNotifications = "other_notifications"
        static let quietHours = "quiet_hours"
        static let advanceReminders = "advance_reminders"
        static let testNotifications = "test_notifications"
        static let temporaryMute = "temporary_mute"
    }

    @State private var highlightedSection: String? = nil

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Notifications",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 24)

                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        // Permission Status Card
                        notificationStatusCard

                        if isLoading {
                            loadingCard
                        } else if let error = loadError {
                            errorCard(error)
                        } else {
                            // Channel Preferences — Project Updates
                            settingsSection(title: "PROJECT NOTIFICATIONS") {
                                channelPreferencesSection(eventTypes: projectEventTypes)
                            }
                            .id(AnchorID.projectNotifications)
                            .deepLinkSpotlight(highlightedSection == AnchorID.projectNotifications)

                            // Channel Preferences — Financial
                            settingsSection(title: "FINANCIAL NOTIFICATIONS") {
                                channelPreferencesSection(eventTypes: financialEventTypes)
                            }
                            .id(AnchorID.financialNotifications)
                            .deepLinkSpotlight(highlightedSection == AnchorID.financialNotifications)

                            // Channel Preferences — Other
                            settingsSection(title: "OTHER") {
                                channelPreferencesSection(eventTypes: otherEventTypes)
                            }
                            .id(AnchorID.otherNotifications)
                            .deepLinkSpotlight(highlightedSection == AnchorID.otherNotifications)

                            // Quiet Hours (Supabase-backed)
                            settingsSection(title: "QUIET HOURS") {
                                quietHoursSettings
                            }
                            .id(AnchorID.quietHours)
                            .deepLinkSpotlight(highlightedSection == AnchorID.quietHours)
                        }

                        // Advance Notice Section (local-only)
                        settingsSection(title: "ADVANCE REMINDERS") {
                            advanceNoticeSettings
                        }
                        .id(AnchorID.advanceReminders)
                        .deepLinkSpotlight(highlightedSection == AnchorID.advanceReminders)

                        // Test Notification Section
                        settingsSection(title: "TEST NOTIFICATIONS") {
                            testNotificationCard
                        }
                        .id(AnchorID.testNotifications)
                        .deepLinkSpotlight(highlightedSection == AnchorID.testNotifications)

                        // Temporary Mute Section (local-only)
                        settingsSection(title: "TEMPORARY MUTE") {
                            temporaryMuteSettings
                        }
                        .id(AnchorID.temporaryMute)
                        .deepLinkSpotlight(highlightedSection == AnchorID.temporaryMute)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .wizardTarget("configure_notifications")
                // Bug e33aa336 — settings search deep-link target. Scroll
                // to and pulse the matching section once the cover lands.
                .onReceive(NotificationCenter.default.publisher(for: SettingsDeepLink.notifications)) { notification in
                    guard let section = notification.userInfo?[SettingsDeepLink.userInfoSectionKey] as? String else { return }
                    handleDeepLink(section: section, proxy: proxy)
                }
                }
            }
        }
        .trackScreen("Settings.Notifications")
        .navigationBarBackButtonHidden(true)
        .onDisappear {
            NotificationCenter.default.post(
                name: Notification.Name("WizardScreenDismissed"),
                object: nil,
                userInfo: ["screen": "NotificationSettings"]
            )
        }
        .onAppear {
            notificationManager.getAuthorizationStatus()
            checkMuteExpiration()
            NotificationCenter.default.post(name: Notification.Name("WizardNotificationsConfigured"), object: nil)
            loadPreferences()
        }
    }

    /// Resolve a search-result section identifier to a scroll anchor and
    /// run the spotlight animation. Unknown sections are no-ops, so a
    /// future search entry pointing at a section that doesn't exist yet
    /// simply lands the user at the top of the page (graceful degradation).
    private func handleDeepLink(section: String, proxy: ScrollViewProxy) {
        let anchor: String?
        switch section {
        case "project_notifications":   anchor = AnchorID.projectNotifications
        case "financial_notifications": anchor = AnchorID.financialNotifications
        case "other_notifications":    anchor = AnchorID.otherNotifications
        case "quiet_hours":             anchor = AnchorID.quietHours
        case "advance_reminders":       anchor = AnchorID.advanceReminders
        case "test_notifications":      anchor = AnchorID.testNotifications
        case "temporary_mute":          anchor = AnchorID.temporaryMute
        default: anchor = nil
        }
        guard let anchor else { return }

        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(OPSStyle.Animation.smooth) {
            proxy.scrollTo(anchor, anchor: .top)
        }
        withAnimation(.easeIn(duration: 0.2).delay(0.15)) {
            highlightedSection = anchor
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                withAnimation(OPSStyle.Animation.fast) {
                    highlightedSection = nil
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadPreferences() {
        guard let userId = UserDefaults.standard.string(forKey: "currentUserId"),
              let companyId = UserDefaults.standard.string(forKey: "company_id") else {
            loadError = "Not signed in"
            isLoading = false
            return
        }

        Task {
            do {
                let fetched = try await repository.fetchPreferences(userId: userId, companyId: companyId)
                await MainActor.run {
                    self.preferences = fetched
                    self.isLoading = false
                    // Cache for NotificationManager
                    notificationManager.cachedChannelPreferences = fetched.channelPreferences
                    notificationManager.cachedPushEnabled = fetched.pushEnabled
                }
            } catch {
                await MainActor.run {
                    self.loadError = "Could not load preferences"
                    self.isLoading = false
                    print("[NOTIFICATION PREFS] Fetch error: \(error)")
                }
            }
        }
    }

    // MARK: - Gold Standard Helpers

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

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

    // MARK: - Loading & Error States

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(OPSStyle.Colors.loadingSpinner)
            Text("Loading preferences...")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(OPSStyle.Icons.exclamationmarkTriangleFill)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                Text(message)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }

            Button {
                isLoading = true
                loadError = nil
                loadPreferences()
            } label: {
                Text("RETRY")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Notification Status Card

    private var notificationStatusCard: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Circle()
                .fill(notificationManager.isNotificationsEnabled
                      ? OPSStyle.Colors.successStatus
                      : OPSStyle.Colors.errorStatus)
                .frame(width: OPSStyle.Layout.Indicator.dotMD,
                       height: OPSStyle.Layout.Indicator.dotMD)

            VStack(alignment: .leading, spacing: 2) {
                Text(notificationManager.isNotificationsEnabled
                     ? "NOTIFICATIONS ENABLED"
                     : "NOTIFICATIONS DISABLED")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(notificationManager.isNotificationsEnabled
                     ? "Stay updated on projects"
                     : "Enable to receive updates")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            Button {
                if notificationManager.isNotificationsEnabled {
                    notificationManager.openAppSettings()
                } else {
                    notificationManager.requestPermission { _ in }
                }
            } label: {
                Text(notificationManager.isNotificationsEnabled ? "MANAGE" : "ENABLE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(notificationManager.isNotificationsEnabled
                                     ? OPSStyle.Colors.primaryAccent
                                     : OPSStyle.Colors.invertedText)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .padding(.vertical, OPSStyle.Layout.spacing1)
                    .background(notificationManager.isNotificationsEnabled
                                ? Color.clear
                                : OPSStyle.Colors.primaryText)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(notificationManager.isNotificationsEnabled
                                    ? OPSStyle.Colors.primaryAccent
                                    : Color.clear,
                                    lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Channel Mode Enum

    /// Represents the four notification delivery modes for a single event type
    private enum ChannelMode: String, CaseIterable {
        case off = "OFF"
        case phone = "PHONE"
        case email = "EMAIL"
        case both = "BOTH"

        static func from(toggle: ChannelToggle) -> ChannelMode {
            switch (toggle.push, toggle.email) {
            case (false, false): return .off
            case (true, false):  return .phone
            case (false, true):  return .email
            case (true, true):   return .both
            }
        }

        var toToggle: ChannelToggle {
            switch self {
            case .off:   return ChannelToggle(push: false, email: false)
            case .phone: return ChannelToggle(push: true, email: false)
            case .email: return ChannelToggle(push: false, email: true)
            case .both:  return ChannelToggle(push: true, email: true)
            }
        }
    }

    // MARK: - Channel Preferences Section (matches Permission Override layout)

    private func channelPreferencesSection(eventTypes: [NotificationEventType]) -> some View {
        VStack(spacing: 0) {
            // Category header with bulk picker (lighter background — matches permissions)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("ALL IN SECTION")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    if sectionBulkMode(eventTypes: eventTypes) == nil {
                        Text("MIXED")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }

                SettingsSegmentedPicker(
                    selection: sectionBulkMode(eventTypes: eventTypes),
                    options: ChannelMode.allCases.map { ($0, $0.rawValue) },
                    isMixed: sectionBulkMode(eventTypes: eventTypes) == nil
                ) { newMode in
                    for eventType in eventTypes {
                        setChannelMode(eventType: eventType, mode: newMode)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(OPSStyle.Colors.subtleBackground)

            // Individual event type rows (darker background)
            ForEach(eventTypes, id: \.self) { eventType in
                Rectangle()
                    .fill(OPSStyle.Colors.cardBorderSubtle)
                    .frame(height: 1)

                channelPreferenceRow(eventType: eventType)
            }
        }
    }

    /// Determine the bulk mode for a section (mixed → nil, uniform → that mode)
    private func sectionBulkMode(eventTypes: [NotificationEventType]) -> ChannelMode? {
        let modes = eventTypes.map { eventType -> ChannelMode in
            let toggle = preferences?.toggle(for: eventType) ?? ChannelToggle(push: true, email: false)
            return ChannelMode.from(toggle: toggle)
        }
        let unique = Set(modes)
        return unique.count == 1 ? unique.first : nil
    }

    private func channelPreferenceRow(eventType: NotificationEventType) -> some View {
        let toggle = preferences?.toggle(for: eventType) ?? ChannelToggle(push: true, email: false)
        let currentMode = ChannelMode.from(toggle: toggle)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(eventType.displayName)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(currentMode != .off ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)

                Spacer()

                Text(eventType.displayDescription)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }

            SettingsSegmentedPicker(
                selection: currentMode,
                options: ChannelMode.allCases.map { ($0, $0.rawValue) },
                isMixed: false
            ) { newMode in
                setChannelMode(eventType: eventType, mode: newMode)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // Picker is now SettingsSegmentedPicker in Styles/Components/SegmentedControl.swift

    /// Set channel mode for a single event type — updates both push and email in one write
    private func setChannelMode(eventType: NotificationEventType, mode: ChannelMode) {
        let newToggle = mode.toToggle

        // Optimistic local update
        guard var prefs = preferences else { return }
        prefs.channelPreferences[eventType.rawValue] = newToggle
        preferences = prefs

        // Update NotificationManager cache
        notificationManager.cachedChannelPreferences = prefs.channelPreferences

        // Write-through to Supabase (update both channels)
        guard let userId = UserDefaults.standard.string(forKey: "currentUserId"),
              let companyId = UserDefaults.standard.string(forKey: "company_id") else { return }

        Task {
            do {
                try await repository.updateChannelPreference(
                    userId: userId,
                    companyId: companyId,
                    eventType: eventType.rawValue,
                    channel: "push",
                    enabled: newToggle.push
                )
                try await repository.updateChannelPreference(
                    userId: userId,
                    companyId: companyId,
                    eventType: eventType.rawValue,
                    channel: "email",
                    enabled: newToggle.email
                )
            } catch {
                print("[NOTIFICATION PREFS] Channel mode update failed, reverting: \(error)")
                loadPreferences()
            }
        }
    }

    // MARK: - Channel Toggle Write-Through (legacy — kept for quiet hours compatibility)

    // MARK: - Quiet Hours (Supabase-backed)

    private var quietHoursSettings: some View {
        let isEnabled = preferences?.quietHoursStart != nil

        return VStack(spacing: 0) {
            // Enable toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quiet Hours")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("Silence notifications during set hours")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        if newValue {
                            updateQuietHours(startHour: 22, endHour: 7)
                        } else {
                            clearQuietHours()
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.primaryAccent))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)

            if isEnabled {
                Divider().background(OPSStyle.Colors.cardBorder)

                VStack(alignment: .leading, spacing: 12) {
                    Text("QUIET HOURS")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    HStack(spacing: 16) {
                        // Start time picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("From")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Menu {
                                ForEach(0..<24, id: \.self) { hour in
                                    Button {
                                        updateQuietHours(startHour: hour, endHour: quietHoursEndInt)
                                    } label: {
                                        if quietHoursStartInt == hour {
                                            Label(formatHour(hour), image: OPSStyle.Icons.checkmark)
                                        } else {
                                            Text(formatHour(hour))
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(formatHour(quietHoursStartInt))
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    Image(OPSStyle.Icons.chevronDown)
                                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(OPSStyle.Colors.cardBackground)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                        }

                        // End time picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("To")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Menu {
                                ForEach(0..<24, id: \.self) { hour in
                                    Button {
                                        updateQuietHours(startHour: quietHoursStartInt, endHour: hour)
                                    } label: {
                                        if quietHoursEndInt == hour {
                                            Label(formatHour(hour), image: OPSStyle.Icons.checkmark)
                                        } else {
                                            Text(formatHour(hour))
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(formatHour(quietHoursEndInt))
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    Image(OPSStyle.Icons.chevronDown)
                                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(OPSStyle.Colors.cardBackground)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                        }

                        Spacer()
                    }

                    Text("Notifications silenced \(formatHour(quietHoursStartInt)) - \(formatHour(quietHoursEndInt))")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.top, 4)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
        }
    }

    /// Parse quiet_hours_start TIME string (e.g. "22:00:00") to hour int
    private var quietHoursStartInt: Int {
        guard let str = preferences?.quietHoursStart else { return 22 }
        return parseHour(from: str)
    }

    private var quietHoursEndInt: Int {
        guard let str = preferences?.quietHoursEnd else { return 7 }
        return parseHour(from: str)
    }

    private func parseHour(from timeString: String) -> Int {
        let parts = timeString.split(separator: ":")
        guard let hour = parts.first, let h = Int(hour) else { return 0 }
        return h
    }

    private func updateQuietHours(startHour: Int, endHour: Int) {
        let startStr = String(format: "%02d:00:00", startHour)
        let endStr = String(format: "%02d:00:00", endHour)

        // Optimistic update
        preferences?.quietHoursStart = startStr
        preferences?.quietHoursEnd = endStr

        // Also keep local @AppStorage in sync for NotificationManager's shouldSendNotification
        UserDefaults.standard.set(true, forKey: "quietHoursEnabled")
        UserDefaults.standard.set(startHour, forKey: "quietHoursStart")
        UserDefaults.standard.set(endHour, forKey: "quietHoursEnd")

        guard let userId = UserDefaults.standard.string(forKey: "currentUserId"),
              let companyId = UserDefaults.standard.string(forKey: "company_id") else { return }

        Task {
            do {
                try await repository.updateQuietHours(
                    userId: userId,
                    companyId: companyId,
                    start: startStr,
                    end: endStr
                )
            } catch {
                print("[NOTIFICATION PREFS] Quiet hours update failed: \(error)")
                loadPreferences()
            }
        }
    }

    private func clearQuietHours() {
        preferences?.quietHoursStart = nil
        preferences?.quietHoursEnd = nil

        UserDefaults.standard.set(false, forKey: "quietHoursEnabled")

        guard let userId = UserDefaults.standard.string(forKey: "currentUserId"),
              let companyId = UserDefaults.standard.string(forKey: "company_id") else { return }

        Task {
            do {
                try await repository.updateQuietHours(
                    userId: userId,
                    companyId: companyId,
                    start: nil,
                    end: nil
                )
            } catch {
                print("[NOTIFICATION PREFS] Quiet hours clear failed: \(error)")
                loadPreferences()
            }
        }
    }

    // MARK: - Advance Notice Settings (local-only, unchanged)

    private var advanceNoticeSettings: some View {
        VStack(spacing: 0) {
            SettingsToggle(
                title: "Enable Advance Reminders",
                description: "Get notified before projects start",
                isOn: $notifyProjectAdvance
            )
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .onChange(of: notifyProjectAdvance) { _, newValue in
                if newValue {
                    rescheduleAllNotifications()
                } else {
                    Task {
                        await notificationManager.removeAllAdvanceNotices()
                    }
                }
            }

            if notifyProjectAdvance {
                Divider().background(OPSStyle.Colors.cardBorder)

                VStack(alignment: .leading, spacing: 12) {
                    Text("REMINDER SCHEDULE")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    HStack(spacing: 12) {
                        DaySelector(value: $advanceNoticeDays1, label: "First", allowNone: false)
                            .onChange(of: advanceNoticeDays1) { _, _ in rescheduleAllNotifications() }
                        DaySelector(value: $advanceNoticeDays2, label: "Second", allowNone: true)
                            .onChange(of: advanceNoticeDays2) { _, _ in rescheduleAllNotifications() }
                        DaySelector(value: $advanceNoticeDays3, label: "Third", allowNone: true)
                            .onChange(of: advanceNoticeDays3) { _, _ in rescheduleAllNotifications() }
                    }

                    Text(reminderSummaryText)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)

                Divider().background(OPSStyle.Colors.cardBorder)

                VStack(alignment: .leading, spacing: 12) {
                    Text("NOTIFICATION TIME")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    HStack {
                        Text("Send reminders at")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()

                        DatePicker("", selection: Binding(
                            get: { self.notificationTime },
                            set: { newValue in
                                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                self.advanceNoticeHour = components.hour ?? 8
                                self.advanceNoticeMinute = components.minute ?? 0
                                self.rescheduleAllNotifications()
                            }
                        ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .colorScheme(.dark)
                        .accentColor(OPSStyle.Colors.primaryAccent)
                        .scaleEffect(0.9)
                        .frame(height: 36)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Test Notification

    private var testNotificationCard: some View {
        VStack(spacing: 16) {
            Text("Send a test to verify settings")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                sendTestNotification()
            } label: {
                HStack {
                    Image(OPSStyle.Icons.bell)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))

                    Text("SEND TEST NOTIFICATION")
                        .font(OPSStyle.Typography.button)
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.thick)
                )
            }
            .disabled(!notificationManager.isNotificationsEnabled)
            .opacity(notificationManager.isNotificationsEnabled ? 1.0 : 0.5)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

    // MARK: - Temporary Mute Settings (local-only, unchanged)

    private var temporaryMuteSettings: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mute All Notifications")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("Silence all notifications temporarily")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()

                Toggle("", isOn: $isMuted)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.primaryAccent))
                    .onChange(of: isMuted) { _, newValue in
                        if newValue {
                            muteUntil = Date().addingTimeInterval(Double(muteHours) * 3600).timeIntervalSince1970
                        } else {
                            muteUntil = 0
                        }
                    }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)

            if isMuted {
                Divider().background(OPSStyle.Colors.cardBorder)

                VStack(alignment: .leading, spacing: 12) {
                    Text("MUTE DURATION")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    HStack(spacing: 8) {
                        ForEach([1, 2, 4, 8, 24], id: \.self) { hours in
                            Button {
                                muteHours = hours
                                muteUntil = Date().addingTimeInterval(Double(hours) * 3600).timeIntervalSince1970
                            } label: {
                                Text("\(hours)h")
                                    .font(OPSStyle.Typography.caption)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(muteHours == hours ?
                                                OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBackground)
                                    .foregroundColor(muteHours == hours ? OPSStyle.Colors.invertedText : OPSStyle.Colors.primaryText)
                                    .cornerRadius(OPSStyle.Layout.largeCornerRadius)
                            }
                        }
                    }

                    if muteUntil > Date().timeIntervalSince1970 {
                        let endDate = Date(timeIntervalSince1970: muteUntil)
                        HStack {
                            Image(OPSStyle.Icons.notificationMuted)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.warningStatus)

                            Text("Muted until \(endDate.formatted(date: .omitted, time: .shortened))")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Helper Functions

    private func formatHour(_ hour: Int) -> String {
        let hourDisplay = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let amPm = hour >= 12 ? "PM" : "AM"
        return "\(hourDisplay) \(amPm)"
    }

    private func checkMuteExpiration() {
        if isMuted && muteUntil > 0 && muteUntil < Date().timeIntervalSince1970 {
            isMuted = false
            muteUntil = 0
        }
    }

    private func sendTestNotification() {
        let testDate = Date().addingTimeInterval(5)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeString = formatter.string(from: notificationTime)

        _ = notificationManager.scheduleProjectNotification(
            projectId: "test",
            title: "OPS Test Notification",
            body: "Your notifications are working! Advance reminders will be sent at \(timeString).",
            date: testDate
        )
    }

    private func rescheduleAllNotifications() {
        Task {
            guard let modelContext = dataController.modelContext else { return }
            await notificationManager.scheduleAdvanceNoticesForAllTasks(using: modelContext)
        }
    }
}

// MARK: - Supporting Views

struct DaySelector: View {
    @Binding var value: Int
    let label: String
    let allowNone: Bool

    private let dayOptions = [1, 2, 3, 5, 7, 14]

    init(value: Binding<Int>, label: String, allowNone: Bool = false) {
        self._value = value
        self.label = label
        self.allowNone = allowNone
    }

    var body: some View {
        Menu {
            if allowNone {
                Button {
                    value = 0
                } label: {
                    if value == 0 {
                        Label("None", image: OPSStyle.Icons.checkmark)
                    } else {
                        Text("None")
                    }
                }

                Divider()
            }

            ForEach(dayOptions, id: \.self) { day in
                Button {
                    value = day
                } label: {
                    if value == day {
                        Label("\(day) days", image: OPSStyle.Icons.checkmark)
                    } else {
                        Text("\(day) days")
                    }
                }
            }
        } label: {
            VStack(spacing: 4) {
                Text(label.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                HStack(spacing: 4) {
                    if value == 0 {
                        Text("NONE")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    } else {
                        Text("\(value)")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("DAYS")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }

                    Image(OPSStyle.Icons.chevronDown)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    NotificationSettingsView()
        .environmentObject(NotificationManager.shared)
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
