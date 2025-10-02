//
//  ClientDetailsView.swift
//  OPS
//
//  Detailed view for a specific client showing all their information and associated projects
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct ClientDetailsView: View {
    let client: Client

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Query private var allProjects: [Project]

    @State private var clientNotes: String
    @State private var originalClientNotes: String
    @State private var showingUnsavedChangesAlert = false
    @State private var showingSaveNotification = false
    @State private var notificationTimer: Timer?
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingProjectDetails = false
    @State private var selectedProject: Project?

    // Computed property for client's projects
    private var clientProjects: [Project] {
        client.projects.sorted { p1, p2 in
            // Sort by status priority (active first), then by date
            if p1.status.isActive != p2.status.isActive {
                return p1.status.isActive && !p2.status.isActive
            }
            if p1.status.isCompleted != p2.status.isCompleted {
                return !p1.status.isCompleted && p2.status.isCompleted
            }
            return (p1.startDate ?? Date.distantPast) > (p2.startDate ?? Date.distantPast)
        }
    }

    // Computed property for active projects count
    private var activeProjectsCount: Int {
        clientProjects.filter { $0.status == .inProgress || $0.status == .accepted }.count
    }

    init(client: Client) {
        self.client = client
        let notes = client.notes ?? ""
        _clientNotes = State(initialValue: notes)
        _originalClientNotes = State(initialValue: notes)
    }

    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background
                .edgesIgnoringSafeArea(.all)

            // Main content
            VStack(spacing: 0) {
                // Header with frosted glass effect
                headerView

                // Scrollable content
                ScrollView {
                    VStack(spacing: 24) {
                        // Contact information
                        contactSection

                        // Location section (if address exists)
                        if client.address != nil && !client.address!.isEmpty {
                            locationSection
                        }

                        // Projects section
                        projectsSection

                        // Notes section
                        notesSection

                        // Delete client button
                        deleteSection

                        // Bottom padding
                        Spacer()
                            .frame(height: 80)
                    }
                    .padding(.top, 16)
                }
            }
        }
        .navigationBarHidden(true)
        .overlay(saveNotificationOverlay)
        .confirmationDialog(
            "Unsaved Changes",
            isPresented: $showingUnsavedChangesAlert,
            titleVisibility: .visible
        ) {
            Button("Save Changes", role: .none) {
                saveClientNotes()
                dismiss()
            }

            Button("Discard Changes", role: .destructive) {
                dismiss()
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes to your notes. Would you like to save them before leaving?")
        }
        .sheet(isPresented: $showingEditSheet) {
            ClientFormSheet(mode: .edit(client)) { _ in
                // Refresh will happen automatically through SwiftData
            }
        }
        .sheet(isPresented: $showingProjectDetails) {
            if let project = selectedProject {
                ProjectDetailsView(project: project)
                    .environmentObject(dataController)
                    .environmentObject(appState)
            }
        }
        .alert("Delete Client", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteClient()
            }
        } message: {
            Text("Are you sure you want to delete \(client.name)? This action cannot be undone.")
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        ZStack {
            // Blurred background
            BlurView(style: .dark)
                .edgesIgnoringSafeArea(.top)

            VStack(spacing: 8) {
                // Top row with project count and buttons
                HStack {
                    // Project count badge
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 14))
                        Text("\(activeProjectsCount) ACTIVE")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(activeProjectsCount > 0 ?
                               Status.inProgress.color :
                               OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(20)

                    Spacer()

                    // Edit button
                    Button(action: { showingEditSheet = true }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(width: 36, height: 36)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(18)
                    }

                    // Done button
                    Button("Done") {
                        checkForUnsavedChanges()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .foregroundColor(Color.black)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                    .font(OPSStyle.Typography.bodyBold)
                }

                // Client name
                HStack {
                    Text(client.name.uppercased())
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer()
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 90)
        .background(Color.black)
    }

    // MARK: - Contact Section
    private var contactSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "person.circle")
                    .font(.system(size: 16))
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text("CONTACT INFORMATION")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Contact card
            VStack(spacing: 0) {
                // Email
                if let email = client.email, !email.isEmpty {
                    contactRow(
                        icon: "envelope",
                        label: "EMAIL",
                        value: email,
                        action: {
                            if let url = URL(string: "mailto:\(email)") {
                                UIApplication.shared.open(url)
                            }
                        }
                    )

                    if client.phoneNumber != nil {
                        Divider()
                            .background(Color.white.opacity(0.1))
                    }
                }

                // Phone
                if let phone = client.phoneNumber, !phone.isEmpty {
                    contactRow(
                        icon: "phone",
                        label: "PHONE",
                        value: formatPhoneNumber(phone),
                        action: {
                            if let url = URL(string: "tel:\(phone)") {
                                UIApplication.shared.open(url)
                            }
                        }
                    )
                }

                // No contact info
                if (client.email == nil || client.email!.isEmpty) &&
                   (client.phoneNumber == nil || client.phoneNumber!.isEmpty) {
                    HStack {
                        Text("No contact information available")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }

    // MARK: - Location Section
    private var locationSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "location")
                    .font(.system(size: 16))
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text("ADDRESS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Use LocationCard component
            LocationCard(
                address: client.address ?? "No address provided",
                latitude: client.latitude,
                longitude: client.longitude
            )
            .padding(.horizontal)
        }
    }

    // MARK: - Projects Section
    private var projectsSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "folder")
                    .font(.system(size: 16))
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text("PROJECTS (\(clientProjects.count))")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Projects list
            if clientProjects.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 32))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Text("No projects yet")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(clientProjects.enumerated()), id: \.element.id) { index, project in
                        projectRow(project: project)

                        if index < clientProjects.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.1))
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Notes Section
    private var notesSection: some View {
        NotesCard(
            title: "CLIENT NOTES",
            notes: .init(
                get: { clientNotes.isEmpty ? nil : clientNotes },
                set: { clientNotes = $0 ?? "" }
            ),
            isEditable: true,
            onSave: saveClientNotes
        )
        .padding(.horizontal)
    }

    // MARK: - Delete Section
    private var deleteSection: some View {
        Button(action: { showingDeleteConfirmation = true }) {
            HStack {
                Image(systemName: "trash")
                    .font(.system(size: 16))

                Text("DELETE CLIENT")
                    .font(OPSStyle.Typography.bodyBold)
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.red.opacity(0.1))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }

    // MARK: - Helper Views
    private func contactRow(icon: String, label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text(value)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func projectRow(project: Project) -> some View {
        Button(action: {
            selectedProject = project
            showingProjectDetails = true
        }) {
            HStack {
                // Status indicator
                Circle()
                    .fill(project.status.color)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        // Status
                        Text(project.status.displayName.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        // Date
                        if let date = project.startDate {
                            Text(DateHelper.fullDateString(from: date))
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
                }

                Spacer()

                // Task count (if project has tasks)
                if project.tasks.count > 0 {
                    Text("\(project.tasks.count)")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(12)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var saveNotificationOverlay: some View {
        Group {
            if showingSaveNotification {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)

                        Text("Notes saved")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 120)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
            }
        }
    }

    // MARK: - Helper Methods
    private func checkForUnsavedChanges() {
        if clientNotes != originalClientNotes {
            showingUnsavedChangesAlert = true
        } else {
            dismiss()
        }
    }

    private func saveClientNotes() {
        guard clientNotes != originalClientNotes else { return }

        client.notes = clientNotes.isEmpty ? nil : clientNotes
        client.needsSync = true
        originalClientNotes = clientNotes

        // Show save notification
        showingSaveNotification = true

        // Hide notification after 2 seconds
        notificationTimer?.invalidate()
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            withAnimation {
                showingSaveNotification = false
            }
        }

        // Trigger background sync
        dataController.syncManager?.triggerBackgroundSync()
    }

    private func deleteClient() {
        // Mark client for deletion
        client.needsSync = true

        // Delete from model context
        modelContext.delete(client)

        // Save changes
        do {
            try modelContext.save()
        } catch {
            print("Error deleting client: \(error)")
        }

        // Dismiss view
        dismiss()

        // Trigger sync
        dataController.syncManager?.triggerBackgroundSync()
    }

    private func formatPhoneNumber(_ phone: String) -> String {
        // Remove non-numeric characters
        let digits = phone.filter { $0.isNumber }

        // Format as (XXX) XXX-XXXX if US number
        if digits.count == 10 {
            let areaCode = String(digits.prefix(3))
            let middle = String(digits.dropFirst(3).prefix(3))
            let last = String(digits.dropFirst(6))
            return "(\(areaCode)) \(middle)-\(last)"
        }

        return phone
    }

}