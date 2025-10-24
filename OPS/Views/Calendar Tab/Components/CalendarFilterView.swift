//
//  CalendarFilterView.swift
//  OPS
//
//  Filter popover for calendar events by team member, task type, and client
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
    
    // Available options
    @State private var availableTeamMembers: [TeamMember] = []
    @State private var availableTaskTypes: [TaskType] = []
    @State private var availableClients: [Client] = []

    // Search state for clients
    @State private var clientSearchText: String = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Team Members Section
                        if !availableTeamMembers.isEmpty {
                            filterSection(
                                title: "TEAM MEMBERS",
                                icon: "person.2.fill"
                            ) {
                                teamMembersContent
                            }
                        }
                        
                        // Task Types Section
                        if !availableTaskTypes.isEmpty {
                            filterSection(
                                title: "TASK TYPES",
                                icon: "checkmark.circle.fill"
                            ) {
                                taskTypesContent
                            }
                        }
                        
                        // Clients Section
                        if !availableClients.isEmpty {
                            filterSection(
                                title: "CLIENTS",
                                icon: "building.2.fill"
                            ) {
                                clientsContent
                            }
                        }
                        
                        // Active Filters Summary
                        if hasActiveFilters {
                            activeFiltersSummary
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("FILTER CALENDAR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        applyFilters()
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .onAppear {
            loadAvailableOptions()
            loadCurrentFilters()
        }
    }
    
    // MARK: - Section Components
    
    private func filterSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(title)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
            }
            
            // Content card
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Team Members Content
    
    private var teamMembersContent: some View {
        VStack(spacing: 0) {
            // Select All option
            filterRow(
                title: "All Team Members",
                isSelected: selectedTeamMemberIds.isEmpty,
                isSpecial: true
            ) {
                selectedTeamMemberIds.removeAll()
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Individual team members
            ForEach(availableTeamMembers, id: \.id) { member in
                filterRow(
                    title: member.fullName,
                    subtitle: member.role,
                    isSelected: selectedTeamMemberIds.contains(member.id)
                ) {
                    toggleSelection(member.id, in: &selectedTeamMemberIds)
                }
                
                if member.id != availableTeamMembers.last?.id {
                    Divider()
                        .background(Color.white.opacity(0.05))
                        .padding(.leading, 16)
                }
            }
        }
    }
    
    // MARK: - Task Types Content
    
    private var taskTypesContent: some View {
        VStack(spacing: 0) {
            // Select All option
            filterRow(
                title: "All Task Types",
                isSelected: selectedTaskTypeIds.isEmpty,
                isSpecial: true
            ) {
                selectedTaskTypeIds.removeAll()
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Individual task types
            ForEach(availableTaskTypes, id: \.id) { taskType in
                HStack(spacing: 12) {
                    // Task type color indicator
                    Circle()
                        .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                        .frame(width: 10, height: 10)
                    
                    // Task type icon
                    if let icon = taskType.icon {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                            .frame(width: 20)
                    }
                    
                    Text(taskType.display)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Spacer()
                    
                    // Selection checkmark
                    if selectedTaskTypeIds.contains(taskType.id) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleSelection(taskType.id, in: &selectedTaskTypeIds)
                }
                
                if taskType.id != availableTaskTypes.last?.id {
                    Divider()
                        .background(Color.white.opacity(0.05))
                        .padding(.leading, 16)
                }
            }
        }
    }
    
    // MARK: - Clients Content

    private var clientsContent: some View {
        VStack(spacing: 0) {
            // Select All option
            filterRow(
                title: "All Clients",
                isSelected: selectedClientIds.isEmpty,
                isSpecial: true
            ) {
                selectedClientIds.removeAll()
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                TextField("Search clients...", text: $clientSearchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .autocapitalization(.none)
                    .autocorrectionDisabled(true)

                if !clientSearchText.isEmpty {
                    Button(action: {
                        clientSearchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.background.opacity(0.5))

            Divider()
                .background(Color.white.opacity(0.1))

            // Individual clients (filtered)
            ForEach(filteredClients, id: \.id) { client in
                filterRow(
                    title: client.name,
                    subtitle: client.email ?? "",
                    isSelected: selectedClientIds.contains(client.id)
                ) {
                    toggleSelection(client.id, in: &selectedClientIds)
                }

                if client.id != filteredClients.last?.id {
                    Divider()
                        .background(Color.white.opacity(0.05))
                        .padding(.leading, 16)
                }
            }

            // Show message if no results
            if filteredClients.isEmpty && !clientSearchText.isEmpty {
                Text("No clients found")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.vertical, 32)
            }
        }
    }

    // Filtered clients based on search text
    private var filteredClients: [Client] {
        if clientSearchText.isEmpty {
            return availableClients
        }
        return availableClients.filter { client in
            client.name.localizedCaseInsensitiveContains(clientSearchText) ||
            (client.email?.localizedCaseInsensitiveContains(clientSearchText) ?? false) ||
            (client.address?.localizedCaseInsensitiveContains(clientSearchText) ?? false)
        }
    }
    
    // MARK: - Filter Row Component
    
    private func filterRow(
        title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        isSpecial: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(isSpecial ? OPSStyle.Typography.bodyBold : OPSStyle.Typography.body)
                    .foregroundColor(isSpecial ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryText)
                
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            
            Spacer()
            
            if isSelected && !isSpecial {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            } else if isSpecial && isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
    
    // MARK: - Active Filters Summary
    
    private var activeFiltersSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIVE FILTERS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            HStack {
                
                VStack(alignment: .leading, spacing: 8) {
                    if !selectedTeamMemberIds.isEmpty {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            
                            Text("\(selectedTeamMemberIds.count) team member\(selectedTeamMemberIds.count == 1 ? "" : "s") selected")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                    
                    if !selectedTaskTypeIds.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            
                            Text("\(selectedTaskTypeIds.count) task type\(selectedTaskTypeIds.count == 1 ? "" : "s") selected")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                    
                    if !selectedClientIds.isEmpty {
                        HStack {
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            
                            Text("\(selectedClientIds.count) client\(selectedClientIds.count == 1 ? "" : "s") selected")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                    
                    Button(action: resetFilters) {
                        Text("Reset All Filters")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            Spacer()
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var hasActiveFilters: Bool {
        !selectedTeamMemberIds.isEmpty || !selectedTaskTypeIds.isEmpty || !selectedClientIds.isEmpty
    }
    
    // MARK: - Helper Methods
    
    private func toggleSelection(_ id: String, in set: inout Set<String>) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }
    
    private func loadAvailableOptions() {
        guard let companyId = dataController.currentUser?.companyId,
              let company = dataController.getCompany(id: companyId) else { return }
        
        // Load team members
        availableTeamMembers = company.teamMembers.sorted { $0.fullName < $1.fullName }
        
        // Load task types
        availableTaskTypes = dataController.getAllTaskTypes(for: companyId).sorted { $0.displayOrder < $1.displayOrder }
        
        // Load clients
        availableClients = dataController.getAllClients(for: companyId).sorted { $0.name < $1.name }
    }
    
    private func loadCurrentFilters() {
        // Load current filters from view model
        selectedTeamMemberIds = viewModel.selectedTeamMemberIds
        selectedTaskTypeIds = viewModel.selectedTaskTypeIds
        selectedClientIds = viewModel.selectedClientIds
    }
    
    private func applyFilters() {
        // Apply filters to view model
        viewModel.applyFilters(
            teamMemberIds: selectedTeamMemberIds,
            taskTypeIds: selectedTaskTypeIds,
            clientIds: selectedClientIds
        )
    }
    
    private func resetFilters() {
        selectedTeamMemberIds.removeAll()
        selectedTaskTypeIds.removeAll()
        selectedClientIds.removeAll()
    }
}
