//
//  ProjectDetailsViewRedesign.swift
//  OPS
//
//  Redesigned ProjectDetailsView — thin container composing sub-views.
//  Replaces the former 5K-line monolith.
//

import SwiftUI
import SwiftData

struct ProjectDetailsView: View {
    @Bindable var project: Project
    var isEditMode: Bool = false
    var initialSelectedTask: ProjectTask? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase
    @Environment(\.wizardTriggerService) private var wizardTriggerService
    @Environment(\.wizardStateManager) private var wizardStateManager
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState

    @StateObject private var viewModel: ProjectDetailsViewModel
    @StateObject private var notesViewModel: ProjectNotesViewModel
    @StateObject private var expenseViewModel = ExpenseViewModel()

    // Photo state owned by container (sheets need them)
    @State private var noteSelectedImages: [UIImage] = []
    @State private var selectedTeamMember: User? = nil
    @State private var editingExpense: ExpenseDTO? = nil
    @State private var showNewExpenseSheet = false
    @State private var showingStatusPicker = false
    @State private var showingCameraBatch = false
    @State private var showingDeckCreationPicker = false
    @State private var deckDesignToOpen: DeckDesign?
    @ObservedObject private var permissionStore = PermissionStore.shared
    @State private var isNoteComposing = false
    @State private var showingTaskPicker = false
    @State private var taskDetailTask: ProjectTask? = nil
    @State private var lastTeamEditTask: ProjectTask? = nil
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var allTeamMembers: [TeamMember] = []
    @State private var showingClientPicker = false
    @State private var dismissDragOffset: CGFloat = 0
    @State private var isKeyboardVisible = false
    @State private var shareSource: ProjectShareItemSource?
    @State private var isPreparingShare = false

    init(project: Project, isEditMode: Bool = false, initialSelectedTask: ProjectTask? = nil) {
        self._project = Bindable(wrappedValue: project)
        self.isEditMode = isEditMode
        self.initialSelectedTask = initialSelectedTask

        self._viewModel = StateObject(wrappedValue: ProjectDetailsViewModel(
            project: project,
            initialSelectedTask: initialSelectedTask
        ))
        self._notesViewModel = StateObject(wrappedValue: ProjectNotesViewModel(projectId: project.id))
    }

