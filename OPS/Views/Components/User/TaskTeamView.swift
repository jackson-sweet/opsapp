//
//  TaskTeamView.swift
//  OPS
//
//  Task team member view - display only (editing handled via sheet)
//

import SwiftUI
import SwiftData

/// Compact team member view for tasks - display only
struct TaskTeamView: View {
    let task: ProjectTask
    @State private var selectedTeamMember: User? = nil
    @State private var showingTeamMemberDetails = false
    @EnvironmentObject private var dataController: DataController
    @State private var loadedTeamMembers: [User] = []
    @State private var refreshKey = UUID()
    @Query private var users: [User]

    init(task: ProjectTask) {
        self.task = task
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if loadedTeamMembers.isEmpty && task.teamMembers.isEmpty {
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
        .onChange(of: task.teamMemberIdsString) { _, _ in
            // Reload team members when the IDs change
            loadTaskTeamMembers()
            refreshKey = UUID()
        }
        .id(refreshKey)
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

            Image(systemName: OPSStyle.Icons.chevronRight)
                .font(.system(size: 14))
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
        .onTapGesture {
            selectedTeamMember = member
            showingTeamMemberDetails = true
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
}
