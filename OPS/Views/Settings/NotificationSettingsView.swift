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
    
    // Project notification preferences
    @AppStorage("notifyProjectAssignment") private var notifyProjectAssignment = true
    @AppStorage("notifyProjectScheduleChanges") private var notifyProjectScheduleChanges = true
    @AppStorage("notifyProjectCompletion") private var notifyProjectCompletion = true
    
    // Advance notice settings
    @AppStorage("notifyProjectAdvance") private var notifyProjectAdvance = true
    @AppStorage("advanceNoticeDays1") private var advanceNoticeDays1 = 1
    @AppStorage("advanceNoticeDays2") private var advanceNoticeDays2 = 0  // Default to None
    @AppStorage("advanceNoticeDays3") private var advanceNoticeDays3 = 0  // Default to None
    @AppStorage("advanceNoticeHour") private var advanceNoticeHour = 8
    @AppStorage("advanceNoticeMinute") private var advanceNoticeMinute = 0
    
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
        
        // Always include first day
        activeDays.append(advanceNoticeDays1)
        
        // Include second and third if not "None" (0)
        if advanceNoticeDays2 > 0 {
            activeDays.append(advanceNoticeDays2)
        }
        if advanceNoticeDays3 > 0 {
            activeDays.append(advanceNoticeDays3)
        }
        
        // Format the days
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
        
        // Format time for display
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeString = formatter.string(from: notificationTime)
        
        return "\(dayText) at \(timeString)"
    }
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Notifications",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 24)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Permission Status Card
                        notificationStatusCard
                            .padding(20)
                        
                        // Project Notifications Section
                        SectionCard(
                            icon: "bell.badge",
                            title: "Project Updates",
                            contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                        ) {
                            projectNotificationSettings
                        }
                        .padding(.horizontal, 20)
                        
                        // Advance Notice Section
                        SectionCard(
                            icon: "clock.badge",
                            title: "Advance Reminders"
                        ) {
                            advanceNoticeSettings
                        }
                        .padding(.horizontal, 20)

                        // Test Notification Section
                        SectionCard(
                            icon: "bell.circle",
                            title: "Test Notifications"
                        ) {
                            testNotificationCard
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            notificationManager.getAuthorizationStatus()
        }
    }
    
    // MARK: - Components
    
    private var notificationStatusCard: some View {
        HStack(spacing: 16) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(notificationManager.isNotificationsEnabled ? 
                          OPSStyle.Colors.successStatus.opacity(0.2) : 
                          OPSStyle.Colors.errorStatus.opacity(0.2))
                    .frame(width: 48, height: 48)
                
                Image(systemName: notificationManager.isNotificationsEnabled ?
                      OPSStyle.Icons.bellFill : "bell.slash.fill")
                    .font(.system(size: 24))
                    .foregroundColor(notificationManager.isNotificationsEnabled ? 
                                   OPSStyle.Colors.successStatus : 
                                   OPSStyle.Colors.errorStatus)
            }
            
            // Status Text
            VStack(alignment: .leading, spacing: 4) {
                Text(notificationManager.isNotificationsEnabled ? 
                     "NOTIFICATIONS ENABLED" : "NOTIFICATIONS DISABLED")
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(.white)
                
                Text(notificationManager.isNotificationsEnabled ?
                     "Stay updated on projects" : "Enable to receive updates")
                    .font(OPSStyle.Typography.cardBody)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            
            Spacer()
            
            // Action Button
            Button {
                if notificationManager.isNotificationsEnabled {
                    notificationManager.openAppSettings()
                } else {
                    notificationManager.requestPermission { _ in }
                }
            } label: {
                Text(notificationManager.isNotificationsEnabled ? "MANAGE" : "ENABLE")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(notificationManager.isNotificationsEnabled ? 
                                   OPSStyle.Colors.primaryText : .black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(notificationManager.isNotificationsEnabled ? 
                                Color.clear : OPSStyle.Colors.primaryText)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(notificationManager.isNotificationsEnabled ? 
                                  OPSStyle.Colors.primaryText : Color.clear, 
                                  lineWidth: 1)
                    )
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
        .padding(24)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    private var projectNotificationSettings: some View {
        VStack(spacing: 0) {
            // Assignment Notifications
            SettingsToggle(
                title: "Project Assignments",
                description: "Get notified when assigned to new projects",
                isOn: $notifyProjectAssignment
            )

            Divider()
                .background(OPSStyle.Colors.cardBorder)
                .padding(.vertical, 8)

            // Schedule Changes
            SettingsToggle(
                title: "Schedule Changes",
                description: "Receive alerts when project dates change",
                isOn: $notifyProjectScheduleChanges
            )

            Divider()
                .background(OPSStyle.Colors.cardBorder)
                .padding(.vertical, 8)

            // Completion Notifications
            SettingsToggle(
                title: "Project Completion",
                description: "Be notified when projects are marked complete",
                isOn: $notifyProjectCompletion
            )
        }
    }
    
    private var advanceNoticeSettings: some View {
        VStack(spacing: 12) {
            // Master Toggle
            SettingsCard(title: "", showTitle: false) {
                SettingsToggle(
                    title: "Enable Advance Reminders",
                    description: "Get notified before projects start",
                    isOn: $notifyProjectAdvance
                )
                .onChange(of: notifyProjectAdvance) { _, newValue in
                    if newValue {
                        // Enabled - schedule notifications
                        rescheduleAllNotifications()
                    } else {
                        // Disabled - cancel all project notifications
                        Task {
                            await notificationManager.cancelAllProjectNotifications()
                        }
                    }
                }
            }
            
            // Day Selectors and Time
            if notifyProjectAdvance {
                SettingsCard(title: "REMINDER SCHEDULE") {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            DaySelector(value: $advanceNoticeDays1, label: "First", allowNone: false)
                                .onChange(of: advanceNoticeDays1) { _, _ in
                                    rescheduleAllNotifications()
                                }
                            DaySelector(value: $advanceNoticeDays2, label: "Second", allowNone: true)
                                .onChange(of: advanceNoticeDays2) { _, _ in
                                    rescheduleAllNotifications()
                                }
                            DaySelector(value: $advanceNoticeDays3, label: "Third", allowNone: true)
                                .onChange(of: advanceNoticeDays3) { _, _ in
                                    rescheduleAllNotifications()
                                }
                        }
                        
                        Text(reminderSummaryText)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
                
                // Time Picker
                SettingsCard(title: "NOTIFICATION TIME") {
                    HStack {
                        Text("Send reminders at")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        
                        Spacer()
                        
                        // Use a simple DatePicker with custom styling
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
            }
        }
    }
    
    private var testNotificationCard: some View {
        VStack(spacing: 16) {
            Text("Send a test to verify settings")
                .font(OPSStyle.Typography.cardBody)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button {
                sendTestNotification()
            } label: {
                HStack {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 18))
                    
                    Text("SEND TEST NOTIFICATION")
                        .font(OPSStyle.Typography.button)
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                )
            }
            .disabled(!notificationManager.isNotificationsEnabled)
            .opacity(notificationManager.isNotificationsEnabled ? 1.0 : 0.5)
        }
        .padding(24)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    // MARK: - Helper Components
    
    private func sendTestNotification() {
        // Schedule a test notification for 5 seconds from now
        let testDate = Date().addingTimeInterval(5)
        
        // Format the time for display
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
            await notificationManager.scheduleNotificationsForAllProjects(using: modelContext)
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
                        Label("None", systemImage: "checkmark")
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
                        Label("\(day) days", systemImage: OPSStyle.Icons.checkmark)
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
                            .foregroundColor(.white)
                        
                        Text("DAYS")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    
                    Image(systemName: OPSStyle.Icons.chevronDown)
                        .font(.system(size: 10))
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
