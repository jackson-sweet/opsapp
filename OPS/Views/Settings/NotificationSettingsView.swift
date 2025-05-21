//
//  NotificationSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-12.
//

import SwiftUI
import UserNotifications
import Combine

struct NotificationSettingsView: View {
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    
    // Basic notification settings
    @State private var showPermissionAlert = false
    
    // Notification settings (removed temporary mute and priority settings)
    
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
                // Header with back button
                SettingsHeader(
                    title: "Notifications",
                    onBackTapped: {
                        dismiss()
                    }
                )
                
                // Use ScrollView with VStack for a cleaner look
                ScrollView {
                    VStack(spacing: 24) {
                        // Section 1: Permission status
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: notificationManager.isNotificationsEnabled ? "bell.fill" : "bell.slash.fill")
                                            .foregroundColor(notificationManager.isNotificationsEnabled ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                                            .font(OPSStyle.Typography.bodyEmphasis)
                                        
                                        Text(notificationManager.isNotificationsEnabled ? "Notifications Enabled" : "Notifications Disabled")
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(.white)
                                    }
                                    
                                    Text(notificationManager.isNotificationsEnabled ? 
                                         "You will receive notifications about projects and team updates." : 
                                         "You won't receive important updates about your projects and team.")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    if notificationManager.isNotificationsEnabled {
                                        // Already enabled, open settings to turn off
                                        notificationManager.openAppSettings()
                                    } else {
                                        // Request permission
                                        notificationManager.requestPermission { _ in
                                            // Will update authorizationStatus automatically
                                        }
                                    }
                                }) {
                                    Text(notificationManager.isNotificationsEnabled ? "Settings" : "Enable")
                                        .font(OPSStyle.Typography.captionBold)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(notificationManager.isNotificationsEnabled ? OPSStyle.Colors.cardBackground : OPSStyle.Colors.primaryAccent)
                                        .foregroundColor(notificationManager.isNotificationsEnabled ? .white : .black)
                                        .cornerRadius(8)
                                }
                            }
                            .padding(16)
                            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                        }
                        
                        // Section 2: Project Notifications
                        VStack(alignment: .leading, spacing: 16) {
                            Text("PROJECT NOTIFICATIONS")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.horizontal, 20)
                            
                            ProjectNotificationPreferences(
                                notifyProjectAssignment: $notifyProjectAssignment,
                                notifyProjectScheduleChanges: $notifyProjectScheduleChanges,
                                notifyProjectCompletion: $notifyProjectCompletion
                            )
                            .padding(.horizontal, 20)
                            
                            AdvanceNoticePreferences(
                                notifyProjectAdvance: $notifyProjectAdvance,
                                advanceNoticeDays1: $advanceNoticeDays1,
                                advanceNoticeDays2: $advanceNoticeDays2,
                                advanceNoticeDays3: $advanceNoticeDays3
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // Section 3: Testing
                        VStack(alignment: .leading, spacing: 16) {
                            Text("TEST NOTIFICATIONS")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.horizontal, 20)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Send a test notification to verify your settings.")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Menu {
                                    Button(action: {
                                        sendProjectAssignmentTest()
                                    }) {
                                        Label("Test Project Assignment", systemImage: "person.badge.plus")
                                    }
                                    
                                    Button(action: {
                                        sendProjectScheduleUpdateTest()
                                    }) {
                                        Label("Test Schedule Change", systemImage: "calendar.badge.clock")
                                    }
                                    
                                    Button(action: {
                                        sendProjectCompletionTest()
                                    }) {
                                        Label("Test Project Completion", systemImage: "checkmark.circle")
                                    }
                                    
                                    Button(action: {
                                        sendProjectAdvanceNoticeTest()
                                    }) {
                                        Label("Test Advance Notice", systemImage: "bell.badge.clock")
                                    }
                                    
                                    Button(action: {
                                        sendTestNotification()
                                    }) {
                                        Label("Test Generic Notification", systemImage: "bell.badge.fill")
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "bell.badge.fill")
                                            .font(OPSStyle.Typography.body)
                                        
                                        Text("Send Test Notification")
                                            .font(OPSStyle.Typography.bodyBold)
                                        
                                        Image(systemName: "chevron.down")
                                            .font(OPSStyle.Typography.smallCaption)
                                    }
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                                    )
                                }
                                .disabled(!notificationManager.isNotificationsEnabled)
                                .opacity(notificationManager.isNotificationsEnabled ? 1.0 : 0.6)
                            }
                            .padding(16)
                            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Refresh notification permission status
            notificationManager.getAuthorizationStatus()
            // Get all pending notifications
            notificationManager.getAllPendingNotifications()
        }
        .alert("Enable Notifications", isPresented: $showPermissionAlert) {
            Button("Open Settings", action: {
                notificationManager.openAppSettings()
            })
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please enable notifications in Settings to use this feature.")
        }
    }
    
    // Helper functions
    
    // Send a test notification
    private func sendTestNotification() {
        // Create a test notification that will trigger immediately
        _ = notificationManager.scheduleProjectNotification(
            projectId: "test-project",
            title: "Test Notification",
            body: "This is a test notification from OPS. If you can see this, notifications are working correctly!",
            date: nil
        )
    }
    
    // Send a test project assignment notification
    private func sendProjectAssignmentTest() {
        _ = notificationManager.scheduleProjectAssignmentNotification(
            projectId: "test-project",
            projectTitle: "Example Project",
            assignedBy: "Team Lead"
        )
    }
    
    // Send a test schedule update notification
    private func sendProjectScheduleUpdateTest() {
        let previousDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let newDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        
        _ = notificationManager.scheduleProjectUpdateNotification(
            projectId: "test-project",
            projectTitle: "Example Project",
            updateType: "schedule",
            previousDate: previousDate,
            newDate: newDate
        )
    }
    
    // Send a test project completion notification
    private func sendProjectCompletionTest() {
        _ = notificationManager.scheduleProjectCompletionNotification(
            projectId: "test-project",
            projectTitle: "Example Project"
        )
    }
    
    // Send a test advance notice notification
    private func sendProjectAdvanceNoticeTest() {
        // Set a start date 3 days from now to test advance notice
        let futureStartDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        
        // Use the first active advance notice setting
        let daysInAdvance = advanceNoticeDays1
        
        _ = notificationManager.scheduleProjectAdvanceNotice(
            projectId: "test-project",
            projectTitle: "Example Project",
            startDate: futureStartDate,
            daysInAdvance: daysInAdvance
        )
    }
}

#Preview {
    NotificationSettingsView()
        .environmentObject(NotificationManager.shared)
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
