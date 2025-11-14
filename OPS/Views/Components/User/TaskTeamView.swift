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
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
            } else {
                // Exiting edit mode
                selectedMemberIds.removeAll()
                availableMembers.removeAll()
            }
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
                .background(Color.white.opacity(0.1))
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
            // No changes, just exit edit mode
            isEditing = false
            return
        }

        // Haptic feedback on save
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        isSaving = true

        Task {
            do {
                print("[TASK_TEAM_UPDATE] Updating task team members...")
                print("[TASK_TEAM_UPDATE] Selected member IDs: \(Array(selectedMemberIds))")

                // Update task team members
                let updates = [BubbleFields.Task.teamMembers: Array(selectedMemberIds)]
                let bodyData = try JSONSerialization.data(withJSONObject: updates)

                let _: EmptyResponse = try await dataController.apiService.executeRequest(
                    endpoint: "api/1.1/obj/Task/\(task.id)",
                    method: "PATCH",
                    body: bodyData,
                    requiresAuth: true
                )

                print("[TASK_TEAM_UPDATE] ✅ Team updated in Bubble")

                // Update calendar event team members if exists
                if let calendarEvent = task.calendarEvent {
                    let eventUpdates = [BubbleFields.CalendarEvent.teamMembers: Array(selectedMemberIds)]
                    let eventBodyData = try JSONSerialization.data(withJSONObject: eventUpdates)

                    let _: EmptyResponse = try await dataController.apiService.executeRequest(
                        endpoint: "api/1.1/obj/CalendarEvent/\(calendarEvent.id)",
                        method: "PATCH",
                        body: eventBodyData,
                        requiresAuth: true
                    )

                    print("[TASK_TEAM_UPDATE] ✅ Calendar event team updated")
                }

                await MainActor.run {
                    task.setTeamMemberIds(Array(selectedMemberIds))
                    task.needsSync = false
                    task.lastSyncedAt = Date()

                    if let calendarEvent = task.calendarEvent {
                        calendarEvent.setTeamMemberIds(Array(selectedMemberIds))
                        calendarEvent.needsSync = false
                        calendarEvent.lastSyncedAt = Date()
                    }

                    do {
                        try dataController.modelContext?.save()
                    } catch {
                        print("Error saving context: \(error)")
                    }

                    // Refresh team members
                    loadTaskTeamMembers()
                    refreshKey = UUID()

                    // Exit edit mode and clear selections
                    isEditing = false
                    selectedMemberIds.removeAll()
                    availableMembers.removeAll()
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    print("[TASK_TEAM_UPDATE] ❌ Error: \(error)")
                    isSaving = false
                }
            }
        }
    }
}
