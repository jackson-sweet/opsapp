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
            await MainActor.run {
                project.status = selectedStatus
                project.needsSync = true

                if project.eventType == .task {
                    for task in project.tasks {
                        switch selectedStatus {
                        case .completed, .closed:
                            if task.status != .completed && task.status != .cancelled {
                                task.status = .completed
                                task.needsSync = true
                            }
                        case .inProgress:
                            if task.status == .scheduled {
                                task.status = .inProgress
                                task.needsSync = true
                            }
                        default:
                            break
                        }
                    }
                }

                do {
                    try modelContext.save()
                    dismiss()
                } catch {
                    isSaving = false
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

    private var targetMode: CalendarEventType {
        project.eventType == .project ? .task : .project
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: OPSStyle.Layout.spacing4) {
                    // Icon
                    Image(systemName: targetMode == .task ? "checklist" : "calendar")
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
                        if targetMode == .task {
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
                                text: "Current project calendar event will be hidden"
                            )
                        } else {
                            FeaturePoint(
                                icon: "calendar",
                                text: "Project will have single calendar entry"
                            )
                            FeaturePoint(
                                icon: "eye.slash",
                                text: "Individual tasks won't appear on calendar"
                            )
                            FeaturePoint(
                                icon: "clock",
                                text: "You'll set project dates directly"
                            )
                        }
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

    private func convertSchedulingMode(project: Project, to targetMode: CalendarEventType) async throws {
        try await MainActor.run {
            // Update project
            project.eventType = targetMode

            if targetMode == .task {
                // Converting to task-based
                // Update project's calendar event (deactivates it)
                if let event = project.primaryCalendarEvent, event.type == .project {
                    event.updateProjectEventTypeCache(from: project)
                }

                // Update all task calendar events (activates them)
                for task in project.tasks {
                    if let event = task.calendarEvent {
                        event.updateProjectEventTypeCache(from: project)
                    }
                }

                // Update project dates based on tasks
                updateProjectDatesFromTasks(project)

            } else {
                // Converting to project-based
                // Create or activate project calendar event
                var projectEvent: CalendarEvent?

                // Use existing project calendar event
                if let event = project.primaryCalendarEvent, event.type == .project {
                    projectEvent = event
                }

                if let projectEvent = projectEvent {
                    projectEvent.updateProjectEventTypeCache(from: project)
                } else {
                    // Create new calendar event if needed
                    let newEvent = CalendarEvent(
                        id: UUID().uuidString,
                        projectId: project.id,
                        companyId: project.companyId,
                        title: project.title,
                        startDate: project.startDate ?? Date(),
                        endDate: project.endDate ?? Date().addingTimeInterval(86400),
                        color: "#59779F", // Default project color
                        type: .project,
                        active: true
                    )
                    newEvent.taskId = nil
                    newEvent.updateProjectEventTypeCache(from: project)
                    modelContext.insert(newEvent)
                }

                // Update all task calendar events (deactivates them)
                for task in project.tasks {
                    if let event = task.calendarEvent {
                        event.updateProjectEventTypeCache(from: project)
                    }
                }
            }

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
            if project.eventType == .task && !project.tasks.isEmpty {
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
                    }
                    .padding(20)
                }
            }
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
                await MainActor.run {
                    project.setTeamMemberIds(Array(selectedMemberIds))
                    project.needsSync = true

                    if project.eventType == .task {
                        for task in project.tasks {
                            task.setTeamMemberIds(Array(selectedMemberIds))
                            task.needsSync = true
                        }
                    }
                }

                try await dataController.apiService.updateProjectTeamMembers(
                    projectId: project.id,
                    teamMemberIds: Array(selectedMemberIds)
                )

                await MainActor.run {
                    project.needsSync = false
                    project.lastSyncedAt = Date()

                    do {
                        try modelContext.save()
                        dismiss()
                    } catch {
                        isSaving = false
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
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
                let currentTaskId = task.id
                let calendarEventId = task.calendarEvent?.id
                var projectTeamIds: [String] = []

                await MainActor.run {
                    task.setTeamMemberIds(Array(selectedMemberIds))

                    let userDescriptor = FetchDescriptor<User>(
                        predicate: #Predicate<User> { user in
                            selectedMemberIds.contains(user.id)
                        }
                    )

                    if let users = try? modelContext.fetch(userDescriptor) {
                        task.teamMembers = users
                    }

                    task.needsSync = true

                    if let calendarEvent = task.calendarEvent {
                        calendarEvent.setTeamMemberIds(Array(selectedMemberIds))
                        if let users = try? modelContext.fetch(userDescriptor) {
                            calendarEvent.teamMembers = users
                        }
                        calendarEvent.needsSync = true
                    }

                    updateProjectTeamFromAllTasks()
                    projectTeamIds = project.getTeamMemberIds()

                    do {
                        try modelContext.save()
                    } catch {
                        print("[TASK_TEAM_CHANGE] ❌ Error saving: \(error)")
                    }
                }

                try await dataController.apiService.updateTaskTeamMembers(
                    id: currentTaskId,
                    teamMemberIds: Array(selectedMemberIds)
                )

                if let eventId = calendarEventId {
                    try await dataController.apiService.updateCalendarEventTeamMembers(
                        id: eventId,
                        teamMemberIds: Array(selectedMemberIds)
                    )
                }

                try await dataController.apiService.updateProjectTeamMembers(
                    projectId: project.id,
                    teamMemberIds: projectTeamIds
                )

                await MainActor.run {
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }

    private func updateProjectTeamFromAllTasks() {
        var allTeamMemberIds = Set<String>()

        for task in project.tasks {
            allTeamMemberIds.formUnion(task.getTeamMemberIds())
        }

        project.setTeamMemberIds(Array(allTeamMemberIds))
        project.needsSync = true
    }
}

// MARK: - Project Deletion Confirmation
struct ProjectDeletionConfirmation: View {
    let project: Project
    @State private var isDeleting = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: OPSStyle.Layout.spacing4) {
                    // Warning Icon
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(OPSStyle.Colors.errorStatus)

                    // Title
                    Text("DELETE PROJECT")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    // Project Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(project.title)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text(project.effectiveClientName)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)

                    // Warning Message
                    if !project.tasks.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(OPSStyle.Colors.warningStatus)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("WARNING")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.warningStatus)

                                Text("This will permanently delete \(project.tasks.count) task\(project.tasks.count == 1 ? "" : "s") associated with this project")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }

                            Spacer()
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .fill(OPSStyle.Colors.warningStatus.opacity(0.1))
                                .stroke(OPSStyle.Colors.warningStatus.opacity(0.3), lineWidth: 1)
                        )
                    }

                    Spacer()

                    // Buttons
                    HStack(spacing: 16) {
                        Button("CANCEL") {
                            dismiss()
                        }
                        .buttonStyle(JBSecondaryButtonStyle())

                        Button(action: deleteProject) {
                            if isDeleting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("DELETE")
                            }
                        }
                        .buttonStyle(DestructiveButtonStyle())
                        .disabled(isDeleting)
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
            }
            .navigationTitle("CONFIRM DELETION")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    func deleteProject() {
        isDeleting = true

        Task {
            await MainActor.run {
                // Delete associated calendar event
                if let event = project.primaryCalendarEvent {
                    modelContext.delete(event)
                }

                // Delete associated tasks
                for task in project.tasks {
                    // Delete task calendar events
                    if let event = task.calendarEvent {
                        modelContext.delete(event)
                    }
                    modelContext.delete(task)
                }

                // Delete project
                modelContext.delete(project)

                do {
                    try modelContext.save()
                } catch {
                    print("Error deleting project: \(error)")
                }

                dismiss()
            }

            // Trigger sync to update backend
            dataController.syncManager?.triggerBackgroundSync()
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
