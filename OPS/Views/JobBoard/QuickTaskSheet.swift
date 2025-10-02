//
//  QuickTaskSheet.swift
//  OPS
//
//  Created by Assistant on 2025-09-26.
//

import SwiftUI
import SwiftData

struct QuickTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Query private var allProjects: [Project]
    @Query private var allTaskTypes: [TaskType]
    @Query private var allTeamMembers: [TeamMember]

    // Step 1: Project Selection
    @State private var selectedProject: Project?
    @State private var showingConversionAlert = false

    // Step 2: Task Details
    @State private var selectedTaskTypeId: String?
    @State private var taskNotes: String = ""
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var allDay: Bool = false
    @State private var duration: Int = 1 // in hours

    // Task Type Creation
    @State private var showingCreateTaskType = false

    // Loading state
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private var availableProjects: [Project] {
        allProjects.filter { $0.status != .completed && $0.status != .closed }
            .sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    private var availableTaskTypes: [TaskType] {
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        return allTaskTypes.filter { $0.companyId == companyId || $0.isDefault }
    }

    private var selectedTaskType: TaskType? {
        guard let selectedTaskTypeId = selectedTaskTypeId else { return nil }
        return availableTaskTypes.first { $0.id == selectedTaskTypeId }
    }

    private var formattedDuration: String {
        let hours = Int(endDate.timeIntervalSince(startDate) / 3600)
        let minutes = Int((endDate.timeIntervalSince(startDate).truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
    }

    private var isValid: Bool {
        selectedTaskTypeId != nil
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                if selectedProject == nil {
                    projectSelectionView
                } else {
                    taskDetailsForm
                }
            }
            .navigationTitle("CREATE TASK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }

                if selectedProject != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("CREATE") { createTask() }
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .disabled(!isValid || isCreating)
                    }
                }
            }
            .alert("Switch to Task-Based Scheduling?", isPresented: $showingConversionAlert) {
                Button("CANCEL", role: .cancel) {
                    selectedProject = nil
                }
                Button("CONVERT") {
                    convertProjectScheduling()
                }
            } message: {
                Text("This project uses project-based scheduling. Converting will make individual tasks appear on the calendar.")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
        .sheet(isPresented: $showingCreateTaskType) {
            TaskTypeFormSheet { newTaskType in
                selectedTaskTypeId = newTaskType.id
            }
        }
    }

    // MARK: - Project Selection View

    private var projectSelectionView: some View {
        VStack(spacing: 0) {
            // Header
            Text("SELECT PROJECT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)

            if availableProjects.isEmpty {
                // Empty state
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Text("No Active Projects")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text("Create a project first to add tasks")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(maxHeight: .infinity)
            } else {
                // Project List
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(availableProjects) { project in
                            ProjectSelectionRow(
                                project: project,
                                onSelect: { selectProject(project) }
                            )

                            if project.id != availableProjects.last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.1))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Task Details Form

    private var taskDetailsForm: some View {
        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing3) {
                // Selected Project Display
                if let project = selectedProject {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PROJECT")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.title)
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                Text(project.effectiveClientName)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }

                            Spacer()

                            Button(action: { selectedProject = nil }) {
                                Text("CHANGE")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                        }
                        .padding(12)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }

                // Task Type Section
                taskTypeSection

                // Notes Section
                notesSection

                // Team Section
                teamSelectionSection

                // Schedule Section
                scheduleSection
            }
            .padding(OPSStyle.Layout.spacing3)
        }
    }

    private var taskTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TASK TYPE *")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Menu {
                Button("Create New Type") {
                    showingCreateTaskType = true
                }

                Divider()

                ForEach(availableTaskTypes) { taskType in
                    Button(action: { selectedTaskTypeId = taskType.id }) {
                        HStack {
                            Circle()
                                .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                                .frame(width: 10, height: 10)

                            if let icon = taskType.icon {
                                Image(systemName: icon)
                                    .foregroundColor(Color(hex: taskType.color))
                            }

                            Text(taskType.display)

                            if selectedTaskTypeId == taskType.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    if let selectedType = selectedTaskType {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: selectedType.color) ?? OPSStyle.Colors.primaryAccent)
                                .frame(width: 10, height: 10)

                            if let icon = selectedType.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: selectedType.color))
                            }

                            Text(selectedType.display)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    } else {
                        Text("Select task type")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(12)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextEditor(text: $taskNotes)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(minHeight: 80)
                .padding(8)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    private var teamSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ASSIGN TEAM MEMBERS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(selectedProject?.teamMembers.sorted { $0.firstName < $1.firstName } ?? []) { member in
                        UserChip(
                            user: member,
                            isSelected: selectedTeamMemberIds.contains(member.id)
                        ) {
                            toggleTeamMember(member.id)
                        }
                    }
                }
            }

            if !selectedTeamMemberIds.isEmpty {
                Text("\(selectedTeamMemberIds.count) member\(selectedTeamMemberIds.count == 1 ? "" : "s") assigned")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCHEDULE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Toggle(isOn: $allDay) {
                Text("All-Day Task")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .tint(OPSStyle.Colors.primaryAccent)

            if !allDay {
                DatePicker(
                    "Start",
                    selection: $startDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)

                DatePicker(
                    "End",
                    selection: $endDate,
                    in: startDate...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)

                // Auto-calculated duration
                HStack {
                    Text("Duration")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    Text(formattedDuration)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.vertical, 8)
            } else {
                DatePicker(
                    "Date",
                    selection: $startDate,
                    displayedComponents: .date
                )
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Helper Methods

    private func selectProject(_ project: Project) {
        if project.eventType == .project {
            selectedProject = project
            showingConversionAlert = true
        } else {
            selectedProject = project
        }
    }

    private func toggleTeamMember(_ memberId: String) {
        if selectedTeamMemberIds.contains(memberId) {
            selectedTeamMemberIds.remove(memberId)
        } else {
            selectedTeamMemberIds.insert(memberId)
        }
    }

    private func convertProjectScheduling() {
        guard let project = selectedProject else { return }

        Task {
            await MainActor.run {
                project.eventType = .task
                project.needsSync = true

                // Deactivate project calendar event
                if let event = project.primaryCalendarEvent, event.type == .project {
                    event.active = false
                }

                do {
                    try modelContext.save()
                } catch {
                    print("Error converting project scheduling: \(error)")
                }
            }

            dataController.syncManager?.triggerBackgroundSync()
        }
    }

    private func createTask() {
        guard let project = selectedProject,
              let taskType = selectedTaskType else { return }

        isCreating = true

        Task {
            do {
                let newTask = ProjectTask(
                    id: UUID().uuidString,
                    projectId: project.id,
                    taskTypeId: taskType.id,
                    companyId: project.companyId,
                    status: .scheduled
                )

                // Set notes and sync flag
                newTask.taskNotes = taskNotes.isEmpty ? nil : taskNotes
                newTask.needsSync = true

                // Add team members
                let members = project.teamMembers.filter { selectedTeamMemberIds.contains($0.id) }
                newTask.teamMembers = Array(members)

                // Create calendar event for task-based projects
                if project.eventType == .task {
                    let calendarEvent = CalendarEvent(
                        id: UUID().uuidString,
                        projectId: project.id,
                        companyId: project.companyId,
                        title: newTask.displayTitle,
                        startDate: startDate,
                        endDate: allDay ? startDate : endDate,
                        color: newTask.effectiveColor,
                        type: .task,
                        active: true
                    )
                    calendarEvent.taskId = newTask.id
                    modelContext.insert(calendarEvent)
                }

                await MainActor.run {
                    project.tasks.append(newTask)
                    modelContext.insert(newTask)

                    do {
                        try modelContext.save()
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                        showingError = true
                        isCreating = false
                    }
                }

                dataController.syncManager?.triggerBackgroundSync()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isCreating = false
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct ProjectSelectionRow: View {
    let project: Project
    let onSelect: () -> Void

    var badgeText: String {
        if project.eventType == .project {
            return "PROJECT-BASED"
        } else {
            let taskCount = project.tasks.count
            return taskCount == 0 ? "NO TASKS" : "\(taskCount) TASK\(taskCount == 1 ? "" : "S")"
        }
    }

    var badgeColor: Color {
        project.eventType == .project
            ? Color.orange
            : OPSStyle.Colors.primaryAccent
    }

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(project.effectiveClientName)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()

                // Scheduling Mode Badge
                Text(badgeText)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badgeColor)
                    .cornerRadius(4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - User Chip Component
struct UserChip: View {
    let user: User
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                } else {
                    Circle()
                        .stroke(OPSStyle.Colors.primaryText.opacity(0.3), lineWidth: 1)
                        .frame(width: 14, height: 14)
                }

                Text(user.fullName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? OPSStyle.Colors.primaryAccent.opacity(0.1) : OPSStyle.Colors.cardBackgroundDark)
                    .stroke(
                        isSelected ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}