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
    @State private var showingTeamPicker = false

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isEditingNotes = false
    @State private var tempNotes: String = ""

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
                        // Live preview card at top
                        previewCard

                        // TASK DETAILS section - ALL FIELDS IN ONE SECTION
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TASK DETAILS")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            VStack(spacing: 16) {
                                projectField
                                taskTypeField
                                teamField
                                datesField
                                notesField
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                        }
                    }
                    .padding()
                    .padding(.bottom, 100)
                }

                if isSaving {
                    savingOverlay
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                ToolbarItem(placement: .principal) {
                    Text(mode.isCreate ? "CREATE TASK" : "EDIT TASK")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(mode.isCreate ? "CREATE" : "SAVE") {
                        saveTask()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(isValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .disabled(!isValid || isSaving)
                }
            }
            .interactiveDismissDisabled()
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
                        status: .booked
                    )),
                    currentStartDate: startDate,
                    currentEndDate: endDate,
                    onScheduleUpdate: { newStart, newEnd in
                        self.startDate = newStart
                        self.endDate = newEnd
                    },
                    preselectedTeamMemberIds: selectedTeamMemberIds.isEmpty ? nil : selectedTeamMemberIds
                )
                .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingCreateTaskType) {
            TaskTypeFormSheet { newTaskType in
                selectedTaskTypeId = newTaskType.id
            }
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingTeamPicker) {
            TeamMemberPickerSheet(
                selectedTeamMemberIds: $selectedTeamMemberIds,
                allTeamMembers: uniqueTeamMembers
            )
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

    // MARK: - Preview Card
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // "PREVIEW" label
            Text("PREVIEW")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            // Preview card with live updates
            HStack(spacing: 0) {
                // Colored left border (4pt width) - task type color
                Rectangle()
                    .fill(selectedTaskType.map { Color(hex: $0.color) ?? OPSStyle.Colors.primaryAccent } ?? OPSStyle.Colors.primaryAccent)
                    .frame(width: 4)

                HStack(alignment: .top, spacing: 12) {
                    // Task content
                    VStack(alignment: .leading, spacing: 6) {
                        // Task type name (uppercase, bold)
                        Text(selectedTaskType?.display.uppercased() ?? "SELECT TASK TYPE")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(selectedTaskType != nil ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)

                        // Project name (if selected)
                        if let project = selectedProject {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.system(size: 12))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                Text(project.title)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }

                        // Scheduled date (if selected)
                        if let startDate = startDate {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 12))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                Text(formatDate(startDate))
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }

                        // Team member avatars (if selected)
                        if !selectedTeamMemberIds.isEmpty {
                            let selectedMembers = uniqueTeamMembers.filter { selectedTeamMemberIds.contains($0.id) }
                            HStack(spacing: -8) {
                                ForEach(selectedMembers.prefix(3), id: \.id) { member in
                                    UserAvatar(teamMember: member, size: 24)
                                }
                                if selectedMembers.count > 3 {
                                    Text("+\(selectedMembers.count - 3)")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                        .padding(.leading, 4)
                                }
                            }
                        }
                    }

                    Spacer()

                    // Status badge (top-right) - always show "BOOKED" for new tasks
                    Text("BOOKED")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(OPSStyle.Colors.primaryAccent.opacity(0.2))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.7)) // Semi-transparent to indicate preview
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
        }
    }

    private var projectField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROJECT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    TextField("Search or select project", text: $projectSearchText, onEditingChanged: { isEditing in
                        showingProjectSuggestions = isEditing
                    })
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.clear)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .font(OPSStyle.Typography.body)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.words)

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

    private var taskTypeField: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title and "NEW TYPE" button
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

            // Task type picker with colored left border
            HStack(spacing: 0) {
                // Colored left border (4pt width) - task type color
                Rectangle()
                    .fill(selectedTaskType.map { Color(hex: $0.color) ?? OPSStyle.Colors.primaryAccent } ?? Color.white.opacity(0.25))
                    .frame(width: 4)

                Menu {
                    ForEach(allTaskTypes.sorted(by: { $0.display < $1.display })) { taskType in
                        Button(action: {
                            selectedTaskTypeId = taskType.id
                        }) {
                            HStack {
                                // Colored dot in menu
                                Circle()
                                    .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                                    .frame(width: 12, height: 12)
                                Text(taskType.display.uppercased())
                                if selectedTaskTypeId == taskType.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        if let taskType = selectedTaskType {
                            Text(taskType.display.uppercased())
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
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
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
        }
    }

    private var teamField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ASSIGN TEAM (OPTIONAL)")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Team member picker showing avatars
            Button(action: {
                showingTeamPicker = true
            }) {
            HStack {
                if selectedTeamMemberIds.isEmpty {
                    Text("Select team members")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                } else {
                    // Show selected team member avatars
                    let selectedMembers = uniqueTeamMembers.filter { selectedTeamMemberIds.contains($0.id) }
                    HStack(spacing: -8) {
                        ForEach(selectedMembers.prefix(3), id: \.id) { member in
                            UserAvatar(teamMember: member, size: 24)
                        }
                        if selectedMembers.count > 3 {
                            Text("+\(selectedMembers.count - 3)")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.leading, 8)
                        }
                    }

                    Text("\(selectedMembers.count) member\(selectedMembers.count == 1 ? "" : "s")")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.leading, 12)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
        }
        }
    }

    private var datesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DATES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Button(action: {
                    // Ensure dates are set before showing scheduler
                    if startDate == nil {
                        startDate = Date()
                    }
                    if endDate == nil {
                        endDate = Date().addingTimeInterval(86400)
                    }

                    // Delay to ensure state updates before sheet presentation
                    DispatchQueue.main.async {
                        showingScheduler = true
                    }
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
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.clear)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                }
                .disabled(selectedProjectId == nil)
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 12) {
                ZStack(alignment: .topLeading) {
                    // Placeholder text
                    if (isEditingNotes ? tempNotes : taskNotes).isEmpty {
                        Text("Add notes...")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.top, 20)
                            .padding(.leading, 16)
                    }

                    TextEditor(text: isEditingNotes ? $tempNotes : $taskNotes)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(minHeight: 100, maxHeight: 200)
                        .padding(12)
                        .background(Color.clear)
                        .scrollContentBackground(.hidden)
                        .onTapGesture {
                            if !isEditingNotes {
                                tempNotes = taskNotes
                                isEditingNotes = true
                            }
                        }
                }
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )

                if isEditingNotes {
                    HStack(spacing: 16) {
                        Spacer()

                        Button("CANCEL") {
                            tempNotes = ""
                            isEditingNotes = false
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                        Button("SAVE") {
                            taskNotes = tempNotes
                            isEditingNotes = false
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
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
            let task: ProjectTask

            do {
                if case .edit(let existingTask) = mode {
                    task = existingTask
                } else {
                    let taskColor = selectedTaskType?.color ?? "#59779F"
                    print("[TASK_CREATE] 🎨 Creating task with color: \(taskColor) from taskType: \(selectedTaskType?.display ?? "nil")")

                    task = ProjectTask(
                        id: UUID().uuidString,
                        projectId: selectedProjectId!,
                        taskTypeId: selectedTaskTypeId!,
                        companyId: dataController.currentUser?.companyId ?? "",
                        status: .booked,
                        taskColor: taskColor
                    )

                    print("[TASK_CREATE] ✅ Task created locally with ID: \(task.id), color: \(task.taskColor)")

                    if let project = selectedProject {
                        task.project = project
                    }

                    if let taskType = selectedTaskType {
                        task.taskType = taskType
                    }

                    modelContext.insert(task)
                }

                task.taskNotes = taskNotes.isEmpty ? nil : taskNotes
                task.setTeamMemberIds(Array(selectedTeamMemberIds))

                if let calendarEvent = task.calendarEvent {
                    calendarEvent.title = task.project?.effectiveClientName ?? task.displayTitle
                    calendarEvent.startDate = startDate
                    calendarEvent.endDate = endDate
                    if let start = startDate, let end = endDate {
                        let daysDiff = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
                        calendarEvent.duration = daysDiff + 1
                    }
                } else {
                    let newEvent = CalendarEvent.fromTask(task, startDate: startDate, endDate: endDate)
                    task.calendarEvent = newEvent
                    modelContext.insert(newEvent)
                }

                task.needsSync = true
                if let calendarEvent = task.calendarEvent {
                    calendarEvent.needsSync = true
                }

                try modelContext.save()
                print("[TASK_FORM] ✅ Task saved locally")

            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save task locally: \(error.localizedDescription)"
                    showingError = true
                }
                return
            }

            var savedOffline = false

            do {
                try await Task.timeout(seconds: 5) {
                    print("[TASK_FORM] 🔵 Creating task on Bubble...")
                    let taskDTO = TaskDTO.from(task)
                    let createdTask = try await dataController.apiService.createTask(taskDTO)
                    print("[TASK_FORM] ✅ Task created on Bubble with ID: \(createdTask.id)")

                    task.id = createdTask.id
                    task.needsSync = false
                    task.lastSyncedAt = Date()

                    if let calendarEvent = task.calendarEvent {
                        print("[TASK_FORM] 📅 Creating calendar event on Bubble...")
                        let dateFormatter = ISO8601DateFormatter()
                        // Task-only scheduling migration: type parameter removed
                        let eventDTO = CalendarEventDTO(
                            id: calendarEvent.id,
                            color: calendarEvent.color,
                            companyId: calendarEvent.companyId,
                            projectId: calendarEvent.projectId,
                            taskId: createdTask.id,
                            duration: Double(calendarEvent.duration),
                            endDate: calendarEvent.endDate.map { dateFormatter.string(from: $0) },
                            startDate: calendarEvent.startDate.map { dateFormatter.string(from: $0) },
                            teamMembers: calendarEvent.getTeamMemberIds(),
                            title: calendarEvent.title,
                            createdDate: nil,
                            modifiedDate: nil,
                            deletedAt: nil
                        )

                        // Create and link calendar event (automatically links to task based on type)
                        let createdEvent = try await dataController.apiService.createAndLinkCalendarEvent(eventDTO)
                        calendarEvent.id = createdEvent.id
                        task.calendarEventId = createdEvent.id
                        calendarEvent.needsSync = false
                        calendarEvent.lastSyncedAt = Date()
                        print("[TASK_FORM] ✅ Calendar event created and linked with ID: \(createdEvent.id)")
                    }

                    try modelContext.save()
                    print("[TASK_FORM] ✅ Task and calendar event saved to SwiftData")

                    if let project = task.project {
                        print("[TASK_FORM] 📅 Project dates automatically computed from tasks...")

                        print("[TASK_FORM] 🔄 Syncing project dates to Bubble...")
                        try await dataController.apiService.updateProjectDates(
                            projectId: project.id,
                            startDate: project.startDate,
                            endDate: project.endDate
                        )
                        print("[TASK_FORM] ✅ Project dates update complete")

                        print("[TASK_FORM] 👥 Updating project team members from tasks...")
                        await MainActor.run {
                            project.updateTeamMembersFromTasks(in: modelContext)
                            try? modelContext.save()
                        }

                        let teamMemberIds = project.getTeamMemberIds()
                        print("[TASK_FORM] 🔄 Syncing project team members to Bubble...")
                        print("[TASK_FORM] Team member IDs: \(teamMemberIds)")
                        try await dataController.apiService.updateProjectTeamMembers(
                            projectId: project.id,
                            teamMemberIds: teamMemberIds
                        )
                        print("[TASK_FORM] ✅ Project team members update complete")
                    }
                }

            } catch is CancellationError {
                // Timeout error - network is slow or unavailable
                savedOffline = true
                print("[TASK_FORM] ⏱️ Network timeout - task saved offline")
            } catch let error as URLError {
                // Network-related errors (no connection, timeout, etc.)
                savedOffline = true
                print("[TASK_FORM] ❌ Network error - task saved offline: \(error)")
            } catch let error as APIError {
                // API errors (validation, limits, server errors) - show actual error message
                print("[TASK_FORM] ❌ API error during task creation: \(error)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isSaving = false
                }
                return
            } catch {
                // Other unexpected errors
                print("[TASK_FORM] ❌ Unexpected error during task creation: \(error)")
                await MainActor.run {
                    errorMessage = "Failed to create task: \(error.localizedDescription)"
                    showingError = true
                    isSaving = false
                }
                return
            }

            await MainActor.run {
                if savedOffline {
                    // Warning haptic feedback for offline save
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.warning)

                    errorMessage = "WEAK/NO CONNECTION, QUEUING FOR LATER SYNC. SAVED LOCALLY"
                    showingError = true
                    isSaving = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        onSave(task)
                        dismiss()
                    }
                } else {
                    // Success haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    isSaving = false
                    onSave(task)

                    // Brief delay for graceful dismissal
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
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

// MARK: - Team Member Picker Sheet
struct TeamMemberPickerSheet: View {
    @Binding var selectedTeamMemberIds: Set<String>
    let allTeamMembers: [TeamMember]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(allTeamMembers) { member in
                            Button(action: {
                                if selectedTeamMemberIds.contains(member.id) {
                                    selectedTeamMemberIds.remove(member.id)
                                } else {
                                    selectedTeamMemberIds.insert(member.id)
                                }
                            }) {
                                HStack(spacing: 12) {
                                    // Checkbox
                                    Image(systemName: selectedTeamMemberIds.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedTeamMemberIds.contains(member.id) ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                                        .font(.system(size: 20))

                                    // Avatar
                                    UserAvatar(teamMember: member, size: 40)

                                    // Name and role
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(member.fullName)
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(OPSStyle.Colors.primaryText)

                                        Text(member.role)
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
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SELECT TEAM MEMBERS")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("DONE") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }
}

extension Task where Failure == Error {
    static func timeout(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> Success) async throws -> Success {
        try await withThrowingTaskGroup(of: Success.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task<Never, Never>.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw _Concurrency.CancellationError()
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}