    var body: some View {
        Group {
            if viewModel.isDeleting {
                ZStack {
                    OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            } else {
                mainContent
                    .navigationBarHidden(true)
                    // MARK: - Sheets & Alerts
                    .overlay(saveNotificationOverlay)
                    .fullScreenCover(isPresented: $viewModel.showingPhotoViewer) {
                        photoViewerContent
                            .onAppear {
                                NotificationCenter.default.post(
                                    name: Notification.Name("WizardPhotoViewed"),
                                    object: nil
                                )
                            }
                    }
                    .sheet(isPresented: $viewModel.showingImagePicker) {
                        imagePickerContent
                    }
                    .fullScreenCover(isPresented: $showingCameraBatch) {
                        CameraBatchView { capturedImages in
                            viewModel.selectedImages = capturedImages
                            if !capturedImages.isEmpty {
                                viewModel.addPhotosToProject(tutorialMode: tutorialMode)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    NotificationCenter.default.post(
                                        name: Notification.Name("WizardPhotoCaptured"),
                                        object: nil
                                    )
                                }
                            }
                        }
                    }
                    .sheet(isPresented: $viewModel.showingNoteImagePicker) {
                        noteImagePickerContent
                    }
                    .fullScreenCover(isPresented: $viewModel.showingNotePhotoViewer) {
                        notePhotoViewerContent
                    }
                    .sheet(isPresented: $showingDeckCreationPicker) {
                        deckCreationPickerContent
                    }
                    .fullScreenCover(item: $deckDesignToOpen) { design in
                        deckBuilderContent(design: design)
                    }
                    .sheet(isPresented: $viewModel.showingClientContact) {
                        clientContactSheet
                    }
                    .sheet(item: $shareSource) { source in
                        // Item-driven sheet: `source` arrives as a parameter so
                        // SwiftUI never renders this body with an empty items
                        // array (the root cause of the blank-first-tap bug).
                        ActivityView(items: [source])
                    }
                    .sheet(isPresented: $showingClientPicker) {
                        ClientPickerSheet(
                            currentClientId: project.clientId,
                            companyId: project.companyId,
                            onSelect: { client in
                                project.client = client
                                project.clientId = client.id
                                project.needsSync = true
                                try? dataController.modelContext?.save()
                                Task {
                                    try? await dataController.updateProjectFields(
                                        projectId: project.id,
                                        fields: ["client_id": .string(client.id)]
                                    )
                                    project.needsSync = false
                                    project.lastSyncedAt = Date()
                                    try? dataController.modelContext?.save()
                                }
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                            }
                        )
                        .environmentObject(dataController)
                    }
                    .sheet(item: $selectedTeamMember) { member in
                        ContactDetailView(user: member)
                            .environmentObject(dataController)
                    }
                    .sheet(isPresented: $viewModel.showingScheduler) {
                        CalendarSchedulerSheet(
                            isPresented: $viewModel.showingScheduler,
                            itemType: .project(project),
                            currentStartDate: project.startDate,
                            currentEndDate: project.endDate,
                            onScheduleUpdate: { start, end in
                                viewModel.handleScheduleUpdate(startDate: start, endDate: end)
                            },
                            onClearDates: { viewModel.handleClearDates() }
                        )
                        .environmentObject(dataController)
                    }
                    // Address editing is now inline in DetailsTabView
                    .sheet(isPresented: $viewModel.showingAddTaskSheet) {
                        TaskFormSheet(
                            mode: .create,
                            preselectedProjectId: project.id,
                            onSave: { _ in }
                        )
                        .environmentObject(dataController)
                    }
                    .sheet(isPresented: $viewModel.showingTaskScheduler) {
                        if let task = viewModel.selectedTask {
                            CalendarSchedulerSheet(
                                isPresented: $viewModel.showingTaskScheduler,
                                itemType: .task(task),
                                currentStartDate: task.startDate,
                                currentEndDate: task.endDate,
                                onScheduleUpdate: viewModel.handleTaskScheduleUpdate,
                                onClearDates: {
                                    // Bug f3604d52 — allow clearing the task's
                                    // dates from the scheduler sheet toolbar.
                                    task.startDate = nil
                                    task.endDate = nil
                                    task.needsSync = true
                                    try? dataController.modelContext?.save()
                                }
                            )
                            .environmentObject(dataController)
                        }
                    }
                    .sheet(item: $editingExpense) { expense in
                        ExpenseFormSheet(viewModel: expenseViewModel, editing: expense)
                            .environmentObject(dataController)
                    }
                    .sheet(isPresented: $showNewExpenseSheet) {
                        ExpenseFormSheet(viewModel: expenseViewModel, prefilledProjectId: project.id)
                            .environmentObject(dataController)
                    }
                    .sheet(isPresented: $showingStatusPicker) {
                        ProjectStatusChangeSheet(project: project)
                            .environmentObject(dataController)
                    }
                    // Task picker is now an inline overlay (see mainContent)
                    .sheet(item: $taskDetailTask, onDismiss: {
                        saveTaskTeamChanges()
                    }) { task in
                        TaskDetailPopupSheet(
                            task: task,
                            onSelect: { t in
                                taskDetailTask = nil
                                withAnimation(OPSStyle.Animation.fast) {
                                    viewModel.selectedTask = t
                                }
                            },
                            onComplete: { t in
                                viewModel.selectedTask = t
                                taskDetailTask = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    viewModel.toggleTaskStatus()
                                }
                            },
                            onReschedule: { t in
                                viewModel.selectedTask = t
                                taskDetailTask = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    viewModel.showingTaskScheduler = true
                                }
                            },
                            onCancel: { t in
                                viewModel.selectedTask = t
                                viewModel.cancelSelectedTask()
                            },
                            onScheduleTap: { t in
                                viewModel.selectedTask = t
                                taskDetailTask = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    viewModel.showingTaskScheduler = true
                                }
                            },
                            selectedTeamMemberIds: $selectedTeamMemberIds,
                            allTeamMembers: allTeamMembers,
                            isProjectCompleted: project.status == .completed
                        )
                    }
                    .confirmationDialog("Unsaved Changes", isPresented: $viewModel.showingUnsavedChangesAlert, titleVisibility: .visible) {
                        Button("Discard Changes", role: .destructive) { dismiss() }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("You have unsaved changes. Discard them?")
                    }
                    .alert("Network Error", isPresented: $viewModel.showingNetworkError) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(viewModel.networkErrorMessage)
                    }
                    .alert("Delete Project?", isPresented: $viewModel.showingDeleteAlert) {
                        Button("Delete", role: .destructive) {
                            viewModel.isDeleting = true
                            viewModel.deleteProject()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismiss() }
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This action cannot be undone.")
                    }
                    // Cancel task confirmation is now inline in TaskDetailPopupSheet
                    .alert("Delete Task?", isPresented: $viewModel.showingTaskDeleteConfirmation) {
                        Button("Delete", role: .destructive) { viewModel.deleteSelectedTask() }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This action cannot be undone.")
                    }
                    .onAppear { handleOnAppear() }
                    .onDisappear {
                        // Wizard system: notify that project details was closed
                        NotificationCenter.default.post(
                            name: Notification.Name("WizardScreenDismissed"),
                            object: nil,
                            userInfo: ["screen": "ProjectDetails"]
                        )
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardEvaluatePrerequisites"))) { _ in
                        // Re-evaluate prerequisites with current photo count
                        wizardStateManager?.evaluateStepPrerequisites(
                            projectPhotoCount: viewModel.project.getProjectImages().count
                        )
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardStepChanged"))) { notification in
                        guard let mgr = wizardStateManager,
                              mgr.isActive,
                              mgr.activeWizard?.wizardId == "documentation",
                              let stepId = notification.userInfo?["stepId"] as? String else { return }

                        switch stepId {
                        case "write_note", "view_photo":
                            // Ensure Activity tab is visible — compose bar and photo gallery live there
                            if viewModel.selectedTab != .activity {
                                viewModel.selectedTab = .activity
                            }
                        case "capture_photo":
                            // Dismiss keyboard so the floating action bar reappears
                            isNoteComposing = false
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            // Ensure Activity tab is visible (photos section is there)
                            if viewModel.selectedTab != .activity {
                                viewModel.selectedTab = .activity
                            }
                        default:
                            break
                        }
                    }
            }
        }
        .trackScreen("ProjectDetails")
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ZStack(alignment: .top) {
            // Layer 1: Fixed map background (behind everything)
            VStack(spacing: 0) {
                ProjectMapHeader(
                    project: project,
                    taskColorHexes: viewModel.projectTaskColorHexes,
                    pinLabel: viewModel.pinLabel,
                    nearbyProjects: viewModel.nearbyProjectPins,
                    onMapTap: { viewModel.openDirections() }
                )
                Spacer()
            }

            // Layer 2: Scrollable content that slides up over the map
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // Initial spacer — positions content in lower portion of map.
                    // Pulled down 40pt so the gradient starts later, revealing
                    // more map above the title (Bug a2f7e6fa).
                    Color.clear.frame(height: ProjectMapHeader.mapHeight - 130)

                    // Gradient scrolls with content (not pinned — avoids content peeking through)
                    mapScrollGradient

                    // Pinned header: title + tab bar (solid background blocks content behind it)
                    Section(header: stickyHeader) {
                        tabContent
                            .padding(.bottom, 100)
                            .background(OPSStyle.Colors.background)
                    }
                }
            }

            // Layer 3: Task picker overlay (below nav bar)
            if showingTaskPicker {
                taskPickerOverlay
                    .zIndex(15)
            }

            // Layer 4: Nav bar (above everything — CANCEL badge visible over gradient)
            projectNavBar
                .zIndex(20)

            // Layer 5: Floating toolbar — quick actions (hidden when composing notes or keyboard visible)
            if !isNoteComposing && !isKeyboardVisible {
                VStack {
                    Spacer()
                    ProjectQuickActionsBar(
                        selectedTask: viewModel.selectedTask,
                        hasClientContact: viewModel.hasClientContact,
                        canEdit: viewModel.canEditProject,
                        isMentionOnly: viewModel.isMentionOnlyAccess,
                        onPhoto: { showingCameraBatch = true },
                        onNote: {
                            viewModel.selectedTab = .activity
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                isNoteComposing = true
                            }
                        },
                        onExpense: { openNewExpenseSheet() },
                        onComplete: { viewModel.toggleTaskStatus() },
                        onReschedule: { viewModel.showingTaskScheduler = true },
                        onContact: { viewModel.showingClientContact = true },
                        onAddTask: { viewModel.showingAddTaskSheet = true },
                        onDeckDesign: permissionStore.isFeatureEnabled("deck_builder") ? { showingDeckCreationPicker = true } : nil,
                        onShare: { shareProject() },
                        onPhotoLibrary: {
                            // Bug 1b7e59f7 — open the existing image picker
                            // sheet (which wraps PhotosPicker). The selected
                            // images flow into viewModel.addPhotosToProject
                            // exactly like camera-captured images.
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.showingImagePicker = true
                        },
                        allTasksComplete: {
                            let activeTasks = project.tasks.filter { $0.deletedAt == nil && $0.status != .cancelled }
                            return !activeTasks.isEmpty && activeTasks.allSatisfy { $0.status == .completed }
                        }(),
                        projectIsActive: project.status != .completed && project.status != .closed && project.status != .archived,
                        onCompleteProject: { viewModel.handleProjectCompletion() }
                    )
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(5)
            }
        }
        .background(OPSStyle.Colors.background.edgesIgnoringSafeArea(.all))
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(OPSStyle.Animation.fast) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(OPSStyle.Animation.fast) { isKeyboardVisible = false }
        }
        .offset(y: dismissDragOffset)
        .opacity(dismissDragOffset > 0 ? 1.0 - Double(dismissDragOffset) / 600.0 : 1.0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onChanged { value in
                    // Only respond to gestures starting in the top 120pt
                    guard value.startLocation.y < 120 else { return }
                    let translation = max(0, value.translation.height)
                    dismissDragOffset = translation
                }
                .onEnded { value in
                    guard value.startLocation.y < 120 else { return }
                    if value.translation.height > 150 {
                        withAnimation(.easeOut(duration: 0.25)) {
                            dismissDragOffset = UIScreen.main.bounds.height
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            dismiss()
                        }
                    } else {
                        withAnimation(OPSStyle.Animation.standard) {
                            dismissDragOffset = 0
                        }
                    }
                }
        )
    }

    /// Gradient overlay that scrolls with title content — fades map into background.
    /// Stops stay mostly-transparent through the top two-thirds so the map
    /// underneath reads through, then ramps quickly to solid at the title
    /// edge. Bug a2f7e6fa: previous stops produced too much opaque black
    /// space above the title.
    private var mapScrollGradient: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: OPSStyle.Colors.background.opacity(0.25), location: 0.55),
                .init(color: OPSStyle.Colors.background.opacity(0.75), location: 0.85),
                .init(color: OPSStyle.Colors.background, location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 90)
        .allowsHitTesting(false)
    }

    /// Navigation bar extracted from map header — sits above scroll view for reliable tap targets
    private var projectNavBar: some View {
        HStack {
            // DONE button
            Button(action: { handleDismiss() }) {
                Text("DONE")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(OPSStyle.Colors.primaryText)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
            }

            Spacer()

            // Task badge — tappable to open/close picker
            if showingTaskPicker {
                // When picker is open, badge becomes CANCEL button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingTaskPicker = false
                    }
                }) {
                    TaskBadge(
                        name: "Cancel",
                        color: OPSStyle.Colors.tertiaryText,
                        size: .navBar
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else if let task = viewModel.selectedTask {
                let taskColor = Color(hex: task.taskColor) ?? OPSStyle.Colors.primaryAccent
                let isComplete = task.status == .completed
                let isCancelled = task.status == .cancelled
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingTaskPicker = true
                    }
                }) {
                    // Task badge with status overlay for completed/cancelled
                    ZStack(alignment: .bottomTrailing) {
                        TaskBadge(
                            name: task.taskType?.display ?? "Task",
                            color: taskColor,
                            size: .navBar,
                            faded: isComplete || isCancelled
                        )

                        if isComplete {
                            StatusBadgePill(
                                text: "COMPLETE",
                                color: TaskStatus.completed.color,
                                size: .small
                            )
                            .offset(x: 6, y: 10)
                        } else if isCancelled {
                            StatusBadgePill(
                                text: "CANCELLED",
                                color: TaskStatus.cancelled.color,
                                size: .small
                            )
                            .offset(x: 6, y: 10)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            } else if project.tasks.isEmpty {
                // No tasks on project — non-tappable
                TaskBadge(
                    name: "No Tasks",
                    color: OPSStyle.Colors.tertiaryText,
                    size: .navBar,
                    faded: true
                )
            } else {
                // Has tasks but none selected — tappable
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingTaskPicker = true
                    }
                }) {
                    TaskBadge(
                        name: "Select Task",
                        color: OPSStyle.Colors.tertiaryText,
                        size: .navBar
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Pinned section header: title + tab bar with solid background.
    /// Solid background blocks content from showing through when pinned.
    /// Top clearance keeps the title below the DONE button when pinned.
    private var stickyHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Nav bar clearance — when pinned, keeps title below DONE button
            Color.clear.frame(height: 56)

            ProjectTitleOverlay(
                project: project,
                isEditingTitle: viewModel.isEditingTitle,
                editedTitle: $viewModel.editedTitle,
                canEdit: viewModel.canEditProject,
                onStartEditingTitle: {
                    viewModel.editedTitle = project.title
                    viewModel.isEditingTitle = true
                },
                onSaveTitle: { viewModel.saveTitle() },
                onClientLongPress: { showingClientPicker = true }
            )
            ProjectDetailsTabBar(selectedTab: $viewModel.selectedTab, visibleTabs: visibleTabs)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        .background(OPSStyle.Colors.background)
    }

    // MARK: - Tab Visibility

    private var visibleTabs: [ProjectDetailTab] {
        var tabs: [ProjectDetailTab] = [.activity, .details, .expenses]
        if permissionStore.isFeatureEnabled("deck_builder") && permissionStore.can("deck_builder.view") {
            tabs.append(.deck)
        }
        return tabs
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .activity:
            ActivityTabView(
                notesViewModel: notesViewModel,
                project: project,
                onShowImagePicker: { viewModel.showingImagePicker = true },
                onShowNoteImagePicker: { viewModel.showingNoteImagePicker = true },
                onPhotoTap: { urls, index in
                    viewModel.notePhotoViewerURLs = urls
                    viewModel.notePhotoViewerIndex = index
                    viewModel.showingNotePhotoViewer = true
                },
                onProjectPhotoTap: { index in
                    viewModel.selectedPhotoIndex = index
                    viewModel.showingPhotoViewer = true
                },
                noteFieldFocused: $isNoteComposing
            )

        case .details:
            DetailsTabView(
                project: project,
                viewModel: viewModel,
                onClientTap: { viewModel.showingClientContact = true },
                onTeamMemberTap: { member in selectedTeamMember = member },
                onTaskTap: { task in
                    selectedTeamMemberIds = Set(task.getTeamMemberIds())
                    lastTeamEditTask = task
                    loadAvailableTeamMembers()
                    taskDetailTask = task
                },
                onAddTask: { viewModel.showingAddTaskSheet = true },
                onSelectTask: { task in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(OPSStyle.Animation.fast) {
                        if viewModel.selectedTask?.id == task.id {
                            viewModel.selectedTask = nil
                        } else {
                            viewModel.selectedTask = task
                        }
                    }
                },
                onCompleteTask: { task in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.selectedTask = task
                    viewModel.toggleTaskStatus()
                },
                onReopenTask: { task in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.selectedTask = task
                    viewModel.toggleTaskStatus()
                },
                onCancelTask: { task in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.selectedTask = task
                    viewModel.cancelSelectedTask()
                },
                onDeleteTask: { task in
                    viewModel.selectedTask = task
                    viewModel.showingTaskDeleteConfirmation = true
                },
                onClientLongPress: { showingClientPicker = true }
            )

        case .expenses:
            ProjectExpensesTabView(
                viewModel: viewModel,
                expenseViewModel: expenseViewModel,
                onAddExpense: { openNewExpenseSheet() },
                onTapExpense: { expense in editingExpense = expense }
            )

        case .deck:
            DeckTabView(
                project: project,
                onCreateDeckDesign: { showingDeckCreationPicker = true },
                onEditDeckDesign: { design in deckDesignToOpen = design }
            )
        }
    }

    // MARK: - Sheet Contents

    private var photoViewerContent: some View {
        let photos = project.getProjectImages()
        let safeIndex = min(viewModel.selectedPhotoIndex, max(photos.count - 1, 0))
        return PhotoCommentViewer(
            photos: photos,
            initialIndex: safeIndex,
            onDismiss: { viewModel.showingPhotoViewer = false },
            projectId: project.id
        )
        .environmentObject(dataController)
        .id(safeIndex)
    }

    private var imagePickerContent: some View {
        ImagePicker(
            images: $viewModel.selectedImages,
            allowsEditing: false,
            selectionLimit: 10,
            onSelectionComplete: {
                viewModel.showingImagePicker = false
                if !viewModel.selectedImages.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        viewModel.addPhotosToProject(tutorialMode: tutorialMode)
                    }
                }
            }
        )
    }

    private var noteImagePickerContent: some View {
        ImagePicker(
            images: $noteSelectedImages,
            allowsEditing: false,
            selectionLimit: 5,
            onSelectionComplete: {
                viewModel.showingNoteImagePicker = false
                for image in noteSelectedImages {
                    notesViewModel.addImage(image)
                }
                noteSelectedImages = []
            }
        )
    }

    @ViewBuilder
    private var deckCreationPickerContent: some View {
        let companyId = UserDefaults.standard.string(forKey: "currentUserCompanyId") ?? ""
        let userId = UserDefaults.standard.string(forKey: "currentUserId")
        CreationPickerView(
            projectId: project.id,
            companyId: companyId,
            userId: userId,
            onDesignCreated: { design in
                deckDesignToOpen = design
            }
        )
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func deckBuilderContent(design: DeckDesign) -> some View {
        if let modelContext = dataController.modelContext {
            DeckBuilderView(deckDesign: design, modelContext: modelContext)
        }
    }

    private var notePhotoViewerContent: some View {
        PhotoCommentViewer(
            photos: viewModel.notePhotoViewerURLs,
            initialIndex: viewModel.notePhotoViewerIndex,
            onDismiss: { viewModel.showingNotePhotoViewer = false },
            projectId: project.id
        )
        .environmentObject(dataController)
    }

    @ViewBuilder
    private var clientContactSheet: some View {
        if let client = project.client {
            ContactDetailView(client: client, project: project)
                .presentationDragIndicator(.visible)
                .environmentObject(dataController)
        } else {
            Text("No client assigned")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    // MARK: - Task Picker Overlay (right-aligned, top-aligned below task badge)

    @State private var scrolledTaskID: UUID?
    @State private var lastSnappedTaskID: UUID?

    private var taskPickerOverlay: some View {
        let sortedTasks = project.tasks.sorted { $0.displayOrder < $1.displayOrder }
        let baseDelay: Double = 0.04

        return ZStack(alignment: .topTrailing) {
            // Gradient background — tap to dismiss
            LinearGradient(
                colors: [Color(OPSStyle.Colors.background).opacity(0.90), .clear],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()
            .transition(.opacity)
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingTaskPicker = false
                }
            }

            // Task items — right-aligned, top-aligned below nav bar
            VStack(alignment: .trailing, spacing: 0) {
                // Clearance for nav bar badge
                Color.clear.frame(height: 52)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .trailing, spacing: 0) {
                        // Task list
                        ForEach(Array(sortedTasks.enumerated()), id: \.element.id) { index, task in
                            let isSelected = viewModel.selectedTask?.id == task.id
                            let taskColor = Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent

                            Button(action: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(OPSStyle.Animation.fast) {
                                    viewModel.selectedTask = task
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showingTaskPicker = false
                                }
                            }) {
                                HStack(spacing: 8) {
                                    // Status badge for non-active tasks
                                    if task.status == .completed {
                                        StatusBadgePill(
                                            text: "COMPLETE",
                                            color: TaskStatus.completed.color,
                                            size: .small
                                        )
                                    } else if task.status == .cancelled {
                                        StatusBadgePill(
                                            text: "CANCELLED",
                                            color: TaskStatus.cancelled.color,
                                            size: .small
                                        )
                                    }

                                    TaskBadge(
                                        name: task.displayTitle,
                                        color: taskColor,
                                        size: .large,
                                        faded: task.status == .completed || task.status == .cancelled
                                    )

                                    // Checkmark for currently selected task
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .id(task.id)
                            .padding(.vertical, 6)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .animation(
                                OPSStyle.Animation.standard.delay(Double(index) * baseDelay),
                                value: showingTaskPicker
                            )

                            // Minimal divider between items (not after last)
                            if index < sortedTasks.count - 1 {
                                Rectangle()
                                    .fill(OPSStyle.Colors.separator)
                                    .frame(width: 120, height: 1)
                                    .padding(.vertical, 2)
                            }
                        }

                        // Deselect option (if a task is selected)
                        if viewModel.selectedTask != nil {
                            Rectangle()
                                .fill(OPSStyle.Colors.separator)
                                .frame(width: 120, height: 1)
                                .padding(.vertical, 4)

                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(OPSStyle.Animation.fast) {
                                    viewModel.selectedTask = nil
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showingTaskPicker = false
                                }
                            }) {
                                TaskBadge(
                                    name: "Deselect",
                                    color: OPSStyle.Colors.tertiaryText,
                                    size: .large
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.vertical, 6)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .animation(
                                OPSStyle.Animation.standard.delay(Double(sortedTasks.count) * baseDelay),
                                value: showingTaskPicker
                            )
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .frame(maxHeight: 400)
                .scrollTargetBehavior(.viewAligned)
                .onChange(of: scrolledTaskID) { _, newValue in
                    guard newValue != nil, newValue != lastSnappedTaskID else { return }
                    lastSnappedTaskID = newValue
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                // Edge fade mask
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 20)
                        Color.black
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 24)
                    }
                )
                .transition(
                    .opacity.combined(with: .scale(scale: 0.8, anchor: .topTrailing))
                )
            }
            .padding(.trailing, 16)
        }
    }

    // MARK: - Save Notification Overlay

    private var saveNotificationOverlay: some View {
        Group {
            if viewModel.showingSaveNotification {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: OPSStyle.Icons.complete)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        Text("Saved")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
                    .padding(.bottom, 32)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(OPSStyle.Animation.standard, value: viewModel.showingSaveNotification)
            }
        }
    }

    // MARK: - Actions

    private func handleDismiss() {
        if viewModel.checkForUnsavedChanges() {
            viewModel.showingUnsavedChangesAlert = true
        } else {
            dismiss()
        }
    }

    private func openNewExpenseSheet() {
        showNewExpenseSheet = true
    }

    /// Builds a project deep link and presents the system share sheet with a
    /// rich preview card (project title + first project image as thumbnail).
    /// The image loads asynchronously off the main thread. Setting
    /// `shareSource` (not a separate isPresented flag) drives `.sheet(item:)`,
    /// which passes the source directly to the content builder — that avoids
    /// the stale-snapshot race where the first presentation rendered with an
    /// empty items array.
    private func shareProject() {
        guard !isPreparingShare, shareSource == nil else { return }
        guard let url = ProjectShareLinkBuilder.url(for: project) else { return }

        let title = project.title
        let subtitle = project.effectiveClientName.isEmpty ? nil : project.effectiveClientName

        isPreparingShare = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task { @MainActor in
            let thumbnail = await ProjectShareImageLoader.loadFirstImage(for: project)
            shareSource = ProjectShareItemSource(
                url: url,
                title: title,
                subtitle: subtitle,
                image: thumbnail
            )
            isPreparingShare = false

            AnalyticsService.shared.track(
                eventType: .action,
                eventName: "project_shared",
                properties: [
                    "project_id": project.id,
                    "has_thumbnail": thumbnail != nil
                ]
            )
        }
    }

    private func loadAvailableTeamMembers() {
        guard let companyId = dataController.currentUser?.companyId else { return }

        // Fetch User objects and convert to TeamMember
        let users = dataController.getTeamMembers(companyId: companyId)
        if !users.isEmpty {
            allTeamMembers = users.map { TeamMember.fromUser($0) }
                .sorted { $0.fullName < $1.fullName }
            return
        }

        // Fallback: trigger async sync then retry
        Task {
            await dataController.triggerTeamMembersSync(companyId: companyId)
            await MainActor.run {
                let retryUsers = dataController.getTeamMembers(companyId: companyId)
                allTeamMembers = retryUsers.map { TeamMember.fromUser($0) }
                    .sorted { $0.fullName < $1.fullName }
            }
        }
    }

    private func saveTaskTeamChanges() {
        guard let task = lastTeamEditTask else { return }
        let currentIds = Set(task.getTeamMemberIds())
        guard selectedTeamMemberIds != currentIds else {
            lastTeamEditTask = nil
            return
        }

        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        let newMemberIds = Array(selectedTeamMemberIds)

        Task {
            do {
                try await dataController.updateTaskTeamMembers(task: task, memberIds: newMemberIds)
                print("[PROJECT_DETAILS] ✅ Task team update complete")
            } catch {
                print("[PROJECT_DETAILS] ⚠️ Team update failed: \(error)")
            }
        }

        lastTeamEditTask = nil
    }

    private func handleOnAppear() {
        // Inject dependencies
        viewModel.dataController = dataController
        viewModel.appState = appState

        // Setup expense VM
        if let companyId = dataController.currentUser?.companyId {
            expenseViewModel.setup(companyId: companyId)
            Task { await expenseViewModel.loadCategories() }
        }

        // Setup notes VM
        setupNotesViewModel()

        // Refresh client
        viewModel.refreshClientData()

        // Hydrate map coordinates when the project has an address but no
        // cached lat/lng (legacy Bubble rows, prior failed geocode).
        viewModel.geocodeAddressIfNeeded()

        // Wizard system: notify project opened (completes Job Board wizard step)
        NotificationCenter.default.post(
            name: Notification.Name("WizardJobBoardProjectTapped"),
            object: nil
        )

        // Wizard system: store this project for documentation wizard deep navigation
        // so CONTINUE GUIDE and initial deep nav return to THIS project, not "most recent"
        if let mgr = wizardStateManager {
            mgr.deepNavProjectId = project.id
        }

        // Wizard system: trigger documentation wizard on first project detail visit
        if let wizard = WizardRegistry.contextualWizard(for: "documentation") {
            wizardTriggerService?.evaluateTrigger(for: wizard, context: "project_detail_visit", projectCount: 1)
        }

        // Wizard: evaluate step prerequisites with actual photo count (auto-skip view_photo if 0 photos)
        if let mgr = wizardStateManager, mgr.isActive {
            let photoCount = project.getProjectImages().count
            mgr.evaluateStepPrerequisites(projectPhotoCount: photoCount)
        }

        // Pre-composite photo annotations into image cache so gallery
        // thumbnails and the photo viewer show annotations immediately.
        if let modelContext = dataController.modelContext {
            Task {
                await PhotoAnnotationSyncManager.shared.preCompositeAnnotations(
                    projectId: project.id,
                    modelContext: modelContext
                )
            }
        }
    }

    private func setupNotesViewModel() {
        guard let currentUser = dataController.currentUser,
              let companyId = currentUser.companyId,
              let company = dataController.getCurrentUserCompany(),
              let modelContext = dataController.modelContext else { return }

        // Use dataController.getTeamMembers() — company.teamMembers relationship is not populated by sync
        let teamUsers = dataController.getTeamMembers(companyId: companyId)
        let teamMemberObjects = teamUsers.map { TeamMember.fromUser($0) }

        notesViewModel.setup(
            companyId: companyId,
            currentUserId: currentUser.id,
            teamMembers: teamMemberObjects,
            modelContext: modelContext
        )
        Task { await notesViewModel.loadNotes() }
    }
}

