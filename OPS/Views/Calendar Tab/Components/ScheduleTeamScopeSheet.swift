//
//  ScheduleTeamScopeSheet.swift
//  OPS
//
//  Multi-select team member filter for the schedule calendar.
//  Uses the generic FilterSheet component for consistent styling.
//

import SwiftUI

struct ScheduleTeamScopeSheet: View {
    @ObservedObject var viewModel: CalendarViewModel
    @EnvironmentObject private var dataController: DataController

    /// Local binding that syncs to/from the viewModel
    @State private var selectedMemberIds: Set<String> = []

    /// Team members sorted with self at top
    private var sortedMembers: [TeamMember] {
        let currentUserId = dataController.currentUser?.id
        return viewModel.availableTeamMembers.sorted { a, b in
            let aIsSelf = a.id == currentUserId
            let bIsSelf = b.id == currentUserId
            if aIsSelf != bIsSelf { return aIsSelf }
            return a.fullName < b.fullName
        }
    }

    var body: some View {
        FilterSheet<NoSort>(
            title: "Filter by Team",
            filters: [
                .multiSelectById(
                    title: "TEAM MEMBERS",
                    icon: OPSStyle.Icons.crew,
                    options: sortedMembers,
                    selection: $selectedMemberIds,
                    getId: { $0.id },
                    getDisplay: { $0.fullName },
                    getSubtitle: { $0.role }
                )
            ]
        )
        .onAppear {
            selectedMemberIds = viewModel.selectedTeamMemberIds
        }
        .onChange(of: selectedMemberIds) { _, newValue in
            viewModel.selectedTeamMemberIds = newValue

            // Update scope based on selection
            if newValue.isEmpty {
                viewModel.updateScheduleScope(.all)
            } else if newValue.count == 1, let onlyId = newValue.first {
                viewModel.updateScheduleScope(.member(onlyId))
            } else {
                viewModel.updateScheduleScope(.all)
            }
        }
    }
}
