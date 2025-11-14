//
//  ProjectTeamView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI

/// Compact team member view for projects with navigation to details
struct ProjectTeamView: View {
    let project: Project
    @Binding var isEditing: Bool
    @Binding var triggerSave: Bool
    @State private var selectedTeamMember: User? = nil
    @State private var showingTeamMemberDetails = false
    @State private var showingTeamPicker = false
    @State private var selectedMemberIds: Set<String> = []
    @State private var availableMembers: [TeamMember] = []
    @State private var isSaving = false
    @EnvironmentObject private var dataController: DataController
    @State private var teamsRefreshed = false
    @State private var refreshKey = UUID() // Force refresh when this changes
    @State private var refreshedProject: Project? = nil

    init(project: Project, isEditing: Binding<Bool> = .constant(false), triggerSave: Binding<Bool> = .constant(false)) {
        self.project = project
        self._isEditing = isEditing
        self._triggerSave = triggerSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let activeProject = refreshedProject ?? project

            if !teamsRefreshed && activeProject.getTeamMemberIds().count > 0 && activeProject.teamMembers.isEmpty {
                loadingStateView
            } else if activeProject.teamMembers.isEmpty && !isEditing {
                emptyStateView(activeProject)
            } else {
                teamMembersView(activeProject)
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .sheet(isPresented: $showingTeamPicker) {
            ProjectTeamChangeSheet(project: project)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingTeamMemberDetails) {
            if let selectedMember = selectedTeamMember {
                // Show team member details
                ContactDetailView(user: selectedMember)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.medium, .large])
            } else {
                // Show full team list using the refreshed project if available
                if let refreshed = refreshedProject {
                    FullTeamListView(project: refreshed)
                } else {
                    FullTeamListView(project: project)
                }
            }
        }
        .onAppear {
            // Debug log the project team members when this view appears
            
            // Trigger manual team member sync
            if !teamsRefreshed {
                Task {
                    // Sync team members
                    await dataController.syncProjectTeamMembers(project)
                    
                    // Print updated info after sync
                    await MainActor.run {
                        
                        // Fetch fresh project from DataController (critical step)
                        if let freshProject = dataController.getProject(id: project.id) {
                            
                            if freshProject.teamMembers.isEmpty {
                            } else {
                                for (index, member) in freshProject.teamMembers.enumerated() {
                            }
                            
                            }
                            
                            // Update the refreshed project to trigger UI refresh
                            refreshedProject = freshProject
                        } else {
                        }
                        
                        // Update state to refresh the view
                        teamsRefreshed = true
                        refreshKey = UUID() // Force refresh
                    }
                }
            }
        }
        .id(refreshKey) // Force view to refresh when key changes
        .onChange(of: isEditing) { oldValue, newValue in
            if newValue {
                // Entering edit mode
                selectedMemberIds = Set(project.getTeamMemberIds())
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

    private var loadingStateView: some View {
        HStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
            Text("Loading team members...")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(.vertical, 8)
    }

    private func emptyStateView(_ activeProject: Project) -> some View {
        HStack {
            Text(activeProject.getTeamMemberIds().isEmpty ?
               "No team members assigned" :
               "Team member data unavailable")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))

            Spacer()

            if !activeProject.usesTaskBasedScheduling {
                Button("ADD") {
                    showingTeamPicker = true
                }
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
        .padding(.vertical, 8)
    }

    private func teamMembersView(_ activeProject: Project) -> some View {
        VStack(spacing: 0) {
            currentTeamMembersSection(activeProject)

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

    private func currentTeamMembersSection(_ activeProject: Project) -> some View {
        ForEach(activeProject.teamMembers, id: \.id) { member in
            teamMemberRow(member)
        }
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

    // MARK: - Inline Editing Functions

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
        guard selectedMemberIds != Set(project.getTeamMemberIds()) else {
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
                print("[TEAM_UPDATE] Updating project team members...")
                print("[TEAM_UPDATE] Selected member IDs: \(Array(selectedMemberIds))")

                let updates = [BubbleFields.Project.teamMembers: Array(selectedMemberIds)]
                let bodyData = try JSONSerialization.data(withJSONObject: updates)

                // Try with EmptyResponse since Bubble might return empty for this field update
                let _: EmptyResponse = try await dataController.apiService.executeRequest(
                    endpoint: "api/1.1/obj/Project/\(project.id)",
                    method: "PATCH",
                    body: bodyData,
                    requiresAuth: true
                )

                print("[TEAM_UPDATE] ✅ Team updated in Bubble")

                await MainActor.run {
                    project.setTeamMemberIds(Array(selectedMemberIds))
                    project.needsSync = false
                    project.lastSyncedAt = Date()

                    do {
                        try dataController.modelContext?.save()
                    } catch {
                        print("Error saving context: \(error)")
                    }

                    // Refresh team members to show updated list
                    Task {
                        await dataController.syncProjectTeamMembers(project)
                        await MainActor.run {
                            if let freshProject = dataController.getProject(id: project.id) {
                                refreshedProject = freshProject
                            }
                            teamsRefreshed = true
                            refreshKey = UUID()

                            // Exit edit mode and clear selections
                            isEditing = false
                            selectedMemberIds.removeAll()
                            availableMembers.removeAll()
                            isSaving = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    print("[TEAM_UPDATE] ❌ Error: \(error)")
                    isSaving = false
                }
            }
        }
    }
}

// TeamMemberAvatar component removed - using unified UserAvatar instead

/// Full team list view that shows in a sheet
struct FullTeamListView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTeamMember: User? = nil
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(project.teamMembers) { member in
                            HStack(spacing: 16) {
                                // Avatar
                                UserAvatar(user: member, size: 50)
                                
                                // Details
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(member.firstName) \(member.lastName)")
                                        .font(OPSStyle.Typography.body.weight(.medium))
                                        .foregroundColor(.white)
                                    
                                    Text(member.role.displayName)
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                    
                                    if let email = member.email, !email.isEmpty {
                                        Text(email)
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                            .lineLimit(1)
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .font(OPSStyle.Typography.smallBody)
                            }
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(12)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTeamMember = member
                            }
                            .onLongPressGesture {
                                // Same action as tap for now, can be customized later
                                selectedTeamMember = member
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PROJECT TEAM")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                }
            }
            .sheet(item: $selectedTeamMember) { member in
                ContactDetailView(user: member)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

struct ProjectTeamView_Previews: PreviewProvider {
    static var previews: some View {
        let project = Project(id: "123", title: "Sample Project", status: .inProgress)
        
        // Add sample team members
        let member1 = User(id: "1", firstName: "John", lastName: "Doe", role: .fieldCrew, companyId: "company-123")
        let member2 = User(id: "2", firstName: "Jane", lastName: "Smith", role: .officeCrew, companyId: "company-123")
        let member3 = User(id: "3", firstName: "Mike", lastName: "Johnson", role: .fieldCrew, companyId: "company-123")
        let member4 = User(id: "4", firstName: "Sarah", lastName: "Williams", role: .officeCrew, companyId: "company-123")
        
        project.teamMembers = [member1, member2, member3, member4]
        
        return Group {
            ProjectTeamView(project: project)
                .environmentObject(DataController())
                .padding()
                .background(OPSStyle.Colors.background)
                .preferredColorScheme(.dark)
                .previewLayout(.sizeThatFits)
            
            FullTeamListView(project: project)
                .preferredColorScheme(.dark)
        }
    }
}
