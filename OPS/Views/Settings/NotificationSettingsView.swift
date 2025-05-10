//
//  NotificationSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-09.
//

import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var dataController: DataController
    
    @State private var showPermissionAlert = false
    @State private var selectedProject: Project?
    @State private var projectTitle = ""
    @State private var reminderDate = Date()
    @State private var showProjectPicker = false
    @State private var notificationTitle = "Project Reminder"
    @State private var notificationBody = "Don't forget about your upcoming project!"
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Notification Settings")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 24)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Permission status card
                        permissionStatusCard
                        
                        // Test notification section
                        testNotificationSection
                        
                        // Project notification section
                        projectNotificationSection
                        
                        // Schedule reminder section
                        scheduleReminderSection
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Refresh notification permission status
            notificationManager.getAuthorizationStatus()
            // Get all pending notifications
            notificationManager.getAllPendingNotifications()
        }
        .sheet(isPresented: $showProjectPicker) {
            projectPickerView
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
    
    // Permission status card
    private var permissionStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notification Permission")
                .font(OPSStyle.Typography.subheading)
                .foregroundColor(.white)
            
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: notificationManager.isNotificationsEnabled ? "bell.fill" : "bell.slash.fill")
                            .foregroundColor(notificationManager.isNotificationsEnabled ? .green : .red)
                            .font(.system(size: 22))
                        
                        Text(notificationManager.isNotificationsEnabled ? "Notifications Enabled" : "Notifications Disabled")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                    }
                    
                    Text(notificationManager.isNotificationsEnabled ? 
                         "You will receive notifications about projects and team updates." : 
                         "You won't receive important updates about your projects and team.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
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
                        .font(OPSStyle.Typography.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(notificationManager.isNotificationsEnabled ? OPSStyle.Colors.cardBackground : OPSStyle.Colors.primaryAccent)
                        .foregroundColor(notificationManager.isNotificationsEnabled ? .white : .black)
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(12)
    }
    
    // Test notification section
    private var testNotificationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Test Notification")
                .font(OPSStyle.Typography.subheading)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Send a test notification to verify everything is working correctly.")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                
                Button(action: {
                    if notificationManager.isNotificationsEnabled {
                        // Send a test notification
                        sendTestNotification()
                    } else {
                        // Show alert to enable permissions
                        showPermissionAlert = true
                    }
                }) {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 16))
                        
                        Text("Send Test Notification")
                            .font(OPSStyle.Typography.body)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(OPSStyle.Colors.primaryAccent)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                }
                .disabled(!notificationManager.isNotificationsEnabled)
                .opacity(notificationManager.isNotificationsEnabled ? 1.0 : 0.6)
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(12)
    }
    
    // Project notification section
    private var projectNotificationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project Notification")
                .font(OPSStyle.Typography.subheading)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Project:")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Button(action: {
                        // Show project picker
                        showProjectPicker = true
                    }) {
                        HStack {
                            Text(selectedProject?.title ?? "Select Project")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(selectedProject != nil ? .white : OPSStyle.Colors.tertiaryText)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(OPSStyle.Colors.cardBackground)
                        .cornerRadius(8)
                    }
                }
                
                TextField("Notification Title", text: $notificationTitle)
                    .font(OPSStyle.Typography.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(OPSStyle.Colors.cardBackground)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                
                TextField("Notification Message", text: $notificationBody)
                    .font(OPSStyle.Typography.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(OPSStyle.Colors.cardBackground)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                
                DatePicker("Notification Date", selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .padding(.top, 8)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(OPSStyle.Colors.cardBackground)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                
                Button(action: {
                    if notificationManager.isNotificationsEnabled {
                        guard let project = selectedProject else { return }
                        
                        NotificationManager.shared.scheduleProjectNotification(
                            projectId: project.id,
                            title: notificationTitle,
                            body: notificationBody,
                            date: reminderDate
                        )
                        
                        // Show feedback
                        notificationBody = "Notification scheduled for \(formatDate(reminderDate))"
                        
                        // Refresh pending notifications
                        notificationManager.getAllPendingNotifications()
                    } else {
                        // Show alert to enable permissions
                        showPermissionAlert = true
                    }
                }) {
                    Text("Schedule Project Notification")
                        .font(OPSStyle.Typography.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(OPSStyle.Colors.primaryAccent)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                }
                .disabled(selectedProject == nil || !notificationManager.isNotificationsEnabled)
                .opacity((selectedProject == nil || !notificationManager.isNotificationsEnabled) ? 0.6 : 1.0)
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(12)
    }
    
    // Schedule reminder section
    private var scheduleReminderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today's Schedule Reminder")
                .font(OPSStyle.Typography.subheading)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Schedule a 7 AM reminder for your daily projects.")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                
                DatePicker("Reminder Date", selection: $reminderDate, displayedComponents: [.date])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(OPSStyle.Colors.cardBackground)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                
                Button(action: {
                    if notificationManager.isNotificationsEnabled {
                        // Schedule a 7 AM reminder
                        NotificationManager.shared.scheduleReminderNotification(
                            date: reminderDate,
                            projectCount: 3 // Placeholder count for demo
                        )
                        
                        // Show feedback
                        notificationBody = "Daily reminder scheduled for \(formatDate(reminderDate))"
                        
                        // Refresh pending notifications
                        notificationManager.getAllPendingNotifications()
                    } else {
                        // Show alert to enable permissions
                        showPermissionAlert = true
                    }
                }) {
                    Text("Schedule Daily Reminder")
                        .font(OPSStyle.Typography.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(OPSStyle.Colors.primaryAccent)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                }
                .disabled(!notificationManager.isNotificationsEnabled)
                .opacity(notificationManager.isNotificationsEnabled ? 1.0 : 0.6)
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(12)
    }
    
    // Pending notifications section
    private var pendingNotificationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Pending Notifications")
                    .font(OPSStyle.Typography.subheading)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    // Refresh pending notifications
                    notificationManager.getAllPendingNotifications()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            
            if notificationManager.pendingNotifications.isEmpty {
                Text("No pending notifications")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(notificationManager.pendingNotifications, id: \.identifier) { request in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(request.content.title)
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(.white)
                                
                                Text(request.content.body)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                // Remove this notification
                                notificationManager.removeNotification(identifier: request.identifier)
                                notificationManager.getAllPendingNotifications()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(OPSStyle.Colors.cardBackground)
                        .cornerRadius(8)
                    }
                }
            }
            
            if !notificationManager.pendingNotifications.isEmpty {
                Button(action: {
                    // Cancel all notifications
                    notificationManager.removeAllPendingNotifications()
                    notificationManager.getAllPendingNotifications()
                }) {
                    Text("Clear All Notifications")
                        .font(OPSStyle.Typography.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(OPSStyle.Colors.cardBackground)
                        .foregroundColor(.red)
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(12)
    }
    
    // Project picker view
    private var projectPickerView: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                HStack {
                    Text("Select Project")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button("Done") {
                        showProjectPicker = false
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                
                // Projects list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                .scaleEffect(1.0)
                                .padding()
                        } else {
                            ForEach(loadProjects(), id: \.id) { project in
                                Button(action: {
                                    selectedProject = project
                                    showProjectPicker = false
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(project.title)
                                                .font(OPSStyle.Typography.body)
                                                .foregroundColor(.white)
                                            
                                            Text(project.clientName)
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                        
                                        Spacer()
                                        
                                        if selectedProject?.id == project.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(OPSStyle.Colors.cardBackground)
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    // Helper function to load projects
    private func loadProjects() -> [Project] {
        do {
            // Try to get projects from data controller
            return try dataController.getProjectsForMap()
        } catch {
            print("Error loading projects: \(error.localizedDescription)")
            return []
        }
    }
    
    // Send a test notification
    private func sendTestNotification() {
        // Create a test notification that will trigger immediately
        _ = NotificationManager.shared.scheduleProjectNotification(
            projectId: "test-project",
            title: "Test Notification",
            body: "This is a test notification from OPS. If you can see this, notifications are working correctly!",
            date: nil
        )
    }
    
    // Format date helper
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    NotificationSettingsView()
        .environmentObject(NotificationManager.shared)
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}