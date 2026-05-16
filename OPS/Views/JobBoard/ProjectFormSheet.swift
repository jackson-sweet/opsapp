//
//  ProjectFormSheet.swift
//  OPS
//
//  Created by Assistant on 2025-09-26.
//  Overhauled on November 16, 2025 - Progressive Disclosure Design
//

import SwiftUI
import SwiftData
import PhotosUI
import Supabase

struct ProjectFormSheet: View {
    enum Mode {
        case create
        case edit(Project)

        var isCreate: Bool {
            if case .create = self { return true }
            return false
        }

        var project: Project? {
            if case .edit(let project) = self { return project }
            return nil
        }
    }

    let mode: Mode
    let onSave: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase
    // Wizard state so the project-lifecycle banner + instruction bar stay
    // visible when this sheet is presented over the root view.
    @Environment(\.wizardStateManager) private var wizardStateManager
    @Query private var allClients: [Client]
    @Query private var allTeamMembers: [TeamMember]
    @Query private var allTaskTypes: [TaskType]
    // Bug 9d5c2535 — feeds the "start from recent" suggestions strip.
    // Filtered locally in `recentSuggestedProjects` rather than via a
    // SwiftData predicate so the tutorial-mode `DEMO_` filter and the
    // current-user scoping live in one place.
    @Query private var allProjects: [Project]

    // Tutorial mode filtering - only show DEMO_ entities when in tutorial
    private var availableClients: [Client] {
        if tutorialMode {
            return allClients.filter { $0.id.hasPrefix("DEMO_") }
        }
        return allClients
    }

    private var availableTeamMembers: [TeamMember] {
        if tutorialMode {
            return allTeamMembers.filter { $0.id.hasPrefix("DEMO_") }
        }
        return allTeamMembers
    }

    private var uniqueTeamMembers: [TeamMember] {
        var seen = Set<String>()
        return availableTeamMembers.filter { member in
            guard !seen.contains(member.id) else { return false }
            seen.insert(member.id)
            return true
        }
    }

    // MARK: - Form Fields
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var notes: String = ""
    @State private var address: String = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var selectedClientId: String?
    @State private var selectedStatus: Status = .rfq
    @State private var startDate: Date? = nil
    @State private var endDate: Date? = nil
    @State private var projectImages: [UIImage] = []

    // Local tasks for multiple task creation
    @State private var localTasks: [LocalTask] = []

    @AppStorage("defaultProjectStatus") private var defaultProjectStatusRaw: String = Status.rfq.rawValue

    private var defaultProjectStatus: Status {
        Status(rawValue: defaultProjectStatusRaw) ?? .rfq
    }

    // MARK: - UI State
    @State private var showingCreateClient = false
    @State private var clientSearchText = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingImagePicker = false
    /// Bug 02222904 — choose between camera multi-capture and library
    /// pick before opening the actual picker. Previously the project
    /// creation form only offered the photo library.
    @State private var showingPhotoSourceChooser = false
    @State private var showingCameraBatch = false
    @State private var showingScheduler = false
    @State private var showingCopyFromProject = false
    @State private var showingTaskForm = false
    @State private var editingTaskIndex: Int?

    // MARK: - Inline task row state
    //
    // Bug 2daf95f2 — task creation inside the project form sheet is now an
    // inline table of `InlineTaskRow`s. Each row exposes type / team / date
    // as in-line chips that present the SAME sheets used by `TaskFormSheet`,
    // so the data flow and persistence are unchanged. Status / notes /
    // dependencies remain accessible via long-press → "Open full editor".
    //
    /// Resolved `User` objects for the team-member picker presented from a row.
    /// Fetched once on appear via `dataController.getTeamMembers(companyId:)`
    /// because `TeamMemberPickerSheet` wants full `User`s for avatar rendering,
    /// while the rest of this form continues to use the lightweight
    /// `[TeamMember]` `@Query` for counts and team rollups.
    @State private var fetchedTeamUsers: [User] = []
    /// LocalTask whose chip is currently driving a presented sheet (team or
    /// scheduler). Lookup by id so a list edit (insert/delete) doesn't shift
    /// the sheet onto the wrong row.
    @State private var rowEditingTaskId: UUID?
    /// Bug 4890bdee — row team picker, scheduler, and create-task-type
    /// sheets used to be three separate `.sheet(isPresented:)` modifiers
    /// attached only to `tutorialModeProjectContent`. In standard mode they
    /// were never in the view hierarchy, so tapping the team or date chip
    /// silently did nothing. The three are now driven by a single enum and
    /// presented from `mainProjectContent` (shared by both modes) via
    /// `.sheet(item:)`, which also dodges any multi-sheet stacking edge
    /// case.
    @State private var rowSheetTarget: RowSheetTarget?
    /// Local mirror of the row's dates while the scheduler sheet is open.
    /// Bound into `CalendarSchedulerSheet`, then written back to the row on
    /// confirm. Mirrors the pattern used by `TaskFormSheet`.
    @State private var rowSchedulerStart: Date = Date()
    @State private var rowSchedulerEnd: Date = Date()
    @State private var rowDatesExistedBeforeScheduler = false
    @State private var rowSchedulerConfirmed = false

    // Expanded sections tracking
    @State private var isBasicInfoExpanded = true // New: for client and project name
    @State private var isDescriptionExpanded = false
    @State private var isNotesExpanded = false
    @State private var isTasksExpanded = false
    @State private var isDatesExpanded = false
    @State private var isPhotosExpanded = false

    // Bug f86cf554 — deck design capture from the create-project form.
    // Shows the deck creation picker when tapped; the resulting DeckDesign
    // is held locally and attached to the project after save.
    @State private var showingDeckCreationPicker = false
    @State private var capturedDeckDesign: DeckDesign?
    /// Bug 55c9de66 — tapping "Blank Canvas" / similar should also OPEN the
    /// deck builder so the user can immediately start drawing. Without this
    /// the picker just dismissed and left a placeholder behind.
    @State private var showingDeckBuilderForCapture: DeckDesign?
    /// Bug 55c9de66 (re-fix) — handoff buffer between the picker sheet and
    /// the deck-builder fullScreenCover. Set in onDesignCreated, consumed in
    /// the picker sheet's onDismiss. Using a delay-based handoff was racing
    /// with the parent re-render triggered by capturedDeckDesign, so the
    /// cover silently failed to present on some devices. onDismiss fires
    /// deterministically once the picker is fully gone.
    @State private var pendingBuilderDesign: DeckDesign?

    // Section ordering - tracks which sections appear first
    @State private var sectionOrder: [OptionalSection] = [.description, .notes, .tasks, .photos]

    enum OptionalSection: CaseIterable, Hashable {
        case description
        case notes
        case tasks
        case photos
    }

    /// Bug 4890bdee — drives the single `.sheet(item:)` that hosts every
    /// inline-task-row sheet. Replaces three separate `@State` flags so the
    /// row sheets attach to the shared `mainProjectContent` and work in
    /// both tutorial and standard modes. Each case carries the row's
    /// `LocalTask.id` so a row reorder during presentation can't shift
    /// the sheet onto the wrong row.
    enum RowSheetTarget: Identifiable, Equatable {
        case team(UUID)
        case schedule(UUID)
        case createTaskType(UUID)

        var id: String {
            switch self {
            case .team(let id): return "team:\(id.uuidString)"
            case .schedule(let id): return "schedule:\(id.uuidString)"
            case .createTaskType(let id): return "createTaskType:\(id.uuidString)"
            }
        }

        var taskId: UUID {
            switch self {
            case .team(let id), .schedule(let id), .createTaskType(let id):
                return id
            }
        }
    }

    @State private var isSaving = false

    // Bug 3cc5aefa — duplicate project name detection. When the user tries
    // to create a project with a title that already exists in the same
    // company, surface an alert with a suggested alternative using the
    // word-suffix convention ("Backyard Deck Two", "Three"… up to "Ten",
    // then "11", "12"…). The user can edit the name, accept the
    // suggestion, or save anyway.
    @State private var showingDuplicateNameAlert = false
    @State private var suggestedAlternativeName: String = ""
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isStatusMenuFocused = false

    // Focus states for input fields
    @FocusState private var focusedField: FormField?

    // Temporary state for notes and description editing
    @State private var tempNotes: String = ""
    @State private var tempDescription: String = ""

    // Tutorial highlight animation state
    @State private var tutorialHighlightPulse: Bool = false

    // Bug 9d5c2535 — once the user has either tapped a recent-suggestion card
    // or typed into the form, hide the strip for the rest of the session even
    // if they clear inputs. Prevents flicker as fields toggle in and out of
    // empty.
    @State private var hasInteractedWithRecentSuggestions: Bool = false

    enum FormField: Hashable, CaseIterable {
        // Bug 705cc320 — site address sits above project name visually, so the
        // keyboard "next" chain follows the same order. The cases are
        // referenced by name elsewhere (tutorial auto-focus, onSubmit
        // handlers, advanceToNextField), so reordering is safe.
        case client
        case address
        case title
        case notes
        case description
    }

    /// Advances focus to the next field, or dismisses keyboard if at the last field
    /// In tutorial mode during projectFormName phase, dismisses keyboard and advances tutorial
    private func advanceToNextField() {
        guard let current = focusedField else {
            focusedField = nil
            return
        }

        // Tutorial mode: special handling for project name field
        if tutorialMode && current == .title && tutorialPhase == .projectFormName && !title.isEmpty {
            focusedField = nil // Dismiss keyboard
            NotificationCenter.default.post(
                name: Notification.Name("TutorialProjectNameEntered"),
                object: nil
            )
            return
        }

        let allFields = FormField.allCases
        if let currentIndex = allFields.firstIndex(of: current) {
            let nextIndex = currentIndex + 1
            if nextIndex < allFields.count {
                focusedField = allFields[nextIndex]
            } else {
                focusedField = nil // Dismiss keyboard at last field
            }
        } else {
            focusedField = nil
        }
    }

    private var isValid: Bool {
        !title.isEmpty && selectedClientId != nil
    }

    private var matchingClients: [Client] {
        // In tutorial mode, show all demo clients when text is empty for easy selection
        if tutorialMode && clientSearchText.isEmpty {
            return availableClients
        }
        guard !clientSearchText.isEmpty else { return [] }
        return availableClients.filter {
            $0.name.localizedCaseInsensitiveContains(clientSearchText)
        }
    }

    private var selectedClient: Client? {
        guard let selectedClientId = selectedClientId else { return nil }
        return allClients.first { $0.id == selectedClientId }
    }

    // Track which fields are populated for copy warnings
    private var populatedFields: Set<String> {
        var fields = Set<String>()
        if !title.isEmpty { fields.insert("name") }
        if selectedClientId != nil { fields.insert("client") }
        if !address.isEmpty { fields.insert("address") }
        if !description.isEmpty { fields.insert("description") }
        if !notes.isEmpty { fields.insert("notes") }
        if !localTasks.isEmpty { fields.insert("tasks") }
        return fields
    }

    // MARK: - Tutorial Phase Control

    /// Whether client field is enabled for current tutorial phase
    private var isClientFieldEnabled: Bool {
        guard tutorialMode else { return true }
        return tutorialPhase == .projectFormClient
    }

    /// Whether project name field is enabled for current tutorial phase
    private var isNameFieldEnabled: Bool {
        guard tutorialMode else { return true }
        return tutorialPhase == .projectFormName
    }

    /// Whether add task button is enabled for current tutorial phase
    private var isAddTaskEnabled: Bool {
        guard tutorialMode else { return true }
        return tutorialPhase == .projectFormAddTask
    }

    /// Whether CREATE button is enabled for current tutorial phase
    private var isCreateButtonEnabled: Bool {
        guard tutorialMode else { return true }
        return tutorialPhase == .projectFormComplete
    }

