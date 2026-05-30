//
//  TaskFormSheet.swift
//  OPS
//
//  Created by Assistant on 2025-09-29.
//

import SwiftUI
import SwiftData
import Supabase

struct TaskFormSheet: View {
    enum Mode {
        case create
        case edit(ProjectTask)
        case draft(LocalTask?) // For creating tasks without a project yet
        case editDraft(LocalTask)

        var isCreate: Bool {
            if case .create = self { return true }
            if case .draft = self { return true }
            return false
        }

        var isDraft: Bool {
            if case .draft = self { return true }
            if case .editDraft = self { return true }
            return false
        }

        var task: ProjectTask? {
            if case .edit(let task) = self { return task }
            return nil
        }

        var localTask: LocalTask? {
            if case .draft(let task) = self { return task }
            if case .editDraft(let task) = self { return task }
            return nil
        }
    }

    let mode: Mode
    let onSave: ((ProjectTask) -> Void)?
    let onSaveDraft: ((LocalTask) -> Void)?
    let preselectedProjectId: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase
    // Wizard state so the project-lifecycle / task-flow banner + instruction
    // bar stay visible when this sheet is presented over the root view.
    @Environment(\.wizardStateManager) private var wizardStateManager
    @Query private var allProjects: [Project]
    @Query private var allTaskTypes: [TaskType]
    /// Team members as full `User` objects. Using `User` (not the lightweight
    /// `TeamMember`) means `UserAvatar` has access to `profileImageData`,
    /// `profileImageURL`, and `userColor` — so rows render real avatars
    /// instead of falling back to initials when the remote URL is slow or
    /// the user only has locally-cached image bytes.
    @State private var fetchedTeamMembers: [User] = []

    // Tutorial mode filtering - only show DEMO_ entities when in tutorial
    private var availableProjects: [Project] {
        if tutorialMode {
            return allProjects.filter { $0.id.hasPrefix("DEMO_") }
        }
        return allProjects
    }

    private var availableTaskTypes: [TaskType] {
        if tutorialMode {
            return allTaskTypes.filter { $0.id.hasPrefix("DEMO_") }
        }
        return allTaskTypes
    }

    private var availableTeamMembers: [User] {
        if tutorialMode {
            return fetchedTeamMembers.filter { $0.id.hasPrefix("DEMO_") }
        }
        return fetchedTeamMembers
    }

    private var uniqueTeamMembers: [User] {
        var seen = Set<String>()
        return availableTeamMembers.filter { member in
            guard !seen.contains(member.id) else { return false }
            seen.insert(member.id)
            return true
        }
    }

    /// Bug 9d5c2535 — team members sorted by who has most recently been
    /// assigned to the currently-selected task type. Members never assigned
    /// to this type fall to the bottom alphabetically. Fallback to plain
    /// alphabetical when no task type is selected (e.g. user opens the
    /// team picker before picking a type).
    private var recencyOrderedTeamMembers: [User] {
        let alphaSorted = uniqueTeamMembers.sorted {
            $0.fullName.localizedCompare($1.fullName) == .orderedAscending
        }

        guard let taskTypeId = selectedTaskTypeId, !taskTypeId.isEmpty,
              let companyId = dataController.currentUser?.companyId else {
            return alphaSorted
        }

        let recentIds = dataController.recentTeamMemberIds(
            forTaskType: taskTypeId,
            companyId: companyId
        )
        guard !recentIds.isEmpty else { return alphaSorted }

        let recencyIndex = Dictionary(
            uniqueKeysWithValues: recentIds.enumerated().map { ($1, $0) }
        )
        let recentSet = Set(recentIds)

        let recentTier = alphaSorted
            .filter { recentSet.contains($0.id) }
            .sorted { lhs, rhs in
                (recencyIndex[lhs.id] ?? Int.max) < (recencyIndex[rhs.id] ?? Int.max)
            }
        let restTier = alphaSorted.filter { !recentSet.contains($0.id) }
        return recentTier + restTier
    }

    /// Set of team-member IDs that qualify as "recent" for the active task
    /// type. Used by the picker to draw a RECENT tag on those rows.
    private var recentTeamMemberIdSet: Set<String> {
        guard let taskTypeId = selectedTaskTypeId, !taskTypeId.isEmpty,
              let companyId = dataController.currentUser?.companyId else {
            return []
        }
        return Set(dataController.recentTeamMemberIds(
            forTaskType: taskTypeId,
            companyId: companyId
        ))
    }

    /// Bug 9d5c2535 — task types sorted by most-recently used across the
    /// company, with a divider between recent and the alphabetical rest.
    private var recencyOrderedTaskTypes: [TaskType] {
        let alphaSorted = availableTaskTypes.sorted { $0.display < $1.display }

        guard let companyId = dataController.currentUser?.companyId else {
            return alphaSorted
        }

        let recentIds = dataController.recentTaskTypeIds(companyId: companyId)
        guard !recentIds.isEmpty else { return alphaSorted }

        let recencyIndex = Dictionary(
            uniqueKeysWithValues: recentIds.enumerated().map { ($1, $0) }
        )
        let recentSet = Set(recentIds)

        let recentTier = alphaSorted
            .filter { recentSet.contains($0.id) }
            .sorted { lhs, rhs in
                (recencyIndex[lhs.id] ?? Int.max) < (recencyIndex[rhs.id] ?? Int.max)
            }
        let restTier = alphaSorted.filter { !recentSet.contains($0.id) }
        return recentTier + restTier
    }

    /// Number of "recent" task types so the picker knows where to draw
    /// the divider between recent and alphabetical-rest tiers.
    private var recentTaskTypeCount: Int {
        guard let companyId = dataController.currentUser?.companyId else { return 0 }
        let recentSet = Set(dataController.recentTaskTypeIds(companyId: companyId))
        return availableTaskTypes.filter { recentSet.contains($0.id) }.count
    }

    @State private var selectedProjectId: String?
    @State private var selectedTaskTypeId: String?
    @State private var newTaskTypeName: String = ""
    @State private var taskNotes: String = ""
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var showingScheduler = false
    @State private var startDate: Date? = nil
    @State private var endDate: Date? = nil
    @State private var datesExistedBeforeScheduler = false  // Track if dates existed before opening scheduler
    @State private var schedulerConfirmed = false  // Track if scheduler was confirmed vs cancelled
    @State private var showingCreateTaskType = false
    @State private var showingTaskTypeList = false
    @State private var projectSearchText: String = ""
    @State private var showingProjectSuggestions = false
    @State private var showingTeamPicker = false
    @State private var selectedStatus: TaskStatus = .active

    @State private var dependencyOverrides: [TaskTypeDependency]? = nil
    @State private var showingDependencyOverride = false

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @FocusState private var focusedField: TaskFormField?
    @State private var tempNotes: String = ""

    enum TaskFormField {
        case notes
    }

    private var isValid: Bool {
        // In draft mode, only task type is required
        if mode.isDraft {
            return selectedTaskTypeId != nil
        }
        // In regular mode, both project and task type are required
        return selectedProjectId != nil && selectedTaskTypeId != nil
    }

    // MARK: - Tutorial Phase Control

    /// Whether task type field is enabled for current tutorial phase
    private var isTaskTypeFieldEnabled: Bool {
        guard tutorialMode else { return true }
        return tutorialPhase == .taskFormType
    }

