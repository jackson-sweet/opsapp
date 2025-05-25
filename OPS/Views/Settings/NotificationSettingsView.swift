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
                    VStack(spacing: 32) {
                        // Permission Status Card
                        notificationStatusCard
                        
                        // Project Notifications Section
                        VStack(alignment: .leading, spacing: 16) {
                            sectionHeader("PROJECT UPDATES")
                            projectNotificationsCard
                        }
                        
                        // Advance Notice Section
                        VStack(alignment: .leading, spacing: 16) {
                            sectionHeader("ADVANCE REMINDERS")
                            advanceNoticeCard
                        }
                        
                        // Test Notification Section
                        VStack(alignment: .leading, spacing: 16) {
                            sectionHeader("TEST NOTIFICATIONS")
                            testNotificationCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .tabBarPadding()
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
    
    private var projectNotificationsCard: some View {
        VStack(spacing: 0) {
            // Assignment Notifications
            NotificationRow(
                icon: "person.badge.plus",
                title: "Project Assignments",
                description: "When assigned to new projects",
                isOn: $notifyProjectAssignment
            )
            
            Divider()
                .background(OPSStyle.Colors.cardBackground)
                .padding(.vertical, 4)
            
            // Schedule Changes
            NotificationRow(
                icon: "calendar.badge.clock",
                title: "Schedule Changes",
                description: "When project dates change",
                isOn: $notifyProjectScheduleChanges
            )
            
            Divider()
                .background(OPSStyle.Colors.cardBackground)
                .padding(.vertical, 4)
            
            // Completion Notifications
            NotificationRow(
                icon: "checkmark.circle",
                title: "Project Completion",
                description: "When projects are marked complete",
                isOn: $notifyProjectCompletion
            )
        }
        .padding(24)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    private var advanceNoticeCard: some View {
        VStack(spacing: 20) {
            // Master Toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ADVANCE REMINDERS")
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(.white)
                    
                    Text("Get notified before projects start")
                        .font(OPSStyle.Typography.cardBody)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                Spacer()
                
                Toggle("", isOn: $notifyProjectAdvance)
                    .tint(OPSStyle.Colors.primaryAccent)
            }
            
            // Day Selectors
            if notifyProjectAdvance {
                VStack(spacing: 12) {
                    Text("REMIND ME")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
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
        .padding(24)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
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
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.secondaryText)
    }
    
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

struct NotificationRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .tint(OPSStyle.Colors.primaryAccent)
        }
        .padding(.vertical, 4)
    }
}

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
