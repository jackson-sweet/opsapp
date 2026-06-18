//
//  ProjectManagementSheets.swift
//  OPS
//
//  Created by Assistant on 2025-09-26.
//

import SwiftUI
import SwiftData

// MARK: - Project Status Change Sheet
struct ProjectStatusChangeSheet: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @State private var selectedStatus: Status
    @State private var isSaving = false

    init(project: Project) {
        self.project = project
        _selectedStatus = State(initialValue: project.status)
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                QuickActionSheetHeader(
                    title: "CHANGE STATUS",
                    canSave: selectedStatus != project.status,
                    isSaving: isSaving,
                    onDismiss: { dismiss() },
                    onSave: saveStatus
                )

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3_5) {
                        QuickActionContextHeader(
                            clientName: project.effectiveClientName,
                            projectAddress: project.address,
                            projectName: project.title,
                            taskName: nil,
                            accentColor: nil
                        )
                        .environmentObject(dataController)

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                            Text("CURRENT STATUS")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                                Rectangle()
                                    .fill(project.status.color)
                                    .frame(width: 3, height: 40)

                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                    Text(project.status.displayName.uppercased())
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
                                ForEach(Status.allCases, id: \.self) { status in
                                    StatusOption(
                                        status: status,
                                        isSelected: selectedStatus == status,
                                        isDisabled: status == project.status
                                    ) {
                                        selectedStatus = status
                                    }

                                    if status != Status.allCases.last {
                                        Divider()
                                            .background(OPSStyle.Colors.cardBorderSubtle)
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
                // Update project status using centralized function
                try await dataController.updateProjectStatus(project: project, to: selectedStatus)

                // Update task statuses using centralized function
                // Task-only scheduling migration: All projects use tasks
                if true {
                    for task in project.tasks {
                        var newTaskStatus: TaskStatus? = nil

                        switch selectedStatus {
                        case .completed, .closed:
                            if task.status != .completed && task.status != .cancelled {
                                newTaskStatus = .completed
                            }
                        default:
                            break
                        }

                        // Use centralized function for each task status change
                        if let newStatus = newTaskStatus {
                            try await dataController.updateTaskStatus(task: task, to: newStatus)
                        }
                    }
                }

                await MainActor.run {
                    // Success haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    ToastCenter.shared.present(Feedback.JobBoard.statusChanged)

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

// MARK: - Status Option View
struct StatusOption: View {
    let status: Status
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
                        .background(OPSStyle.Colors.surfaceInput)
                        .cornerRadius(OPSStyle.Layout.chipRadius)
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

// MARK: - Scheduling Mode Conversion Sheet
struct SchedulingModeConversionSheet: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @State private var isConverting = false
    @State private var errorMessage: String? = nil

    // Note: This feature is disabled in task-only scheduling migration
    // Kept for potential future re-enablement
    private var targetMode: String {
        "task"  // Always task-based now
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: OPSStyle.Layout.spacing4) {
                    // Icon
                    Image(systemName: "checklist")  // Always task-based now
                        .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)

                    // Title
                    Text("SWITCH SCHEDULING MODE")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    // Current Mode
                    HStack(spacing: OPSStyle.Layout.spacing3_5) {
                        VStack(spacing: OPSStyle.Layout.spacing2) {
                            Text("FROM")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                           // SchedulingModeBadge(eventType: project.eventType ?? .project)
                        }

                        Image(systemName: "arrow.right")
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        VStack(spacing: OPSStyle.Layout.spacing2) {
                            Text("TO")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            //SchedulingModeBadge(eventType: targetMode)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                    .glassSurface()

                    // Explanation
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                        // Always task-based now
                        FeaturePoint(
                            icon: "checkmark.circle",
                            text: "Each task will appear separately on calendar"
                        )
                        FeaturePoint(
                            icon: "calendar.badge.clock",
                            text: "Project dates will be determined by task dates"
                        )
                        FeaturePoint(
                            icon: "info.circle",
                            text: "All scheduling is now task-based"
                        )
                    }
                    .padding(OPSStyle.Layout.spacing3)
                    .glassSurface()

                    Spacer()

                    // Buttons
                    HStack(spacing: OPSStyle.Layout.spacing3) {
                        Button("CANCEL") {
                            dismiss()
                        }
                        .buttonStyle(OPSButtonStyle.Secondary())

                        Button(action: performConversion) {
                            if isConverting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.loadingSpinner))
                            } else {
                                Text("CONVERT")
                            }
                        }
                        .buttonStyle(OPSButtonStyle.Primary())
                        .disabled(isConverting)
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
            }
            .navigationTitle("CONVERSION DETAILS")
            .navigationBarTitleDisplayMode(.inline)
        }
        .loadingOverlay(isPresented: $isConverting, message: "Converting...")
        .errorToast($errorMessage, label: Feedback.Err.conversionFailed)
    }

    private func performConversion() {
        isConverting = true

        Task {
            do {
                try await convertSchedulingMode(project: project, to: targetMode)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isConverting = false
                }
            }
        }
    }

    private func convertSchedulingMode(project: Project, to targetMode: String) async throws {
        try await MainActor.run {
            // Note: Task-only scheduling migration - all projects use task-based scheduling now
            // Project dates are automatically computed from task calendar events

            project.needsSync = true

            do {
                try modelContext.save()
            } catch {
                throw error
            }
        }

        // Trigger sync
        dataController.triggerBackgroundSync()
    }

    private func updateProjectDatesFromTasks(_ project: Project) {
        let tasksWithDates = project.tasks.filter { $0.startDate != nil }
        guard !tasksWithDates.isEmpty else {
            project.startDate = nil
            project.endDate = nil
            return
        }

        // Find earliest start and latest end
        let startDates = tasksWithDates.compactMap { $0.startDate }
        let endDates = tasksWithDates.compactMap { $0.endDate }

        project.startDate = startDates.min()
        project.endDate = endDates.max()
    }
}

