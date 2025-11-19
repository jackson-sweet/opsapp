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
                    VStack(spacing: 20) {
                        QuickActionContextHeader(
                            clientName: project.effectiveClientName,
                            projectAddress: project.address,
                            projectName: project.title,
                            taskName: nil,
                            accentColor: nil
                        )
                        .environmentObject(dataController)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("CURRENT STATUS")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            HStack(spacing: 12) {
                                Rectangle()
                                    .fill(project.status.color)
                                    .frame(width: 3, height: 40)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.status.displayName.uppercased())
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)

                                    Text("Active Status")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }

                                Spacer()
                            }
                            .padding(16)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }

                        VStack(alignment: .leading, spacing: 12) {
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
                                            .background(Color.white.opacity(0.05))
                                    }
                                }
                            }
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
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
                        case .inProgress:
                            if task.status == .booked {
                                newTaskStatus = .inProgress
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
            HStack(spacing: 12) {
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }

                if isDisabled {
                    Text("CURRENT")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 16)
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
    @State private var showingError = false
    @State private var errorMessage = ""

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
                        .font(.system(size: 48))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)

                    // Title
                    Text("SWITCH SCHEDULING MODE")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    // Current Mode
                    HStack(spacing: 20) {
                        VStack(spacing: 8) {
                            Text("FROM")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                           // SchedulingModeBadge(eventType: project.eventType ?? .project)
                        }

                        Image(systemName: "arrow.right")
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        VStack(spacing: 8) {
                            Text("TO")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            //SchedulingModeBadge(eventType: targetMode)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)

                    // Explanation
                    VStack(alignment: .leading, spacing: 12) {
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
                    .padding(16)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)

                    Spacer()

                    // Buttons
                    HStack(spacing: 16) {
                        Button("CANCEL") {
                            dismiss()
                        }
                        .buttonStyle(JBSecondaryButtonStyle())

                        Button(action: performConversion) {
                            if isConverting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("CONVERT")
                            }
                        }
                        .buttonStyle(JBPrimaryButtonStyle())
                        .disabled(isConverting)
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
            }
            .navigationTitle("CONVERSION DETAILS")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
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
                    showingError = true
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
        dataController.syncManager?.triggerBackgroundSync()
    }

    private func updateProjectDatesFromTasks(_ project: Project) {
        let taskEvents = project.tasks.compactMap { $0.calendarEvent }
        guard !taskEvents.isEmpty else {
            project.startDate = nil
            project.endDate = nil
            return
        }

        // Find earliest start and latest end
        let startDates = taskEvents.compactMap { $0.startDate }
        let endDates = taskEvents.compactMap { $0.endDate }

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
                    VStack(spacing: 20) {
                        QuickActionContextHeader(
                            clientName: project.effectiveClientName,
                            projectAddress: project.address,
                            projectName: project.title,
                            taskName: nil,
                            accentColor: nil
                        )
                        .environmentObject(dataController)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("SELECT WHICH TASK'S TEAM TO EDIT")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            VStack(spacing: 0) {
                                ForEach(Array(project.tasks.enumerated()), id: \.element.id) { index, task in
                                    Button(action: {
                                        onTaskSelected(task.id)
                                    }) {
                                        HStack(spacing: 12) {
                                            Circle()
                                                .fill(Color(hex: task.taskColor) ?? OPSStyle.Colors.primaryAccent)
                                                .frame(width: 12, height: 12)

                                            VStack(alignment: .leading, spacing: 4) {
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
                                                .font(.system(size: 14))
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    if index < project.tasks.count - 1 {
                                        Divider()
                                            .background(Color.white.opacity(0.05))
                                    }
                                }
                            }
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }

                        // Create New Task button
                        Button(action: {
                            showingTaskForm = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                Text("CREATE NEW TASK")
                                    .font(OPSStyle.Typography.bodyBold)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(20)
                }
            }
        }
        .sheet(isPresented: $showingTaskForm) {
            TaskFormSheet(project: project)
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
            VStack(spacing: 20) {
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
            .padding(20)
        }
    }

    private var currentTeamSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var currentTeamList: some View {
        VStack(spacing: 0) {
            ForEach(Array(project.teamMembers.enumerated()), id: \.element.id) { index, member in
                HStack(spacing: 12) {
                    Image(systemName: OPSStyle.Icons.personFill)
                        .font(.system(size: 14))
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if index < project.teamMembers.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.05))
                }
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var teamSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                .padding(16)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
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
                                .background(Color.white.opacity(0.05))
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
        }
    }


    private func loadAvailableMembers() {
        availableMembers = dataController.getCompanyTeamMembers(companyId: project.companyId)
            .sorted { $0.fullName < $1.fullName }
    }

    private func saveTeam() {
        isSaving = true

        Task {
            do {
                // Update project team using centralized function
                try await dataController.updateProjectTeamMembers(project: project, memberIds: Array(selectedMemberIds))

                // Task-only scheduling migration: Update all task teams
                for task in project.tasks {
                    try await dataController.updateTaskTeamMembers(task: task, memberIds: Array(selectedMemberIds))
                }

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

struct TeamMemberOption: View {
    let member: TeamMember
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? OPSStyle.Icons.checkmarkSquareFill : OPSStyle.Icons.square)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)

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
            .padding(.horizontal, 16)
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
                        VStack(spacing: 20) {
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
                        .padding(20)
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
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var currentTeamList: some View {
        VStack(spacing: 0) {
            if let task = task {
                ForEach(Array(task.teamMembers.enumerated()), id: \.element.id) { index, member in
                HStack(spacing: 12) {
                    Image(systemName: OPSStyle.Icons.personFill)
                        .font(.system(size: 14))
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if index < task.teamMembers.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.05))
                }
            }
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var teamSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                .padding(16)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
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
                                .background(Color.white.opacity(0.05))
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
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
        availableMembers = dataController.getCompanyTeamMembers(companyId: project.companyId)
            .sorted { $0.fullName < $1.fullName }
    }

    private func saveTeam() {
        guard let task = task else { return }
        isSaving = true

        Task {
            do {
                // Update task team using centralized function
                try await dataController.updateTaskTeamMembers(task: task, memberIds: Array(selectedMemberIds))

                // Update calendar event team if exists
                if let calendarEvent = task.calendarEvent {
                    try await dataController.updateCalendarEventTeamMembers(event: calendarEvent, memberIds: Array(selectedMemberIds))
                }

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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
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

// Button Styles
struct JBPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(OPSStyle.Colors.primaryAccent)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct JBSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(OPSStyle.Colors.errorStatus)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}
