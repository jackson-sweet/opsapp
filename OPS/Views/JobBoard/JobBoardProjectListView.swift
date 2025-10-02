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
        case .createdDateDescending:
            return filtered.sorted(by: { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) })
        case .createdDateAscending:
            return filtered.sorted(by: { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) })
        case .scheduledDateDescending:
            return filtered.sorted(by: { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) })
        case .scheduledDateAscending:
            return filtered.sorted(by: { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) })
        case .statusAscending:
            return filtered.sorted(by: { $0.status.sortOrder < $1.status.sortOrder })
        case .statusDescending:
            return filtered.sorted(by: { $0.status.sortOrder > $1.status.sortOrder })
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
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

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
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(activeProjects) { project in
                                UniversalJobBoardCard(cardType: .project(project))

                                    .environmentObject(dataController)
                                    .id("\(project.id)-\(project.teamMemberIdsString)-\(project.tasks.count)")
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
                                            .id("\(project.id)-\(project.teamMemberIdsString)-\(project.tasks.count)")
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
                                            .id("\(project.id)-\(project.teamMemberIdsString)-\(project.tasks.count)")
                                    }
                                }
                            }
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 120)
                    }
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
                                isSelected ? Color.white.opacity(0.1) : Color.clear,
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
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
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
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                VStack(spacing: 12) {
                    content()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Project Management Row
struct ProjectManagementRow: View {
    let project: Project
    @State private var showingActions = false
    @State private var showingEdit = false
    @State private var showingStatusChange = false
    @State private var showingTeamChange = false
    @State private var showingSchedulingConversion = false
    @State private var showingDelete = false
    @State private var showingProjectDetails = false
    @EnvironmentObject private var dataController: DataController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                if project.usesTaskBasedScheduling {
                    let taskCount = project.tasks.count
                    Text(taskCount == 1 ? "1 TASK" : "\(taskCount) TASKS")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(OPSStyle.Colors.secondaryAccent.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(OPSStyle.Colors.secondaryAccent.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    Text("PROJECT")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(project.status.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(OPSStyle.Colors.primaryAccent.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                        )
                }

                Spacer()

                Text(project.status.displayName.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(project.status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(project.status.color.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(project.status.color, lineWidth: 1)
                    )
            }

            Text(project.title.uppercased())
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)

            Text(project.effectiveClientName)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack(spacing: 12) {
                if let startDate = project.startDate {
                    Label(
                        DateHelper.fullDateString(from: startDate),
                        systemImage: "calendar"
                    )
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                if !project.teamMembers.isEmpty {
                    Label(
                        "\(project.teamMembers.count)",
                        systemImage: "person.2"
                    )
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                if !project.tasks.isEmpty {
                    Label(
                        "\(project.tasks.count)",
                        systemImage: "checklist"
                    )
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                Menu {
                Button(action: { showingEdit = true }) {
                    Label("Edit", systemImage: "pencil")
                }

                Button(action: { showingStatusChange = true }) {
                    Label("Change Status", systemImage: "arrow.triangle.2.circlepath")
                }

                Button(action: { showingTeamChange = true }) {
                    Label("Change Team", systemImage: "person.2")
                }

                Button(action: { showingSchedulingConversion = true }) {
                    Label("Convert Scheduling", systemImage: "calendar.badge.clock")
                }

                Divider()

                Button(role: .destructive, action: { showingDelete = true }) {
                    Label("Delete", systemImage: "trash")
                }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing3)
        .contentShape(Rectangle())
        .onTapGesture {
            showingProjectDetails = true
        }
        .sheet(isPresented: $showingProjectDetails) {
            NavigationView {
                ProjectDetailsView(project: project)
            }
        }
        .sheet(isPresented: $showingEdit) {
            ProjectFormSheet(mode: .edit(project)) { _ in
                // Refresh will happen through SwiftData
            }
        }
        .sheet(isPresented: $showingStatusChange) {
            ProjectStatusChangeSheet(project: project)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingTeamChange) {
            ProjectTeamChangeSheet(project: project)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingSchedulingConversion) {
            SchedulingModeConversionSheet(project: project)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingDelete) {
            ProjectDeletionConfirmation(project: project)
                .environmentObject(dataController)
        }
    }
}

