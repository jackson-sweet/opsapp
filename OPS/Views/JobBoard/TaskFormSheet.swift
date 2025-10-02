//
//  TaskFormSheet.swift
//  OPS
//
//  Created by Assistant on 2025-09-29.
//

import SwiftUI
import SwiftData

struct TaskFormSheet: View {
    enum Mode {
        case create
        case edit(ProjectTask)

        var isCreate: Bool {
            if case .create = self { return true }
            return false
        }

        var task: ProjectTask? {
            if case .edit(let task) = self { return task }
            return nil
        }
    }

    let mode: Mode
    let onSave: (ProjectTask) -> Void
    let preselectedProjectId: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Query private var allProjects: [Project]
    @Query private var allTaskTypes: [TaskType]
    @Query private var allTeamMembers: [TeamMember]

    private var uniqueTeamMembers: [TeamMember] {
        var seen = Set<String>()
        return allTeamMembers.filter { member in
            guard !seen.contains(member.id) else { return false }
            seen.insert(member.id)
            return true
        }
    }

    @State private var selectedProjectId: String?
    @State private var selectedTaskTypeId: String?
    @State private var newTaskTypeName: String = ""
    @State private var taskNotes: String = ""
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var showingScheduler = false
    @State private var startDate: Date? = nil
    @State private var endDate: Date? = nil
    @State private var showingCreateTaskType = false
    @State private var projectSearchText: String = ""
    @State private var showingProjectSuggestions = false

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private var isValid: Bool {
        selectedProjectId != nil && selectedTaskTypeId != nil
    }

    private var selectedProject: Project? {
        guard let id = selectedProjectId else { return nil }
        return allProjects.first { $0.id == id }
    }

    private var selectedTaskType: TaskType? {
        guard let id = selectedTaskTypeId else { return nil }
        return allTaskTypes.first { $0.id == id }
    }

    private var filteredProjects: [Project] {
        if projectSearchText.isEmpty {
            return allProjects.sorted(by: { $0.title < $1.title })
        }
        return allProjects.filter {
            $0.title.localizedCaseInsensitiveContains(projectSearchText) ||
            $0.effectiveClientName.localizedCaseInsensitiveContains(projectSearchText)
        }.sorted(by: { $0.title < $1.title })
    }

    init(mode: Mode, preselectedProjectId: String? = nil, onSave: @escaping (ProjectTask) -> Void) {
        self.mode = mode
        self.preselectedProjectId = preselectedProjectId
        self.onSave = onSave

        if case .edit(let task) = mode {
            _selectedProjectId = State(initialValue: task.projectId)
            _selectedTaskTypeId = State(initialValue: task.taskTypeId)
            _taskNotes = State(initialValue: task.taskNotes ?? "")
            _selectedTeamMemberIds = State(initialValue: Set(task.getTeamMemberIds()))
            _startDate = State(initialValue: task.calendarEvent?.startDate)
            _endDate = State(initialValue: task.calendarEvent?.endDate)
        } else if let projectId = preselectedProjectId {
            _selectedProjectId = State(initialValue: projectId)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        projectSection
                        taskTypeSection
                        teamSection
                        datesSection
                        notesSection
                    }
                    .padding()
                    .padding(.bottom, 100)
                }

