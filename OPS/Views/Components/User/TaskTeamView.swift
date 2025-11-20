//
//  TaskTeamView.swift
//  OPS
//
//  Task team member view with inline editing
//

import SwiftUI
import SwiftData

/// Compact team member view for tasks with inline editing
struct TaskTeamView: View {
    let task: ProjectTask
    @Binding var isEditing: Bool
    @Binding var triggerSave: Bool
    @State private var selectedTeamMember: User? = nil
    @State private var showingTeamMemberDetails = false
    @State private var selectedMemberIds: Set<String> = []
    @State private var availableMembers: [TeamMember] = []
    @State private var isSaving = false
    @EnvironmentObject private var dataController: DataController
    @State private var loadedTeamMembers: [User] = []
    @State private var refreshKey = UUID()
    @Query private var users: [User]

    init(task: ProjectTask, isEditing: Binding<Bool> = .constant(false), triggerSave: Binding<Bool> = .constant(false)) {
        self.task = task
        self._isEditing = isEditing
        self._triggerSave = triggerSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if loadedTeamMembers.isEmpty && task.teamMembers.isEmpty && !isEditing {
                emptyStateView
            } else {
                teamMembersView()
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
        .sheet(isPresented: $showingTeamMemberDetails) {
            if let selectedMember = selectedTeamMember {
                ContactDetailView(user: selectedMember)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            loadTaskTeamMembers()
        }
        .id(refreshKey)
        .onChange(of: isEditing) { oldValue, newValue in
            if newValue {
                // Entering edit mode
                selectedMemberIds = Set(task.getTeamMemberIds())
                loadAvailableMembers()
            }
            // Note: No need to clear on exit - save function handles it
        }
        .onChange(of: triggerSave) { oldValue, newValue in
            // When trigger changes, save the team changes
            if isEditing {
                saveTeamChanges()
            }
        }
    }

    // MARK: - View Components

    private var emptyStateView: some View {
        HStack {
            Text("No team members assigned")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func teamMembersView() -> some View {
        let teamMembers = loadedTeamMembers.isEmpty ? Array(task.teamMembers) : loadedTeamMembers

        return VStack(spacing: 0) {
            ForEach(teamMembers, id: \.id) { member in
                teamMemberRow(member)
            }

            if isEditing && !availableMembers.isEmpty {
                availableMembersSection
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isEditing)
        .animation(.easeInOut(duration: 0.3), value: availableMembers.count)
    }

    private func teamMemberRow(_ member: User) -> some View {
        HStack(spacing: 12) {
            UserAvatar(user: member, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(member.firstName) \(member.lastName)")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(member.role.rawValue)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            ZStack {
                if isEditing {
                    checkboxButton(member.id)
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                } else {
                    chevronIndicator
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isEditing)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
        .onTapGesture {
            if isEditing {
                toggleMemberSelection(memberId: member.id)
            } else {
                selectedTeamMember = member
                showingTeamMemberDetails = true
            }
        }
    }

    private func checkboxButton(_ memberId: String) -> some View {
        Button(action: {
            toggleMemberSelection(memberId: memberId)
        }) {
            Image(systemName: selectedMemberIds.contains(memberId) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundColor(selectedMemberIds.contains(memberId) ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
        }
    }

    private var chevronIndicator: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14))
            .foregroundColor(OPSStyle.Colors.secondaryText)
    }

    private var availableMembersSection: some View {
        Group {
            Divider()
                .background(OPSStyle.Colors.separator)
                .padding(.vertical, 8)

            Text("ADD TEAM MEMBERS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal)

            ForEach(availableMembers, id: \.id) { member in
                availableMemberRow(member)
            }
        }
    }

    private func availableMemberRow(_ member: TeamMember) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(OPSStyle.Colors.primaryAccent)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(member.initials)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(member.fullName)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(member.role)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            Button(action: {
                toggleMemberSelection(memberId: member.id)
            }) {
                Image(systemName: selectedMemberIds.contains(member.id) ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 24))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
        .onTapGesture {
            toggleMemberSelection(memberId: member.id)
        }
    }

    // MARK: - Helper Functions

    private func loadTaskTeamMembers() {
        let teamMemberIds = task.getTeamMemberIds()

        if !teamMemberIds.isEmpty && task.teamMembers.isEmpty {
            // Load team members from Query results
            var loaded: [User] = []

            for memberId in teamMemberIds {
                if let user = users.first(where: { $0.id == memberId }) {
                    loaded.append(user)
                }
            }

            loadedTeamMembers = loaded
        } else {
            loadedTeamMembers = Array(task.teamMembers)
        }
    }

    private func toggleMemberSelection(memberId: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedMemberIds.contains(memberId) {
                selectedMemberIds.remove(memberId)
            } else {
                selectedMemberIds.insert(memberId)
            }
        }
    }

    private func loadAvailableMembers() {
        guard let companyId = dataController.currentUser?.companyId else { return }

        Task {
            do {
                let userDTOs = try await dataController.apiService.fetchCompanyUsers(companyId: companyId)
                let teamMembers = userDTOs.map { TeamMember.fromUserDTO($0) }
                await MainActor.run {
                    self.availableMembers = teamMembers
                }
            } catch {
                print("Error loading available members: \(error)")
            }
        }
    }

    func saveTeamChanges() {
        guard selectedMemberIds != Set(task.getTeamMemberIds()) else {
            // No changes, nothing to save
            return
        }

        // Haptic feedback on save
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Store the new member IDs for optimistic update
        let newMemberIds = Array(selectedMemberIds)

        // Optimistically update UI immediately
        task.setTeamMemberIds(newMemberIds)
        task.needsSync = true  // Mark for sync

        // Also update calendar event if exists
        if let calendarEvent = task.calendarEvent {
            calendarEvent.setTeamMemberIds(newMemberIds)
            calendarEvent.needsSync = true
        }

        // Save to local database
        try? dataController.modelContext?.save()

        loadTaskTeamMembers()
        refreshKey = UUID()

        // Clear selections (parent will handle exiting edit mode)
        selectedMemberIds.removeAll()
        availableMembers.removeAll()

        // Perform API sync in background
        Task {
            do {
                print("[TASK_TEAM_UPDATE] Syncing task team members to API in background...")
                print("[TASK_TEAM_UPDATE] Selected member IDs: \(newMemberIds)")

                // Use DataController method which includes project team sync
                try await dataController.updateTaskTeamMembers(task: task, memberIds: newMemberIds)

                print("[TASK_TEAM_UPDATE] ✅ Task team synced to API (includes project team sync)")

                // Update calendar event team members if exists
                if let calendarEvent = task.calendarEvent {
                    try await dataController.updateCalendarEventTeamMembers(event: calendarEvent, memberIds: newMemberIds)
                    print("[TASK_TEAM_UPDATE] ✅ Calendar event team synced to API")
                }

            } catch {
                print("[TASK_TEAM_UPDATE] ⚠️ Sync failed: \(error)")
                print("[TASK_TEAM_UPDATE] ℹ️ Changes saved locally and marked for retry")
                // Changes are already saved locally with needsSync = true
                // Next sync will pick them up
            }
        }
    }
}
