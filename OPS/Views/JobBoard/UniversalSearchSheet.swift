//
//  UniversalSearchSheet.swift
//  OPS
//
//  Universal search across projects and tasks, role-filtered.
//  Opened from the Job Board header search button.
//

import SwiftUI
import SwiftData

struct UniversalSearchSheet: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss
    @Query private var allProjects: [Project]
    @FocusState private var searchFocused: Bool
    @State private var query: String = ""

    // Permission-based pipeline access
    private var hasPipelineAccess: Bool {
        permissionStore.can("pipeline.view")
    }

    // Permission-based restricted access (field crew equivalent)
    private var isFieldCrew: Bool {
        !permissionStore.hasFullAccess("projects.view")
    }

    // Field crew see only projects they are assigned to.
    // Users without pipeline access cannot see RFQ or Estimated projects.
    private var availableProjects: [Project] {
        guard let userId = dataController.currentUser?.id else { return [] }
        var projects: [Project]
        if isFieldCrew {
            projects = allProjects.filter { $0.getTeamMemberIds().contains(userId) }
        } else {
            projects = Array(allProjects)
        }
        if !hasPipelineAccess {
            projects = projects.filter { $0.status != .rfq && $0.status != .estimated }
        }
        return projects
    }

    // Flatten tasks from all visible projects
    private var availableTasks: [ProjectTask] {
        availableProjects.flatMap { $0.tasks }
    }

    // ProjectTask.displayTitle is the computed title (customTitle or taskType.display)
    // ProjectTask.taskNotes is the optional notes string
    private var matchingProjects: [Project] {
        guard !query.isEmpty else { return [] }
        return availableProjects.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.effectiveClientName.localizedCaseInsensitiveContains(query) ||
            ($0.address?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var matchingTasks: [ProjectTask] {
        guard !query.isEmpty else { return [] }
        return availableTasks.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query) ||
            ($0.taskNotes?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var hasResults: Bool {
        !matchingProjects.isEmpty || !matchingTasks.isEmpty
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Search header bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    TextField("Search projects, tasks...", text: $query)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .autocorrectionDisabled()
                        .focused($searchFocused)

                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }

                    Button("CANCEL") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .overlay(
                    Rectangle()
                        .fill(OPSStyle.Colors.separator)
                        .frame(height: 1),
                    alignment: .bottom
                )

                // Body
                if query.isEmpty {
                    emptyQueryState
                } else if !hasResults {
                    noResultsState
                } else {
                    resultsView
                }
            }
        }
        .onAppear { searchFocused = true }
    }

    // MARK: - Results

    private var resultsView: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {

                if !matchingProjects.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            ForEach(matchingProjects) { project in
                                UniversalJobBoardCard(cardType: .project(project))
                                    .environmentObject(dataController)
                                    .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 12)
                    } header: {
                        sectionHeader("[ PROJECTS ]")
                    }
                }

                if !matchingTasks.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            ForEach(matchingTasks) { task in
                                UniversalJobBoardCard(cardType: .task(task))
                                    .environmentObject(dataController)
                                    .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 12)
                    } header: {
                        sectionHeader("[ TASKS ]")
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .animation(.accessibleEaseInOut(duration: 0.15), value: query)
    }

    private func sectionHeader(_ label: String) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(OPSStyle.Colors.background)
    }

    // MARK: - Empty States

    private var emptyQueryState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl, weight: .light))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("Search projects, tasks, and more")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Text("No results for \"\(query)\"")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
}
