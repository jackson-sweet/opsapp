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
    @State private var sortOption: ProjectSortOption = .scheduledDateDescending
    @State private var showingCreateProject = false
    @State private var showingClosedSheet = false
    @State private var showingArchivedSheet = false

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
        case .scheduledDateDescending:
            return filtered.sorted { p1, p2 in
                let p1Unscheduled = (p1.startDate == nil || p1.endDate == nil) && p1.status != .closed && p1.status != .archived
                let p2Unscheduled = (p2.startDate == nil || p2.endDate == nil) && p2.status != .closed && p2.status != .archived
                let p1Unassigned = p1.teamMembers.isEmpty && p1.status != .closed && p1.status != .archived
                let p2Unassigned = p2.teamMembers.isEmpty && p2.status != .closed && p2.status != .archived

                if p1Unscheduled != p2Unscheduled { return p1Unscheduled }
                if p1Unassigned != p2Unassigned { return p1Unassigned }
                return (p1.startDate ?? Date.distantPast) > (p2.startDate ?? Date.distantPast)
            }
        case .scheduledDateAscending:
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
                    .padding(.bottom, 8)
            }

            if allProjects.isEmpty {
                JobBoardEmptyState(
                    icon: OPSStyle.Icons.project,
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

                        // Closed and Archived section buttons
                        if !closedProjects.isEmpty || !archivedProjects.isEmpty {
                            HStack(spacing: 12) {
                                if !closedProjects.isEmpty {
                                    SectionButton(
                                        title: "CLOSED",
                                        count: closedProjects.count,
                                        color: Status.closed.color
                                    ) {
                                        showingClosedSheet = true
                                    }
                                }

                                if !archivedProjects.isEmpty {
                                    SectionButton(
                                        title: "ARCHIVED",
                                        count: archivedProjects.count,
                                        color: Status.archived.color
                                    ) {
                                        showingArchivedSheet = true
                                    }
                                }
                            }
                            .padding(.top, 8)
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
        .sheet(isPresented: $showingClosedSheet) {
            ProjectListSheet(
                title: "Closed Projects",
                projects: closedProjects,
                dataController: dataController
            )
        }
        .sheet(isPresented: $showingArchivedSheet) {
            ProjectListSheet(
                title: "Archived Projects",
                projects: archivedProjects,
                dataController: dataController
            )
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

// MARK: - Section Button
/// Button that opens a sheet containing items (used for Closed/Archived sections)
struct SectionButton: View {
    let title: String
    let count: Int
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text("(\(count))")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Project List Sheet
/// Sheet displaying a list of projects (used for Closed/Archived)
struct ProjectListSheet: View {
    let title: String
    let projects: [Project]
    let dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filteredProjects: [Project] {
        if searchText.isEmpty {
            return projects
        }
        return projects.filter { project in
            project.title.localizedCaseInsensitiveContains(searchText) ||
            project.effectiveClientName.localizedCaseInsensitiveContains(searchText) ||
            (project.projectDescription?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (project.address?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 12) {
                        Image(systemName: OPSStyle.Icons.search)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .font(.system(size: 16))

                        TextField("Search projects...", text: $searchText)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .autocorrectionDisabled()

                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    if filteredProjects.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "folder")
                                .font(.system(size: 48))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(searchText.isEmpty ? "No projects" : "No matching projects")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredProjects) { project in
                                    UniversalJobBoardCard(cardType: .project(project), disableSwipe: true)
                                        .environmentObject(dataController)
                                        .id("\(project.id)-\(project.teamMemberIdsString)")
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("DONE") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }
}
