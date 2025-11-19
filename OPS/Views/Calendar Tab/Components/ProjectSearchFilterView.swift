//
//  ProjectSearchFilterView.swift
//  OPS
//
//  Multi-select filter view for ProjectSearchSheet
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
    // Removed: scheduling type filter (task-only scheduling migration)
    // @Binding var selectedSchedulingTypes: Set<ProjectEventType>
    
    // Available options
    let availableTeamMembers: [TeamMember]
    let availableTaskTypes: [TaskType]
    let availableClients: [Client]
    
    // All available statuses
    private let availableStatuses: [Status] = [.inProgress, .accepted, .estimated, .rfq, .completed, .closed, .archived]
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Scheduling Type Section - Removed (task-only scheduling migration)
                        // filterSection(
                        //     title: "SCHEDULING TYPE",
                        //     icon: "calendar"
                        // ) {
                        //     schedulingTypeContent
                        // }
                        
                        // Status Section
                        filterSection(
                            title: "PROJECT STATUS",
                            icon: "flag.fill"
                        ) {
                            statusContent
                        }
                        
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
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("FILTER PROJECTS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                ToolbarItem(placement: .principal) {
                    Text("FILTER PROJECTS")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("APPLY") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }
    
    // MARK: - Content Sections

    // Removed: schedulingTypeContent - task-only scheduling migration
    // All projects now use task-based scheduling
    
    private var statusContent: some View {
        VStack(spacing: 0) {
            // "All" option
            filterRow(
                title: "All Statuses",
                subtitle: nil,
                isSelected: selectedStatuses.isEmpty,
                isSpecial: true
            ) {
                selectedStatuses.removeAll()
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Individual statuses
            ForEach(availableStatuses, id: \.self) { status in
                HStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 10, height: 10)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(status.displayName)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        
                        Spacer()
                        
                        if selectedStatuses.contains(status) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleSelection(status, in: &selectedStatuses)
                }
                
                if status != availableStatuses.last {
                    Divider()
                        .background(Color.white.opacity(0.05))
                        .padding(.leading, 40)
                }
            }
        }
    }
    
    private var teamMembersContent: some View {
        VStack(spacing: 0) {
            // "All" option
            filterRow(
                title: "All Team Members",
                subtitle: nil,
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
                        .padding(.leading, 40)
                }
            }
        }
    }
    
    private var taskTypesContent: some View {
        VStack(spacing: 0) {
            // "All" option
            filterRow(
                title: "All Task Types",
                subtitle: nil,
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
                    
                    filterRow(
                        title: taskType.display,
                        subtitle: nil,
                        isSelected: selectedTaskTypeIds.contains(taskType.id)
                    ) {
                        toggleSelection(taskType.id, in: &selectedTaskTypeIds)
                    }
                }
                
                if taskType.id != availableTaskTypes.last?.id {
                    Divider()
                        .background(Color.white.opacity(0.05))
                        .padding(.leading, 40)
                }
            }
        }
    }
    
    private var clientsContent: some View {
        VStack(spacing: 0) {
            // "All" option
            filterRow(
                title: "All Clients",
                subtitle: nil,
                isSelected: selectedClientIds.isEmpty,
                isSpecial: true
            ) {
                selectedClientIds.removeAll()
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Individual clients
            ForEach(availableClients, id: \.id) { client in
                filterRow(
                    title: client.name,
                    subtitle: client.email ?? "",
                    isSelected: selectedClientIds.contains(client.id)
                ) {
                    toggleSelection(client.id, in: &selectedClientIds)
                }
                
                if client.id != availableClients.last?.id {
                    Divider()
                        .background(Color.white.opacity(0.05))
                        .padding(.leading, 40)
                }
            }
        }
    }
    
    // MARK: - Helper Views
    
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
            }
            .padding(.horizontal, 20)
            
            // Section content
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
            .padding(.horizontal, 20)
        }
    }
    
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
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
    
    private var activeFiltersSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIVE FILTERS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, 20)
            
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    if !selectedStatuses.isEmpty {
                        HStack {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            
                            Text("\(selectedStatuses.count) status\(selectedStatuses.count == 1 ? "" : "es") selected")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                    
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
                    
                    // Removed: scheduling type filter display (task-only scheduling migration)
                    /*
                    if !selectedSchedulingTypes.isEmpty {
                        HStack {
                            Image(systemName: "calendar")
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text("\(selectedSchedulingTypes.count) scheduling type\(selectedSchedulingTypes.count == 1 ? "" : "s") selected")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                    */
                    
                    Button(action: resetFilters) {
                        Text("Reset All Filters")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
                )
                
                Spacer()
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Helper Properties
    
    private var hasActiveFilters: Bool {
        !selectedStatuses.isEmpty || !selectedTeamMemberIds.isEmpty || !selectedTaskTypeIds.isEmpty || !selectedClientIds.isEmpty // || !selectedSchedulingTypes.isEmpty
    }
    
    // MARK: - Helper Methods
    
    private func toggleSelection<T: Hashable>(_ item: T, in set: inout Set<T>) {
        if set.contains(item) {
            set.remove(item)
        } else {
            set.insert(item)
        }
    }
    
    private func resetFilters() {
        selectedStatuses.removeAll()
        selectedTeamMemberIds.removeAll()
        selectedTaskTypeIds.removeAll()
        selectedClientIds.removeAll()
        // selectedSchedulingTypes.removeAll()  // Removed (task-only scheduling migration)
    }
}