//
//  DetailsTabView.swift
//  OPS
//
//  Project metadata organized in card sections — the Details tab.
//  Sections: Client, Team, Tasks, Schedule, Description, Address, Delete.
//

import SwiftUI

struct DetailsTabView: View {
    @Bindable var project: Project
    @ObservedObject var viewModel: ProjectDetailsViewModel
    let onClientTap: () -> Void
    let onTeamMemberTap: (User) -> Void
    let onTaskTap: (ProjectTask) -> Void
    let onAddTask: () -> Void
    let onEditAddress: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // DATE HEADER — subtle inline row above client
            if project.computedStartDate != nil || project.computedEndDate != nil {
                HStack {
                    if let start = project.computedStartDate {
                        Text(DateHelper.simpleDateString(from: start))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    Spacer()
                    if let end = project.computedEndDate {
                        Text(DateHelper.simpleDateString(from: end))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .padding(.horizontal, 16)
            }

            // CLIENT
            ClientSection(
                project: project,
                onTap: onClientTap,
                onCall: { if let p = project.effectiveClientPhone { viewModel.callPhone(p) } },
                onEmail: { if let e = project.effectiveClientEmail { viewModel.sendEmail(e) } }
            )

            // ADDRESS (below client)
            AddressSection(
                address: project.address,
                canEdit: viewModel.canEditProject,
                onEdit: onEditAddress,
                onDirections: { viewModel.openDirections() }
            )

            // TASKS
            TaskListSection(
                tasks: project.tasks.sorted { $0.displayOrder < $1.displayOrder },
                selectedTask: viewModel.selectedTask,
                project: project,
                canEdit: viewModel.canEditProject,
                onTaskTap: onTaskTap,
                onAddTask: onAddTask
            )

            // DESCRIPTION
            DescriptionSection(
                project: project,
                canEdit: viewModel.canEditProject,
                isEditing: $viewModel.isEditingProjectDetails,
                editText: $viewModel.editingProjectDetailsText,
                onSave: { viewModel.saveDescription() }
            )

            // TEAM (at bottom)
            TeamSection(
                teamMembers: project.teamMembers,
                canEdit: viewModel.canEditProject,
                onMemberTap: onTeamMemberTap
            )

            // DELETE PROJECT (admin only)
            if viewModel.canEditProject {
                Button(action: {
                    viewModel.showingDeleteAlert = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: OPSStyle.Icons.delete)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        Text("DELETE PROJECT")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.errorStatus, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
            }

            Spacer()
                .frame(height: 200)
        }
        .padding(.top, 16)
    }
}

// MARK: - Client Section

struct ClientSection: View {
    let project: Project
    let onTap: () -> Void
    let onCall: () -> Void
    let onEmail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section label
            sectionLabel("CLIENT")

            // Client card
            Button(action: onTap) {
                HStack(spacing: 12) {
                    if let client = project.client {
                        UserAvatar(client: client, size: 36)
                    } else {
                        Circle()
                            .fill(OPSStyle.Colors.cardBackgroundDark)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "building.2")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.effectiveClientName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        if project.client != nil {
                            Text("Client")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }

                    Spacer()

                    // Contact action icons — always visible, dim when unavailable
                    HStack(spacing: 16) {
                        let hasPhone = project.effectiveClientPhone != nil && !project.effectiveClientPhone!.isEmpty
                        let hasEmail = project.effectiveClientEmail != nil && !project.effectiveClientEmail!.isEmpty

                        Button(action: onCall) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: OPSStyle.Layout.IconSize.md))
                                .foregroundColor(hasPhone ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText.opacity(0.3))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(!hasPhone)

                        Button(action: onEmail) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: OPSStyle.Layout.IconSize.md))
                                .foregroundColor(hasEmail ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText.opacity(0.3))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(!hasEmail)
                    }

                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(14)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Team Section

struct TeamSection: View {
    let teamMembers: [User]
    let canEdit: Bool
    let onMemberTap: (User) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TEAM")

