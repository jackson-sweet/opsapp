//
//  ProjectSearchFilterView.swift
//  OPS
//
//  Multi-select filter view for ProjectSearchSheet
//  Wrapper around generic FilterSheet component
//

import SwiftUI

struct ProjectSearchFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    // Bindings to parent view
    @Binding var selectedStatuses: Set<Status>
    @Binding var selectedTeamMemberIds: Set<String>
    @Binding var selectedTaskTypeIds: Set<String>
    @Binding var selectedClientIds: Set<String>

    // Available options
    let availableTeamMembers: [TeamMember]
    let availableTaskTypes: [TaskType]
    let availableClients: [Client]

    private var companyId: String? {
        dataController.currentUser?.companyId
    }

    /// Grouped by colour so like chips cluster (bug bc9c2e83).
    private var selectableTaskTypes: [TaskType] {
        guard let companyId else { return [] }

        return TaskTypeSelectionPolicy.colorOrdered(
            TaskTypeSelectionPolicy.selectableTaskTypes(
                from: availableTaskTypes,
                companyId: companyId
            )
        )
    }

    private var selectableTaskTypeIds: [String] {
        selectableTaskTypes.map(\.id)
    }

    var body: some View {
        FilterSheet<NoSort>(
            title: "Filter Projects",
            filters: buildFilters()
        )
        .onAppear {
            sanitizeTaskTypeSelection()
        }
        .onChange(of: selectableTaskTypeIds) { _, _ in
            sanitizeTaskTypeSelection()
        }
        .onChange(of: companyId) { _, _ in
            sanitizeTaskTypeSelection()
        }
    }

    private func buildFilters() -> [FilterSectionConfig] {
        var filters: [FilterSectionConfig] = []

        // Status filter
        let availableStatuses: [Status] = [.inProgress, .accepted, .estimated, .rfq, .completed, .closed, .archived]
        filters.append(.multiSelect(
            title: "PROJECT STATUS",
            icon: OPSStyle.Icons.alert,
            options: availableStatuses,
            selection: $selectedStatuses,
            getDisplay: { $0.displayName },
            getColorIndicator: { .circle($0.color) }
        ))

        // Team members filter
        if !availableTeamMembers.isEmpty {
            filters.append(.multiSelectById(
                title: "TEAM MEMBERS",
                icon: OPSStyle.Icons.crew,
                options: availableTeamMembers,
                selection: $selectedTeamMemberIds,
                getId: { $0.id },
                getDisplay: { $0.fullName },
                getSubtitle: { $0.role }
            ))
        }

        // Task types filter
        if !selectableTaskTypes.isEmpty {
            filters.append(.multiSelectById(
                title: "TASK TYPES",
                icon: "checkmark.circle.fill",
                options: selectableTaskTypes,
                selection: $selectedTaskTypeIds,
                getId: { $0.id },
                getDisplay: { $0.display },
                getIcon: { $0.icon ?? "checkmark.circle.fill" },
                getIconColor: { Color(hex: $0.color) ?? OPSStyle.Colors.primaryAccent }
            ))
        }

        // Clients filter
        if !availableClients.isEmpty {
            filters.append(.multiSelectById(
                title: "CLIENTS",
                icon: "building.2.fill",
                options: availableClients,
                selection: $selectedClientIds,
                getId: { $0.id },
                getDisplay: { $0.name },
                getSubtitle: { $0.email ?? "" }
            ))
        }

        return filters
    }

    private func sanitizeTaskTypeSelection() {
        guard let companyId else {
            selectedTaskTypeIds.removeAll()
            return
        }

        let sanitized = TaskTypeSelectionPolicy.sanitizedSelection(
            selectedTaskTypeIds,
            from: availableTaskTypes,
            companyId: companyId
        )
        guard sanitized != selectedTaskTypeIds else { return }
        selectedTaskTypeIds = sanitized
    }
}
