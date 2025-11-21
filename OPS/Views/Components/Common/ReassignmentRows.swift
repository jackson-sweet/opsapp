//
//  ReassignmentRows.swift
//  OPS
//
//  Supporting components for DeletionSheet reassignment UI
//

import SwiftUI

// MARK: - Project Reassignment Row

struct ProjectReassignmentRow: View {
    let project: Project
    @Binding var selectedClientId: String?
    let markedForDeletion: Bool
    let availableClients: [Client]
    let onToggleDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(project.status.color)
                    .frame(width: 8, height: 8)

                Text(project.title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(markedForDeletion ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)

                if markedForDeletion {
                    Spacer()
                    Text("Will be deleted")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .italic()
                }
            }

            if markedForDeletion {
                Button(action: onToggleDelete) {
                    HStack {
                        Image(systemName: OPSStyle.Icons.close)
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.errorStatus)

                        Text("Don't Delete Project")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.errorStatus)

                        Spacer()
                    }
                    .padding(12)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
                }
            } else {
                HStack(spacing: 8) {
                    SearchField(
                        selectedId: $selectedClientId,
                        items: availableClients,
                        placeholder: "Search for client",
                        leadingIcon: OPSStyle.Icons.client,
                        getId: { $0.id },
                        getDisplayText: { $0.name },
                        getSubtitle: { client in
                            client.projects.count > 0
                                ? "\(client.projects.count) project\(client.projects.count == 1 ? "" : "s")"
                                : nil
                        }
                    )

                    Button(action: onToggleDelete) {
                        Image(systemName: OPSStyle.Icons.delete)
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .frame(width: 44, height: 44)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
}

// MARK: - Task Reassignment Row

struct TaskReassignmentRow: View {
    let task: ProjectTask
    @Binding var selectedTaskTypeId: String?
    let markedForDeletion: Bool
    let availableTaskTypes: [TaskType]
    let onToggleDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(task.status.color)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.displayTitle)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(markedForDeletion ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)

                    HStack(spacing: 4) {
                        if let projectTitle = task.project?.title {
                            Text(projectTitle)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }

                        if let clientName = task.project?.client?.name {
                            if task.project?.title != nil {
                                Text("•")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            Text(clientName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                }

                if markedForDeletion {
                    Spacer()
                    Text("Will be deleted")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .italic()
                }
            }

            if markedForDeletion {
                Button(action: onToggleDelete) {
                    HStack {
                        Image(systemName: OPSStyle.Icons.close)
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.errorStatus)

                        Text("Don't Delete Task")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.errorStatus)

                        Spacer()
                    }
                    .padding(12)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
                }
            } else {
                HStack(spacing: 8) {
                    SearchField(
                        selectedId: $selectedTaskTypeId,
                        items: availableTaskTypes,
                        placeholder: "Search for task type",
                        leadingIcon: "square.grid.2x2.fill",
                        getId: { $0.id },
                        getDisplayText: { $0.display },
                        getSubtitle: { taskType in
                            taskType.tasks.count > 0
                                ? "\(taskType.tasks.count) task\(taskType.tasks.count == 1 ? "" : "s")"
                                : nil
                        },
                        getLeadingAccessory: { taskType in
                            AnyView(
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                                        .frame(width: 8, height: 8)

                                    if let icon = taskType.icon {
                                        Image(systemName: icon)
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                                    }
                                }
                            )
                        }
                    )

                    Button(action: onToggleDelete) {
                        Image(systemName: OPSStyle.Icons.delete)
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .frame(width: 44, height: 44)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
}