            VStack(spacing: 0) {
                if teamMembers.isEmpty {
                    HStack {
                        Text("No team members assigned")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer()
                    }
                    .padding(14)
                } else {
                    // Horizontal avatar row
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(teamMembers, id: \.id) { member in
                                Button(action: { onMemberTap(member) }) {
                                    VStack(spacing: 4) {
                                        UserAvatar(user: member, size: 36)
                                        Text(member.firstName ?? "")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(14)
                    }
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Task List Section

struct TaskListSection: View {
    let tasks: [ProjectTask]
    let selectedTask: ProjectTask?
    let project: Project
    let canEdit: Bool
    let onTaskTap: (ProjectTask) -> Void
    let onAddTask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TASKS")

            VStack(spacing: 0) {
                ForEach(tasks, id: \.id) { task in
                    let isSelected = selectedTask?.id == task.id
                    let hasSelection = selectedTask != nil
                    let taskColor = Color(hex: task.taskColor) ?? OPSStyle.Colors.primaryAccent
                    let isComplete = task.status == .completed

                    Button(action: { onTaskTap(task) }) {
                        HStack(spacing: 8) {
                            // Left cluster: task type badge + status badge (always adjacent)
                            TaskBadge(
                                name: task.taskType?.display ?? "Task",
                                color: taskColor,
                                size: .medium,
                                faded: isComplete
                            )

                            if isComplete {
                                StatusBadgePill(
                                    text: "COMPLETE",
                                    color: TaskStatus.completed.color,
                                    size: .medium
                                )
                            } else if isSelected {
                                StatusBadgePill(
                                    text: "ACTIVE",
                                    color: OPSStyle.Colors.primaryAccent,
                                    size: .medium
                                )
                            }

                            Spacer()

                            // Right side: SELECTED badge OR chevron — never both
                            if isSelected {
                                StatusBadgePill(
                                    text: "SELECTED",
                                    color: OPSStyle.Colors.tertiaryText,
                                    size: .small
                                )
                            } else {
                                Image(systemName: OPSStyle.Icons.chevronRight)
                                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .background(isSelected ? OPSStyle.Colors.cardBackgroundDark.opacity(0.5) : Color.clear)
                        .opacity(isSelected || !hasSelection ? 1.0 : 0.45)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Divider
                    if task.id != tasks.last?.id {
                        Rectangle()
                            .fill(OPSStyle.Colors.cardBorderSubtle)
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }

                // Add task row (admin only)
                if canEdit {
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorderSubtle)
                        .frame(height: 1)
                        .padding(.leading, 16)

                    Button(action: onAddTask) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            Text("ADD TASK")
                                .font(OPSStyle.Typography.captionBold)
                            Spacer()
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Description Section

struct DescriptionSection: View {
    @Bindable var project: Project
    let canEdit: Bool
    @Binding var isEditing: Bool
    @Binding var editText: String
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("DESCRIPTION")

            VStack(alignment: .leading, spacing: 8) {
                if isEditing {
                    TextEditor(text: $editText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 80)
                        .padding(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )

                    HStack {
                        Button("Cancel") {
                            isEditing = false
                            editText = ""
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                        Spacer()

                        Button("Save") {
                            onSave()
                        }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                } else if let description = project.projectDescription, !description.isEmpty {
                    HStack(alignment: .top) {
                        Text(description)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()

                        if canEdit {
                            Button(action: {
                                editText = description
                                isEditing = true
                            }) {
                                Image(systemName: OPSStyle.Icons.pencil)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                } else if canEdit {
                    Button(action: {
                        editText = ""
                        isEditing = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            Text("ADD DESCRIPTION")
                                .font(OPSStyle.Typography.captionBold)
                            Spacer()
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Text("No description")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(14)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Address Section

struct AddressSection: View {
    let address: String?
    let canEdit: Bool
    let onEdit: () -> Void
    let onDirections: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ADDRESS")

            HStack {
                if let address = address, !address.isEmpty {
                    Button(action: onDirections) {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.circle")
                                .font(.system(size: OPSStyle.Layout.IconSize.md))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Text(address)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Text("No address set")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                if canEdit {
                    Button(action: onEdit) {
                        Image(systemName: OPSStyle.Icons.pencil)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(14)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Photos Section

struct PhotosSection: View {
    let project: Project
    let onPhotoTap: (Int) -> Void
    let onAddPhoto: () -> Void

    var body: some View {
        let photos = project.getProjectImages()

        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PHOTOS")

            VStack(spacing: 0) {
                if photos.isEmpty {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("No photos yet")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer()
                    }
                    .padding(14)
                } else {
                    // Horizontal scroll of photo thumbnails
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                                Button(action: { onPhotoTap(index) }) {
                                    PhotoThumbnail(url: url, project: project)
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(14)
                    }

                    // Photo count
                    Text("\(photos.count) PHOTO\(photos.count == 1 ? "" : "S")")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Section Label Helper

/// Reusable section label: `[ LABEL ]` — Kosugi 12pt caps, tertiaryText
/// Section headers appear OUTSIDE cards per design system
func sectionLabel(_ title: String) -> some View {
    Text("[ \(title) ]")
        .font(.custom("Kosugi-Regular", size: 12))
        .textCase(.uppercase)
        .tracking(1)
        .foregroundColor(OPSStyle.Colors.tertiaryText)
        .padding(.horizontal, 16)
}
