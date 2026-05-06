//
//  DetailsTabView.swift
//  OPS
//
//  Project metadata organized in card sections — the Details tab.
//  Sections: Client, Team, Tasks, Schedule, Description, Address, Delete.
//

import SwiftUI
import SwiftData
import MapKit

struct DetailsTabView: View {
    @Bindable var project: Project
    @ObservedObject var viewModel: ProjectDetailsViewModel
    let onClientTap: () -> Void
    let onTeamMemberTap: (User) -> Void
    let onTaskTap: (ProjectTask) -> Void
    let onAddTask: () -> Void
    var onSelectTask: ((ProjectTask) -> Void)? = nil
    var onCompleteTask: ((ProjectTask) -> Void)? = nil
    var onReopenTask: ((ProjectTask) -> Void)? = nil
    var onCancelTask: ((ProjectTask) -> Void)? = nil
    var onDeleteTask: ((ProjectTask) -> Void)? = nil
    var onClientLongPress: (() -> Void)? = nil

    /// All Users in the store. Used to resolve team member avatars from the
    /// authoritative `teamMemberIdsString` CSV on both Project and ProjectTask.
    /// We render from this lookup rather than the `teamMembers: [User]`
    /// SwiftData relationship because that relationship can be empty even
    /// when the id-string has values (hydration lag: user-objects may sync
    /// in a separate batch, or `linkAllRelationships` may not have run yet
    /// for a freshly-inserted local row).
    @Query private var allUsers: [User]

