//
//  TaskListFilterSheet.swift
//  OPS
//
//  Job Board comprehensive filter sheet for tasks
//  Wrapper around generic FilterSheet component
//

import SwiftUI

struct TaskListFilterSheet: View {
    @EnvironmentObject private var dataController: DataController

    @Binding var selectedStatuses: Set<TaskStatus>
    @Binding var selectedTaskTypeIds: Set<String>
    @Binding var selectedTeamMemberIds: Set<String>
    @Binding var sortOption: TaskSortOption

    let availableTaskTypes: [TaskType]
    let availableTeamMembers: [User]

    var body: some View {
        let sortBinding = Binding<TaskSortOption?>(
            get: { sortOption },
            set: { if let newValue = $0 { sortOption = newValue } }
        )

        return FilterSheet(
            title: "Filter Tasks",
            filters: buildFilters(),
            sortOptions: TaskSortOption.allCases,
            selectedSort: sortBinding,
            getSortDisplay: { $0.rawValue }
        )
    }

    private func buildFilters() -> [FilterSectionConfig] {
        var filters: [FilterSectionConfig] = []

        // Status filter
        filters.append(.multiSelect(
            title: "TASK STATUS",
            icon: OPSStyle.Icons.alert,
            options: [TaskStatus.active, .completed, .cancelled],
            selection: $selectedStatuses,
            getDisplay: { $0.displayName },
            getColorIndicator: { .rectangle($0.color) }
        ))

        // Task type filter
        if !availableTaskTypes.isEmpty {
            filters.append(.multiSelectById(
                title: "TASK TYPE",
                icon: "checkmark.circle.fill",
                options: availableTaskTypes,
                selection: $selectedTaskTypeIds,
                getId: { $0.id },
                getDisplay: { $0.display },
                getIcon: { $0.icon ?? "checkmark.circle.fill" },
                getIconColor: { Color(hex: $0.color) ?? OPSStyle.Colors.primaryAccent }
            ))
        }

        // Team members filter
        if !availableTeamMembers.isEmpty {
            filters.append(.multiSelectById(
                title: "ASSIGNED TEAM MEMBERS",
                icon: OPSStyle.Icons.crew,
                options: availableTeamMembers,
                selection: $selectedTeamMemberIds,
                getId: { $0.id },
                getDisplay: { "\($0.firstName) \($0.lastName)" },
                getSubtitle: { $0.role.rawValue }
            ))
        }

        return filters
    }
}
