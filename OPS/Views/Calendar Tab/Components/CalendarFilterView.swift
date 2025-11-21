//
//  CalendarFilterView.swift
//  OPS
//
//  Filter popover for calendar events by team member, task type, client, and status
//  Wrapper around generic FilterSheet component
//

import SwiftUI
import SwiftData

struct CalendarFilterView: View {
    @EnvironmentObject private var dataController: DataController
    @ObservedObject var viewModel: CalendarViewModel
    @Environment(\.dismiss) private var dismiss

    // Local state for filters being edited
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var selectedTaskTypeIds: Set<String> = []
    @State private var selectedClientIds: Set<String> = []
    @State private var selectedStatuses: Set<Status> = []

    // Available options
    @State private var availableTeamMembers: [TeamMember] = []
    @State private var availableTaskTypes: [TaskType] = []
    @State private var availableClients: [Client] = []

    var body: some View {
        FilterSheet<NoSort>(
            title: "Filter Calendar",
            filters: buildFilters()
        )
        .onAppear {
            loadAvailableOptions()
            loadCurrentFilters()
        }
        .onChange(of: selectedTeamMemberIds) { _, _ in applyFilters() }
        .onChange(of: selectedTaskTypeIds) { _, _ in applyFilters() }
        .onChange(of: selectedClientIds) { _, _ in applyFilters() }
        .onChange(of: selectedStatuses) { _, _ in applyFilters() }
    }

    private func buildFilters() -> [FilterSectionConfig] {
        var filters: [FilterSectionConfig] = []

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
        if !availableTaskTypes.isEmpty {
            filters.append(.multiSelectById(
                title: "TASK TYPES",
                icon: "checkmark.circle.fill",
                options: availableTaskTypes,
                selection: $selectedTaskTypeIds,
                getId: { $0.id },
                getDisplay: { $0.display },
                getIcon: { $0.icon ?? "checkmark.circle.fill" },
                getIconColor: { Color(hex: $0.color) ?? OPSStyle.Colors.primaryAccent }
            ))
        }

        // Status filter
        filters.append(.multiSelect(
            title: "STATUS",
            icon: OPSStyle.Icons.alert,
            options: Status.allCases,
            selection: $selectedStatuses,
            getDisplay: { $0.displayName },
            getColorIndicator: { .circle($0.color) }
        ))

        // Clients filter with search
        if !availableClients.isEmpty {
            filters.append(.multiSelectWithSearch(
                title: "CLIENTS",
                icon: "building.2.fill",
                options: availableClients,
                selection: $selectedClientIds,
                getId: { $0.id },
                getDisplay: { $0.name },
                getSubtitle: { $0.email ?? "" },
                searchPlaceholder: "Search clients...",
                pageSize: 5
            ))
        }

        return filters
    }

    private func loadAvailableOptions() {
        guard let companyId = dataController.currentUser?.companyId,
              let company = dataController.getCompany(id: companyId) else { return }

        // Load team members
        availableTeamMembers = company.teamMembers.sorted { $0.fullName < $1.fullName }

        // Load task types
        availableTaskTypes = dataController.getAllTaskTypes(for: companyId).sorted { $0.displayOrder < $1.displayOrder }

        // Load clients - sorted by most recent first (createdAt descending)
        availableClients = dataController.getAllClients(for: companyId).sorted {
            // If both have createdAt, sort by most recent first
            if let date1 = $0.createdAt, let date2 = $1.createdAt {
                return date1 > date2
            }
            // If only one has createdAt, prioritize it
            if $0.createdAt != nil { return true }
            if $1.createdAt != nil { return false }
            // Fallback to alphabetical if neither has createdAt
            return $0.name < $1.name
        }
    }

    private func loadCurrentFilters() {
        selectedTeamMemberIds = viewModel.selectedTeamMemberIds
        selectedTaskTypeIds = viewModel.selectedTaskTypeIds
        selectedClientIds = viewModel.selectedClientIds
        selectedStatuses = viewModel.selectedStatuses
    }

    private func applyFilters() {
        viewModel.applyFilters(
            teamMemberIds: selectedTeamMemberIds,
            taskTypeIds: selectedTaskTypeIds,
            clientIds: selectedClientIds,
            statuses: selectedStatuses
        )
    }
}
