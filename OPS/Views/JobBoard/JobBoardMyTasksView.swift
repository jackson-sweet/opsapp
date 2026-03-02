//
//  JobBoardMyTasksView.swift
//  OPS
//
//  Personal task list for field crew — shows tasks assigned to the current user,
//  grouped by project, with filter chips.
//

import SwiftUI
import SwiftData

// MARK: - Filter

enum MyTasksFilter: String, CaseIterable {
    case all       = "ALL"
    case today     = "TODAY"
    case upcoming  = "UPCOMING"
    case completed = "COMPLETED"
}

// MARK: - Main View

struct JobBoardMyTasksView: View {
    @EnvironmentObject private var dataController: DataController
    @Query private var allProjects: [Project]
    @State private var activeFilter: MyTasksFilter = .all
    @State private var isLoading: Bool = false
    @State private var loadError: Bool = false

    // Projects where the current user is a team member
    private var assignedProjects: [Project] {
        guard let userId = dataController.currentUser?.id else { return [] }
        return allProjects.filter { project in
            project.getTeamMemberIds().contains(userId)
        }
    }

    // All tasks from assigned projects that are assigned to the current user
    // Falls back to all project tasks when a task has no explicit assignment
    private var myTasks: [ProjectTask] {
        guard let userId = dataController.currentUser?.id else { return [] }
        return assignedProjects.flatMap { project in
            project.tasks.filter { task in
                let taskMemberIds = task.getTeamMemberIds()
                return taskMemberIds.isEmpty || taskMemberIds.contains(userId)
            }
        }
    }

    // Tasks after applying the active filter
    private var filteredTasks: [ProjectTask] {
        switch activeFilter {
        case .all:
            return myTasks.filter { $0.status == .active }
        case .today:
            return myTasks.filter { $0.status == .active && $0.isToday }
        case .upcoming:
            let today = Calendar.current.startOfDay(for: Date())
            return myTasks.filter { task in
                guard task.status == .active, let start = task.startDate else { return false }
                return Calendar.current.startOfDay(for: start) > today
            }
        case .completed:
            return myTasks.filter { $0.status == .completed }
        }
    }

    // Tasks grouped by project, sorted by project title
    private var groupedTasks: [(project: Project, tasks: [ProjectTask])] {
        var map: [String: (project: Project, tasks: [ProjectTask])] = [:]
        for task in filteredTasks {
            guard let project = task.project else { continue }
            if map[project.id] == nil {
                map[project.id] = (project: project, tasks: [])
            }
            map[project.id]!.tasks.append(task)
        }
        return map.values
            .map { group in
                let sorted = group.tasks.sorted { a, b in
                    switch (a.startDate, b.startDate) {
                    case let (aDate?, bDate?): return aDate < bDate
                    case (nil, _?):            return false
                    case (_?, nil):            return true
                    case (nil, nil):           return a.displayTitle < b.displayTitle
                    }
                }
                return (project: group.project, tasks: sorted)
            }
            .sorted { $0.project.title < $1.project.title }
    }

    // Empty-state message for the current filter
    private var emptyMessage: String {
        activeFilter == .all
            ? "No tasks assigned to you"
            : "No \(activeFilter.rawValue) tasks"
    }

    var body: some View {
        VStack(spacing: 0) {
            filterChips
            if isLoading {
                skeletonRows
            } else if loadError {
                errorState
            } else {
                taskList
            }
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MyTasksFilter.allCases, id: \.self) { filter in
                    TaskFilterChip(
                        label: filter.rawValue,
                        isActive: activeFilter == filter
                    ) {
                        withAnimation(.accessibleEaseInOut(duration: 0.2)) {
                            activeFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Task List

    @ViewBuilder
    private var taskList: some View {
        if groupedTasks.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(groupedTasks, id: \.project.id) { group in
                        ProjectTaskGroup(project: group.project, tasks: group.tasks)
                    }
                }
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text(emptyMessage)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Loading State

    private var skeletonRows: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Simulate 2 project groups with 3 skeleton rows each
                ForEach(0..<2, id: \.self) { _ in
                    // Group header placeholder
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .frame(height: 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    // Row placeholders
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(OPSStyle.Colors.cardBackgroundDark)
                            .frame(height: 60)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(.bottom, 100)
        }
    }

    // MARK: - Error State

    private var errorState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Couldn't load tasks")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Button("Retry") {
                retryLoad()
            }
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .frame(minWidth: 44, minHeight: 44)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func retryLoad() {
        loadError = false
        isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLoading = false
        }
    }
}

// MARK: - Filter Chip

private struct TaskFilterChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(isActive ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(isActive ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBackgroundDark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(isActive ? Color.clear : OPSStyle.Colors.cardBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Project Task Group

struct ProjectTaskGroup: View {
    let project: Project
    let tasks: [ProjectTask]
    @State private var isExpanded: Bool = true
    @EnvironmentObject private var dataController: DataController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader
            if isExpanded {
                taskCards
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Group Header

    private var groupHeader: some View {
        Button {
            withAnimation(.accessibleEaseInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text("[ \(project.title.uppercased()) ]")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Task Cards

    private var taskCards: some View {
        VStack(spacing: 0) {
            ForEach(tasks) { task in
                UniversalJobBoardCard(cardType: .task(task))
            }
        }
    }
}
