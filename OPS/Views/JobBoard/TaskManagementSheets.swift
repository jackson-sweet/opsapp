//
//  TaskManagementSheets.swift
//  OPS
//
//  Management sheets for task operations
//

import SwiftUI
import SwiftData

// MARK: - Task Status Change Sheet
struct TaskStatusChangeSheet: View {
    let task: ProjectTask
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @State private var selectedStatus: TaskStatus
    @State private var isSaving = false

    init(task: ProjectTask) {
        self.task = task
        _selectedStatus = State(initialValue: task.status)
    }

    private var project: Project? {
        dataController.getAllProjects().first(where: { $0.id == task.projectId })
    }

    private var taskTypeName: String {
        if let taskType = dataController.getAllTaskTypes(for: task.companyId).first(where: { $0.id == task.taskTypeId }) {
            return taskType.display
        }
        return "Task"
    }

    private var taskTypeColor: Color? {
        if let taskType = dataController.getAllTaskTypes(for: task.companyId).first(where: { $0.id == task.taskTypeId }) {
            return Color(hex: taskType.color)
        }
        return nil
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                QuickActionSheetHeader(
                    title: "CHANGE STATUS",
                    canSave: selectedStatus != task.status,
                    isSaving: isSaving,
                    onDismiss: { dismiss() },
                    onSave: saveStatus
                )

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3_5) {
                        QuickActionContextHeader(
                            clientName: project?.effectiveClientName,
                            projectAddress: project?.address,
                            projectName: project?.title ?? "Unknown Project",
                            taskName: taskTypeName,
                            accentColor: taskTypeColor
                        )
                        .environmentObject(dataController)

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                            Text("CURRENT STATUS")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                                Rectangle()
                                    .fill(task.status.color)
                                    .frame(width: 3, height: 40)

                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                    Text(task.status.displayName.uppercased())
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)

