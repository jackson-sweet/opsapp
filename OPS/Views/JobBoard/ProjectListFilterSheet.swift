//
//  ProjectListFilterSheet.swift
//  OPS
//
//  Job Board comprehensive filter sheet for projects
//  Wrapper around generic FilterSheet component
//

import SwiftUI

struct ProjectListFilterSheet: View {
    @EnvironmentObject private var dataController: DataController

    @Binding var selectedStatuses: Set<Status>
    @Binding var selectedTeamMemberIds: Set<String>
    @Binding var sortOption: ProjectSortOption

    let availableTeamMembers: [User]

    var body: some View {
        let sortBinding = Binding<ProjectSortOption?>(
            get: { sortOption },
            set: { if let newValue = $0 { sortOption = newValue } }
        )

        return FilterSheet(
            title: "Filter Projects",
            filters: buildFilters(),
            sortOptions: ProjectSortOption.allCases,
            selectedSort: sortBinding,
            getSortDisplay: { $0.rawValue }
        )
    }

    private func buildFilters() -> [FilterSectionConfig] {
        var filters: [FilterSectionConfig] = []

        // Status filter
        filters.append(.multiSelect(
            title: "PROJECT STATUS",
            icon: OPSStyle.Icons.alert,
            options: [Status.rfq, .estimated, .accepted, .inProgress, .completed, .closed],
            selection: $selectedStatuses,
            getDisplay: { $0.displayName },
            getColorIndicator: { .rectangle($0.color) }
        ))

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