    /// Tutorial highlight state for client field
    private var clientHighlight: TutorialInputHighlight {
        let isHighlighted = tutorialMode && tutorialPhase == .projectFormClient
        return TutorialInputHighlight(isHighlighted: isHighlighted, animatePulse: tutorialHighlightPulse)
    }

    /// Tutorial highlight state for title field
    private var titleHighlight: TutorialInputHighlight {
        let isHighlighted = tutorialMode && tutorialPhase == .projectFormName
        return TutorialInputHighlight(isHighlighted: isHighlighted, animatePulse: tutorialHighlightPulse)
    }

    /// Tutorial highlight state for add tasks pill
    private var addTasksPillHighlight: TutorialInputHighlight {
        let isHighlighted = tutorialMode && tutorialPhase == .projectFormAddTask && !isTasksExpanded
        return TutorialInputHighlight(isHighlighted: isHighlighted, animatePulse: tutorialHighlightPulse)
    }

    /// Tutorial highlight state for add task button (inside expanded section)
    private var addTaskButtonHighlight: TutorialInputHighlight {
        let isHighlighted = tutorialMode && tutorialPhase == .projectFormAddTask && isTasksExpanded
        return TutorialInputHighlight(isHighlighted: isHighlighted, animatePulse: tutorialHighlightPulse)
    }

    // MARK: - Inline task row helpers