    /// Whether crew field is enabled for current tutorial phase
    private var isCrewFieldEnabled: Bool {
        guard tutorialMode else { return true }
        return tutorialPhase == .taskFormCrew
    }

    /// Whether dates field is enabled for current tutorial phase
    private var isDatesFieldEnabled: Bool {
        guard tutorialMode else { return true }
        return tutorialPhase == .taskFormDate
    }

    /// Whether DONE button is enabled for current tutorial phase
    private var isDoneButtonEnabled: Bool {
        guard tutorialMode else { return true }
        return tutorialPhase == .taskFormDone
    }

    // MARK: - Tutorial Highlight States

    @State private var tutorialHighlightPulse: Bool = false

    /// Highlight state for task type field
    private var taskTypeHighlight: TutorialInputHighlight {
        let isHighlighted = tutorialMode && tutorialPhase == .taskFormType
        return TutorialInputHighlight(isHighlighted: isHighlighted, animatePulse: tutorialHighlightPulse)
    }

    /// Highlight state for crew field
    private var crewHighlight: TutorialInputHighlight {
        let isHighlighted = tutorialMode && tutorialPhase == .taskFormCrew
        return TutorialInputHighlight(isHighlighted: isHighlighted, animatePulse: tutorialHighlightPulse)
    }

    /// Highlight state for dates field
    private var datesHighlight: TutorialInputHighlight {
        let isHighlighted = tutorialMode && tutorialPhase == .taskFormDate
        return TutorialInputHighlight(isHighlighted: isHighlighted, animatePulse: tutorialHighlightPulse)
    }

    private var selectedProject: Project? {
        guard let id = selectedProjectId else { return nil }
        return allProjects.first { $0.id == id }
    }

    // MARK: - Project Selection Control (Non-Tutorial Mode)

    /// Whether fields should be disabled because no project is selected (non-draft mode only)
    private var needsProjectSelection: Bool {
        !mode.isDraft && selectedProjectId == nil
    }

    /// Whether the project field should be highlighted (when no project selected)
    private var shouldHighlightProjectField: Bool {
        !tutorialMode && needsProjectSelection
    }

    private var selectedTaskType: TaskType? {
        guard let id = selectedTaskTypeId else { return nil }
        return allTaskTypes.first { $0.id == id }
    }

    private var filteredProjects: [Project] {
        if projectSearchText.isEmpty {
            return availableProjects.sorted(by: { $0.title < $1.title })
        }
        let q = projectSearchText
        return availableProjects.filter { project in
            if project.title.localizedCaseInsensitiveContains(q) { return true }
            if project.effectiveClientName.localizedCaseInsensitiveContains(q) { return true }
            // Match on sub-client contacts so the task picker surfaces the
            // project when users search for a site contact by name.
            if let subClients = project.client?.subClients {
                for sub in subClients where sub.deletedAt == nil {
                    if sub.name.localizedCaseInsensitiveContains(q) { return true }
                    if sub.title?.localizedCaseInsensitiveContains(q) == true { return true }
                    if sub.email?.localizedCaseInsensitiveContains(q) == true { return true }
                    if sub.phoneNumber?.localizedCaseInsensitiveContains(q) == true { return true }
                }
            }
            return false
        }.sorted(by: { $0.title < $1.title })
    }

    // Regular init for ProjectTask mode.
    //
    // `prefilledTaskTypeId` / `prefilledTeamMemberIds` are optional create-mode
    // hints — used by QuickAddSuggestionsRail's long-press "Edit Before
    // Adding" path so the form opens with the suggestion preselected. Ignored
    // in edit mode (the task's own values win).
    init(
        mode: Mode,
        preselectedProjectId: String? = nil,
        prefilledTaskTypeId: String? = nil,
        prefilledTeamMemberIds: [String]? = nil,
        onSave: @escaping (ProjectTask) -> Void
    ) {
        self.mode = mode
        self.preselectedProjectId = preselectedProjectId
        self.onSave = onSave
        self.onSaveDraft = nil

        if case .edit(let task) = mode {
            _selectedProjectId = State(initialValue: task.projectId)
            _selectedTaskTypeId = State(initialValue: task.taskTypeId)
            _taskNotes = State(initialValue: task.taskNotes ?? "")
            _selectedTeamMemberIds = State(initialValue: Set(task.getTeamMemberIds()))
            _startDate = State(initialValue: task.startDate)
            _endDate = State(initialValue: task.endDate)
            _selectedStatus = State(initialValue: task.status)
            _dependencyOverrides = State(initialValue: task.dependencyOverridesJSON != nil ? task.effectiveDependencies : nil)
        } else {
            if let projectId = preselectedProjectId {
                _selectedProjectId = State(initialValue: projectId)
            }
            if let taskTypeId = prefilledTaskTypeId {
                _selectedTaskTypeId = State(initialValue: taskTypeId)
            }
            if let teamMemberIds = prefilledTeamMemberIds {
                _selectedTeamMemberIds = State(initialValue: Set(teamMemberIds))
            }
        }
    }

    // Draft init for LocalTask mode (for use in ProjectFormSheet)
    init(draftMode: Mode, onSaveDraft: @escaping (LocalTask) -> Void) {
        self.mode = draftMode
        self.preselectedProjectId = nil
        self.onSave = nil
        self.onSaveDraft = onSaveDraft

        if case .editDraft(let task) = draftMode {
            _selectedTaskTypeId = State(initialValue: task.taskTypeId)
            _selectedTeamMemberIds = State(initialValue: Set(task.teamMemberIds))
            _startDate = State(initialValue: task.startDate)
            _endDate = State(initialValue: task.endDate)
            _selectedStatus = State(initialValue: task.status)
        } else if case .draft(let task) = draftMode, let task = task {
            _selectedTaskTypeId = State(initialValue: task.taskTypeId)
            _selectedTeamMemberIds = State(initialValue: Set(task.teamMemberIds))
            _startDate = State(initialValue: task.startDate)
            _endDate = State(initialValue: task.endDate)
            _selectedStatus = State(initialValue: task.status)
        }
    }

