//
//  JobBoardProjectListView.swift
//  OPS
//
//  Created by Assistant on 2025-09-26.
//

import SwiftUI
import SwiftData

struct JobBoardProjectListView: View {
    @EnvironmentObject private var dataController: DataController
    @Query private var allProjects: [Project]
    let searchText: String
    @Binding var showingFilters: Bool
    @Binding var showingFilterSheet: Bool
    @State private var selectedStatuses: Set<Status> = []
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var sortOption: ProjectSortOption = .createdDateDescending
    @State private var showingCreateProject = false
    @State private var isClosedExpanded = false
    @State private var isArchivedExpanded = false

    private var availableTeamMembers: [User] {
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        return dataController.getTeamMembers(companyId: companyId)
    }

    private var filteredProjects: [Project] {
        var filtered = allProjects

        if !selectedStatuses.isEmpty {
            filtered = filtered.filter { selectedStatuses.contains($0.status) }
        }

        if !selectedTeamMemberIds.isEmpty {
            filtered = filtered.filter { project in
                let projectTeamMemberIds = Set(project.getTeamMemberIds())
                return !projectTeamMemberIds.intersection(selectedTeamMemberIds).isEmpty
            }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { project in
                project.title.localizedCaseInsensitiveContains(searchText) ||
                project.effectiveClientName.localizedCaseInsensitiveContains(searchText) ||
                (project.projectDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        switch sortOption {
        case .createdDateDescending, .scheduledDateDescending:
            return filtered.sorted { p1, p2 in
                let p1Unscheduled = (p1.startDate == nil || p1.endDate == nil) && p1.status != .closed && p1.status != .archived
                let p2Unscheduled = (p2.startDate == nil || p2.endDate == nil) && p2.status != .closed && p2.status != .archived
                let p1Unassigned = p1.teamMembers.isEmpty && p1.status != .closed && p1.status != .archived
                let p2Unassigned = p2.teamMembers.isEmpty && p2.status != .closed && p2.status != .archived

                if p1Unscheduled != p2Unscheduled { return p1Unscheduled }
                if p1Unassigned != p2Unassigned { return p1Unassigned }
                return (p1.startDate ?? Date.distantPast) > (p2.startDate ?? Date.distantPast)
            }
        case .createdDateAscending, .scheduledDateAscending:
            return filtered.sorted { p1, p2 in
                let p1Unscheduled = (p1.startDate == nil || p1.endDate == nil) && p1.status != .closed && p1.status != .archived
                let p2Unscheduled = (p2.startDate == nil || p2.endDate == nil) && p2.status != .closed && p2.status != .archived
                let p1Unassigned = p1.teamMembers.isEmpty && p1.status != .closed && p1.status != .archived
                let p2Unassigned = p2.teamMembers.isEmpty && p2.status != .closed && p2.status != .archived

                if p1Unscheduled != p2Unscheduled { return p1Unscheduled }
                if p1Unassigned != p2Unassigned { return p1Unassigned }
                return (p1.startDate ?? Date.distantPast) < (p2.startDate ?? Date.distantPast)
            }
        case .statusAscending:
            return filtered.sorted { p1, p2 in
                let p1Unscheduled = (p1.startDate == nil || p1.endDate == nil) && p1.status != .closed && p1.status != .archived
                let p2Unscheduled = (p2.startDate == nil || p2.endDate == nil) && p2.status != .closed && p2.status != .archived
                let p1Unassigned = p1.teamMembers.isEmpty && p1.status != .closed && p1.status != .archived
                let p2Unassigned = p2.teamMembers.isEmpty && p2.status != .closed && p2.status != .archived

                if p1Unscheduled != p2Unscheduled { return p1Unscheduled }
                if p1Unassigned != p2Unassigned { return p1Unassigned }
                return p1.status.sortOrder < p2.status.sortOrder
            }
        case .statusDescending:
            return filtered.sorted { p1, p2 in
                let p1Unscheduled = (p1.startDate == nil || p1.endDate == nil) && p1.status != .closed && p1.status != .archived
                let p2Unscheduled = (p2.startDate == nil || p2.endDate == nil) && p2.status != .closed && p2.status != .archived
                let p1Unassigned = p1.teamMembers.isEmpty && p1.status != .closed && p1.status != .archived
                let p2Unassigned = p2.teamMembers.isEmpty && p2.status != .closed && p2.status != .archived

                if p1Unscheduled != p2Unscheduled { return p1Unscheduled }
                if p1Unassigned != p2Unassigned { return p1Unassigned }
                return p1.status.sortOrder > p2.status.sortOrder
            }
        }
    }

    private var activeProjects: [Project] {
        filteredProjects.filter { $0.status != .closed && $0.status != .archived }
    }

    private var closedProjects: [Project] {
        filteredProjects.filter { $0.status == .closed }
    }

    private var archivedProjects: [Project] {
        filteredProjects.filter { $0.status == .archived }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingFilters && hasActiveFilters {
                activeFilterBadges
                    .padding(.top, 8)
            }

            if allProjects.isEmpty {
                JobBoardEmptyState(
                    icon: "folder.fill",
                    title: "No Projects Yet",
                    subtitle: "Create your first project to get started"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(activeProjects) { project in
                            UniversalJobBoardCard(cardType: .project(project))
                                .environmentObject(dataController)
                                .id("\(project.id)-\(project.teamMemberIdsString)")
                        }

                        if !closedProjects.isEmpty {
                            CollapsibleSection(
                                title: "CLOSED",
                                count: closedProjects.count,
                                isExpanded: $isClosedExpanded
                            ) {
                                ForEach(closedProjects) { project in
                                    UniversalJobBoardCard(cardType: .project(project))
                                        .environmentObject(dataController)
                                        .id("\(project.id)-\(project.teamMemberIdsString)")
                                }
                            }
                        }

                        if !archivedProjects.isEmpty {
                            CollapsibleSection(
                                title: "ARCHIVED",
                                count: archivedProjects.count,
                                isExpanded: $isArchivedExpanded
                            ) {
                                ForEach(archivedProjects) { project in
                                    UniversalJobBoardCard(cardType: .project(project))
                                        .environmentObject(dataController)
                                        .id("\(project.id)-\(project.teamMemberIdsString)")
                                }
                            }
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            ProjectListFilterSheet(
                selectedStatuses: $selectedStatuses,
                selectedTeamMemberIds: $selectedTeamMemberIds,
                sortOption: $sortOption,
                availableTeamMembers: availableTeamMembers
            )
            .environmentObject(dataController)
            .onDisappear {
                updateFilterVisibility()
            }
        }
        .onChange(of: selectedStatuses) { _, _ in
            updateFilterVisibility()
        }
        .onChange(of: selectedTeamMemberIds) { _, _ in
            updateFilterVisibility()
        }
    }


    private var activeFilterBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedStatuses), id: \.self) { status in
                    FilterBadge(
                        text: status.displayName,
                        color: status.color,
                        onRemove: {
                            selectedStatuses.remove(status)
                        }
                    )
                }

                ForEach(Array(selectedTeamMemberIds), id: \.self) { memberId in
                    if let member = availableTeamMembers.first(where: { $0.id == memberId }) {
                        FilterBadge(
                            text: "\(member.firstName) \(member.lastName)",
                            color: OPSStyle.Colors.primaryAccent,
                            onRemove: {
                                selectedTeamMemberIds.remove(memberId)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var hasActiveFilters: Bool {
        !selectedStatuses.isEmpty || !selectedTeamMemberIds.isEmpty
    }

    private func updateFilterVisibility() {
        if hasActiveFilters {
            showingFilters = true
        } else {
            showingFilters = false
        }
    }
}

struct FilterBadge: View {
    let text: String
    let color: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(text.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Project Filter Bar
struct ProjectFilterBar: View {
    @Binding var selectedStatus: Status?

    private let statuses: [Status?] = [
        nil,
        .rfq,
        .estimated,
        .accepted,
        .inProgress,
        .completed,
        .closed
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(statuses, id: \.self) { status in
                    JBFilterChip(
                        title: status?.displayName ?? "All",
                        isSelected: selectedStatus == status,
                        color: status?.color ?? OPSStyle.Colors.primaryAccent
                    ) {
                        withAnimation {
                            selectedStatus = status
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Filter Chip
struct JBFilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isSelected {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }

                Text(title.uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(isSelected ? OPSStyle.Colors.cardBackgroundDark : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(
                                isSelected ? OPSStyle.Colors.cardBorder : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
        }
    }
}

// MARK: - Collapsible Section
struct CollapsibleSection<Content: View>: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("[ \(title) ]")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Rectangle()
                    .fill(OPSStyle.Colors.secondaryText.opacity(0.3))
                    .frame(height: 1)

                Text("[ \(count) ]")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Image(systemName: isExpanded ? OPSStyle.Icons.chevronUp : OPSStyle.Icons.chevronDown)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                VStack(spacing: 12) {
                    content()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
