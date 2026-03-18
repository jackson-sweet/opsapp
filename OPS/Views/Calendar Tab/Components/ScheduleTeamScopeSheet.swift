//
//  ScheduleTeamScopeSheet.swift
//  OPS
//
//  Multi-select team member filter for the schedule calendar.
//  Replaces the inline scope chips with a dedicated sheet.
//

import SwiftUI

struct ScheduleTeamScopeSheet: View {
    @ObservedObject var viewModel: CalendarViewModel
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    /// Current user's ID — appears first in the list
    private var currentUserId: String? {
        dataController.currentUser?.id
    }

    /// Team members sorted with self at top
    private var sortedMembers: [TeamMember] {
        let members = viewModel.availableTeamMembers
        return members.sorted { a, b in
            let aIsSelf = a.id == currentUserId
            let bIsSelf = b.id == currentUserId
            if aIsSelf != bIsSelf { return aIsSelf }
            return a.fullName < b.fullName
        }
    }

    /// Whether "All Projects" (no member filter) is active
    private var isAllSelected: Bool {
        viewModel.scheduleScope == .all && viewModel.selectedTeamMemberIds.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("FILTER BY TEAM")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .tracking(1)

                Spacer()

                Button("DONE") {
                    dismiss()
                }
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // All Projects row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.selectedTeamMemberIds.removeAll()
                    viewModel.updateScheduleScope(.all)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: 36, height: 36)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .clipShape(Circle())

                    Text("ALL PROJECTS")
                        .font(OPSStyle.Typography.bodyEmphasis)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    if isAllSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 20)
                .padding(.vertical, 4)

            // Team members list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(sortedMembers, id: \.id) { member in
                        let isSelf = member.id == currentUserId
                        let isSelected = viewModel.selectedTeamMemberIds.contains(member.id)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                toggleMember(member.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                UserAvatar(teamMember: member, size: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(member.fullName.uppercased())
                                            .font(OPSStyle.Typography.bodyEmphasis)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                            .lineLimit(1)

                                        if isSelf {
                                            Text("YOU")
                                                .font(OPSStyle.Typography.miniLabel)
                                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.15))
                                                )
                                        }
                                    }

                                    if !member.role.isEmpty {
                                        Text(member.role.uppercased())
                                            .font(OPSStyle.Typography.microLabel)
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
        }
        .background(OPSStyle.Colors.background)
    }

    private func toggleMember(_ memberId: String) {
        if viewModel.selectedTeamMemberIds.contains(memberId) {
            viewModel.selectedTeamMemberIds.remove(memberId)
        } else {
            viewModel.selectedTeamMemberIds.insert(memberId)
        }

        // Update scope based on selection
        if viewModel.selectedTeamMemberIds.isEmpty {
            viewModel.updateScheduleScope(.all)
        } else if viewModel.selectedTeamMemberIds.count == 1,
                  let onlyId = viewModel.selectedTeamMemberIds.first {
            viewModel.updateScheduleScope(.member(onlyId))
        } else {
            // Multi-select: keep scope as .all but the selectedTeamMemberIds
            // will be used by the task filter to show only selected members' tasks
            viewModel.updateScheduleScope(.all)
        }
    }
}