// MARK: - Project Team Change Sheet
struct ProjectTeamChangeSheet: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @State private var selectedTaskId: String?
    @State private var showingTaskTeamChange = false

    var body: some View {
        NavigationStack {
            // Task-only scheduling migration: All projects use tasks
            if !project.tasks.isEmpty {
                TaskPickerForTeamChange(
                    project: project,
                    onTaskSelected: { taskId in
                        selectedTaskId = taskId
                        showingTaskTeamChange = true
                    }
                )
                .navigationDestination(isPresented: $showingTaskTeamChange) {
                    if let taskId = selectedTaskId {
                        TaskTeamChangeView(
                            taskId: taskId,
                            project: project,
                            onComplete: {
                                dismiss()
                            }
                        )
                        .environmentObject(dataController)
                    }
                }
            } else {
                ProjectTeamChangeView(project: project)
                    .environmentObject(dataController)
            }
        }
    }
}

// MARK: - Task Picker For Team Change
struct TaskPickerForTeamChange: View {
    let project: Project
    let onTaskSelected: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @State private var showingTaskForm = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                QuickActionSheetHeader(
                    title: "SELECT TASK",
                    canSave: false,
                    isSaving: false,
                    onDismiss: { dismiss() },
                    onSave: {}
                )

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3_5) {
                        QuickActionContextHeader(
                            clientName: project.effectiveClientName,
                            projectAddress: project.address,
                            projectName: project.title,
                            taskName: nil,
                            accentColor: nil
                        )
                        .environmentObject(dataController)

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                            Text("SELECT WHICH TASK'S TEAM TO EDIT")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            VStack(spacing: 0) {
                                ForEach(Array(project.tasks.enumerated()), id: \.element.id) { index, task in
                                    Button(action: {
                                        onTaskSelected(task.id)
                                    }) {
                                        HStack(spacing: OPSStyle.Layout.spacing2_5) {
                                            Circle()
                                                .fill(Color(hex: task.taskColor) ?? OPSStyle.Colors.primaryAccent)
                                                .frame(width: 12, height: 12)

                                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                                Text(task.taskType?.display ?? "Task")
                                                    .font(OPSStyle.Typography.bodyBold)
                                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                                if !task.getTeamMemberIds().isEmpty {
                                                    Text("\(task.getTeamMemberIds().count) team member\(task.getTeamMemberIds().count == 1 ? "" : "s")")
                                                        .font(OPSStyle.Typography.smallCaption)
                                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                }
                                            }

                                            Spacer()

                                            Image(systemName: "chevron.right")
                                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                        }
                                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                                        .padding(.vertical, 14)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    if index < project.tasks.count - 1 {
                                        Divider()
                                            .background(OPSStyle.Colors.cardBorderSubtle)
                                    }
                                }
                            }
                            .glassSurface()
                        }

                        // Create New Task button
                        Button(action: {
                            showingTaskForm = true
                        }) {
                            HStack {
                                Image(systemName: OPSStyle.Icons.add)
                                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                                Text("CREATE NEW TASK")
                                    .font(OPSStyle.Typography.bodyBold)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(OPSStyle.Colors.surfaceInput)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(OPSStyle.Layout.spacing3_5)
                }
            }
        }
        .sheet(isPresented: $showingTaskForm) {
            TaskFormSheet(mode: .create, preselectedProjectId: project.id) { _ in }
                .environmentObject(dataController)
        }
    }
}