                                    Text("Active Status")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }

                                Spacer()
                            }
                            .padding(OPSStyle.Layout.spacing3)
                            .glassSurface()
                        }

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                            Text("SELECT NEW STATUS")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            VStack(spacing: 0) {
                                ForEach(TaskStatus.allCases, id: \.self) { status in
                                    TaskStatusSelectionRow(
                                        status: status,
                                        isSelected: selectedStatus == status,
                                        isDisabled: status == task.status
                                    ) {
                                        selectedStatus = status
                                    }

                                    if status != TaskStatus.allCases.last {
                                        Divider()
                                            .background(OPSStyle.Colors.line)
                                    }
                                }
                            }
                            .glassSurface()
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3_5)
                }
            }
        }
        .loadingOverlay(isPresented: $isSaving, message: "Updating...")
    }

    private func saveStatus() {
        isSaving = true

        Task {
            do {
                // Use the centralized, reusable status update function
                // This ensures ONLY the status field is updated on the server
                // and prevents duplicate task references in project.tasks
                try await dataController.updateTaskStatus(task: task, to: selectedStatus)

                await MainActor.run {
                    // Success haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    // Brief delay for graceful dismissal
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false

                    // Error haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Task Status Selection View
struct TaskStatusSelectionRow: View {
    let status: TaskStatus
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Rectangle()
                    .fill(status.color)
                    .frame(width: 3, height: 30)
                    .opacity(isDisabled ? 0.3 : 1)

                Text(status.displayName.uppercased())
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(isDisabled ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)

                Spacer()

                if isSelected && !isDisabled {
                    Image(systemName: OPSStyle.Icons.checkmark)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.text)
                }

                if isDisabled {
                    Text("CURRENT")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(OPSStyle.Colors.fillNeutral)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Task Team Change Sheet
struct TaskTeamChangeSheet: View {
    let task: ProjectTask
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @State private var selectedMemberIds: Set<String>
    @State private var isSaving = false
    @State private var availableMembers: [User] = []

    init(task: ProjectTask) {
        self.task = task
        _selectedMemberIds = State(initialValue: Set(task.getTeamMemberIds()))
    }

    private var taskTypeName: String {
        if let taskType = dataController.getAllTaskTypes(for: task.companyId).first(where: { $0.id == task.taskTypeId }) {
            return taskType.display
        }
        return "Task"
    }

    private var taskTypeColor: Color? {
        if let taskType = dataController.getAllTaskTypes(for: task.companyId).first(where: { $0.id == task.taskTypeId }) {
            return Color(hex: taskType.color)
        }
        return nil
    }

    private var projectName: String {
        if let project = dataController.getAllProjects().first(where: { $0.id == task.projectId }) {
            return project.title
        }
        return "Unknown Project"
    }

    private var project: Project? {
        dataController.getAllProjects().first(where: { $0.id == task.projectId })
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                QuickActionSheetHeader(
                    title: "CHANGE TEAM",
                    canSave: selectedMemberIds != Set(task.getTeamMemberIds()),
                    isSaving: isSaving,
                    onDismiss: { dismiss() },
                    onSave: saveTeam
                )

                contentView
            }
        }
        .loadingOverlay(isPresented: $isSaving, message: "Updating...")
        .onAppear {
            loadAvailableMembers()
        }
    }

    private var contentView: some View {
        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing3_5) {
                QuickActionContextHeader(
                    clientName: project?.effectiveClientName,
                    projectAddress: project?.address,
                    projectName: project?.title ?? "Unknown Project",
                    taskName: taskTypeName,
                    accentColor: taskTypeColor
                )
                .environmentObject(dataController)

                currentTeamSection
                teamSelectionSection
            }
            .padding(OPSStyle.Layout.spacing3_5)
        }
    }

    private var currentTeamSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("CURRENT TEAM")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if task.teamMembers.isEmpty {
                emptyTeamView
            } else {
                currentTeamList
            }
        }
    }

    private var emptyTeamView: some View {
        HStack {
            Text("No team members assigned")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private var currentTeamList: some View {
        VStack(spacing: 0) {
            ForEach(Array(task.teamMembers.enumerated()), id: \.element.id) { index, member in
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Image(systemName: OPSStyle.Icons.crew)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.fullName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text(member.role.displayName)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    Spacer()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)

                if index < task.teamMembers.count - 1 {
                    Divider()
                        .background(OPSStyle.Colors.line)
                }
            }
        }
        .glassSurface()
    }

    private var teamSelectionSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("SELECT TEAM MEMBERS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if availableMembers.isEmpty {
                HStack {
                    Text("No team members available")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Spacer()
                }
                .padding(OPSStyle.Layout.spacing3)
                .glassSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(availableMembers, id: \.id) { member in
                        TaskTeamMemberOption(
                            member: member,
                            isSelected: selectedMemberIds.contains(member.id)
                        ) {
                            toggleMember(member.id)
                        }

                        if member.id != availableMembers.last?.id {
                            Divider()
                                .background(OPSStyle.Colors.line)
                        }
                    }
                }
                .glassSurface()
            }
        }
    }


    private func loadAvailableMembers() {
        guard let companyId = dataController.currentUser?.companyId else { return }

        // Try local User fetch first
        let users = dataController.getTeamMembers(companyId: companyId)
        if !users.isEmpty {
            availableMembers = users.sorted { $0.fullName < $1.fullName }
            return
        }

        // Fallback: trigger async sync then retry
        Task {
            await dataController.triggerTeamMembersSync(companyId: companyId)
            await MainActor.run {
                let retryUsers = dataController.getTeamMembers(companyId: companyId)
                availableMembers = retryUsers.sorted { $0.fullName < $1.fullName }
            }
        }
    }

    private func toggleMember(_ memberId: String) {
        if selectedMemberIds.contains(memberId) {
            selectedMemberIds.remove(memberId)
        } else {
            selectedMemberIds.insert(memberId)
        }
    }

    private func saveTeam() {
        isSaving = true
        Task {
            do {
                try await dataController.updateTaskTeamMembers(task: task, memberIds: Array(selectedMemberIds))
                await MainActor.run {
                    // Success haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    // Brief delay for graceful dismissal
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false

                    // Error haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Task Team Member Option View
struct TaskTeamMemberOption: View {
    let member: User
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: isSelected ? OPSStyle.Icons.checkmarkSquareFill : OPSStyle.Icons.square)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.tertiaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.fullName)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(member.role.displayName)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