    private var userById: [String: User] {
        Dictionary(allUsers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Resolve the project's team members from the canonical id string.
    /// Falls back to the relationship only if the id string is empty — that's
    /// the legitimate "no one assigned" case.
    private var resolvedProjectTeam: [User] {
        let ids = project.getTeamMemberIds()
        guard !ids.isEmpty else { return [] }
        return ids.compactMap { userById[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // PROJECT TIMELINE — dates + task progress
            if project.hasTasks {
                ProjectTimelineSection(project: project)
            }

            // CLIENT
            ClientSection(
                project: project,
                canEdit: viewModel.canEditProject,
                onContactTap: onClientTap,
                onCall: { if let p = project.effectiveClientPhone { viewModel.callPhone(p) } },
                onEmail: { if let e = project.effectiveClientEmail { viewModel.sendEmail(e) } },
                onAssignClient: onClientLongPress
            )

            // ADDRESS (below client)
            AddressSection(
                address: project.address,
                canEdit: viewModel.canEditProject,
                onEdit: {},
                onDirections: { viewModel.openDirections() },
                onSaveAddress: { newAddress in
                    viewModel.editedAddress = newAddress
                    viewModel.saveAddress()
                }
            )

            // TASKS
            TaskListSection(
                tasks: project.tasks.sorted { $0.displayOrder < $1.displayOrder },
                selectedTask: viewModel.selectedTask,
                project: project,
                canEdit: viewModel.canEditProject,
                userById: userById,
                onTaskTap: onTaskTap,
                onAddTask: onAddTask,
                onSelectTask: onSelectTask,
                onCompleteTask: onCompleteTask,
                onReopenTask: onReopenTask,
                onCancelTask: onCancelTask,
                onDeleteTask: onDeleteTask
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
                teamMembers: resolvedProjectTeam,
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
        .onAppear {
            NotificationCenter.default.post(name: Notification.Name("WizardDetailsTabViewed"), object: nil)
        }
    }
}

// MARK: - Project Timeline Section

private struct ProjectTimelineSection: View {
    let project: Project

    private var activeTasks: [ProjectTask] {
        project.tasks.filter { $0.status != .cancelled }
    }

    private var completedCount: Int {
        activeTasks.filter { $0.status == .completed }.count
    }

    private var totalCount: Int {
        activeTasks.count
    }

    private var progress: Double {
        totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Date labels
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PROJECT START")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    if let start = project.computedStartDate {
                        Text(DateHelper.simpleDateString(from: start))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    } else {
                        Text("—")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("PROJECT COMPLETE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    if let end = project.computedEndDate {
                        Text(DateHelper.simpleDateString(from: end))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    } else {
                        Text("—")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }

            // Progress bar
            if totalCount > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(OPSStyle.Colors.cardBackgroundDark)

                        Capsule()
                            .fill(progress >= 1.0
                                  ? OPSStyle.Colors.successStatus
                                  : OPSStyle.Colors.primaryAccent)
                            .frame(width: max(0, geo.size.width * CGFloat(progress)))
                    }
                }
                .frame(height: 6)

                // Task count
                Text("\(completedCount) of \(totalCount) TASKS COMPLETE")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Client Section

struct ClientSection: View {
    let project: Project
    let canEdit: Bool
    let onContactTap: () -> Void
    let onCall: () -> Void
    let onEmail: () -> Void
    var onAssignClient: (() -> Void)? = nil

    private var hasClient: Bool { project.client != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("CLIENT")

            if hasClient {
                // Client assigned — tap to view contact, long press to reassign
                clientCard
            } else if canEdit {
                // No client, user can assign — tap to pick
                emptyCard
                    .onTapGesture {
                        if let assign = onAssignClient {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            assign()
                        }
                    }
            } else {
                // No client, no permission — static display
                emptyCard
            }
        }
    }

    private var clientCard: some View {
        HStack(spacing: 12) {
            // Left side — tap to open contact details
            Button(action: onContactTap) {
                HStack(spacing: 12) {
                    if let client = project.client {
                        UserAvatar(client: client, size: 36)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.effectiveClientName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("Client")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Contact action buttons — independent tap targets
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
                .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)

                Button(action: onEmail) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(hasEmail ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText.opacity(0.3))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!hasEmail)
                .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
            }

            Button(action: onContactTap) {
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(14)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    if canEdit, let assign = onAssignClient {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        assign()
                    }
                }
        )
        .padding(.horizontal, 16)
    }

    private var emptyCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "building.2")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                )

            Text("NO CLIENT ASSIGNED")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Spacer()

            if canEdit {
                Text("ASSIGN")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
        .contentShape(Rectangle())
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
    /// User lookup keyed by id — used to resolve task team-member avatars from
    /// the authoritative `teamMemberIdsString` CSV. Passed down from
    /// DetailsTabView so the @Query only runs once per project view.
    let userById: [String: User]
    let onTaskTap: (ProjectTask) -> Void
    let onAddTask: () -> Void
    var onSelectTask: ((ProjectTask) -> Void)? = nil
    var onCompleteTask: ((ProjectTask) -> Void)? = nil
    var onReopenTask: ((ProjectTask) -> Void)? = nil
    var onCancelTask: ((ProjectTask) -> Void)? = nil
    var onDeleteTask: ((ProjectTask) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TASKS")

            VStack(spacing: 0) {
                ForEach(tasks, id: \.id) { task in
                    let isSelected = selectedTask?.id == task.id
                    let hasSelection = selectedTask != nil
                    let taskColor = Color(hex: task.taskColor) ?? OPSStyle.Colors.primaryAccent
                    let isInactive = task.status == .completed || task.status == .cancelled

                    Button(action: { onTaskTap(task) }) {
                        HStack(spacing: 8) {
                            // Left cluster: task type badge + status badge (always adjacent)
                            TaskBadge(
                                name: task.taskType?.display ?? "Task",
                                color: taskColor,
                                size: .medium,
                                faded: isInactive
                            )

                            if task.status == .completed {
                                StatusBadgePill(
                                    text: "COMPLETE",
                                    color: TaskStatus.completed.color,
                                    size: .medium
                                )
                            } else if task.status == .cancelled {
                                StatusBadgePill(
                                    text: "CANCELLED",
                                    color: TaskStatus.cancelled.color,
                                    size: .medium
                                )
                            }

                            // Assigned team avatars — resolved from `teamMemberIdsString`
                            // (the authoritative source) via the parent's User lookup.
                            // Reading `task.teamMembers` directly would miss rows whose
                            // relationship hasn't been rewired yet (post-insert, pre-sync).
                            let assignedMembers: [User] = task.getTeamMemberIds().compactMap { userById[$0] }
                            if !assignedMembers.isEmpty {
                                HStack(spacing: -6) {
                                    ForEach(Array(assignedMembers.prefix(3)), id: \.id) { member in
                                        UserAvatar(user: member, size: 22)
                                            .overlay(
                                                Circle()
                                                    .stroke(OPSStyle.Colors.cardBackgroundDark, lineWidth: 1.5)
                                            )
                                    }
                                    if assignedMembers.count > 3 {
                                        Text("+\(assignedMembers.count - 3)")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                            .padding(.leading, 8)
                                    }
                                }
                                .padding(.leading, 4)
                            }

                            Spacer()

                            // Schedule date
                            if let startDate = task.startDate {
                                Text(TaskListSection.formatTaskDate(startDate))
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(Calendar.current.isDateInToday(startDate) ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)

                            }

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
                    .contextMenu {
                        // Select / Deselect
                        if isSelected {
                            Button(action: { onSelectTask?(task) }) {
                                Label("Deselect", systemImage: "xmark.circle")
                            }
                        } else {
                            Button(action: { onSelectTask?(task) }) {
                                Label("Select Task", systemImage: "checkmark.circle")
                            }
                        }

                        Divider()

                        // Status actions based on current status
                        if task.status == .active {
                            Button(action: { onCompleteTask?(task) }) {
                                Label("Complete", systemImage: "checkmark")
                            }
                            Button(role: .destructive, action: { onCancelTask?(task) }) {
                                Label("Cancel Task", systemImage: "xmark")
                            }
                        } else if task.status == .completed || task.status == .cancelled {
                            Button(action: { onReopenTask?(task) }) {
                                Label("Reopen", systemImage: "arrow.uturn.backward")
                            }
                        }

                        Divider()

                        // Delete (always available for admin)
                        if canEdit {
                            Button(role: .destructive, action: { onDeleteTask?(task) }) {
                                Label("Delete Task", systemImage: "trash")
                            }
                        }
                    }

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

    // MARK: - Date Formatting

    static func formatTaskDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "TODAY"
        }
        if calendar.isDateInTomorrow(date) {
            return "TOMORROW"
        }
        let formatter = DateFormatter()
        // Same year → "Mar 9", different year → "Mar 9, 2025"
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            formatter.dateFormat = "MMM d"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date).uppercased()
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
    var onSaveAddress: ((String) -> Void)? = nil

    @State private var isEditing = false
    @State private var draft = ""
    @StateObject private var completer = InlineAddressCompleter()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ADDRESS")

            VStack(spacing: 0) {
                if isEditing {
                    // Inline edit mode
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.circle")
                                .font(.system(size: OPSStyle.Layout.IconSize.md))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)

                            TextField("Start typing an address...", text: $draft)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .focused($fieldFocused)
                                .onSubmit { saveAndClose() }
                                .onChange(of: draft) { _, newValue in
                                    completer.search(newValue)
                                }

                            // Save / Cancel
                            Button(action: saveAndClose) {
                                Text("SAVE")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: cancelEdit) {
                                Image(systemName: OPSStyle.Icons.xmark)
                                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(14)

                        // Inline suggestions
                        if !completer.results.isEmpty {
                            Rectangle()
                                .fill(OPSStyle.Colors.cardBorderSubtle)
                                .frame(height: 1)

                            ForEach(completer.results, id: \.self) { result in
                                Button(action: { selectResult(result) }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "location.fill")
                                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(result.title)
                                                .font(OPSStyle.Typography.body)
                                                .foregroundColor(OPSStyle.Colors.primaryText)
                                                .lineLimit(1)
                                            if !result.subtitle.isEmpty {
                                                Text(result.subtitle)
                                                    .font(OPSStyle.Typography.smallCaption)
                                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())

                                if result != completer.results.last {
                                    Rectangle()
                                        .fill(OPSStyle.Colors.cardBorderSubtle)
                                        .frame(height: 1)
                                        .padding(.leading, 36)
                                }
                            }
                        }
                    }
                } else {
                    // Display mode
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
                            Button(action: startEditing) {
                                Image(systemName: OPSStyle.Icons.pencil)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(14)
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(isEditing ? OPSStyle.Colors.primaryAccent.opacity(0.5) : OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.2), value: isEditing)
            .padding(.horizontal, 16)
        }
    }

    private func startEditing() {
        draft = address ?? ""
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            fieldFocused = true
        }
    }

    private func saveAndClose() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        onSaveAddress?(trimmed)
        completer.clear()
        withAnimation { isEditing = false }
    }

    private func cancelEdit() {
        completer.clear()
        withAnimation { isEditing = false }
    }

    private func selectResult(_ result: MKLocalSearchCompletion) {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: result))
        search.start { response, _ in
            if let placemark = response?.mapItems.first?.placemark {
                let parts = [
                    placemark.subThoroughfare,
                    placemark.thoroughfare,
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.postalCode
                ].compactMap { $0 }
                draft = parts.joined(separator: " ")
            } else {
                draft = [result.title, result.subtitle]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
            }
            completer.clear()
        }
    }
}

// MARK: - Inline Address Completer

private class InlineAddressCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 3 {
            results = []
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        results = []
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.results = Array(completer.results.prefix(4))
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

// MARK: - Photos Section

struct PhotosSection: View {
    @Bindable var project: Project
    let onPhotoTap: (Int) -> Void
    let onAddPhoto: () -> Void

