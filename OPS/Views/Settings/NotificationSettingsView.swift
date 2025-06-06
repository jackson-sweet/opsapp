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
    @AppStorage("advanceNoticeDays2") private var advanceNoticeDays2 = 2
    @AppStorage("advanceNoticeDays3") private var advanceNoticeDays3 = 7
    
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
                        VStack(alignment: .leading, spacing: 16) {
                            SettingsSectionHeader(title: "PROJECT UPDATES")
                            projectNotificationSettings
                        }
                        
                        // Advance Notice Section
                        VStack(alignment: .leading, spacing: 16) {
                            SettingsSectionHeader(title: "ADVANCE REMINDERS")
                            advanceNoticeSettings
                        }
                        
                        // Test Notification Section
                        VStack(alignment: .leading, spacing: 16) {
                            SettingsSectionHeader(title: "TEST NOTIFICATIONS")
                            testNotificationCard
                        }
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
                      "bell.fill" : "bell.slash.fill")
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
        VStack(spacing: 12) {
            // Assignment Notifications
            SettingsCard(title: "", showTitle: false) {
                SettingsToggle(
                    title: "Project Assignments",
                    description: "Get notified when assigned to new projects",
                    isOn: $notifyProjectAssignment
                )
            }
            
            // Schedule Changes
            SettingsCard(title: "", showTitle: false) {
                SettingsToggle(
                    title: "Schedule Changes",
                    description: "Receive alerts when project dates change",
                    isOn: $notifyProjectScheduleChanges
                )
            }
            
            // Completion Notifications
            SettingsCard(title: "", showTitle: false) {
                SettingsToggle(
                    title: "Project Completion",
                    description: "Be notified when projects are marked complete",
                    isOn: $notifyProjectCompletion
                )
            }
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
            }
            
            // Day Selectors
            if notifyProjectAdvance {
                SettingsCard(title: "REMINDER SCHEDULE") {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            DaySelector(value: $advanceNoticeDays1, label: "First")
                            DaySelector(value: $advanceNoticeDays2, label: "Second")
                            DaySelector(value: $advanceNoticeDays3, label: "Third")
                        }
                        
                        Text("\(advanceNoticeDays1), \(advanceNoticeDays2) & \(advanceNoticeDays3) days before")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
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
        _ = notificationManager.scheduleProjectNotification(
            projectId: "test",
            title: "OPS Test Notification",
            body: "Your notifications are working! You'll receive updates about your projects.",
            date: nil
        )
    }
}

// MARK: - Supporting Views

struct DaySelector: View {
    @Binding var value: Int
    let label: String
    private let options = [1, 2, 3, 5, 7, 14]
    
    var body: some View {
        Menu {
            ForEach(options, id: \.self) { day in
                Button {
                    value = day
                } label: {
                    if value == day {
                        Label("\(day) days", systemImage: "checkmark")
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
                    Text("\(value)")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                    
                    Text("DAYS")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Image(systemName: "chevron.down")
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
