//
//  TaskListFilterSheet.swift
//  OPS
//
//  Job Board comprehensive filter sheet for tasks
//

import SwiftUI

enum TaskSortOption: String, CaseIterable {
    case createdDateDescending = "Created Date (Newest First)"
    case createdDateAscending = "Created Date (Oldest First)"
    case scheduledDateDescending = "Scheduled Date (Latest First)"
    case scheduledDateAscending = "Scheduled Date (Earliest First)"
    case statusAscending = "Status (Scheduled to Completed)"
    case statusDescending = "Status (Completed to Scheduled)"
}

struct TaskListFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @Binding var selectedStatuses: Set<TaskStatus>
    @Binding var selectedTaskTypeIds: Set<String>
    @Binding var selectedTeamMemberIds: Set<String>
    @Binding var sortOption: TaskSortOption

    let availableTaskTypes: [TaskType]
    let availableTeamMembers: [User]

    private let availableStatuses: [TaskStatus] = [.scheduled, .inProgress, .completed, .cancelled]

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        filterSection(
                            title: "TASK STATUS",
                            icon: "flag.fill"
                        ) {
                            statusContent
                        }

                        if !availableTaskTypes.isEmpty {
                            filterSection(
                                title: "TASK TYPE",
                                icon: "checkmark.circle.fill"
                            ) {
                                taskTypeContent
                            }
                        }

                        if !availableTeamMembers.isEmpty {
                            filterSection(
                                title: "ASSIGNED TEAM MEMBERS",
                                icon: "person.2.fill"
                            ) {
                                teamMemberContent
                            }
                        }

                        filterSection(
                            title: "SORT BY",
                            icon: "arrow.up.arrow.down"
                        ) {
                            sortContent
                        }

                        if hasActiveFilters {
                            activeFiltersSummary
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("FILTER TASKS")
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
                    Text("FILTER TASKS")
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

    private var statusContent: some View {
        VStack(spacing: 0) {
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

            ForEach(availableStatuses, id: \.self) { status in
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(statusColor(for: status))
                        .frame(width: 2, height: 12)

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
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleSelection(status, in: &selectedStatuses)
                }

                if status != availableStatuses.last {
                    Divider()
                        .background(Color.white.opacity(0.05))
                        .padding(.leading, 20)
                }
            }
        }
    }

    private var taskTypeContent: some View {
        VStack(spacing: 0) {
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

            ForEach(availableTaskTypes, id: \.id) { taskType in
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                        .frame(width: 2, height: 12)

                    if let icon = taskType.icon {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                            .frame(width: 24)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(taskType.display)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }

                    Spacer()

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
                        .padding(.leading, 20)
                }
            }
        }
    }

    private var teamMemberContent: some View {
        VStack(spacing: 0) {
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

            ForEach(availableTeamMembers, id: \.id) { member in
                filterRow(
                    title: "\(member.firstName) \(member.lastName)",
                    subtitle: member.role.rawValue,
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

    private var sortContent: some View {
        VStack(spacing: 0) {
            ForEach(TaskSortOption.allCases, id: \.self) { option in
                HStack {
                    Text(option.rawValue)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    if sortOption == option {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .onTapGesture {
                    sortOption = option
                }

                if option != TaskSortOption.allCases.last {
                    Divider()
                        .background(Color.white.opacity(0.05))
                        .padding(.leading, 40)
                }
            }
        }
    }

    private func filterSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text(title)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, 20)

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

                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Text(sortOption.rawValue)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

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

    private var hasActiveFilters: Bool {
        !selectedStatuses.isEmpty || !selectedTaskTypeIds.isEmpty || !selectedTeamMemberIds.isEmpty
    }

    private func statusColor(for status: TaskStatus) -> Color {
        return status.color
    }

    private func toggleSelection<T: Hashable>(_ item: T, in set: inout Set<T>) {
        if set.contains(item) {
            set.remove(item)
        } else {
            set.insert(item)
        }
    }

    private func resetFilters() {
        selectedStatuses.removeAll()
        selectedTaskTypeIds.removeAll()
        selectedTeamMemberIds.removeAll()
        sortOption = .createdDateDescending
    }
}
