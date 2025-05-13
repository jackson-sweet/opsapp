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
    
    // Basic notification settings
    @State private var showPermissionAlert = false
    @State private var selectedProject: Project?
    @State private var projectTitle = ""
    @State private var reminderDate = Date()
    @State private var showProjectPicker = false
    
    // Enhanced notification settings
    @AppStorage("notificationStartHour") private var notificationStartHour = 8 // 8 AM
    @AppStorage("notificationEndHour") private var notificationEndHour = 20 // 8 PM
    @AppStorage("notificationsMuted") private var notificationsMuted = false
    @AppStorage("notificationMuteHours") private var notificationMuteHours = 2
    @State private var selectedPriority: NotificationPrioritySelector.NotificationPriority = .important
    
    // Project notification state
    @State private var notificationTitle = "Project Reminder"
    @State private var notificationBody = "Don't forget about your upcoming project!"
    @State private var isLoading = false
    
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
                
                // Use List to match the design inspiration and minimize scrolling
                List {
                    // Section 1: Permission status
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: notificationManager.isNotificationsEnabled ? "bell.fill" : "bell.slash.fill")
                                        .foregroundColor(notificationManager.isNotificationsEnabled ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)
                                        .font(.system(size: 22))
                                    
                                    Text(notificationManager.isNotificationsEnabled ? "Notifications Enabled" : "Notifications Disabled")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                
                                Text(notificationManager.isNotificationsEnabled ? 
                                     "You will receive notifications about projects and team updates." : 
                                     "You won't receive important updates about your projects and team.")
                                    .font(.system(size: 13))
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
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(notificationManager.isNotificationsEnabled ? OPSStyle.Colors.cardBackground : OPSStyle.Colors.primaryAccent)
                                    .foregroundColor(notificationManager.isNotificationsEnabled ? .white : .black)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    
                    // Section 2: You're in control
                    Section(header: Text("YOU'RE IN CONTROL").font(.system(size: 13, weight: .bold)).foregroundColor(OPSStyle.Colors.secondaryText)) {
                        NotificationTimeWindow(
                            startHour: $notificationStartHour,
                            endHour: $notificationEndHour,
                            title: "Time Window",
                            description: "Only receive notifications during these hours"
                        )
                        .padding(.vertical, 8)
                        .listRowBackground(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        
                        NotificationPrioritySelector(
                            selectedPriority: $selectedPriority
                        )
                        .padding(.vertical, 8)
                        .listRowBackground(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        
                        TemporaryMuteControl(
                            isMuted: $notificationsMuted,
                            muteHours: $notificationMuteHours
                        )
                        .padding(.vertical, 8)
                        .listRowBackground(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    }
                    
                    // Section 3: Project notifications 
                    Section(header: Text("PROJECT NOTIFICATIONS").font(.system(size: 13, weight: .bold)).foregroundColor(OPSStyle.Colors.secondaryText)) {
                        VStack(alignment: .leading, spacing: 12) {
                            // Project selector
                            HStack {
                                Text("Project:")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Button(action: {
                                    // Show project picker
                                    showProjectPicker = true
                                }) {
                                    HStack {
                                        Text(selectedProject?.title ?? "Select Project")
                                            .font(.system(size: 16))
                                            .foregroundColor(selectedProject != nil ? .white : OPSStyle.Colors.tertiaryText)
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14))
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(OPSStyle.Colors.cardBackground.opacity(0.6))
                                    .cornerRadius(8)
                                }
                            }
                            
                            // Notification content
                            SettingsField(
                                title: "Title",
                                placeholder: "Notification title",
                                text: $notificationTitle
                            )
                            
                            SettingsField(
                                title: "Message",
                                placeholder: "Notification message",
                                text: $notificationBody
                            )
                            
                            // Date picker
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Reminder Date")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                DatePicker("Notification Date", selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                            
                            // Schedule button
                            SettingsButton(
                                title: "Schedule Notification",
                                icon: "bell.badge.fill",
                                action: {
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
                                }
                            )
                            .disabled(selectedProject == nil || !notificationManager.isNotificationsEnabled)
                            .opacity((selectedProject == nil || !notificationManager.isNotificationsEnabled) ? 0.6 : 1.0)
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    }
                    
                    // Section 4: Testing
                    Section(header: Text("TESTING").font(.system(size: 13, weight: .bold)).foregroundColor(OPSStyle.Colors.secondaryText)) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Send a test notification to verify your settings.")
                                .font(.system(size: 13))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            SettingsButton(
                                title: "Send Test Notification",
                                icon: "bell.badge.fill",
                                style: .secondary,
                                action: {
                                    if notificationManager.isNotificationsEnabled {
                                        // Send a test notification
                                        sendTestNotification()
                                    } else {
                                        // Show alert to enable permissions
                                        showPermissionAlert = true
                                    }
                                }
                            )
                            .disabled(!notificationManager.isNotificationsEnabled)
                            .opacity(notificationManager.isNotificationsEnabled ? 1.0 : 0.6)
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    }
                }
                .listStyle(PlainListStyle())
                .background(Color.clear)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationBarBackButtonHidden(true)
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
    
    // Project picker view
    private var projectPickerView: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        showProjectPicker = false
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    
                    Spacer()
                    
                    Text("Select Project")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button("Done") {
                        showProjectPicker = false
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                // Projects list as a List view for better performance and navigation
                List {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                .scaleEffect(1.0)
                                .padding()
                            Spacer()
                        }
                        .listRowBackground(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    } else {
                        ForEach(loadProjects(), id: \.id) { project in
                            Button(action: {
                                selectedProject = project
                                showProjectPicker = false
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(project.title)
                                            .font(.system(size: 16))
                                            .foregroundColor(.white)
                                        
                                        Text(project.clientName)
                                            .font(.system(size: 13))
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedProject?.id == project.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    }
                                }
                                .padding(.vertical, 12)
                            }
                            .listRowBackground(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .background(Color.clear)
                .scrollContentBackground(.hidden)
            }
        }
    }
    
    // Helper functions
    
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