    var body: some View {
        // Tutorial mode uses custom header since NavigationView toolbar doesn't render in custom containers
        Group {
            if tutorialMode {
                tutorialModeContent
            } else {
                NavigationView {
                    mainContent
                        .standardSheetToolbar(
                            title: mode.isCreate ? "Create Task" : "Edit Task",
                            actionText: mode.isCreate ? "Create" : "Save",
                            isActionEnabled: isValid,
                            isSaving: isSaving,
                            onCancel: { dismiss() },
                            onAction: { saveTask() }
                        )
                        .interactiveDismissDisabled()
                }
            }
        }
        .sheet(isPresented: $showingScheduler, onDismiss: {
            // If scheduler was dismissed without confirming and dates didn't exist before, clear them
            if !schedulerConfirmed && !datesExistedBeforeScheduler {
                startDate = nil
                endDate = nil
            }
        }) {
            if let startDate = startDate, let endDate = endDate {
                // In draft mode, we need a temporary project for the scheduler
                if mode.isDraft {
                    CalendarSchedulerSheet(
                        isPresented: $showingScheduler,
                        itemType: .draftTask(
                            taskTypeId: selectedTaskTypeId ?? "",
                            teamMemberIds: Array(selectedTeamMemberIds),
                            projectId: selectedProject?.id ?? preselectedProjectId
                        ),
                        currentStartDate: startDate,
                        currentEndDate: endDate,
                        onScheduleUpdate: { newStart, newEnd in
                            schedulerConfirmed = true  // Mark as confirmed
                            self.startDate = newStart
                            self.endDate = newEnd
                            // Wizard system: notify task date set
                            NotificationCenter.default.post(
                                name: Notification.Name("WizardTaskDateSet"),
                                object: nil
                            )
                            // Tutorial mode: notify date set
                            if tutorialMode {
                                NotificationCenter.default.post(
                                    name: Notification.Name("TutorialDateSet"),
                                    object: nil
                                )
                            }
                        },
                        preselectedTeamMemberIds: selectedTeamMemberIds.isEmpty ? nil : selectedTeamMemberIds
                    )
                    .environment(\.tutorialMode, tutorialMode)
                    .environmentObject(dataController)
                    .interactiveDismissDisabled(tutorialMode)
                } else if let project = selectedProject {
                    CalendarSchedulerSheet(
                        isPresented: $showingScheduler,
                        itemType: .task(ProjectTask(
                            id: UUID().uuidString,
                            projectId: project.id,
                            taskTypeId: selectedTaskTypeId ?? "",
                            companyId: dataController.currentUser?.companyId ?? "",
                            status: .active
                        )),
                        currentStartDate: startDate,
                        currentEndDate: endDate,
                        onScheduleUpdate: { newStart, newEnd in
                            schedulerConfirmed = true  // Mark as confirmed
                            self.startDate = newStart
                            self.endDate = newEnd
                            // Wizard system: notify task date set
                            NotificationCenter.default.post(
                                name: Notification.Name("WizardTaskDateSet"),
                                object: nil
                            )
                            // Tutorial mode: notify date set
                            if tutorialMode {
                                NotificationCenter.default.post(
                                    name: Notification.Name("TutorialDateSet"),
                                    object: nil
                                )
                            }
                        },
                        preselectedTeamMemberIds: selectedTeamMemberIds.isEmpty ? nil : selectedTeamMemberIds
                    )
                    .environment(\.tutorialMode, tutorialMode)
                    .environmentObject(dataController)
                    .interactiveDismissDisabled(tutorialMode)
                }
            }
        }
        .sheet(isPresented: $showingCreateTaskType) {
            TaskTypeSheet(mode: .create { newTaskType in
                selectedTaskTypeId = newTaskType.id
            })
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingTeamPicker) {
            TeamMemberPickerSheet(
                selectedTeamMemberIds: $selectedTeamMemberIds,
                allTeamMembers: recencyOrderedTeamMembers,
                recentMemberIds: recentTeamMemberIdSet,
                onConfirm: {}
            )
        }
        .onChange(of: selectedTeamMemberIds) { oldValue, newValue in
            // Wizard system: notify crew assigned when going from empty to having members
            if oldValue.isEmpty && !newValue.isEmpty {
                NotificationCenter.default.post(
                    name: Notification.Name("WizardTaskCrewAssigned"),
                    object: nil
                )
            }
        }
        .sheet(isPresented: $showingDependencyOverride) {
            if let taskType = selectedTaskType {
                DependencyPickerSheet(
                    currentTaskTypeId: selectedTaskTypeId,
                    existingDependencies: dependencyOverrides ?? taskType.dependencies,
                    companyId: dataController.currentUser?.companyId ?? "",
                    onSelect: { newDepId in
                        if dependencyOverrides == nil {
                            dependencyOverrides = taskType.dependencies
                        }
                        dependencyOverrides?.append(TaskTypeDependency(dependsOnTaskTypeId: newDepId, overlapPercentage: 0))
                    }
                )
                .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingNewProjectFromSearch) {
            ProjectFormSheet(mode: .create, initialTitle: newProjectNameFromSearch) { newProject in
                // Select the newly created project
                withAnimation(OPSStyle.Animation.fast) {
                    selectedProjectId = newProject.id
                    projectSearchText = newProject.title
                    showingProjectSuggestions = false
                }
            }
            .environmentObject(dataController)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .onAppear {
            // Track screen view for analytics
            AnalyticsManager.shared.trackScreenView(screenName: .taskForm, screenClass: "TaskFormSheet")
            AnalyticsService.shared.trackScreenView(screenName: "task_form")

            if let selectedProject = selectedProject {
                projectSearchText = selectedProject.title
            }

            // Fetch team members as full User objects — required for UserAvatar
            // to render real profile photos (uses profileImageData / profileImageURL
            // / userColor). The lightweight TeamMember projection was dropping
            // profileImageData, forcing every avatar to the initials placeholder.
            if let companyId = dataController.currentUser?.companyId {
                fetchedTeamMembers = dataController.getTeamMembers(companyId: companyId)
                    .sorted { $0.fullName < $1.fullName }
            }

            // Tutorial mode: Start pulse animation for input highlights
            if tutorialMode {
                tutorialHighlightPulse = true
            }

            // Wizard system: notify task added when form opens for new tasks (not edits)
            // This fires on appear so steps 9-10 (assign_date, assign_crew)
            // can complete while the form is still visible
            if mode.localTask == nil && mode.isCreate {
                NotificationCenter.default.post(
                    name: Notification.Name("WizardTaskAdded"),
                    object: nil
                )
            }
        }
        .onDisappear {
            AnalyticsService.shared.endScreenView(screenName: "task_form")
            NotificationCenter.default.post(
                name: Notification.Name("WizardScreenDismissed"),
                object: nil,
                userInfo: ["screen": "TaskForm"]
            )
        }
        // Sheets present above the root view where wizardBanner / wizardOverlay
        // live, so the task-flow guide is invisible here unless the sheet
        // re-attaches the wizard UI itself.
        .wizardBannerIfAvailable(stateManager: wizardStateManager)
        .wizardOverlayIfAvailable(stateManager: wizardStateManager)
        .loadingOverlay(isPresented: $isSaving, message: "Saving...")
        .onChange(of: selectedTaskTypeId) { _, newId in
            // Auto-populate default team members from task type in create mode
            guard mode.isCreate, let newId,
                  let taskType = allTaskTypes.first(where: { $0.id == newId }),
                  !taskType.defaultTeamMemberIdsString.isEmpty else { return }
            let defaultIds = Set(taskType.defaultTeamMemberIdsString.components(separatedBy: ","))
            if !defaultIds.isEmpty {
                selectedTeamMemberIds = defaultIds
            }
        }
    }

    // MARK: - Tutorial Mode Content

    /// Content wrapped with custom header for tutorial mode
    private var tutorialModeContent: some View {
        ZStack {
            VStack(spacing: 0) {
                // Extra padding to push nav bar below tooltip during taskFormDone phase
                if tutorialMode && tutorialPhase == .taskFormDone {
                    Color.clear
                        .frame(height: 90)
                }

                // Custom navigation bar for tutorial mode
                HStack {
                    Button("CANCEL") {
                        // Cancel is disabled in tutorial mode
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .allowsHitTesting(false)
                    .opacity(0.5)

                    Spacer()

                    Text(mode.isCreate ? "CREATE TASK" : "EDIT TASK")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    Button("DONE") {
                        saveTask()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(isValid && isDoneButtonEnabled ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .disabled(!isValid || !isDoneButtonEnabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .tutorialHighlight(for: .taskFormDone, cornerRadius: 6)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(OPSStyle.Colors.background)

                // Divider
                Rectangle()
                    .fill(OPSStyle.Colors.cardBorder)
                    .frame(height: 1)

                mainContent
                    .overlay(
                        Group {
                            if tutorialMode && tutorialPhase == .taskFormDone {
                                OPSStyle.Colors.overlayMedium
                                    .allowsHitTesting(true)
                            }
                        }
                    )
            }

            // Radial gradient overlay centered on DONE button for visibility
            if tutorialMode && tutorialPhase == .taskFormDone {
                RadialGradient(
                    gradient: Gradient(colors: [.clear, OPSStyle.Colors.overlayMedium]),
                    center: UnitPoint(x: 0.85, y: 0.12),
                    startRadius: 60,
                    endRadius: 350
                )
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }
        }
    }

    /// Main scrollable content
    private var mainContent: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            ScrollView {
                ScrollViewReader { proxy in
                VStack(spacing: 24) {
                    // Live preview card at top (greyed out in tutorial mode to reduce distraction)
                    previewCard
                        .opacity(tutorialMode ? 0.3 : 1.0)
                        .allowsHitTesting(false)

                    // TASK DETAILS section - ALL FIELDS IN ONE SECTION
                    ExpandableSection(
                        title: "TASK DETAILS",
                        icon: "checklist",
                        isExpanded: .constant(true),
                        onDelete: nil
                    ) {
                        VStack(spacing: 16) {
                            // Only show project field if not in draft mode
                            if !mode.isDraft {
                                projectField
                                    .allowsHitTesting(!tutorialMode) // Always disabled in tutorial
                                    .opacity(tutorialMode ? 0.5 : 1.0)
                            }
                            taskTypeField
                                .allowsHitTesting(isTaskTypeFieldEnabled && !needsProjectSelection)
                                .opacity((tutorialMode && !isTaskTypeFieldEnabled) || needsProjectSelection ? 0.5 : 1.0)
                            statusField
                                .allowsHitTesting(!tutorialMode && !needsProjectSelection)
                                .opacity(tutorialMode || needsProjectSelection ? 0.5 : 1.0)
                            teamField
                                .wizardTarget("assign_crew", style: .row)
                                .allowsHitTesting(isCrewFieldEnabled && !needsProjectSelection)
                                .opacity((tutorialMode && !isCrewFieldEnabled) || needsProjectSelection ? 0.5 : 1.0)
                            datesField
                                .wizardTarget("assign_date", style: .row)
                                .allowsHitTesting(isDatesFieldEnabled && !needsProjectSelection)
                                .opacity((tutorialMode && !isDatesFieldEnabled) || needsProjectSelection ? 0.5 : 1.0)
                            dependenciesSection
                            notesField
                                .allowsHitTesting(!tutorialMode && !needsProjectSelection)
                                .opacity(tutorialMode || needsProjectSelection ? 0.5 : 1.0)
                        }
                    }
                }
                .padding()
                .padding(.bottom, 100)
                // Wizard system: scroll to the target element when a wizard step activates
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardScrollToTarget"))) { notification in
                    guard let stepId = notification.userInfo?["stepId"] as? String else { return }
                    let wizardId = "wizard_active_\(stepId)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation {
                            proxy.scrollTo(wizardId, anchor: .top)
                        }
                    }
                }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    // Save notes content if notes field is focused
                    if focusedField == .notes {
                        taskNotes = tempNotes
                    }
                    focusedField = nil
                } label: {
                    HStack(spacing: 4) {
                        Text("Enter")
                        Image(systemName: "return")
                    }
                }
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
    }

    // MARK: - Sections

    // MARK: - Preview Card
    private var previewCard: some View {
        // Preview card matching UniversalJobBoardCard task styling
        ZStack {
            HStack(spacing: 0) {
                // Colored left border (4pt width) - task type color
                Rectangle()
                    .fill(selectedTaskType.map { Color(hex: $0.color) ?? OPSStyle.Colors.secondaryText } ?? OPSStyle.Colors.secondaryText)
                    .frame(width: 4)

                // Main content area
                VStack(alignment: .leading, spacing: 8) {
                    // Task type name (title)
                    Text(selectedTaskType?.display.uppercased() ?? "SELECT TASK TYPE")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(selectedTaskType != nil ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Project title - client (if project selected and not in draft mode)
                    if !mode.isDraft {
                        if let project = selectedProject {
                            Text("\(project.title) - \(project.effectiveClientName)")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .lineLimit(1)
                        } else {
                            Text("NO PROJECT SELECTED")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }

                    // Metadata row with icons (matching UniversalJobBoardCard)
                    HStack(spacing: 12) {
                        // Calendar icon + date (always show)
                        HStack(spacing: 4) {
                            Image(OPSStyle.Icons.calendar)
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            if let startDate = startDate {
                                Text(formatDate(startDate))
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .lineLimit(1)
                            } else {
                                Text("—")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }

                        // Team icon + count (always show)
                        HStack(spacing: 4) {
                            Image(OPSStyle.Icons.personTwo)
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text("\(selectedTeamMemberIds.count)")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
            }

            // Top right overlay - status badge and unscheduled badge
            HStack{
                Spacer()
                VStack(alignment: .trailing) {
                        // Status badge
                        Text(selectedStatus.displayName.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(selectedStatus.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .fill(selectedStatus.color.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(selectedStatus.color, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        
                        Spacer()
                        
                        // Unscheduled badge (if no date)
                        if startDate == nil {
                            Text("UNSCHEDULED")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .fill(OPSStyle.Colors.warningStatus.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .stroke(OPSStyle.Colors.warningStatus, lineWidth: OPSStyle.Layout.Border.standard)
                                )
                        }
                        
                    }
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
                
            }
            
            }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var projectField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROJECT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    TextField("Search or select project", text: $projectSearchText, onEditingChanged: { isEditing in
                        // Only expand dropdown if no project is already selected
                        if selectedProject == nil || !isEditing {
                            withAnimation(OPSStyle.Animation.fast) {
                                showingProjectSuggestions = isEditing
                            }
                        }
                    })
                    .onChange(of: projectSearchText) { _, newValue in
                        // Don't expand dropdown if text matches an already-selected project (e.g. preselected on appear)
                        if let selected = selectedProject, newValue == selected.title {
                            return
                        }
                        // Ensure suggestions show while typing (onEditingChanged only fires on focus change)
                        if !newValue.isEmpty && !showingProjectSuggestions {
                            withAnimation(OPSStyle.Animation.fast) {
                                showingProjectSuggestions = true
                            }
                        }
                    }
                    .frame(height: selectedProject != nil && !showingProjectSuggestions ? 64 : 44)
                    .padding(.horizontal, 16)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(
                                shouldHighlightProjectField ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder,
                                lineWidth: shouldHighlightProjectField ? 2 : 1
                            )
                            .animation(OPSStyle.Animation.standard, value: shouldHighlightProjectField)
                    )
                    // Only hide text when project is selected AND not actively searching
                    .foregroundColor(selectedProject != nil && !showingProjectSuggestions ? .clear : OPSStyle.Colors.primaryText)
                    .font(OPSStyle.Typography.body)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.words)
                    .animation(OPSStyle.Animation.fast, value: selectedProject != nil)

                    if showingProjectSuggestions {
                        VStack(spacing: 0) {
                            if !filteredProjects.isEmpty {
                                ForEach(Array(filteredProjects.prefix(5).enumerated()), id: \.element.id) { index, project in
                                    Button(action: {
                                        withAnimation(OPSStyle.Animation.fast) {
                                            selectedProjectId = project.id
                                            projectSearchText = project.title
                                            showingProjectSuggestions = false
                                        }
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
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(OPSStyle.Colors.cardBackgroundDark)
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    Divider()
                                        .background(OPSStyle.Colors.cardBorder)
                                }
                            }

                            // "New Project" option — always visible when searching, allows quick creation
                            if !projectSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button(action: {
                                    withAnimation(OPSStyle.Animation.fast) {
                                        showingProjectSuggestions = false
                                    }
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    createNewProjectFromSearch()
                                }) {
                                    HStack(spacing: 10) {
                                        Image(OPSStyle.Icons.plusCircleFill)
                                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("NEW PROJECT")
                                                .font(OPSStyle.Typography.captionBold)
                                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                            Text("\"\(projectSearchText.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .padding(.top, 4)
                    }
                }

                if let project = selectedProject, !showingProjectSuggestions {
                    HStack(alignment: .center) {
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
                            withAnimation(OPSStyle.Animation.fast) {
                                selectedProjectId = nil
                                projectSearchText = ""
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .padding()
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
                    .foregroundColor(taskTypeHighlight.labelColor)
                    .modifier(TutorialPulseModifier(isHighlighted: taskTypeHighlight.isHighlighted))

                Spacer()

                Button(action: {
                    guard !tutorialMode else { return } // Disabled in tutorial mode
                    showingCreateTaskType = true
                }) {
                    HStack(spacing: 4) {
                        Image(OPSStyle.Icons.add)
                        Text("NEW TYPE")
                    }
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(tutorialMode ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                }
                .allowsHitTesting(!tutorialMode)
                .opacity(tutorialMode ? 0.5 : 1.0)
            }

            // Task type picker with colored left border — inline expandable
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Colored left border (4pt width) - task type color
                    Rectangle()
                        .fill(selectedTaskType.map { Color(hex: $0.color) ?? OPSStyle.Colors.primaryAccent } ?? OPSStyle.Colors.cardBorder)
                        .frame(width: 4)

                    Button(action: {
                        withAnimation(OPSStyle.Animation.fast) {
                            showingTaskTypeList.toggle()
                        }
                    }) {
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

                            Image(systemName: showingTaskTypeList ? "chevron.up" : "chevron.down")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(showingTaskTypeList ? 0 : OPSStyle.Layout.cornerRadius)

                if showingTaskTypeList {
                    // Bug 9d5c2535 — recency-first ordering. Recently-used
                    // task types appear at top, then a tier divider, then
                    // all remaining types alphabetically.
                    let orderedTypes = recencyOrderedTaskTypes
                    let recentCount = recentTaskTypeCount

                    VStack(spacing: 0) {
                        ForEach(Array(orderedTypes.enumerated()), id: \.element.id) { index, taskType in
                            Button(action: {
                                withAnimation(OPSStyle.Animation.fast) {
                                    selectedTaskTypeId = taskType.id
                                    showingTaskTypeList = false
                                }
                                // Wizard system: notify task type selected
                                NotificationCenter.default.post(
                                    name: Notification.Name("WizardTaskTypeSelected"),
                                    object: nil
                                )
                                // Tutorial mode: notify task type selected
                                if tutorialMode {
                                    NotificationCenter.default.post(
                                        name: Notification.Name("TutorialTaskTypeSelected"),
                                        object: nil
                                    )
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                                        .frame(width: 12, height: 12)
                                    Text(taskType.display.uppercased())
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    Spacer()
                                    if selectedTaskTypeId == taskType.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Tier separator: thicker divider after the last
                            // "recent" task type so the boundary between
                            // "your usual" and "everything else" is visible.
                            // Otherwise standard 1pt divider.
                            if index == recentCount - 1 && recentCount > 0 && recentCount < orderedTypes.count {
                                Rectangle()
                                    .fill(OPSStyle.Colors.cardBorder)
                                    .frame(height: 2)
                            } else if index < orderedTypes.count - 1 {
                                Divider()
                                    .background(OPSStyle.Colors.cardBorder)
                            }
                        }
                    }
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(taskTypeHighlight.borderColor, lineWidth: taskTypeHighlight.isHighlighted ? 2 : 1)
                    .modifier(TutorialPulseModifier(isHighlighted: taskTypeHighlight.isHighlighted))
            )
            .wizardTarget("select_task_type", style: .input)
        }
    }

    private var statusField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STATUS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Menu {
                ForEach(TaskStatus.allCases.filter { $0 != .cancelled || PermissionStore.shared.can("tasks.edit") }, id: \.self) { status in
                    Button(action: {
                        selectedStatus = status
                    }) {
                        HStack {
                            Text(status.displayName)
                            if selectedStatus == status {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedStatus.displayName)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
        }
    }

    private var teamField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ASSIGN TEAM")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(crewHighlight.labelColor)
                .modifier(TutorialPulseModifier(isHighlighted: crewHighlight.isHighlighted))

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
                            UserAvatar(user: member, size: 24)
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
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(crewHighlight.borderColor, lineWidth: crewHighlight.isHighlighted ? 2 : 1)
                    .modifier(TutorialPulseModifier(isHighlighted: crewHighlight.isHighlighted))
            )
        }
        }
    }

    private var datesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DATES")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(datesHighlight.labelColor)
                    .modifier(TutorialPulseModifier(isHighlighted: datesHighlight.isHighlighted))

                Spacer()

                // Auto-schedule button — only show when project and task type are selected
                if !tutorialMode && selectedProjectId != nil && selectedTaskTypeId != nil {
                    Button(action: {
                        autoScheduleTask()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            Text("AUTO")
                        }
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }

            Button(action: {
                    // Track if dates existed before opening scheduler
                    datesExistedBeforeScheduler = (startDate != nil && endDate != nil)
                    schedulerConfirmed = false  // Reset confirmation flag

                    // Set temporary dates for scheduler to work with
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
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(datesHighlight.borderColor, lineWidth: datesHighlight.isHighlighted ? 2 : 1)
                            .modifier(TutorialPulseModifier(isHighlighted: datesHighlight.isHighlighted))
                    )
                }
                // In draft mode, always enabled. In regular mode, requires project
                .disabled(!mode.isDraft && selectedProjectId == nil)
        }
    }

    @ViewBuilder
    private var dependenciesSection: some View {
        if let taskType = selectedTaskType, !taskType.dependencies.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    Text("DEPENDENCIES")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                let effectiveDeps = dependencyOverrides ?? taskType.dependencies
                ForEach(effectiveDeps.indices, id: \.self) { index in
                    let dep = effectiveDeps[index]
                    HStack {
                        Text(taskTypeNameForDep(dep.dependsOnTaskTypeId))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()
                        Text("\(dep.overlapPercentage)% overlap")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        if dependencyOverrides == nil {
                            Text("inherited")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .padding(8)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                }

                Button(action: {
                    if dependencyOverrides == nil {
                        dependencyOverrides = taskType.dependencies
                    }
                    showingDependencyOverride = true
                }) {
                    Text(dependencyOverrides == nil ? "Override for this task" : "Edit overrides")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }

    private func taskTypeNameForDep(_ taskTypeId: String) -> String {
        allTaskTypes.first(where: { $0.id == taskTypeId })?.display ?? "Task Type"
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 12) {
                ZStack(alignment: .topLeading) {
                    // Placeholder text
                    if (focusedField == .notes ? tempNotes : taskNotes).isEmpty {
                        Text("Add notes...")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.top, 20)
                            .padding(.leading, 16)
                    }

                    TextEditor(text: focusedField == .notes ? $tempNotes : $taskNotes)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(minHeight: 100, maxHeight: 200)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .focused($focusedField, equals: .notes)
                        .onChange(of: focusedField) { oldValue, newValue in
                            if newValue == .notes && oldValue != .notes {
                                tempNotes = taskNotes
                            }
                        }
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(
                            focusedField == .notes ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )

                if focusedField == .notes {
                    HStack(spacing: 16) {
                        Spacer()

                        Button("CANCEL") {
                            tempNotes = ""
                            focusedField = nil
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                        Button("SAVE") {
                            taskNotes = tempNotes
                            focusedField = nil
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
        }
    }

    // MARK: - Auto Schedule

    private func autoScheduleTask() {
        guard let projectId = selectedProjectId,
              let taskTypeId = selectedTaskTypeId else { return }

        let effectiveDeps = dependencyOverrides ?? (selectedTaskType?.dependencies ?? [])
        let tempTask = TemporarySchedulableTask(
            id: "temp-new-task",
            taskTypeId: taskTypeId,
            startDate: nil,
            endDate: nil,
            duration: max(selectedTaskType?.tasks.first?.duration ?? 1, 1),
            effectiveDependencies: effectiveDeps,
            displayOrder: dataController.getTasksForProject(projectId).count,
            schedulingTeamMemberIds: selectedTeamMemberIds,
            schedulingProjectId: projectId
        )

        let plan = dataController.autoScheduleSingleTask(
            tempTask,
            teamMemberIds: selectedTeamMemberIds,
            anchorDate: Date()
        )

        if let placement = plan.placements.first {
            withAnimation(OPSStyle.Animation.standard) {
                startDate = placement.startDate
                endDate = placement.endDate
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Actions

    @State private var showingNewProjectFromSearch = false
    @State private var newProjectNameFromSearch = ""

    /// Creates a new project inline from the search text and selects it
    private func createNewProjectFromSearch() {
        let trimmed = projectSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newProjectNameFromSearch = trimmed
        showingNewProjectFromSearch = true
    }

    private func saveTask() {
        guard isValid else { return }
        guard !isSaving else { return }

        // Handle draft mode separately
        if mode.isDraft {
            saveDraftTask()
            return
        }

        isSaving = true

        // Snapshot form state synchronously so the async work can't observe
        // torn writes mid-flight (e.g. user editing notes after tapping Create).
        let snapshotProjectId = selectedProjectId
        let snapshotTaskTypeId = selectedTaskTypeId
        let snapshotTaskType = selectedTaskType
        let snapshotStatus = selectedStatus
        let snapshotNotes = taskNotes
        let snapshotTeamMemberIds = Array(selectedTeamMemberIds)
        let snapshotStart = startDate
        let snapshotEnd = endDate
        let snapshotDependencyOverrides = dependencyOverrides
        let snapshotCompanyId = dataController.currentUser?.companyId ?? ""

        Task { @MainActor in
            let task: ProjectTask
            let isEditMode: Bool
            let teamMembersChanged: Bool

            // ----- Phase 1: Local SwiftData write (MainActor) -----
            do {
                if case .edit(let existingTask) = mode {
                    task = existingTask
                    isEditMode = true
                    let previousTeamMemberIds = Set(task.getTeamMemberIds())
                    teamMembersChanged = previousTeamMemberIds != Set(snapshotTeamMemberIds)
                } else {
                    guard let projectId = snapshotProjectId,
                          let taskTypeId = snapshotTaskTypeId else {
                        isSaving = false
                        errorMessage = "Missing project or task type."
                        showingError = true
                        return
                    }
                    let taskColor = snapshotTaskType?.color ?? "#59779F"
                    print("[TASK_CREATE] 🎨 Creating task with color: \(taskColor) from taskType: \(snapshotTaskType?.display ?? "nil")")

                    let newTask = ProjectTask(
                        // Postgres canonicalizes UUID storage to lowercase; Swift's
                        // UUID().uuidString returns UPPERCASE. Storing uppercase
                        // locally causes fetch-by-id to miss when the realtime echo
                        // / pulled DTO comes back lowercase, which produced
                        // duplicate rows. Always canonicalize to lowercase so local
                        // and remote ids compare equal.
                        id: UUID().uuidString.lowercased(),
                        projectId: projectId,
                        taskTypeId: taskTypeId,
                        companyId: snapshotCompanyId,
                        status: snapshotStatus,
                        taskColor: taskColor
                    )
                    // Insert into the context BEFORE wiring relationships so
                    // SwiftData never sees a half-managed model referenced by
                    // managed objects (a crash vector on iOS 18).
                    print("[DUPE_TRACE] SAVETASK.insert id=\(newTask.id) ctx=\(ObjectIdentifier(modelContext)) thread=\(Thread.current)")
                    modelContext.insert(newTask)

                    if let project = selectedProject {
                        newTask.project = project
                    }
                    if let taskType = snapshotTaskType {
                        newTask.taskType = taskType
                    }
                    newTask.setTeamMemberIds(snapshotTeamMemberIds)

                    // setTeamMemberIds only writes the ID string; it does NOT
                    // cascade to the [User] relationship array that the task
                    // list reads for avatar rendering. Populate it here so the
                    // row shows avatars immediately instead of waiting for an
                    // inbound sync to hydrate the relationship.
                    if !snapshotTeamMemberIds.isEmpty {
                        let ids = snapshotTeamMemberIds
                        let descriptor = FetchDescriptor<User>(
                            predicate: #Predicate<User> { user in ids.contains(user.id) }
                        )
                        newTask.teamMembers = (try? modelContext.fetch(descriptor)) ?? []
                    }

                    task = newTask
                    isEditMode = false
                    teamMembersChanged = false

                    print("[TASK_CREATE] ✅ Task inserted locally with ID: \(task.id), color: \(task.taskColor), teamMembers: \(newTask.teamMembers.count)")
                }

                // Common writes (create + edit)
                task.status = snapshotStatus
                task.taskNotes = snapshotNotes.isEmpty ? nil : snapshotNotes

                if let overrides = snapshotDependencyOverrides {
                    task.setDependencyOverrides(overrides)
                } else {
                    task.dependencyOverridesJSON = nil
                }

                task.startDate = snapshotStart
                task.endDate = snapshotEnd
                if let start = snapshotStart, let end = snapshotEnd {
                    let daysDiff = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
                    task.duration = daysDiff + 1
                }

                task.needsSync = true

                try modelContext.save()
                print("[TASK_FORM] ✅ Task saved locally")
            } catch {
                isSaving = false
                errorMessage = "Failed to save task locally: \(error.localizedDescription)"
                showingError = true
                return
            }

            // ----- Phase 2: Queue sync + cascade project updates (MainActor) -----
            // All DataController methods below are @MainActor and only perform
            // local writes + enqueue sync operations via SyncEngine — no network
            // calls block this path. Previously these were wrapped in a 5s
            // Task.timeout(), which ran on the global executor and mutated
            // SwiftData objects off the main actor (crash vector) while also
            // spuriously flagging successful saves as "offline" (duplicate
            // task bug when the sync queue replayed the same create op).
            do {
                if isEditMode && teamMembersChanged {
                    print("[TASK_FORM] 👥 Team members changed in edit mode, using centralized update...")
                    try await dataController.updateTaskTeamMembers(task: task, memberIds: snapshotTeamMemberIds)
                    print("[TASK_FORM] ✅ Team members updated via centralized method")
                }

                if !isEditMode {
                    if task.createdAt == nil { task.createdAt = Date() }
                    let supabaseTaskDTO = SupabaseProjectTaskDTO(
                        id: task.id,
                        bubbleId: nil,
                        companyId: task.companyId,
                        projectId: task.projectId,
                        taskTypeId: task.taskTypeId,
                        customTitle: task.customTitle,
                        taskNotes: task.taskNotes,
                        status: task.status.rawValue,
                        taskColor: task.taskColor,
                        displayOrder: task.displayOrder,
                        teamMemberIds: task.getTeamMemberIds(),
                        sourceLineItemId: nil,
                        sourceEstimateId: nil,
                        startDate: task.startDate.map { ISO8601DateFormatter().string(from: $0) },
                        endDate: task.endDate.map { ISO8601DateFormatter().string(from: $0) },
                        duration: task.duration,
                        dependencyOverrides: snapshotDependencyOverrides,
                        startTime: nil,
                        endTime: nil,
                        pairedFromTaskId: nil,
                        scheduleLocked: nil,
                        deletedAt: nil,
                        createdAt: task.createdAt.map { ISO8601DateFormatter().string(from: $0) }
                    )
                    // DataController.createTask is idempotent: it detects the
                    // task we just inserted and only records the sync op.
                    _ = try await dataController.createTask(dto: supabaseTaskDTO)
                    print("[TASK_FORM] ✅ Task create op queued via DataController")
                }

                if let project = task.project {
                    print("[TASK_FORM] 📅 Syncing project dates...")
                    try await dataController.updateProjectDates(
                        project: project,
                        startDate: project.startDate,
                        endDate: project.endDate
                    )

                    print("[TASK_FORM] 👥 Rolling up project team members from tasks...")
                    project.updateTeamMembersFromTasks(in: modelContext)
                    try? modelContext.save()

                    let teamMemberIds = project.getTeamMemberIds()
                    try await dataController.updateProjectTeamMembers(
                        project: project,
                        memberIds: teamMemberIds
                    )

                    try await dataController.recalculateTaskIndices(for: project)
                    print("[TASK_FORM] ✅ Project cascade updates complete")
                }
            } catch {
                print("[TASK_FORM] ❌ Error during post-save cascade: \(error)")
                // The local task is already saved, so this is a soft failure.
                // Surface the message but do not roll back the task insert.
                errorMessage = "Task saved. Some related updates will retry: \(error.localizedDescription)"
                showingError = true
                // Fall through to dismiss path so the user isn't stuck.
            }

            // ----- Defense against inbound-echo duplicate race -----
            // ProjectTask.id is not @Attribute(.unique), so a realtime echo
            // arriving after the outbound SyncOperation was cleared can slip
            // past origin-suppression in InboundProcessor.mergeTask and insert
            // a second row for the same id. Dedupe immediately, and again
            // after a short delay to catch slow echoes from realtime.
            let createdTaskId = task.id
            Self.dedupeTaskRow(id: createdTaskId, context: modelContext)
            Task { @MainActor [weak ctx = modelContext] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let ctx { Self.dedupeTaskRow(id: createdTaskId, context: ctx) }
            }

            // ----- Phase 3: Success path (MainActor) -----
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            isSaving = false
            onSave?(task)

            if case .create = mode {
                let hasSchedule = snapshotStart != nil || snapshotEnd != nil
                AnalyticsManager.shared.trackTaskCreated(
                    taskType: snapshotTaskType?.display,
                    hasSchedule: hasSchedule,
                    teamSize: snapshotTeamMemberIds.count
                )
                AnalyticsService.shared.track(
                    eventType: .action,
                    eventName: "task_created",
                    properties: [
                        "task_type": snapshotTaskType?.display ?? "unknown",
                        "has_schedule": hasSchedule,
                        "team_size": snapshotTeamMemberIds.count
                    ]
                )
            } else if case .edit = mode {
                AnalyticsManager.shared.trackTaskEdited(taskId: task.id)
            }

            let taskTypeName = snapshotTaskType?.display ?? ""
            NotificationCenter.default.post(
                name: Notification.Name("TaskCreatedSuccess"),
                object: nil,
                userInfo: ["taskTypeName": taskTypeName]
            )

            try? await Task.sleep(nanoseconds: 300_000_000)
            dismiss()
        }
    }

    /// Remove duplicate ProjectTask rows for a given id. Winner is the copy
    /// with needsSync=true (pending local changes) if present, otherwise the
    /// most-recently synced. Called from saveTask to defend against the
    /// inbound-echo race that slips past origin-suppression.
    @MainActor
    private static func dedupeTaskRow(id: String, context: ModelContext) {
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { $0.id == id }
        )
        guard let copies = try? context.fetch(descriptor), copies.count > 1 else { return }
        print("[TASK_FORM] ⚠️ Detected \(copies.count) rows for task \(id), deduping")

        let winner: ProjectTask = copies.first(where: { $0.needsSync })
            ?? copies.max(by: { ($0.lastSyncedAt ?? .distantPast) < ($1.lastSyncedAt ?? .distantPast) })
            ?? copies[0]

        for dup in copies where dup !== winner {
            context.delete(dup)
        }
        try? context.save()
    }

    private func saveDraftTask() {
        guard let taskTypeId = selectedTaskTypeId else { return }

        // Create or update LocalTask
        var localTask: LocalTask
        if case .editDraft(let existingTask) = mode {
            // Create new LocalTask with updated values
            localTask = LocalTask(
                id: existingTask.id,
                taskTypeId: taskTypeId,
                customTitle: existingTask.customTitle,
                status: selectedStatus,
                teamMemberIds: Array(selectedTeamMemberIds)
            )
        } else {
            localTask = LocalTask(
                id: UUID(),
                taskTypeId: taskTypeId,
                customTitle: nil,
                status: selectedStatus,
                teamMemberIds: Array(selectedTeamMemberIds)
            )
        }

        // Add dates to the local task
        localTask.startDate = startDate
        localTask.endDate = endDate

        // Call the draft save callback
        onSaveDraft?(localTask)

        // Wizard system: notify task saved (draft mode = task added to project form)
        NotificationCenter.default.post(
            name: Notification.Name("WizardTaskSaved"),
            object: nil
        )

        // Tutorial mode: notify task form done
        if tutorialMode {
            NotificationCenter.default.post(
                name: Notification.Name("TutorialTaskFormDone"),
                object: nil
            )
        }

        // Success haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Dismiss the sheet
        dismiss()
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Team Member Picker Sheet
struct TeamMemberSelectionDraft: Equatable {
    private let committedIds: Set<String>
    private(set) var draftIds: Set<String>

    init(committedIds: Set<String>) {
        self.committedIds = committedIds
        self.draftIds = committedIds
    }

    mutating func toggle(_ memberId: String) {
        if draftIds.contains(memberId) {
            draftIds.remove(memberId)
        } else {
            draftIds.insert(memberId)
        }
    }

    func cancelledIds() -> Set<String> {
        committedIds
    }

    func confirmedIds() -> Set<String> {
        draftIds
    }
}

struct TeamMemberPickerSheet: View {
    @Binding var selectedTeamMemberIds: Set<String>
    /// Full `User` objects so each row renders a real avatar (profile photo
    /// or cached local bytes) rather than the initials placeholder. Caller
    /// is responsible for ordering (recency-first when a task type is
    /// selected, alphabetical otherwise).
    let allTeamMembers: [User]
    /// Bug 9d5c2535 — IDs that have been assigned to the current task type
    /// before. Rendered with a RECENT tag to mark the boundary between
    /// "your usual crew" and the rest. Empty when no task type is selected
    /// or no prior assignments exist.
    var recentMemberIds: Set<String> = []
    /// Bug 040e4482 — fired only when the operator taps DONE. Drag-to-dismiss
    /// does NOT call this, so callers that need to distinguish "explicit
    /// commit" from "swipe away" (e.g. the unscheduled review's swipe-right
    /// path, which auto-schedules after a commit) can act conditionally.
    /// Optional so existing callers that treat dismiss-equals-commit
    /// (TaskFormSheet's live-binding flow) keep their current behavior.
    var onConfirm: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tutorialMode) private var isTutorialMode
    @State private var selectionDraft = TeamMemberSelectionDraft(committedIds: [])

    private var usesExplicitConfirmation: Bool {
        onConfirm != nil
    }

    private var activeSelectionIds: Set<String> {
        usesExplicitConfirmation ? selectionDraft.draftIds : selectedTeamMemberIds
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: CGFloat(OPSStyle.Layout.spacing3)) {
                Text("SELECT TEAM MEMBERS")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer()

                Button(action: confirmSelection) {
                    Text("DONE")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.opsAccent)
                        .padding(.horizontal, CGFloat(OPSStyle.Layout.spacing3))
                        .frame(minHeight: CGFloat(OPSStyle.Layout.touchTargetMin))
                        .background(
                            RoundedRectangle(cornerRadius: CGFloat(OPSStyle.Layout.buttonRadius))
                                .fill(OPSStyle.Colors.surfaceActive)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CGFloat(OPSStyle.Layout.buttonRadius))
                                .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
            }
            .padding(.horizontal, CGFloat(OPSStyle.Layout.spacing3))
            .padding(.top, CGFloat(OPSStyle.Layout.spacing3))
            .padding(.bottom, CGFloat(OPSStyle.Layout.spacing2))
            .background(OPSStyle.Colors.background)

            Rectangle()
                .fill(OPSStyle.Colors.line)
                .frame(height: OPSStyle.Layout.Border.standard)

            ScrollView {
                VStack(spacing: OPSStyle.Layout.Border.standard) {
                    ForEach(Array(allTeamMembers.enumerated()), id: \.element.id) { index, member in
                        teamMemberRow(member: member, index: index)
                    }
                }
                .padding(CGFloat(OPSStyle.Layout.spacing3))
            }
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .onAppear {
            selectionDraft = TeamMemberSelectionDraft(committedIds: selectedTeamMemberIds)
        }
    }

    private func teamMemberRow(member: User, index: Int) -> some View {
        let isRecent = recentMemberIds.contains(member.id)
        let nextIsRecent = (index + 1) < allTeamMembers.count
            ? recentMemberIds.contains(allTeamMembers[index + 1].id)
            : false
        let isLastRecentRow = isRecent && !nextIsRecent && !recentMemberIds.isEmpty

        return VStack(spacing: 0) {
            Button(action: { toggle(member.id) }) {
                HStack(spacing: CGFloat(OPSStyle.Layout.spacing2_5)) {
                    Image(systemName: activeSelectionIds.contains(member.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(activeSelectionIds.contains(member.id) ? OPSStyle.Colors.opsAccent : OPSStyle.Colors.text3)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))

                    UserAvatar(user: member, size: 40)

                    VStack(alignment: .leading, spacing: CGFloat(OPSStyle.Layout.spacing1)) {
                        Text(member.fullName)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.text)

                        Text(member.role.displayName)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.text3)
                    }

                    Spacer()

                    if isRecent {
                        Text("RECENT")
                            .font(OPSStyle.Typography.badgeCake)
                            .foregroundColor(OPSStyle.Colors.opsAccent)
                            .padding(.horizontal, CGFloat(OPSStyle.Layout.spacing2))
                            .padding(.vertical, CGFloat(OPSStyle.Layout.spacing1))
                            .overlay(
                                RoundedRectangle(cornerRadius: CGFloat(OPSStyle.Layout.chipRadius))
                                    .stroke(OPSStyle.Colors.opsAccent, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                    }
                }
                .padding(CGFloat(OPSStyle.Layout.spacing3))
                .background(OPSStyle.Colors.surfaceHover)
            }
            .buttonStyle(PlainButtonStyle())

            if isLastRecentRow {
                Rectangle()
                    .fill(OPSStyle.Colors.line)
                    .frame(height: OPSStyle.Layout.Border.thick)
                    .padding(.vertical, CGFloat(OPSStyle.Layout.spacing1))
            }
        }
    }

    private func toggle(_ memberId: String) {
        let wasEmpty = activeSelectionIds.isEmpty

        if usesExplicitConfirmation {
            selectionDraft.toggle(memberId)
        } else {
            if selectedTeamMemberIds.contains(memberId) {
                selectedTeamMemberIds.remove(memberId)
            } else {
                selectedTeamMemberIds.insert(memberId)
            }
        }

        if wasEmpty && !activeSelectionIds.isEmpty && isTutorialMode {
            NotificationCenter.default.post(
                name: Notification.Name("TutorialCrewAssigned"),
                object: nil
            )
        }
    }

    private func confirmSelection() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if usesExplicitConfirmation {
            selectedTeamMemberIds = selectionDraft.confirmedIds()
        }
        onConfirm?()
        dismiss()
    }
}

/// Lightweight SchedulableTask for auto-schedule computation on a new task
private struct TemporarySchedulableTask: SchedulableTask {
    let id: String
    let taskTypeId: String
    let startDate: Date?
    let endDate: Date?
    let duration: Int
    let effectiveDependencies: [TaskTypeDependency]
    let displayOrder: Int
    let schedulingTeamMemberIds: Set<String>
    let schedulingProjectId: String
}