    @EnvironmentObject private var dataController: DataController

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
                    // Horizontal scroll of photo thumbnails with per-photo
                    // client-visibility toggle (eye icon). Tapping the eye
                    // adds/removes the URL from clientVisibleImagesString and
                    // syncs the change to project_photos.is_client_visible so
                    // the web client portal reflects the crew's choice.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                                ZStack(alignment: .topTrailing) {
                                    Button(action: { onPhotoTap(index) }) {
                                        PhotoThumbnail(url: url, project: project)
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    // Per-photo client-portal visibility toggle.
                                    // Filled eye = visible to client, slashed = hidden.
                                    ClientVisibilityButton(
                                        url: url,
                                        project: project,
                                        dataController: dataController
                                    )
                                    .offset(x: 4, y: -4)
                                }
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

// MARK: - Client Visibility Button

/// Eye icon toggle that marks a single project photo as visible (or
/// hidden) in the client portal. Writes the change to the local model
/// and syncs to project_photos.is_client_visible on Supabase.
private struct ClientVisibilityButton: View {
    let url: String
    let project: Project
    let dataController: DataController

    @State private var isSyncing = false

    private var isVisible: Bool {
        project.isImageClientVisible(url)
    }

    var body: some View {
        Button(action: toggleVisibility) {
            ZStack {
                Circle()
                    .fill(isSyncing
                          ? OPSStyle.Colors.cardBackgroundDark.opacity(0.85)
                          : (isVisible
                             ? OPSStyle.Colors.primaryAccent.opacity(0.9)
                             : Color.black.opacity(0.55)))
                    .frame(width: 22, height: 22)

                if isSyncing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                        .scaleEffect(0.5)
                } else {
                    Image(systemName: isVisible ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
        .accessibilityLabel(isVisible ? "Hide from client portal" : "Show to client portal")
        .disabled(isSyncing)
    }

    private func toggleVisibility() {
        guard !isSyncing else { return }
        let newVisible = !isVisible

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Optimistic local write
        project.setImageClientVisible(url, visible: newVisible)
        try? dataController.modelContext?.save()

        // Sync to Supabase best-effort
        isSyncing = true
        Task {
            defer { Task { @MainActor in isSyncing = false } }
            do {
                try await dataController.imageSyncManager?.setPhotoClientVisibility(
                    url: url,
                    isVisible: newVisible,
                    projectId: project.id
                )
            } catch {
                // Revert local optimistic write on failure
                await MainActor.run {
                    project.setImageClientVisible(url, visible: !newVisible)
                    try? dataController.modelContext?.save()
                }
                print("[CLIENT_VISIBILITY] Failed to sync for \(url): \(error)")
            }
        }
    }
}

// MARK: - Section Label Helper

/// Reusable section label: `[ LABEL ]` — Kosugi 12pt caps, tertiaryText
/// Section headers appear OUTSIDE cards per design system
func sectionLabel(_ title: String) -> some View {
    Text("[ \(title) ]")
        .font(OPSStyle.Typography.smallCaption)
        .textCase(.uppercase)
        .tracking(1)
        .foregroundColor(OPSStyle.Colors.tertiaryText)
        .padding(.horizontal, 16)
}