    /// Task types ordered most-recently-used first across the company, then
    /// alphabetical for the remainder. Mirrors `TaskFormSheet`'s ordering so
    /// the inline `Menu` shows the user's usual types at the top.
    private var recencyOrderedTaskTypes: [TaskType] {
        let alphaSorted = allTaskTypes.sorted { $0.display < $1.display }

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

    /// Tutorial-mode filtered + recency-ordered task types. The inline `Menu`
    /// inside a row reads from this so tutorial sessions only see DEMO_ types.
    private var availableInlineTaskTypes: [TaskType] {
        if tutorialMode {
            return recencyOrderedTaskTypes.filter { $0.id.hasPrefix("DEMO_") }
        }
        return recencyOrderedTaskTypes
    }

    /// Team-member `User` list ordered alphabetically, recency-promoted by the
    /// row's selected task type when available. Used to seed
    /// `TeamMemberPickerSheet` when launched from a row.
    private func teamUsersOrdered(forTaskTypeId taskTypeId: String?) -> [User] {
        let alphaSorted = fetchedTeamUsers.sorted {
            $0.fullName.localizedCompare($1.fullName) == .orderedAscending
        }

        guard let taskTypeId, !taskTypeId.isEmpty,
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

    /// `Set<String>` binding into a specific row's `teamMemberIds`, looked up
    /// by `LocalTask.id` so insertions/deletions during sheet presentation
    /// can't shift the binding onto the wrong row.
    private func teamSelectionBinding(forTaskId id: UUID) -> Binding<Set<String>> {
        Binding(
            get: {
                guard let idx = localTasks.firstIndex(where: { $0.id == id }) else {
                    return []
                }
                return Set(localTasks[idx].teamMemberIds)
            },
            set: { newValue in
                guard let idx = localTasks.firstIndex(where: { $0.id == id }) else { return }
                localTasks[idx].teamMemberIds = Array(newValue)
            }
        )
    }

    /// Local index for the row currently driving the presented sheets.
    private var rowEditingIndex: Int? {
        guard let id = rowEditingTaskId else { return nil }
        return localTasks.firstIndex(where: { $0.id == id })
    }

    /// Append a new blank row and immediately scroll attention to it.
    private func appendBlankTaskRow() {
        let defaultStatus: TaskStatus = .active
        withAnimation(.accessibleEaseInOut(duration: OPSStyle.Animation.durationPanel)) {
            localTasks.append(
                LocalTask(
                    id: UUID(),
                    taskTypeId: "",
                    status: defaultStatus
                )
            )
        }
        #if !targetEnvironment(simulator)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// Duplicate an existing row with a fresh id (mirrors the long-press
    /// "Duplicate" context-menu action).
    private func duplicateTaskRow(at index: Int) {
        guard localTasks.indices.contains(index) else { return }
        var copy = localTasks[index]
        copy = LocalTask(
            id: UUID(),
            taskTypeId: copy.taskTypeId,
            customTitle: copy.customTitle,
            status: copy.status,
            teamMemberIds: copy.teamMemberIds,
            startDate: copy.startDate,
            endDate: copy.endDate
        )
        withAnimation(.accessibleEaseInOut(duration: OPSStyle.Animation.durationPanel)) {
            localTasks.insert(copy, at: index + 1)
        }
        #if !targetEnvironment(simulator)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    /// Remove a row with the standard collapse animation. Mirrors the
    /// existing `localTasks.remove(at:)` callsite but adds the animation +
    /// haptic in a single place.
    private func removeTaskRow(at index: Int) {
        guard localTasks.indices.contains(index) else { return }
        withAnimation(.accessibleEaseInOut(duration: OPSStyle.Animation.durationPanel)) {
            _ = localTasks.remove(at: index)
        }
        #if !targetEnvironment(simulator)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    /// Open the team picker sheet for a specific row.
    private func presentTeamPicker(forTaskId id: UUID) {
        rowEditingTaskId = id
        rowSheetTarget = .team(id)
    }

    /// Open the scheduler sheet for a specific row, mirroring its current
    /// dates into the local scheduler state.
    private func presentScheduler(forTaskId id: UUID) {
        guard let idx = localTasks.firstIndex(where: { $0.id == id }) else { return }
        rowEditingTaskId = id
        let existingStart = localTasks[idx].startDate
        let existingEnd = localTasks[idx].endDate ?? existingStart
        rowDatesExistedBeforeScheduler = existingStart != nil
        rowSchedulerConfirmed = false
        rowSchedulerStart = existingStart ?? Date()
        rowSchedulerEnd = existingEnd ?? rowSchedulerStart
        rowSheetTarget = .schedule(id)
    }

    /// Open the create-task-type sheet for a specific row.
    private func presentCreateTaskType(forTaskId id: UUID) {
        rowEditingTaskId = id
        rowSheetTarget = .createTaskType(id)
    }

    /// Bug 4890bdee — fires when the single row-sheet binding nils out.
    /// Per-case cleanup runs based on the target that was dismissed; the
    /// `oldTarget` snapshot is captured by the `.onChange` modifier on
    /// `rowSheetTarget` so we know which sheet category just closed even
    /// though the binding has already cleared.
    private func handleRowSheetDismiss(oldTarget: RowSheetTarget) {
        switch oldTarget {
        case .schedule:
            // Mirror `TaskFormSheet` behaviour: if the scheduler was
            // dismissed without an explicit confirm AND no dates existed
            // before opening, clear the row's dates back out.
            if !rowSchedulerConfirmed && !rowDatesExistedBeforeScheduler,
               let idx = localTasks.firstIndex(where: { $0.id == oldTarget.taskId }) {
                localTasks[idx].startDate = nil
                localTasks[idx].endDate = nil
            }
        case .team, .createTaskType:
            break
        }
        rowEditingTaskId = nil
    }

    init(mode: Mode, preselectedClient: Client? = nil, initialTitle: String? = nil, onSave: @escaping (Project) -> Void) {
        self.mode = mode
        self.onSave = onSave

        // Pre-fill title if provided (e.g., from task form "New Project" action)
        if let initialTitle = initialTitle, mode.isCreate {
            _title = State(initialValue: initialTitle)
        }

        if case .edit(let project) = mode {
            _title = State(initialValue: project.title)
            _description = State(initialValue: project.projectDescription ?? "")
            _notes = State(initialValue: project.notes ?? "")
            _address = State(initialValue: project.address ?? "")
            _selectedClientId = State(initialValue: project.client?.id)
            _startDate = State(initialValue: project.startDate)
            _endDate = State(initialValue: project.endDate)

            // Auto-expand sections with data
            _isDescriptionExpanded = State(initialValue: !(project.projectDescription ?? "").isEmpty)
            _isNotesExpanded = State(initialValue: !(project.notes ?? "").isEmpty)
            _isDatesExpanded = State(initialValue: project.startDate != nil)

            // Convert project tasks to local tasks
            _localTasks = State(initialValue: project.tasks.map { task in
                LocalTask(
                    id: UUID(),
                    taskTypeId: task.taskTypeId,
                    customTitle: nil,
                    status: task.status
                )
            })
            _isTasksExpanded = State(initialValue: !project.tasks.isEmpty)
        } else if let preselectedClient = preselectedClient {
            // Pre-populate with client info when creating from client view
            _selectedClientId = State(initialValue: preselectedClient.id)
            if let billingAddress = preselectedClient.address, !billingAddress.isEmpty {
                _address = State(initialValue: billingAddress)
            }
        }
    }

    // MARK: - Helper Functions

    /// Move a section to the top of the display order when it's opened
    private func bringSectionToTop(_ section: OptionalSection) {
        // Remove the section from its current position
        sectionOrder.removeAll { $0 == section }
        // Insert it at the beginning
        sectionOrder.insert(section, at: 0)
    }

    var body: some View {
        // Tutorial mode uses custom header since NavigationView toolbar doesn't render in custom containers
        Group {
            if tutorialMode {
                tutorialModeProjectContent
            } else {
                standardProjectContent
            }
        }
        .onDisappear {
            NotificationCenter.default.post(
                name: Notification.Name("WizardScreenDismissed"),
                object: nil,
                userInfo: ["screen": "ProjectForm"]
            )
        }
        // Sheets present above the root view where wizardBanner / wizardOverlay
        // live, so the project-lifecycle guide is invisible here unless the
        // sheet re-attaches the wizard UI itself.
        .wizardBannerIfAvailable(stateManager: wizardStateManager)
        .wizardOverlayIfAvailable(stateManager: wizardStateManager)
    }

    /// Content with custom header for tutorial mode
    private var tutorialModeProjectContent: some View {
        ZStack {
            VStack(spacing: 0) {
                // Extra padding to push nav bar below tooltip during projectFormComplete phase
                if tutorialMode && tutorialPhase == .projectFormComplete {
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

                    Text(mode.isCreate ? "CREATE PROJECT" : "EDIT PROJECT")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    Button("CREATE") {
                        saveProject()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(isValid && isCreateButtonEnabled ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .disabled(!isValid || isSaving || !isCreateButtonEnabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .tutorialHighlight(for: .projectFormComplete, cornerRadius: 6)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(OPSStyle.Colors.background)

                // Divider
                Rectangle()
                    .fill(OPSStyle.Colors.cardBorder)
                    .frame(height: 1)

                mainProjectContent
                    .overlay(
                        Group {
                            if tutorialMode && tutorialPhase == .projectFormComplete {
                                OPSStyle.Colors.overlayMedium
                                    .allowsHitTesting(true)
                            }
                        }
                    )
            }

            // Radial gradient overlay centered on CREATE button for visibility
            if tutorialMode && tutorialPhase == .projectFormComplete {
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
        .sheet(isPresented: $showingCreateClient) {
            ClientSheet(mode: .create, prefilledName: clientSearchText) { newClient in
                selectedClientId = newClient.id
                clientSearchText = newClient.name
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialTaskSaved"))) { notification in
            if tutorialMode, let task = notification.userInfo?["task"] as? LocalTask {
                localTasks.append(task)
            }
        }
        .onAppear {
            // Tutorial mode: auto-set status to estimated
            if tutorialMode && mode.isCreate {
                selectedStatus = .estimated
                // Do NOT auto-expand tasks section - user must tap the pill
                isTasksExpanded = false
                // Do NOT auto-focus client field - let user tap to focus
                // Start pulse animation for highlights
                withAnimation(.easeInOut(duration: TutorialHighlightStyle.pulseDuration).repeatForever(autoreverses: true)) {
                    tutorialHighlightPulse = true
                }
            }
            // Bug 2daf95f2 — preload full `User` records for the inline
            // task-row team picker. The lightweight `[TeamMember]` `@Query`
            // is fine for counts, but `TeamMemberPickerSheet` wants `[User]`
            // so avatars resolve correctly.
            if let companyId = dataController.currentUser?.companyId {
                fetchedTeamUsers = dataController.getTeamMembers(companyId: companyId)
            }
        }
        .onChange(of: tutorialPhase) { _, newPhase in
            // Only auto-focus on phase change to project name (after client selection)
            // Client field should NOT be auto-focused - user taps to focus
            if tutorialMode {
                switch newPhase {
                case .projectFormName:
                    focusedField = .title
                default:
                    break
                }
            }
        }
        .loadingOverlay(isPresented: $isSaving, message: "Saving...")
    }

    /// Standard content with NavigationView
    private var standardProjectContent: some View {
        NavigationView {
            mainProjectContent
            .standardSheetToolbar(
                title: mode.isCreate ? "Create Project" : "Edit Project",
                actionText: mode.isCreate ? "Create" : "Save",
                isActionEnabled: isValid,
                isSaving: isSaving,
                onCancel: { dismiss() },
                onAction: { saveProject() }
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingCreateClient) {
            ClientSheet(mode: .create, prefilledName: clientSearchText) { newClient in
                selectedClientId = newClient.id
                clientSearchText = newClient.name
            }
        }
        .sheet(isPresented: $showingScheduler) {
            if let start = startDate, let end = endDate {
                CalendarSchedulerSheet(
                    isPresented: $showingScheduler,
                    itemType: .project(Project(id: UUID().uuidString, title: "Temp", status: .rfq)),
                    currentStartDate: start,
                    currentEndDate: end,
                    onScheduleUpdate: { newStart, newEnd in
                        startDate = newStart
                        endDate = newEnd
                    },
                    onClearDates: {
                        // Bug f3604d52 — Clear in the form-sheet resets the
                        // in-memory dates so the form reflects the reset
                        // immediately without needing a server round-trip.
                        startDate = nil
                        endDate = nil
                    }
                )
                .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingTaskForm) {
            TaskFormSheet(draftMode: editingTaskIndex != nil ?
                .draft(localTasks[editingTaskIndex!]) :
                .draft(nil)
            ) { savedTask in
                if let editIndex = editingTaskIndex {
                    localTasks[editIndex] = savedTask
                } else {
                    localTasks.append(savedTask)
                }
                editingTaskIndex = nil
            }
            .environmentObject(dataController)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TutorialTaskSaved"))) { notification in
            if tutorialMode, let task = notification.userInfo?["task"] as? LocalTask {
                localTasks.append(task)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        // Bug 3cc5aefa — collision alert when the entered title matches an
        // existing project in the same company. Three actions: edit the
        // name (cancel), accept the suffixed alternative, or save anyway.
        .alert("DUPLICATE NAME", isPresented: $showingDuplicateNameAlert) {
            Button("Use \"\(suggestedAlternativeName)\"") {
                title = suggestedAlternativeName
                proceedWithSave()
            }
            Button("Save anyway", role: .destructive) {
                proceedWithSave()
            }
            Button("Edit name", role: .cancel) { }
        } message: {
            Text("A project named \"\(title)\" already exists.")
        }
        .loadingOverlay(isPresented: $isSaving, message: "Saving...")
        .sheet(isPresented: $showingCopyFromProject) {
            CopyFromProjectSheet(
                onCopy: handleCopyFromProject,
                populatedFields: currentlyPopulatedFields
            )
        }
        // Bug f86cf554 — deck design capture from project create form.
        // Bug 55c9de66 (re-fix) — open the deck builder from onDismiss, not a
        // timed dispatch. SwiftUI calls onDismiss after the picker sheet is
        // fully gone, which is the only safe window to present another modal
        // from the same parent. The earlier 0.35s delay raced with the parent
        // re-render caused by capturedDeckDesign and dropped the cover
        // silently on some devices.
        .sheet(isPresented: $showingDeckCreationPicker, onDismiss: {
            if let design = pendingBuilderDesign {
                pendingBuilderDesign = nil
                showingDeckBuilderForCapture = design
            }
        }) {
            deckCreationPickerSheet
        }
        // Bug 55c9de66 — open the deck builder right after the user picks
        // their creation method so they can start drawing immediately.
        .fullScreenCover(item: $showingDeckBuilderForCapture) { design in
            if let mc = dataController.modelContext {
                // Bug ab554b5f — pass the syncEngine so the freshly-created
                // design pushes to Supabase as soon as the user draws.
                DeckBuilderView(
                    deckDesign: design,
                    modelContext: mc,
                    syncEngine: dataController.syncEngine
                )
            }
        }
    }

    /// Deck creation picker presented from the project form. The design is
    /// built with a placeholder projectId (empty string) since the real
    /// project id isn't known until after save — attachProjectIdToDeckDesign
    /// swaps the id in during the save cascade.
    /// Bug 55c9de66 — once a design is created we ALSO open the deck builder
    /// so the user can start drawing right away (the previous flow just
    /// stashed the design and returned to the form, which read as nothing
    /// happening).
    @ViewBuilder
    private var deckCreationPickerSheet: some View {
        let companyId = dataController.currentUser?.companyId ?? ""
        let userId = dataController.currentUser?.id
        CreationPickerView(
            projectId: nil, // attached after project is saved
            companyId: companyId,
            userId: userId,
            onDesignCreated: { design in
                // Stash the design for both attachment (capturedDeckDesign
                // re-parents on save) and for the post-dismiss handoff
                // (pendingBuilderDesign is consumed by the picker sheet's
                // onDismiss, which fires once iOS has fully torn down the
                // picker — the only safe window to present the builder
                // fullScreenCover from this same parent).
                capturedDeckDesign = design
                pendingBuilderDesign = design
                showingDeckCreationPicker = false
            }
        )
        .presentationDetents([.medium])
    }

    /// Main scrollable content
    private var mainProjectContent: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            ScrollView {
                    ScrollViewReader { proxy in
                        VStack(spacing: 24) {
                            // PREVIEW CARD (greyed out in tutorial mode to reduce distraction)
                            previewCard
                                .opacity(tutorialMode ? 0.3 : 1.0)
                                .allowsHitTesting(false)

                            // RECENT SUGGESTIONS — empty-state-only, one-tap structural clone.
                            // Bug 9d5c2535 — surfaces the operator's last-5 created projects
                            // so a duplicate job is a single tap instead of a full re-entry.
                            if shouldShowRecentSuggestions {
                                recentSuggestionsStrip
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // MANDATORY FIELDS (always visible)
                            mandatoryFieldsSection

                            // OPTIONAL SECTIONS
                            optionalSectionsArea
                                .onChange(of: sectionOrder) { _, _ in
                                    // Scroll to the first section in the order (most recently opened)
                                    if let firstSection = sectionOrder.first {
                                        // Small delay to allow expansion animation to complete
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            withAnimation {
                                                proxy.scrollTo(firstSection, anchor: .top)
                                            }
                                        }
                                    }
                                }
                                // Bug 705cc320 — when the tasks section is
                                // expanded for the first time and no tasks
                                // exist yet, append a blank row so the
                                // operator types into the chip instead of
                                // hunting for the "Add Task" button.
                                // Subsequent expansions (re-opens after
                                // collapse) leave existing rows alone.
                                // Skipped in tutorial mode — the scripted
                                // task-creation phase wants the empty state.
                                .onChange(of: isTasksExpanded) { oldValue, newValue in
                                    guard !oldValue, newValue, !tutorialMode,
                                          localTasks.isEmpty else { return }
                                    appendBlankTaskRow()
                                }

                        // COPY FROM BUTTON (at bottom) - disabled in tutorial mode
                        if mode.isCreate && !tutorialMode {
                            Button(action: { showingCopyFromProject = true }) {
                                HStack {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                        .foregroundColor(OPSStyle.Colors.primaryText)

                                    Text("COPY FROM PROJECT")
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                )
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, tutorialMode ? 100 : 24)
                    .onChange(of: tutorialPhase) { _, newPhase in
                        if tutorialMode && newPhase == .projectFormAddTask {
                            // Scroll after expansion animation completes
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation {
                                    proxy.scrollTo("addTaskButton", anchor: .center)
                                }
                            }
                        }
                    }
                    // Wizard system: auto-expand collapsed sections when a wizard step targets
                    // an element inside them (e.g., "add_task" is inside the TASKS section)
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardStepChanged"))) { notification in
                        guard let stepId = notification.userInfo?["stepId"] as? String else { return }
                        if stepId == "add_task" && !isTasksExpanded {
                            withAnimation(.accessibleEaseInOut()) {
                                bringSectionToTop(.tasks)
                                isTasksExpanded = true
                            }
                        }
                    }
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
                    // Bug 9d5c2535 — once the user types into the title, hide
                    // the recent-suggestions strip for the rest of the session.
                    // Clearing the title back to empty should not bring it back.
                    .onChange(of: title) { _, newValue in
                        if !newValue.isEmpty, !hasInteractedWithRecentSuggestions {
                            withAnimation(.accessibleEaseInOut()) {
                                hasInteractedWithRecentSuggestions = true
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
                    advanceToNextField()
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
        // Bug 4890bdee — single inline-task-row sheet attached to the
        // shared content so the team picker, scheduler, and create-task-
        // type flows present from both tutorial and standard modes. The
        // companion `.onChange` captures the dismissed target so per-case
        // cleanup (e.g. scheduler "clear dates on unconfirmed dismiss")
        // can run after the binding has nilled.
        .sheet(item: $rowSheetTarget) { target in
            rowSheet(for: target)
        }
        .onChange(of: rowSheetTarget) { oldValue, newValue in
            if let oldTarget = oldValue, newValue == nil {
                handleRowSheetDismiss(oldTarget: oldTarget)
            }
        }
    }

    // MARK: - Row sheet content (bug 4890bdee)

    /// Dispatches the row-sheet binding onto the correct child sheet for
    /// each case. Kept as a `@ViewBuilder` so the if-let unwraps stay
    /// readable per case.
    @ViewBuilder
    private func rowSheet(for target: RowSheetTarget) -> some View {
        switch target {
        case .team(let id):
            rowTeamPickerSheet(forTaskId: id)
        case .schedule(let id):
            rowSchedulerSheet(forTaskId: id)
        case .createTaskType:
            rowCreateTaskTypeSheet()
        }
    }

    @ViewBuilder
    private func rowTeamPickerSheet(forTaskId id: UUID) -> some View {
        if let idx = localTasks.firstIndex(where: { $0.id == id }) {
            let typeId = localTasks[idx].taskTypeId
            let ordered = teamUsersOrdered(forTaskTypeId: typeId)
            let recentIds: Set<String> = {
                guard !typeId.isEmpty,
                      let companyId = dataController.currentUser?.companyId else {
                    return []
                }
                return Set(dataController.recentTeamMemberIds(
                    forTaskType: typeId,
                    companyId: companyId
                ))
            }()
            TeamMemberPickerSheet(
                selectedTeamMemberIds: teamSelectionBinding(forTaskId: id),
                allTeamMembers: ordered,
                recentMemberIds: recentIds
            )
            .environmentObject(dataController)
        }
    }

    @ViewBuilder
    private func rowSchedulerSheet(forTaskId id: UUID) -> some View {
        if let idx = localTasks.firstIndex(where: { $0.id == id }) {
            let typeId = localTasks[idx].taskTypeId
            let teamIds = Set(localTasks[idx].teamMemberIds)
            CalendarSchedulerSheet(
                isPresented: schedulerIsPresentedBinding,
                itemType: .draftTask(
                    taskTypeId: typeId,
                    teamMemberIds: localTasks[idx].teamMemberIds,
                    projectId: nil
                ),
                currentStartDate: rowSchedulerStart,
                currentEndDate: rowSchedulerEnd,
                onScheduleUpdate: { newStart, newEnd in
                    rowSchedulerConfirmed = true
                    guard let editIdx = localTasks.firstIndex(where: { $0.id == id }) else { return }
                    localTasks[editIdx].startDate = newStart
                    localTasks[editIdx].endDate = newEnd
                },
                onClearDates: {
                    guard let editIdx = localTasks.firstIndex(where: { $0.id == id }) else { return }
                    localTasks[editIdx].startDate = nil
                    localTasks[editIdx].endDate = nil
                },
                preselectedTeamMemberIds: teamIds.isEmpty ? nil : teamIds
            )
            .environmentObject(dataController)
        }
    }

    @ViewBuilder
    private func rowCreateTaskTypeSheet() -> some View {
        TaskTypeSheet(mode: .create { newType in
            if let id = rowEditingTaskId,
               let idx = localTasks.firstIndex(where: { $0.id == id }) {
                localTasks[idx].taskTypeId = newType.id
            }
        })
        .environmentObject(dataController)
    }

    /// Bridges `CalendarSchedulerSheet`'s `isPresented:` Binding<Bool>
    /// parameter into the enum-driven row-sheet state — true while a
    /// `.schedule` target is presenting, settable to false to dismiss.
    private var schedulerIsPresentedBinding: Binding<Bool> {
        Binding(
            get: {
                if case .schedule = rowSheetTarget { return true }
                return false
            },
            set: { newValue in
                if !newValue { rowSheetTarget = nil }
            }
        )
    }

    // MARK: - Mandatory Fields Section

    private var mandatoryFieldsSection: some View {
        VStack(spacing: 16) {
            // Expandable section for client and project name
            if isBasicInfoExpanded {
                ExpandableSection(
                    title: "PROJECT DETAILS",
                    icon: "doc.text",
                    isExpanded: $isBasicInfoExpanded,
                    onDelete: nil, // Can't delete mandatory section
                    collapsible: false // Never show collapse chevron for mandatory section
                ) {
                    VStack(spacing: 16) {
                        clientField
                            .allowsHitTesting(isClientFieldEnabled)
                            .opacity(tutorialMode && !isClientFieldEnabled ? 0.5 : 1.0)
                        // Bug 705cc320 — site address sits above project name so
                        // operators anchor the job to a location before naming
                        // it. The autofill chips on the name field can then
                        // pull from the entered address without backtracking.
                        addressField
                            .allowsHitTesting(!tutorialMode)
                            .opacity(tutorialMode ? 0.5 : 1.0)
                        titleField
                            .allowsHitTesting(isNameFieldEnabled)
                            .opacity(tutorialMode && !isNameFieldEnabled ? 0.5 : 1.0)
                        statusField
                            .allowsHitTesting(!tutorialMode) // Always disabled in tutorial
                            .opacity(tutorialMode ? 0.5 : 1.0)

                        // Bug f86cf554 — deck design capture in project form.
                        // Only shown when deck builder feature is enabled for
                        // the company, and only in create mode (edit mode
                        // uses the ProjectDetailsView DECK tab).
                        if mode.isCreate,
                           !tutorialMode,
                           PermissionStore.shared.isFeatureEnabled("deck_builder"),
                           PermissionStore.shared.can("deck_builder.view") {
                            deckDesignField
                        }
                    }
                }
            }
        }
    }

    private var clientField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLIENT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(clientHighlight.labelColor)
                .modifier(TutorialPulseModifier(isHighlighted: clientHighlight.isHighlighted))

            if let selectedClient = selectedClient {
                selectedClientCard
            } else {
                clientSearchField
            }
        }
    }

    private var selectedClientCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedClient!.name)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                if let email = selectedClient!.email {
                    Text(email)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            Spacer()

            // Hide clear button in tutorial mode - prevents undoing client selection
            if !tutorialMode {
                Button(action: {
                    selectedClientId = nil
                    clientSearchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.clear)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var clientSearchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                TextField("Search or create client...", text: $clientSearchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .client)

                if !clientSearchText.isEmpty {
                    Button(action: {
                        clientSearchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(
                        clientHighlight.isHighlighted ? clientHighlight.borderColor : (focusedField == .client ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder),
                        lineWidth: clientHighlight.isHighlighted ? 2 : 1
                    )
                    .modifier(TutorialPulseModifier(isHighlighted: clientHighlight.isHighlighted))
            )
            .wizardTarget("select_client", style: .input)

            // Show suggestions when input is focused and (text is not empty OR in tutorial mode during client phase)
            if focusedField == .client && (!clientSearchText.isEmpty || (tutorialMode && tutorialPhase == .projectFormClient)) {
                VStack(spacing: 0) {
                    if matchingClients.isEmpty && !tutorialMode {
                        Button(action: { showingCreateClient = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                Text("Create \"\(clientSearchText)\"")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        }
                    } else {
                        ForEach(matchingClients.prefix(5)) { client in
                            Button(action: {
                                selectedClientId = client.id
                                clientSearchText = client.name
                                // Wizard system: notify client selected in project form
                                NotificationCenter.default.post(
                                    name: Notification.Name("WizardProjectClientSelected"),
                                    object: nil
                                )
                                // Tutorial mode: notify client selected
                                if tutorialMode {
                                    NotificationCenter.default.post(
                                        name: Notification.Name("TutorialClientSelected"),
                                        object: nil
                                    )
                                }
                            }) {
                                HStack {
                                    Text(client.name)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if client.id != matchingClients.prefix(5).last?.id {
                                Divider()
                                    .background(OPSStyle.Colors.cardBorder)
                            }
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("PROJECT NAME")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(titleHighlight.labelColor)
                    .modifier(TutorialPulseModifier(isHighlighted: titleHighlight.isHighlighted))

                Spacer()

                if !tutorialMode {
                    // Client name prefill button
                    Button {
                        if let name = selectedClient?.name {
                            title = name
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: OPSStyle.Icons.client)
                                .font(.system(size: 10))
                            Text("CLIENT")
                                .font(OPSStyle.Typography.microLabel)
                        }
                        .foregroundColor(selectedClient != nil ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    }
                    .disabled(selectedClient == nil)

                    // Address prefill button
                    Button {
                        if let street = extractStreetNumber(from: address) {
                            title = street
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: OPSStyle.Icons.locationFill)
                                .font(.system(size: 10))
                            Text("ADDRESS")
                                .font(OPSStyle.Typography.microLabel)
                        }
                        .foregroundColor(!address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    }
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            TextField("Enter project name", text: $title)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .title)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(
                            titleHighlight.isHighlighted ? titleHighlight.borderColor : (focusedField == .title ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder),
                            lineWidth: titleHighlight.isHighlighted ? 2 : 1
                        )
                        .modifier(TutorialPulseModifier(isHighlighted: titleHighlight.isHighlighted))
                )
                .onSubmit {
                    // Wizard system: notify project name entered on keyboard dismiss
                    if !title.isEmpty {
                        NotificationCenter.default.post(
                            name: Notification.Name("WizardProjectNameEntered"),
                            object: nil
                        )
                    }
                    // Tutorial mode
                    if tutorialMode && !title.isEmpty {
                        NotificationCenter.default.post(
                            name: Notification.Name("TutorialProjectNameEntered"),
                            object: nil
                        )
                    }
                }
                .onChange(of: focusedField) { oldValue, newValue in
                    // Wizard system: also fire when field loses focus (tap away)
                    if oldValue == .title && newValue != .title && !title.isEmpty {
                        NotificationCenter.default.post(
                            name: Notification.Name("WizardProjectNameEntered"),
                            object: nil
                        )
                    }
                }
                .wizardTarget("enter_project_name", style: .input)

            // Autofill suggestions (hidden in tutorial mode)
            if !tutorialMode && title.isEmpty {
                autofillSuggestions
            }
        }
    }

    /// Quick-fill chips for project name based on client and address
    @ViewBuilder
    private var autofillSuggestions: some View {
        let clientName = selectedClient?.name
        let streetAddress = extractStreetNumber(from: address)
        let hasSuggestions = clientName != nil || streetAddress != nil

        if hasSuggestions {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    if let name = clientName {
                        autofillChip(label: name) {
                            title = name
                        }
                    }

                    if let street = streetAddress {
                        autofillChip(label: street) {
                            title = street
                        }
                    }

                    if let name = clientName, let street = streetAddress {
                        autofillChip(label: "\(street) - \(name)") {
                            title = "\(street) - \(name)"
                        }
                    }
                }
            }
        }
    }

    private func autofillChip(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(OPSStyle.Colors.primaryAccent.opacity(0.1))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
    }

    /// Extract street number and name from an address string (e.g. "123 Main St, City, ST" → "123 Main St")
    private func extractStreetNumber(from fullAddress: String) -> String? {
        let trimmed = fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let components = trimmed.components(separatedBy: ",")
        if let street = components.first?.trimmingCharacters(in: .whitespaces), !street.isEmpty {
            return street
        }
        return nil
    }

    private var statusField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("JOB STATUS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Menu {
                ForEach(Status.allCases, id: \.self) { status in
                    Button(action: {
                        selectedStatus = status
                        defaultProjectStatusRaw = status.rawValue
                        // Unfocus when selection is made
                        withAnimation(OPSStyle.Animation.fast) {
                            isStatusMenuFocused = false
                        }
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
                    Text(selectedStatus.displayName.uppercased())
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(
                            isStatusMenuFocused ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    withAnimation(OPSStyle.Animation.fast) {
                        isStatusMenuFocused = true
                    }
                }
            )
        }
    }

    // MARK: - Optional Sections Area

    private var optionalSectionsArea: some View {
        VStack(spacing: 16) {
            // Collapsed pills for unexpanded sections
            // In tutorial mode, all pills except ADD TASKS are disabled
            OptionalSectionPillGroup(
                pills: [
                    (title: "DESCRIPTION", icon: "text.alignleft", isExpanded: isDescriptionExpanded,
                     isDisabled: tutorialMode, isHighlighted: false, action: {
                        withAnimation(.accessibleEaseInOut()) {
                            bringSectionToTop(.description)
                            isDescriptionExpanded = true
                        }
                    }),
                    (title: "NOTES", icon: "note.text", isExpanded: isNotesExpanded,
                     isDisabled: tutorialMode, isHighlighted: false, action: {
                        withAnimation(.accessibleEaseInOut()) {
                            bringSectionToTop(.notes)
                            isNotesExpanded = true
                        }
                    }),
                    (title: "ADD TASKS", icon: "checklist", isExpanded: isTasksExpanded,
                     isDisabled: tutorialMode && !isAddTaskEnabled, isHighlighted: addTasksPillHighlight.isHighlighted, action: {
                        withAnimation(.accessibleEaseInOut()) {
                            bringSectionToTop(.tasks)
                            isTasksExpanded = true
                        }
                    }),
                    (title: "PHOTOS", icon: "photo", isExpanded: isPhotosExpanded,
                     isDisabled: tutorialMode, isHighlighted: false, action: {
                        withAnimation(.accessibleEaseInOut()) {
                            bringSectionToTop(.photos)
                            isPhotosExpanded = true
                        }
                    })
                ],
                highlightPulse: tutorialHighlightPulse
            )

            // Expanded sections - displayed in dynamic order
            ForEach(sectionOrder, id: \.self) { section in
                switch section {
                case .description:
                    if isDescriptionExpanded {
                        descriptionSection
                            .id(OptionalSection.description)
                    }
                case .notes:
                    if isNotesExpanded {
                        notesSection
                            .id(OptionalSection.notes)
                    }
                case .tasks:
                    if isTasksExpanded {
                        tasksSection
                            .id(OptionalSection.tasks)
                    }
                case .photos:
                    if isPhotosExpanded {
                        photosSection
                            .id(OptionalSection.photos)
                    }
                }
            }
        }
    }

    // MARK: - Optional Section Views

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SITE ADDRESS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                if let client = selectedClient, let billingAddress = client.address, !billingAddress.isEmpty {
                    Button(action: {
                        address = billingAddress
                        #if !targetEnvironment(simulator)
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        #endif
                    }) {
                        Text("USE BILLING ADDRESS")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }

            AddressAutocompleteField(
                address: $address,
                placeholder: "Enter project address",
                onAddressSelected: { fullAddress, coordinates in
                    address = fullAddress
                    if let coords = coordinates {
                        latitude = coords.latitude
                        longitude = coords.longitude
                    }
                }
            )
        }
    }

    /// Bug f86cf554 — deck design capture button shown in the project create
    /// form. Tapping launches CreationPickerView; the resulting DeckDesign is
    /// stashed in capturedDeckDesign and re-parented to the real project id
    /// after save.
    private var deckDesignField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DECK DESIGN")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingDeckCreationPicker = true
            }) {
                HStack(spacing: 12) {
                    Image(systemName: capturedDeckDesign == nil ? "ruler" : "checkmark.circle.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(capturedDeckDesign == nil ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.successStatus)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(capturedDeckDesign == nil ? "Record Deck Design" : "Deck Design Attached")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text(capturedDeckDesign == nil
                             ? "Optional — capture now or add later"
                             : "Tap to replace")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

                    Spacer()

                    if capturedDeckDesign != nil {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            capturedDeckDesign = nil
                        } label: {
                            Image(systemName: OPSStyle.Icons.xmark)
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .padding(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .padding(14)
                .frame(minHeight: 44)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(capturedDeckDesign == nil ? OPSStyle.Colors.inputFieldBorder : OPSStyle.Colors.successStatus.opacity(0.4),
                                lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var descriptionSection: some View {
        ExpandableSection(
            title: "DESCRIPTION",
            icon: "text.alignleft",
            isExpanded: $isDescriptionExpanded,
            onDelete: {
                description = ""
                withAnimation(.accessibleEaseInOut()) {
                    isDescriptionExpanded = false
                }
                #if !targetEnvironment(simulator)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            }
        ) {
            VStack(spacing: 12) {
                TextEditor(text: focusedField == .description ? $tempDescription : $description)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(minHeight: 100)
                    .padding(12)
                    .background(Color.clear)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .scrollContentBackground(.hidden)
                    .focused($focusedField, equals: .description)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(
                                focusedField == .description ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder,
                                lineWidth: OPSStyle.Layout.Border.standard
                            )
                    )
                    .onChange(of: focusedField) { oldValue, newValue in
                        if newValue == .description && oldValue != .description {
                            tempDescription = description
                        }
                    }

                if focusedField == .description {
                    HStack(spacing: 16) {
                        Spacer()

                        Button("CANCEL") {
                            tempDescription = ""
                            focusedField = nil
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                        Button("SAVE") {
                            description = tempDescription
                            focusedField = nil
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        ExpandableSection(
            title: "NOTES",
            icon: "note.text",
            isExpanded: $isNotesExpanded,
            onDelete: {
                notes = ""
                withAnimation(.accessibleEaseInOut()) {
                    isNotesExpanded = false
                }
                #if !targetEnvironment(simulator)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            }
        ) {
            VStack(spacing: 12) {
                TextEditor(text: focusedField == .notes ? $tempNotes : $notes)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(minHeight: 80)
                    .padding(12)
                    .background(Color.clear)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .scrollContentBackground(.hidden)
                    .focused($focusedField, equals: .notes)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(
                                focusedField == .notes ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder,
                                lineWidth: OPSStyle.Layout.Border.standard
                            )
                    )
                    .onChange(of: focusedField) { oldValue, newValue in
                        if newValue == .notes && oldValue != .notes {
                            tempNotes = notes
                        }
                    }

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
                            notes = tempNotes
                            focusedField = nil
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
        }
    }

    private var tasksSection: some View {
        ExpandableSection(
            title: "ADD TASKS",
            icon: "checklist",
            isExpanded: $isTasksExpanded,
            onDelete: {
                withAnimation(.accessibleEaseInOut(duration: OPSStyle.Animation.durationPanel)) {
                    localTasks.removeAll()
                    isTasksExpanded = false
                }
                #if !targetEnvironment(simulator)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            }
        ) {
            VStack(spacing: OPSStyle.Layout.spacing2_5) {
                if !localTasks.isEmpty {
                    VStack(spacing: OPSStyle.Layout.spacing2_5) {
                        ForEach(Array(localTasks.enumerated()), id: \.element.id) { index, task in
                            inlineRow(for: task, at: index)
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .top)),
                                        removal: .opacity
                                    )
                                )
                        }
                    }
                }

                addRowButton
            }
        }
    }

    private func inlineRow(for task: LocalTask, at index: Int) -> some View {
        InlineTaskRow(
            task: task,
            availableTaskTypes: availableInlineTaskTypes,
            teamMemberCount: uniqueTeamMembers.filter { task.teamMemberIds.contains($0.id) }.count,
            isEnabled: !tutorialMode,
            onTaskTypeChange: { newTypeId in
                guard localTasks.indices.contains(index) else { return }
                localTasks[index].taskTypeId = newTypeId
            },
            onCreateNewTaskType: {
                presentCreateTaskType(forTaskId: task.id)
            },
            onTeamTap: {
                presentTeamPicker(forTaskId: task.id)
            },
            onDateTap: {
                presentScheduler(forTaskId: task.id)
            },
            onStatusChange: { newStatus in
                guard localTasks.indices.contains(index) else { return }
                localTasks[index].status = newStatus
            },
            onOpenFullEditor: {
                editingTaskIndex = index
                showingTaskForm = true
            },
            onDuplicate: {
                duplicateTaskRow(at: index)
            },
            onDelete: {
                removeTaskRow(at: index)
            }
        )
    }

    /// "Add row" button — dashed-bordered, primary-accent, matches the
    /// previous "+ Add Task" affordance so the tutorial highlight and
    /// `wizardTarget("add_task")` keep working unchanged.
    private var addRowButton: some View {
        Button(action: handleAddRowTap) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.plusCircleFill)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                Text(localTasks.isEmpty ? "Add Task" : "Add Another Task")
                    .font(OPSStyle.Typography.body)
            }
            .foregroundColor(
                addTaskButtonHighlight.isHighlighted
                    ? addTaskButtonHighlight.labelColor
                    : OPSStyle.Colors.opsAccent
            )
            .modifier(TutorialPulseModifier(isHighlighted: addTaskButtonHighlight.isHighlighted))
            .frame(maxWidth: .infinity)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(
                        addTaskButtonHighlight.isHighlighted
                            ? addTaskButtonHighlight.borderColor
                            : OPSStyle.Colors.opsAccent.opacity(OPSStyle.Layout.Opacity.light),
                        style: addTaskButtonHighlight.isHighlighted
                            ? StrokeStyle(lineWidth: OPSStyle.Layout.Border.thick)
                            : StrokeStyle(lineWidth: OPSStyle.Layout.Border.thick, dash: [5])
                    )
                    .modifier(TutorialPulseModifier(isHighlighted: addTaskButtonHighlight.isHighlighted))
            )
        }
        .wizardTarget("add_task")
        .allowsHitTesting(isAddTaskEnabled)
        .opacity(tutorialMode && !isAddTaskEnabled ? OPSStyle.Layout.Opacity.medium : 1.0)
        .id("addTaskButton")
    }

    /// Tutorial-aware tap handler for the add-row button. In tutorial mode
    /// the wrapper still opens the legacy `TaskFormSheet` so the scripted
    /// task-creation phase has its expected target; outside tutorial we
    /// append a blank inline row.
    private func handleAddRowTap() {
        if tutorialMode {
            editingTaskIndex = nil
            NotificationCenter.default.post(
                name: Notification.Name("TutorialAddTaskTapped"),
                object: nil
            )
            return
        }
        appendBlankTaskRow()
    }

    private var photosSection: some View {
        ExpandableSection(
            title: "PROJECT PHOTOS",
            icon: "photo",
            isExpanded: $isPhotosExpanded,
            onDelete: {
                projectImages.removeAll()
                withAnimation(.accessibleEaseInOut()) {
                    isPhotosExpanded = false
                }
                #if !targetEnvironment(simulator)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            }
        ) {
            if !projectImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(projectImages.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipped()
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(alignment: .topTrailing) {
                                    Button(action: { removeImage(at: index) }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .bold))
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                            .frame(width: 24, height: 24)
                                            .background(
                                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                    .fill(OPSStyle.Colors.imageOverlay)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                    .stroke(OPSStyle.Colors.pinDotNeutral, lineWidth: OPSStyle.Layout.Border.standard)
                                            )
                                    }
                                    .padding(OPSStyle.Layout.spacing2)
                                }
                        }

                        Button(action: { showingPhotoSourceChooser = true }) {
                            VStack {
                                Image(systemName: "plus")
                                    .font(.system(size: OPSStyle.Layout.IconSize.lg))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .frame(width: 100, height: 100)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(style: StrokeStyle(lineWidth: OPSStyle.Layout.Border.thick, dash: [5]))
                                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.5))
                            )
                        }
                    }
                }
            } else {
                Button(action: { showingPhotoSourceChooser = true }) {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                        Text("Add Photos")
                            .font(OPSStyle.Typography.body)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(style: StrokeStyle(lineWidth: OPSStyle.Layout.Border.thick, dash: [5]))
                            .foregroundColor(OPSStyle.Colors.primaryAccent.opacity(0.3))
                    )
                }
            }
        }
        // Bug 02222904 — confirmation dialog lets the user pick between
        // the multi-capture camera and the photo library before any
        // sheet opens. Cancel just dismisses; both paths feed into the
        // same `projectImages` array so the form preview updates the
        // moment images return.
        .confirmationDialog(
            "Add Photos",
            isPresented: $showingPhotoSourceChooser,
            titleVisibility: .visible
        ) {
            // Camera path — only offered when a real camera is present
            // so the simulator doesn't show a button that does nothing.
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photos") {
                    showingCameraBatch = true
                }
            }
            Button("Choose from Library") {
                showingImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Capture photos with the camera or pick existing ones from your library.")
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(
                images: $projectImages,
                allowsEditing: false,
                selectionLimit: 10,
                onSelectionComplete: {
                    showingImagePicker = false
                }
            )
        }
        .fullScreenCover(isPresented: $showingCameraBatch) {
            // Same multi-capture stack used inside ProjectDetailsView —
            // reuse the component so the project creation flow gets the
            // identical stack/review behaviour for free.
            CameraBatchView { capturedImages in
                projectImages.append(contentsOf: capturedImages)
            }
        }
    }

    /// Fields that currently have data (for copy overwrite warning)
    private var currentlyPopulatedFields: Set<String> {
        var fields = Set<String>()
        if !title.isEmpty { fields.insert("name") }
        if selectedClientId != nil { fields.insert("client") }
        if !address.isEmpty { fields.insert("address") }
        if !description.isEmpty { fields.insert("description") }
        if !notes.isEmpty { fields.insert("notes") }
        if !localTasks.isEmpty { fields.insert("tasks") }
        return fields
    }

    // MARK: - Preview Card

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            // Title
                            Text(title.isEmpty ? "PROJECT NAME" : title.uppercased())
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(title.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                                .lineLimit(1)

                            // Client name
                            Text(selectedClient?.name ?? "NO CLIENT SELECTED")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(selectedClient == nil ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                                .lineLimit(1)
                        }

                        Spacer()
                    }

                    // Metadata row
                    HStack(spacing: 12) {
                        // Address
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle")
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(address.isEmpty ? "NO ADDRESS" : address.components(separatedBy: ",").first ?? address)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }

                        // Calendar icon + date
                        HStack(spacing: 4) {
                            Image(systemName: OPSStyle.Icons.calendar)
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            // Show earliest task date or dash if no tasks have dates
                            if let earliestDate = localTasks.compactMap({ $0.startDate }).min() {
                                Text(DateHelper.simpleDateString(from: earliestDate))
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            } else {
                                Text("—")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }

                        // Team icon + unique count across all tasks
                        HStack(spacing: 4) {
                            Image(systemName: OPSStyle.Icons.personTwo)
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            let uniqueTeamMemberIds = Set(localTasks.flatMap { $0.teamMemberIds })
                            Text("\(uniqueTeamMemberIds.count)")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }

                        Spacer()
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .overlay(
                // Badge stack - right side
                VStack(alignment: .trailing, spacing: 0) {
                    // Status badge - top
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

                    // Task count badge
                    if !localTasks.isEmpty {
                        Text("\(localTasks.count) \(localTasks.count == 1 ? "TASK" : "TASKS")")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .fill(OPSStyle.Colors.cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(OPSStyle.Colors.secondaryText.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
                            )

                        Spacer()
                    }

                    // Unscheduled badge - show if any tasks have no dates
                    if !localTasks.filter({ $0.startDate == nil }).isEmpty {
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
                    } else if !localTasks.isEmpty {
                        Color.clear.frame(height: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(8)
            )
        }
        .opacity(0.7) // Slightly faded to indicate it's a preview
    }

    // MARK: - Recent Suggestions (Bug 9d5c2535)

    /// Empty-state gate. The strip is for first-action friction reduction;
    /// once anything has been entered or a card tapped, it stays hidden.
    private var shouldShowRecentSuggestions: Bool {
        guard mode.isCreate,
              !tutorialMode,
              !hasInteractedWithRecentSuggestions,
              title.isEmpty,
              selectedClientId == nil,
              localTasks.isEmpty,
              address.isEmpty,
              description.isEmpty,
              notes.isEmpty
        else { return false }
        return !recentSuggestedProjects.isEmpty
    }

    /// Last 5 projects created by the current user, newest first, scoped to
    /// tutorial mode when active. Excludes pre-migration rows (createdAt nil)
    /// and soft-deleted rows.
    private var recentSuggestedProjects: [Project] {
        guard let userId = dataController.currentUser?.id else { return [] }
        let candidates = tutorialMode
            ? allProjects.filter { $0.id.hasPrefix("DEMO_") }
            : Array(allProjects)
        return dataController.recentlyCreatedProjects(
            by: userId,
            from: candidates,
            limit: 5
        )
    }

    private var recentSuggestionsStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("START FROM RECENT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentSuggestedProjects) { project in
                        recentSuggestionCard(for: project)
                            .contentShape(Rectangle())
                            .onTapGesture { applyStructuralClone(from: project) }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func recentSuggestionCard(for project: Project) -> some View {
        let taskCount = project.tasks.filter { $0.deletedAt == nil }.count
        let relative: String = {
            guard let created = project.createdAt else { return "" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: created, relativeTo: Date()).uppercased()
        }()

        return VStack(alignment: .leading, spacing: 6) {
            Text(project.title.uppercased())
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if taskCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: OPSStyle.Icons.task)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("\(taskCount) TASK\(taskCount == 1 ? "" : "S")")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                if !relative.isEmpty {
                    Text(relative)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(width: 160, height: 80, alignment: .topLeading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    /// One-tap structural clone (C2 — "same shape, new job"). Copies tasks
    /// only — title, client, address, dates, notes, description, images all
    /// stay blank. After the copy the title field is focused so the operator
    /// can name the new job immediately.
    private func applyStructuralClone(from source: Project) {
        #if !targetEnvironment(simulator)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        let taskPayload: [[String: Any]] = source.tasks
            .filter { $0.deletedAt == nil }
            .map { task in
                return [
                    "taskTypeId": task.taskTypeId,
                    "status": TaskStatus.active.rawValue,
                    "teamMemberIds": task.getTeamMemberIds()
                ]
            }

        withAnimation(.accessibleEaseInOut()) {
            hasInteractedWithRecentSuggestions = true
        }

        // Reuse the existing copy-from apply logic so animations, expansion,
        // and haptics stay consistent with the deep copy-from sheet flow.
        handleCopyFromProject(["tasks": taskPayload])

        // Focus the title field so the operator's next move is to name it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            focusedField = .title
        }
    }

    // MARK: - Helper Methods

    private func handleCopyFromProject(_ copiedData: [String: Any]) {
        // Apply copied data with animation
        if let name = copiedData["name"] as? String {
            title = name
        }

        if let clientId = copiedData["clientId"] as? String {
            selectedClientId = clientId
            if let client = allClients.first(where: { $0.id == clientId }) {
                clientSearchText = client.name
            }
        }

        if let addressValue = copiedData["address"] as? String {
            address = addressValue
        }

        if let descriptionValue = copiedData["description"] as? String {
            description = descriptionValue
            withAnimation(.accessibleEaseInOut()) {
                isDescriptionExpanded = true
            }
        }

        if let notesValue = copiedData["notes"] as? String {
            notes = notesValue
            withAnimation(.accessibleEaseInOut()) {
                isNotesExpanded = true
            }
        }

        if let taskData = copiedData["tasks"] as? [[String: Any]] {
            let newTasks = taskData.compactMap { taskDict -> LocalTask? in
                guard let taskTypeId = taskDict["taskTypeId"] as? String,
                      let statusRaw = taskDict["status"] as? String,
                      let status = TaskStatus(rawValue: statusRaw) else {
                    return nil
                }

                // Extract optional fields
                let teamMemberIds = taskDict["teamMemberIds"] as? [String] ?? []
                let startDate = taskDict["startDate"] as? Date
                let endDate = taskDict["endDate"] as? Date

                return LocalTask(
                    id: UUID(),
                    taskTypeId: taskTypeId,
                    customTitle: nil,
                    status: status,
                    teamMemberIds: teamMemberIds,
                    startDate: startDate,
                    endDate: endDate
                )
            }
            localTasks.append(contentsOf: newTasks)
            withAnimation(.accessibleEaseInOut()) {
                isTasksExpanded = true
            }
        }

        #if !targetEnvironment(simulator)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    private func removeImage(at index: Int) {
        guard index < projectImages.count else { return }
        projectImages.remove(at: index)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func saveProject() {
        // Prevent double-tap race condition
        guard !isSaving else {
            print("[PROJECT_SAVE] ⚠️ Save already in progress, ignoring duplicate call")
            return
        }

        // Bug 3cc5aefa — check for an existing project with the same title
        // before proceeding (create-mode only; edit-mode user is by definition
        // already on an existing row). If one exists, prompt with a suffixed
        // alternative; the user picks Cancel / Use suggestion / Save Anyway.
        if case .create = mode,
           let alternative = duplicateProjectNameAlternative(for: title) {
            suggestedAlternativeName = alternative
            showingDuplicateNameAlert = true
            return
        }

        proceedWithSave()
    }

    /// Returns the existing project's suggested alternative name when the
    /// trimmed entered title matches another project in the same company.
    /// `nil` means no collision — caller should proceed with save.
    ///
    /// The suggestion uses word suffixes ("Two".."Ten") then numeric
    /// ("11", "12"…) per the user's "deck two" bug example. If the
    /// entered title already ends with an ordinal suffix, the next
    /// ordinal is used so collisions chain naturally: "Deck Two" →
    /// "Deck Three" → "Deck Four"…
    private func duplicateProjectNameAlternative(for rawTitle: String) -> String? {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Scope to the current user's company. `getAllProjects()` returns
        // the local SwiftData store, which sync already scopes to the
        // user's company — the explicit filter is defensive in case a
        // stale row from a prior company lingers.
        let scopedCompanyId = dataController.currentUser?.companyId
        let existingTitles = dataController.getAllProjects()
            .filter { $0.deletedAt == nil }
            .filter { project in
                guard let scopedCompanyId, !scopedCompanyId.isEmpty else { return true }
                return project.companyId == scopedCompanyId
            }
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let existingSet = Set(existingTitles)

        guard existingSet.contains(trimmed.lowercased()) else { return nil }

        let (baseName, startOrdinal) = Self.stripOrdinalSuffix(trimmed)
        for n in startOrdinal...999 {
            let candidate = "\(baseName) \(Self.ordinalSuffix(for: n))"
            if !existingSet.contains(candidate.lowercased()) {
                return candidate
            }
        }
        // Practically unreachable — would require 998 colliding titles.
        return nil
    }

    /// Convert a 1-indexed ordinal (>= 2) to its OPS suffix form.
    /// 2..10 → "Two".."Ten"; 11+ → numeric string.
    fileprivate static func ordinalSuffix(for n: Int) -> String {
        switch n {
        case 2: return "Two"
        case 3: return "Three"
        case 4: return "Four"
        case 5: return "Five"
        case 6: return "Six"
        case 7: return "Seven"
        case 8: return "Eight"
        case 9: return "Nine"
        case 10: return "Ten"
        default: return String(n)
        }
    }

    /// Detect an existing ordinal suffix on a title and return the base
    /// name (sans suffix) along with the next ordinal to try.
    /// "Deck"        → ("Deck", 2)
    /// "Deck Two"    → ("Deck", 3)
    /// "Deck Three"  → ("Deck", 4)
    /// "Deck 11"     → ("Deck", 12)
    fileprivate static func stripOrdinalSuffix(_ title: String) -> (base: String, nextOrdinal: Int) {
        let wordOrdinals: [(suffix: String, ordinal: Int)] = [
            ("Ten", 10), ("Nine", 9), ("Eight", 8), ("Seven", 7),
            ("Six", 6), ("Five", 5), ("Four", 4), ("Three", 3), ("Two", 2)
        ]
        let lowered = title.lowercased()
        for (suffix, ordinal) in wordOrdinals {
            let needle = " \(suffix.lowercased())"
            if lowered.hasSuffix(needle) {
                let base = String(title.dropLast(needle.count))
                return (base, ordinal + 1)
            }
        }
        if let spaceIndex = title.lastIndex(of: " ") {
            let tail = title[title.index(after: spaceIndex)...]
            if let numericPart = Int(tail) {
                let base = String(title[..<spaceIndex])
                return (base, numericPart + 1)
            }
        }
        return (title, 2)
    }

    /// Internal save path used both by the direct save button and by the
    /// duplicate-name alert when the user accepts the suggestion or chooses
    /// Save Anyway.
    private func proceedWithSave() {
        guard !isSaving else { return }
        isSaving = true

        Task {
            do {
                let project: Project

                if case .create = mode {
                    project = try await createNewProject()
                } else if case .edit(let existingProject) = mode {
                    try await updateExistingProject(existingProject)
                    project = existingProject
                } else {
                    return
                }

                await MainActor.run {
                    #if !targetEnvironment(simulator)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    #endif

                    // Post notification for success message overlay (only for new projects)
                    if case .create = mode {
                        NotificationCenter.default.post(
                            name: Notification.Name("ProjectCreatedSuccess"),
                            object: nil,
                            userInfo: ["projectTitle": title]
                        )
                        // Wizard system: notify project saved
                        NotificationCenter.default.post(
                            name: Notification.Name("WizardProjectSaved"),
                            object: nil
                        )
                    }

                    // Tutorial mode: notify project form complete with project ID for cleanup
                    if tutorialMode {
                        NotificationCenter.default.post(
                            name: Notification.Name("TutorialProjectFormComplete"),
                            object: nil,
                            userInfo: ["projectId": project.id]
                        )
                    }

                    onSave(project)

                    // Brief delay for graceful dismissal
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    #if !targetEnvironment(simulator)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    #endif

                    errorMessage = error.localizedDescription
                    showingError = true
                    isSaving = false
                }
            }
        }
    }

    private func createNewProject() async throws -> Project {
        print("[PROJECT_CREATE] Starting project creation")

        guard let companyId = dataController.currentUser?.companyId,
              let client = selectedClient else {
            print("[PROJECT_CREATE] ❌ Missing required fields")
            throw ProjectError.missingRequiredFields
        }

        // Use DEMO_ prefix in tutorial mode for cleanup.
        // Bug f86cf554 — canonicalize to lowercase so the local id matches
        // Postgres (uuid columns are lowercase). Uppercase UUIDs from
        // Swift's UUID().uuidString caused fetch-by-id in InboundProcessor
        // to miss the realtime echo, inserting a second row.
        let projectId = tutorialMode
            ? "DEMO_PROJECT_\(UUID().uuidString)"
            : UUID().uuidString.lowercased()
        print("[PROJECT_CREATE] Creating project locally with ID: \(projectId)")

        let project = Project(
            id: projectId,
            title: title,
            status: selectedStatus
        )

        project.companyId = companyId
        project.client = client
        project.clientId = client.id
        project.projectDescription = description.isEmpty ? nil : description
        project.notes = notes.isEmpty ? "" : notes
        project.address = address.isEmpty ? "" : address
        project.startDate = startDate
        project.endDate = endDate
        project.allDay = true
        project.needsSync = true

        // Gather all unique team member IDs from all tasks (project team = union of task teams)
        let allTeamMemberIds = Set(localTasks.flatMap { task in
            task.teamMemberIds
        })

        let members = allTeamMembers.filter { allTeamMemberIds.contains($0.id) }
        project.teamMembers = Array(members.map { member in
            let user = User(
                id: member.id,
                firstName: member.firstName,
                lastName: member.lastName,
                role: UserRole(rawValue: member.role.lowercased()) ?? .crew,
                companyId: project.companyId
            )
            user.email = member.email
            return user
        })

        await MainActor.run {
            modelContext.insert(project)
            client.projects.append(project)
            try? modelContext.save()
            print("[PROJECT_CREATE] ✅ Project saved locally")

            // Bug f86cf554 — attach any captured deck design to the real
            // project id. The design was built with a nil projectId from
            // the form; we re-parent it here so it shows up in the DECK
            // tab on first load.
            if let deck = capturedDeckDesign {
                let attachmentUpdatedAt = Date()
                deck.projectId = project.id
                deck.needsSync = true
                deck.updatedAt = attachmentUpdatedAt
                try? modelContext.save()

                if !tutorialMode {
                    dataController.syncEngine.recordOperation(
                        entityType: .deckDesign,
                        entityId: deck.id,
                        operationType: "update",
                        changedFields: [
                            "project_id": project.id,
                            "updated_at": ISO8601DateFormatter().string(from: attachmentUpdatedAt)
                        ],
                        priority: 1
                    )
                }

                print("[PROJECT_CREATE] 🏗️ Attached deck design \(deck.id) to project \(project.id)")
            }
        }

        // Tutorial mode: skip API calls, only save locally
        if tutorialMode {
            print("[PROJECT_CREATE] 📚 Tutorial mode - skipping API sync, project saved locally only")

            // Create tasks locally without API sync
            if !localTasks.isEmpty {
                print("[PROJECT_CREATE] Creating \(localTasks.count) task(s) locally for tutorial")
                for localTask in localTasks {
                    await createTaskLocally(for: project, localTask: localTask)
                }
            }

            return project
        }

        var savedOffline = false

        // Build DTO outside do block so catch blocks can access it.
        // Stamp createdAt/createdBy on insert so the new "start from recent"
        // suggestions strip can scope to projects the current user created.
        let isoFormatter = ISO8601DateFormatter()
        let now = Date()
        project.createdAt = now
        project.createdBy = dataController.currentUser?.id
        let dto = SupabaseProjectDTO(
                id: project.id,
                bubbleId: nil,
                companyId: companyId,
                clientId: client.id,
                opportunityId: nil,
                title: project.title,
                status: project.status.rawValue,
                address: project.address,
                latitude: nil,
                longitude: nil,
                startDate: project.startDate.map { isoFormatter.string(from: $0) },
                endDate: project.endDate.map { isoFormatter.string(from: $0) },
                duration: nil,
                notes: project.notes,
                description: project.projectDescription,
                allDay: project.allDay,
                teamMemberIds: Array(allTeamMemberIds),
                projectImages: nil,
                completedAt: nil,
                deletedAt: nil,
                createdAt: isoFormatter.string(from: now),
                createdBy: dataController.currentUser?.id
            )

        do {
            let _ = try await dataController.createProject(dto: dto)
            print("[PROJECT_CREATE] ✅ Project created via DataController: \(project.id)")
            await MainActor.run {
                project.needsSync = false
                project.lastSyncedAt = Date()
                try? modelContext.save()
            }

            // Create tasks with local project ID
            if !localTasks.isEmpty {
                print("[PROJECT_CREATE] Creating \(localTasks.count) task(s) with project ID: \(project.id)")
                for localTask in localTasks {
                    await createTask(for: project, localTask: localTask)
                }
            }

            // Send project assignment notifications to team members (who don't have tasks)
            // Note: Team members who have tasks will get task assignment notifications instead
            let projectTeamMemberIds = Set(project.teamMembers.map { $0.id })
            let taskTeamMemberIds = Set(localTasks.flatMap { $0.teamMemberIds })
            let projectOnlyMemberIds = projectTeamMemberIds.subtracting(taskTeamMemberIds)

            if !projectOnlyMemberIds.isEmpty {
                let projectName = project.title
                let capturedProjectId = project.id

                for userId in projectOnlyMemberIds {
                    Task {
                        // Create in-app notification
                        let dto = NotificationRepository.CreateNotificationDTO(
                            userId: userId,
                            companyId: companyId,
                            type: "project_assignment",
                            title: "Added to Project",
                            body: "You've been added to \"\(projectName)\"",
                            projectId: capturedProjectId,
                            noteId: nil,
                            expenseId: nil,
                            batchId: nil,
                            deepLinkType: "projectDetails"
                        )
                        try? await NotificationRepository().createNotification(dto)
                        // Send push
                        do {
                            try await OneSignalService.shared.notifyProjectAssignment(
                                userId: userId,
                                projectName: projectName,
                                projectId: capturedProjectId
                            )
                        } catch {
                            print("[PROJECT_CREATE] ⚠️ Failed to send project notification to \(userId): \(error)")
                        }
                    }
                }
                print("[PROJECT_CREATE] 📬 Project assignment notifications queued for \(projectOnlyMemberIds.count) team members")
            }

            // Upload images in background (Supabase — clientId/companyId already on project)
            let capturedDataController = dataController
            let capturedImages = projectImages

            if !capturedImages.isEmpty {
                Task.detached {
                    print("[PROJECT_CREATE] Uploading \(capturedImages.count) project images...")
                    let imageUrls = await capturedDataController.imageSyncManager.saveImages(capturedImages, for: project)
                    print("[PROJECT_CREATE] ✅ Uploaded \(imageUrls.count) images")
                }
            }

            // Trigger background sync so project is pushed to Supabase
            dataController.triggerBackgroundSync()

        } catch is CancellationError {
            savedOffline = true
            print("[PROJECT_CREATE] ⏱️ Network timeout - project saved offline")

            // Queue for SyncEngine push
            await MainActor.run {
                recordProjectSyncOperation(project: project, dto: dto)
            }

            // Create tasks offline with local project ID
            if !localTasks.isEmpty {
                print("[PROJECT_CREATE] Creating \(localTasks.count) task(s) offline with local project ID")
                for localTask in localTasks {
                    await createTask(for: project, localTask: localTask)
                }
            }
        } catch let error as URLError {
            savedOffline = true
            print("[PROJECT_CREATE] ❌ Network error - project saved offline: \(error)")

            // Queue for SyncEngine push
            await MainActor.run {
                recordProjectSyncOperation(project: project, dto: dto)
            }

            // Create tasks offline with local project ID
            if !localTasks.isEmpty {
                print("[PROJECT_CREATE] Creating \(localTasks.count) task(s) offline with local project ID")
                for localTask in localTasks {
                    await createTask(for: project, localTask: localTask)
                }
            }
        } catch {
            print("[PROJECT_CREATE] ❌ Unexpected error during project creation: \(error)")
            await MainActor.run {
                errorMessage = "Failed to create project: \(error.localizedDescription)"
                showingError = true
                isSaving = false
            }
            return project
        }

        await MainActor.run {
            if savedOffline {
                #if !targetEnvironment(simulator)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
                #endif

                errorMessage = "Saved locally. Will sync when connection improves."
                showingError = true
                isSaving = false
            } else {
                isSaving = false
            }
        }

        // ----- Defense against inbound-echo duplicate race (Bug f86cf554) -----
        // Project.id is not @Attribute(.unique). When OutboundProcessor clears
        // the pending SyncOperation before the inbound realtime echo arrives,
        // InboundProcessor.mergeProject can slip past origin-suppression and
        // insert a second row. Mirror the TaskFormSheet pattern (858fa5e):
        // dedupe immediately after cascade, and again 3s later to catch slow
        // realtime echoes. Winner is the copy with needsSync=true (pending
        // local changes) or the most-recently synced.
        let createdProjectId = project.id
        await MainActor.run {
            Self.dedupeProjectRow(id: createdProjectId, context: modelContext)
        }
        Task { @MainActor [weak ctx = modelContext] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if let ctx { Self.dedupeProjectRow(id: createdProjectId, context: ctx) }
        }

        print("[PROJECT_CREATE] ✅ Project creation complete")
        return project
    }

    /// Remove duplicate Project rows for a given id. Winner is the copy
    /// with needsSync=true (pending local changes) if present, otherwise
    /// the most-recently synced. Called from createNewProject to defend
    /// against the inbound-echo race that slips past origin-suppression.
    /// Bug f86cf554 — mirrors TaskFormSheet.dedupeTaskRow (858fa5e).
    @MainActor
    private static func dedupeProjectRow(id: String, context: ModelContext) {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.id == id }
        )
        guard let copies = try? context.fetch(descriptor), copies.count > 1 else { return }
        print("[PROJECT_FORM] ⚠️ Detected \(copies.count) rows for project \(id), deduping")

        let winner: Project = copies.first(where: { $0.needsSync })
            ?? copies.max(by: { ($0.lastSyncedAt ?? .distantPast) < ($1.lastSyncedAt ?? .distantPast) })
            ?? copies[0]

        for dup in copies where dup !== winner {
            context.delete(dup)
        }
        try? context.save()
    }

    private func updateExistingProject(_ project: Project) async throws {
        guard let client = selectedClient else {
            throw ProjectError.missingRequiredFields
        }

        await MainActor.run {
            project.title = title
            project.client = client
            project.projectDescription = description.isEmpty ? nil : description
            project.notes = notes.isEmpty ? "" : notes
            project.address = address.isEmpty ? "" : address
            project.startDate = startDate
            project.endDate = endDate
            project.needsSync = true

            // Gather all unique team member IDs from all tasks (project team = union of task teams)
            let allTeamMemberIds = Set(localTasks.flatMap { task in
                task.teamMemberIds
            })

            let members = allTeamMembers.filter { allTeamMemberIds.contains($0.id) }
            project.teamMembers = Array(members.map { member in
                let user = User(
                    id: member.id,
                    firstName: member.firstName,
                    lastName: member.lastName,
                    role: UserRole(rawValue: member.role.lowercased()) ?? .crew,
                    companyId: project.companyId
                )
                user.email = member.email
                return user
            })

            try? modelContext.save()
        }

        dataController.triggerBackgroundSync()
    }

    private func createTask(for project: Project, localTask: LocalTask) async {
        guard let companyId = dataController.currentUser?.companyId else {
            print("[TASK_CREATE] ❌ No company ID available")
            return
        }

        guard let taskType = allTaskTypes.first(where: { $0.id == localTask.taskTypeId }) else {
            print("[TASK_CREATE] ❌ Task type not found: \(localTask.taskTypeId)")
            return
        }

        // Canonicalize to lowercase: Postgres stores uuid lowercase, Swift's
        // UUID().uuidString returns UPPERCASE. Mismatched case causes local
        // fetch-by-id to miss the realtime echo and produces duplicate rows.
        let taskId = UUID().uuidString.lowercased()
        print("[TASK_CREATE] Creating task with ID: \(taskId)")

        let task = ProjectTask(
            id: taskId,
            projectId: project.id,
            taskTypeId: localTask.taskTypeId,
            companyId: companyId,
            status: localTask.status,
            taskColor: taskType.color
        )

        // Store custom title if provided
        if let customTitle = localTask.customTitle {
            task.customTitle = customTitle
        }

        task.project = project
        task.taskType = taskType

        // Resolve team members: explicit task members > task type defaults > project team
        let resolvedTeamMemberIds: [String]
        if !localTask.teamMemberIds.isEmpty {
            // User explicitly assigned team members to this task
            resolvedTeamMemberIds = localTask.teamMemberIds
        } else if !taskType.defaultTeamMemberIdsString.isEmpty {
            // Task type has default crew — use those
            resolvedTeamMemberIds = taskType.defaultTeamMemberIdsString.components(separatedBy: ",").filter { !$0.isEmpty }
        } else {
            // Fall back to project team members
            resolvedTeamMemberIds = project.teamMembers.map { $0.id }
        }

        // Bug daaf7efe — set the canonical CSV first, then resolve the
        // [User] relationship from SwiftData. The previous version built
        // `task.teamMembers` by instantiating brand-new User() instances
        // that were never inserted into modelContext; SwiftData silently
        // dropped them when saving the relationship array, so the
        // subsequent `task.teamMembers.map { $0.id }` (used to populate the
        // DTO at the Supabase write site) returned [] and the server-side
        // team_member_ids landed empty. Verified in prod: project
        // 2438 Prospector Way (created 2026-05-04 20:23) has 4 team
        // members but its 3 tasks all have empty team_member_ids.
        task.setTeamMemberIds(resolvedTeamMemberIds)
        let resolvedLowercaseIds = task.getTeamMemberIds()
        if !resolvedLowercaseIds.isEmpty {
            let userDescriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { user in resolvedLowercaseIds.contains(user.id) }
            )
            task.teamMembers = (try? modelContext.fetch(userDescriptor)) ?? []
        } else {
            task.teamMembers = []
        }

        await MainActor.run {
            modelContext.insert(task)
            try? modelContext.save()
            print("[TASK_CREATE] ✅ Task saved locally with \(task.teamMembers.count) team members (csv ids: \(resolvedLowercaseIds.count))")
        }

        // Update project status if needed (e.g., reopen completed/closed project)
        await dataController.updateProjectStatusForNewTask(project: project, taskStatus: localTask.status)

        // Sync task to Supabase immediately
        var remoteTaskId = taskId
        do {
            print("[TASK_CREATE] 🔄 Syncing task to Supabase...")
            let supabaseTaskDTO = SupabaseProjectTaskDTO(
                id: taskId,
                bubbleId: nil,
                companyId: companyId,
                projectId: project.id,
                taskTypeId: localTask.taskTypeId,
                customTitle: localTask.customTitle,
                taskNotes: nil,
                status: localTask.status.rawValue,
                taskColor: taskType.color,
                displayOrder: nil,
                // Bug daaf7efe — read from the authoritative CSV (which
                // setTeamMemberIds populated) rather than the [User]
                // relationship. SwiftData drops non-managed User instances
                // assigned via `task.teamMembers = ...`, so the relationship
                // can be empty even when the CSV is correct.
                teamMemberIds: task.getTeamMemberIds(),
                sourceLineItemId: nil,
                sourceEstimateId: nil,
                startDate: localTask.startDate.map { ISO8601DateFormatter().string(from: $0) },
                endDate: localTask.endDate.map { ISO8601DateFormatter().string(from: $0) },
                duration: {
                    if let start = localTask.startDate, let end = localTask.endDate {
                        let daysDiff = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
                        return daysDiff + 1
                    }
                    return 1
                }(),
                dependencyOverrides: nil,
                startTime: nil,
                endTime: nil,
                pairedFromTaskId: nil,
                scheduleLocked: nil,
                deletedAt: nil,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )

            await MainActor.run {
                task.createdAt = Date()
            }

            let createdTaskId = try await dataController.createTask(dto: supabaseTaskDTO)
            remoteTaskId = createdTaskId
            print("[TASK_CREATE] ✅ Task synced to Supabase with ID: \(remoteTaskId)")

            // Update task after server sync
            await MainActor.run {
                task.id = remoteTaskId
                task.needsSync = false
                task.lastSyncedAt = Date()
                try? modelContext.save()
            }

            // Send task assignment notifications to team members
            // Use Set to deduplicate in case teamMembers has duplicates
            let teamMemberIds = Set(task.teamMembers.map { $0.id })
            print("[TASK_CREATE] 📬 Team member IDs for notification: \(teamMemberIds) (count: \(teamMemberIds.count))")
            if !teamMemberIds.isEmpty {
                let taskName = task.displayTitle
                let projectName = project.title

                for userId in teamMemberIds {
                    print("[TASK_CREATE] 📬 Sending notification to user: \(userId)")
                    Task {
                        // Create in-app notification
                        let dto = NotificationRepository.CreateNotificationDTO(
                            userId: userId,
                            companyId: companyId,
                            type: "task_assignment",
                            title: "New Task Assignment",
                            body: "You've been assigned to \"\(taskName)\" on \(projectName)",
                            projectId: project.id,
                            noteId: nil,
                            expenseId: nil,
                            batchId: nil,
                            deepLinkType: "taskDetails"
                        )
                        try? await NotificationRepository().createNotification(dto)
                        // Send push
                        do {
                            try await OneSignalService.shared.notifyTaskAssignment(
                                userId: userId,
                                taskName: taskName,
                                projectName: projectName,
                                taskId: remoteTaskId,
                                projectId: project.id
                            )
                        } catch {
                            print("[TASK_CREATE] ⚠️ Failed to send notification to \(userId): \(error)")
                        }
                    }
                }
                print("[TASK_CREATE] 📬 Task assignment notifications queued for \(teamMemberIds.count) team members")
            }
        } catch {
            print("[TASK_CREATE] ⚠️ Failed to sync task to server: \(error)")
            await MainActor.run {
                task.needsSync = true
                try? modelContext.save()
            }
        }

        // Set scheduling dates directly on the task
        await MainActor.run {
            task.startDate = localTask.startDate
            task.endDate = localTask.endDate
            if let start = localTask.startDate, let end = localTask.endDate {
                let daysDiff = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
                task.duration = daysDiff + 1
            }
            try? modelContext.save()
            print("[TASK_CREATE] ✅ Task dates set locally")
        }

        // Recalculate task indices for the project
        do {
            try await dataController.recalculateTaskIndices(for: project)
        } catch {
            print("[TASK_CREATE] ⚠️ Failed to recalculate task indices: \(error)")
        }

        print("[TASK_CREATE] ✅ Task creation complete")
    }

    /// Records a SyncOperation for offline project creation so OutboundProcessor can push it later.
    @MainActor
    private func recordProjectSyncOperation(project: Project, dto: SupabaseProjectDTO) {
        // Encode DTO to dictionary for SyncOperation payload
        guard let jsonData = try? JSONEncoder().encode(dto),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("[PROJECT_CREATE] ⚠️ Failed to encode project DTO for sync operation")
            return
        }
        dataController.syncEngine.recordOperation(
            entityType: .project,
            entityId: project.id,
            operationType: "create",
            changedFields: dict,
            priority: 0
        )
        print("[PROJECT_CREATE] 📋 SyncOperation queued for offline project: \(project.id)")
    }

    /// Creates a task locally without API sync (for tutorial mode)
    private func createTaskLocally(for project: Project, localTask: LocalTask) async {
        guard let companyId = dataController.currentUser?.companyId else {
            print("[TASK_CREATE_LOCAL] ❌ No company ID available")
            return
        }

        guard let taskType = allTaskTypes.first(where: { $0.id == localTask.taskTypeId }) else {
            print("[TASK_CREATE_LOCAL] ❌ Task type not found: \(localTask.taskTypeId)")
            return
        }

        let taskId = "DEMO_TASK_\(UUID().uuidString)"
        print("[TASK_CREATE_LOCAL] Creating task locally with ID: \(taskId)")

        let task = ProjectTask(
            id: taskId,
            projectId: project.id,
            taskTypeId: localTask.taskTypeId,
            companyId: companyId,
            status: localTask.status,
            taskColor: taskType.color
        )

        if let customTitle = localTask.customTitle {
            task.customTitle = customTitle
        }

        task.project = project
        task.taskType = taskType

        // Resolve team members: explicit task members > task type defaults > project team
        let resolvedTeamMemberIds: [String]
        if !localTask.teamMemberIds.isEmpty {
            resolvedTeamMemberIds = localTask.teamMemberIds
        } else if !taskType.defaultTeamMemberIdsString.isEmpty {
            resolvedTeamMemberIds = taskType.defaultTeamMemberIdsString.components(separatedBy: ",").filter { !$0.isEmpty }
        } else {
            resolvedTeamMemberIds = project.teamMembers.map { $0.id }
        }

        // Bug daaf7efe — same pattern as createTask: set CSV first, then
        // resolve [User] from SwiftData so the relationship contains
        // managed objects. New User() instances would be dropped silently.
        task.setTeamMemberIds(resolvedTeamMemberIds)
        let resolvedLowercaseIds = task.getTeamMemberIds()
        if !resolvedLowercaseIds.isEmpty {
            let userDescriptor = FetchDescriptor<User>(
                predicate: #Predicate<User> { user in resolvedLowercaseIds.contains(user.id) }
            )
            task.teamMembers = (try? modelContext.fetch(userDescriptor)) ?? []
        } else {
            task.teamMembers = []
        }

        // Set scheduling dates directly on the task
        task.startDate = localTask.startDate
        task.endDate = localTask.endDate
        if let start = localTask.startDate, let end = localTask.endDate {
            let daysDiff = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
            task.duration = daysDiff + 1
        }

        await MainActor.run {
            modelContext.insert(task)
            project.tasks.append(task)
            try? modelContext.save()
            print("[TASK_CREATE_LOCAL] ✅ Task saved locally (tutorial mode) with \(task.teamMembers.count) team members")
        }
    }
}

// MARK: - Local Task Model

struct LocalTask: Identifiable, Equatable {
    let id: UUID
    var taskTypeId: String
    var customTitle: String?
    var status: TaskStatus
    var teamMemberIds: [String] = []
    var startDate: Date?
    var endDate: Date?

    static func == (lhs: LocalTask, rhs: LocalTask) -> Bool {
        lhs.id == rhs.id &&
        lhs.taskTypeId == rhs.taskTypeId &&
        lhs.customTitle == rhs.customTitle &&
        lhs.status == rhs.status &&
        lhs.teamMemberIds == rhs.teamMemberIds &&
        lhs.startDate == rhs.startDate &&
        lhs.endDate == rhs.endDate
    }
}

// MARK: - Supporting Types

enum ProjectError: LocalizedError {
    case missingRequiredFields
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .missingRequiredFields:
            return "Please fill in all required fields"
        case .saveFailed:
            return "Failed to save project"
        }
    }
}