// MARK: - Project Team Change View (for project-based scheduling)
struct ProjectTeamChangeView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @State private var selectedMemberIds: Set<String>
    @State private var isSaving = false
    @State private var availableMembers: [TeamMember] = []

    init(project: Project) {
        self.project = project
        _selectedMemberIds = State(initialValue: Set(project.getTeamMemberIds()))
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                QuickActionSheetHeader(
                    title: "CHANGE TEAM",
                    canSave: selectedMemberIds != Set(project.getTeamMemberIds()),
                    isSaving: isSaving,
                    onDismiss: { dismiss() },
                    onSave: saveTeam
                )

                contentView
            }
        }
        .onAppear {
            loadAvailableMembers()
        }
    }

    private var contentView: some View {
        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing3_5) {
                QuickActionContextHeader(
                    clientName: project.effectiveClientName,
                    projectAddress: project.address,
                    projectName: project.title,
                    taskName: nil,
                    accentColor: nil
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

            if project.teamMembers.isEmpty {
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
            ForEach(Array(project.teamMembers.enumerated()), id: \.element.id) { index, member in
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

                if index < project.teamMembers.count - 1 {
                    Divider()
                        .background(OPSStyle.Colors.cardBorderSubtle)
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
                        TeamMemberOption(
                            member: member,
                            isSelected: selectedMemberIds.contains(member.id)
                        ) {
                            if selectedMemberIds.contains(member.id) {
                                selectedMemberIds.remove(member.id)
                            } else {
                                selectedMemberIds.insert(member.id)
                            }
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
        let members = dataController.getCompanyTeamMembers(companyId: project.companyId)
        if !members.isEmpty {
            availableMembers = members.sorted { $0.fullName < $1.fullName }
            return
        }
        // Fallback: fetch User objects and convert
        let users = dataController.getTeamMembers(companyId: project.companyId)
        if !users.isEmpty {
            availableMembers = users.map { TeamMember.fromUser($0) }
                .sorted { $0.fullName < $1.fullName }
            return
        }
        // Last resort: trigger sync then retry
        Task {
            if let companyId = dataController.currentUser?.companyId {
                await dataController.triggerTeamMembersSync(companyId: companyId)
            }
            await MainActor.run {
                let retryMembers = dataController.getCompanyTeamMembers(companyId: project.companyId)
                if !retryMembers.isEmpty {
                    availableMembers = retryMembers.sorted { $0.fullName < $1.fullName }
                } else {
                    let retryUsers = dataController.getTeamMembers(companyId: project.companyId)
                    availableMembers = retryUsers.map { TeamMember.fromUser($0) }
                        .sorted { $0.fullName < $1.fullName }
                }
            }
        }
    }

    private func saveTeam() {
        isSaving = true

        Task {
            do {
                try await dataController.replaceProjectTeamMembersViaServerAssignments(
                    project: project,
                    memberIds: Array(selectedMemberIds)
                )

                await MainActor.run {
                    // Success haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    ToastCenter.shared.present(Feedback.JobBoard.teamUpdated)

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

struct TeamMemberOption: View {
    let member: TeamMember
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

                    Text(member.role)
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

// MARK: - Task Team Change View
struct TaskTeamChangeView: View {
    let taskId: String
    let project: Project
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @State private var selectedMemberIds: Set<String>
    @State private var isSaving = false
    @State private var availableMembers: [TeamMember] = []
    @State private var task: ProjectTask?

    init(taskId: String, project: Project, onComplete: @escaping () -> Void) {
        self.taskId = taskId
        self.project = project
        self.onComplete = onComplete
        _selectedMemberIds = State(initialValue: Set())
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            if let task = task {
                VStack(spacing: 0) {
                    QuickActionSheetHeader(
                        title: "CHANGE TEAM",
                        canSave: selectedMemberIds != Set(task.getTeamMemberIds()),
                        isSaving: isSaving,
                        onDismiss: { dismiss() },
                        onSave: saveTeam
                    )

                    ScrollView {
                        VStack(spacing: OPSStyle.Layout.spacing3_5) {
                            QuickActionContextHeader(
                                clientName: project.effectiveClientName,
                                projectAddress: project.address,
                                projectName: project.title,
                                taskName: task.taskType?.display,
                                accentColor: Color(hex: task.taskColor)
                            )
                            .environmentObject(dataController)

                            currentTeamSection
                            teamSelectionSection
                        }
                        .padding(OPSStyle.Layout.spacing3_5)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadTask()
            loadAvailableMembers()
        }
    }

    private var currentTeamSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("CURRENT TEAM")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if task?.getTeamMemberIds().isEmpty ?? true {
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
            if let task = task {
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
                        .background(OPSStyle.Colors.cardBorderSubtle)
                }
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
                        TeamMemberOption(
                            member: member,
                            isSelected: selectedMemberIds.contains(member.id)
                        ) {
                            if selectedMemberIds.contains(member.id) {
                                selectedMemberIds.remove(member.id)
                            } else {
                                selectedMemberIds.insert(member.id)
                            }
                        }

                        if member.id != availableMembers.last?.id {
                            Divider()
                                .background(OPSStyle.Colors.cardBorderSubtle)
                        }
                    }
                }
                .glassSurface()
            }
        }
    }

    private func loadTask() {
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate { $0.id == taskId }
        )

        if let fetchedTask = try? modelContext.fetch(descriptor).first {
            task = fetchedTask
            selectedMemberIds = Set(fetchedTask.getTeamMemberIds())
        }
    }

    private func loadAvailableMembers() {
        let companyId = project.companyId
        let users = dataController.getTeamMembers(companyId: companyId)
        if !users.isEmpty {
            availableMembers = users.map { TeamMember.fromUser($0) }
                .sorted { $0.fullName < $1.fullName }
            return
        }

        // Fallback: trigger async sync then retry
        Task {
            await dataController.triggerTeamMembersSync(companyId: companyId)
            await MainActor.run {
                let retryUsers = dataController.getTeamMembers(companyId: companyId)
                availableMembers = retryUsers.map { TeamMember.fromUser($0) }
                    .sorted { $0.fullName < $1.fullName }
            }
        }
    }

    private func saveTeam() {
        guard let task = task else { return }
        isSaving = true

        Task {
            do {
                // Update task team using centralized function
                try await dataController.updateTaskTeamMembers(task: task, memberIds: Array(selectedMemberIds))

                // Calculate project team from all tasks
                await MainActor.run {
                    var allTeamMemberIds = Set<String>()
                    for projectTask in project.tasks {
                        allTeamMemberIds.formUnion(projectTask.getTeamMemberIds())
                    }
                    let projectTeamIds = Array(allTeamMemberIds)

                    // Update project team using centralized function
                    Task {
                        do {
                            try await dataController.updateProjectTeamMembers(project: project, memberIds: projectTeamIds)
                            await MainActor.run {
                                // Success haptic feedback
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)

                                ToastCenter.shared.present(Feedback.JobBoard.teamUpdated)

                                // Brief delay for graceful dismissal
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onComplete()
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

// MARK: - Supporting Views

struct FeaturePoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.md))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 20)

            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

// Button Styles — use OPSButtonStyle.Primary, .Secondary, .Destructive from ButtonStyles.swift