                if isSaving {
                    savingOverlay
                }
            }
            .navigationTitle(mode.isCreate ? "NEW TASK" : "EDIT TASK")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                }.foregroundColor(OPSStyle.Colors.primaryAccent),
                trailing: Button("Save") {
                    saveTask()
                }
                .foregroundColor(isValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                .disabled(!isValid || isSaving)
            )
        }
        .sheet(isPresented: $showingScheduler) {
            if let project = selectedProject, let startDate = startDate, let endDate = endDate {
                CalendarSchedulerSheet(
                    isPresented: $showingScheduler,
                    itemType: .task(ProjectTask(
                        id: UUID().uuidString,
                        projectId: project.id,
                        taskTypeId: selectedTaskTypeId ?? "",
                        companyId: dataController.currentUser?.companyId ?? "",
                        status: .scheduled
                    )),
                    currentStartDate: startDate,
                    currentEndDate: endDate,
                    onScheduleUpdate: { newStart, newEnd in
                        self.startDate = newStart
                        self.endDate = newEnd
                    }
                )
                .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingCreateTaskType) {
            TaskTypeFormSheet { _ in }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .onAppear {
            if let selectedProject = selectedProject {
                projectSearchText = selectedProject.title
            }
        }
    }

    // MARK: - Sections

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROJECT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    TextField("Search or select project", text: $projectSearchText, onEditingChanged: { isEditing in
                        showingProjectSuggestions = isEditing
                    })
                    .padding()
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .font(OPSStyle.Typography.body)

                    if showingProjectSuggestions && !filteredProjects.isEmpty {
                        VStack(spacing: 1) {
                            ForEach(filteredProjects.prefix(5)) { project in
                                Button(action: {
                                    selectedProjectId = project.id
                                    projectSearchText = project.title
                                    showingProjectSuggestions = false
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(project.title)
                                                .font(OPSStyle.Typography.bodyBold)
                                                .foregroundColor(OPSStyle.Colors.primaryText)
                                            Text(project.effectiveClientName)
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                        }
                                        Spacer()
                                    }
                                    .padding()
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                        .padding(.top, 4)
                    }
                }

                if let project = selectedProject, !showingProjectSuggestions {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.title)
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Text(project.effectiveClientName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        Spacer()
                        Button(action: {
                            selectedProjectId = nil
                            projectSearchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .padding()
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
    }

    private var taskTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TASK TYPE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                Button(action: {
                    showingCreateTaskType = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("NEW TYPE")
                    }
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }

            Menu {
                ForEach(allTaskTypes.sorted(by: { $0.display < $1.display })) { taskType in
                    Button(action: {
                        selectedTaskTypeId = taskType.id
                    }) {
                        HStack {
                            if let icon = taskType.icon {
                                Image(systemName: icon)
                            }
                            Text(taskType.display)
                            if selectedTaskTypeId == taskType.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    if let taskType = selectedTaskType {
                        HStack(spacing: 12) {
                            if let icon = taskType.icon {
                                Image(systemName: icon)
                                    .foregroundColor(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                            }
                            Text(taskType.display)
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    } else {
                        Text("Select Task Type")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }

    private var teamSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEAM MEMBERS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ScrollView {
                VStack(spacing: 1) {
                    ForEach(uniqueTeamMembers) { member in
                        Button(action: {
                            if selectedTeamMemberIds.contains(member.id) {
                                selectedTeamMemberIds.remove(member.id)
                            } else {
                                selectedTeamMemberIds.insert(member.id)
                            }
                        }) {
                            HStack {
                                Image(systemName: selectedTeamMemberIds.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedTeamMemberIds.contains(member.id) ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)

                                Text(member.fullName)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                Spacer()

                                Text(member.role)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .frame(maxHeight: 300)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DATES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Button(action: {
                if startDate == nil {
                    startDate = Date()
                    endDate = Date().addingTimeInterval(86400)
                }
                showingScheduler = true
            }) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    if let startDate = startDate, let endDate = endDate {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDate(startDate))
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Text("to \(formatDate(endDate))")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    } else {
                        Text("Tap to Schedule")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .disabled(selectedProjectId == nil)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOTES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextEditor(text: $taskNotes)
                .frame(minHeight: 100)
                .padding(12)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .scrollContentBackground(.hidden)
        }
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text("Creating Task...")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Actions

    private func saveTask() {
        guard isValid else { return }

        isSaving = true

        Task {
            do {
                let task: ProjectTask

                if case .edit(let existingTask) = mode {
                    task = existingTask
                } else {
                    task = ProjectTask(
                        id: UUID().uuidString,
                        projectId: selectedProjectId!,
                        taskTypeId: selectedTaskTypeId!,
                        companyId: dataController.currentUser?.companyId ?? "",
                        status: .scheduled
                    )
                    modelContext.insert(task)
                }

                task.taskNotes = taskNotes.isEmpty ? nil : taskNotes
                task.setTeamMemberIds(Array(selectedTeamMemberIds))

                if let startDate = startDate, let endDate = endDate {
                    if let calendarEvent = task.calendarEvent {
                        calendarEvent.startDate = startDate
                        calendarEvent.endDate = endDate
                        let daysDiff = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
                        calendarEvent.duration = daysDiff + 1
                        calendarEvent.needsSync = true
                    } else {
                        let newEvent = CalendarEvent.fromTask(task, startDate: startDate, endDate: endDate)
                        task.calendarEvent = newEvent
                        modelContext.insert(newEvent)
                    }
                }

                task.needsSync = true

                try modelContext.save()

                await MainActor.run {
                    isSaving = false
                    onSave(task)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}