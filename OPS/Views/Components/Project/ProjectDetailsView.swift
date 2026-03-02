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
    @State private var isNoteComposing = false
    @State private var showingTaskPicker = false
    @State private var taskDetailTask: ProjectTask? = nil

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
                    }
                    .sheet(isPresented: $viewModel.showingImagePicker) {
                        imagePickerContent
                    }
                    .fullScreenCover(isPresented: $showingCameraBatch) {
                        CameraBatchView { capturedImages in
                            viewModel.selectedImages = capturedImages
                            if !capturedImages.isEmpty {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    viewModel.addPhotosToProject(tutorialMode: tutorialMode)
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
                    .sheet(isPresented: $viewModel.showingClientContact) {
                        clientContactSheet
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
                    .sheet(isPresented: $viewModel.showingAddressEditor) {
                        AddressEditorSheet(
                            address: $viewModel.editedAddress,
                            onSave: { viewModel.saveAddress() },
                            onCancel: { viewModel.showingAddressEditor = false }
                        )
                    }
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
                                onScheduleUpdate: viewModel.handleTaskScheduleUpdate
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
                    .sheet(isPresented: $showingTaskPicker) {
                        taskPickerSheet
                    }
                    .sheet(item: $taskDetailTask) { task in
                        TaskDetailPopupSheet(
                            task: task,
                            onSelect: { t in
                                withAnimation(OPSStyle.Animation.fast) {
                                    viewModel.selectedTask = t
                                }
                            },
                            onComplete: { t in
                                viewModel.selectedTask = t
                                viewModel.toggleTaskStatus()
                            },
                            onReschedule: { t in
                                viewModel.selectedTask = t
                                viewModel.showingTaskScheduler = true
                            },
                            onCancel: { t in
                                viewModel.selectedTask = t
                                viewModel.showingCancelTaskConfirmation = true
                            }
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
                    .confirmationDialog("Cancel Task?", isPresented: $viewModel.showingCancelTaskConfirmation, titleVisibility: .visible) {
                        Button("Cancel Task", role: .destructive) { viewModel.cancelSelectedTask() }
                        Button("Keep Task", role: .cancel) { }
                    } message: {
                        Text("This task will be marked as cancelled.")
                    }
                    .alert("Delete Task?", isPresented: $viewModel.showingTaskDeleteConfirmation) {
                        Button("Delete", role: .destructive) { viewModel.deleteSelectedTask() }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This action cannot be undone.")
                    }
                    .onAppear { handleOnAppear() }
            }
        }
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
                    // Initial spacer — positions content in lower portion of map
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

            // Layer 3: Nav bar (above scroll view so it's always tappable)
            projectNavBar
                .zIndex(10)

            // Layer 4: Floating toolbar — quick actions or note compose toolbar
            VStack {
                Spacer()
                if isNoteComposing {
                    NoteComposeToolbar(
                        onMention: {
                            notesViewModel.newNoteText += "@"
                            notesViewModel.handleMentionInput(notesViewModel.newNoteText)
                        },
                        onPhoto: { viewModel.showingNoteImagePicker = true },
                        onPost: {
                            Task {
                                await notesViewModel.postNote()
                                isNoteComposing = false
                            }
                        },
                        canPost: notesViewModel.canPost
                    )
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    ProjectQuickActionsBar(
                        selectedTask: viewModel.selectedTask,
                        hasClientContact: viewModel.hasClientContact,
                        canEdit: viewModel.canEditProject,
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
                        onAddTask: { viewModel.showingAddTaskSheet = true }
                    )
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .zIndex(5)
            .animation(OPSStyle.Animation.fast, value: isNoteComposing)
        }
        .background(OPSStyle.Colors.background.edgesIgnoringSafeArea(.all))
    }

    /// Gradient overlay that scrolls with title content — fades map into background
    private var mapScrollGradient: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: OPSStyle.Colors.background.opacity(0.5), location: 0.3),
                .init(color: OPSStyle.Colors.background.opacity(0.85), location: 0.7),
                .init(color: OPSStyle.Colors.background, location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 100)
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

            // Task badge — tappable to open picker
            if let task = viewModel.selectedTask {
                let taskColor = Color(hex: task.taskColor) ?? OPSStyle.Colors.primaryAccent
                let isComplete = task.status == .completed
                Button(action: { showingTaskPicker = true }) {
                    TaskBadge(
                        name: task.taskType?.display ?? "Task",
                        color: taskColor,
                        size: .navBar,
                        faded: isComplete
                    )
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
                Button(action: { showingTaskPicker = true }) {
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
    private var stickyHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectTitleOverlay(project: project)
            ProjectDetailsTabBar(selectedTab: $viewModel.selectedTab)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        .background(OPSStyle.Colors.background)
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
                onTaskTap: { task in taskDetailTask = task },
                onAddTask: { viewModel.showingAddTaskSheet = true },
                onEditAddress: {
                    viewModel.editedAddress = project.address ?? ""
                    viewModel.showingAddressEditor = true
                }
            )

        case .expenses:
            ProjectExpensesTabView(
                viewModel: viewModel,
                expenseViewModel: expenseViewModel,
                onAddExpense: { openNewExpenseSheet() },
                onTapExpense: { expense in editingExpense = expense }
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

    // MARK: - Task Picker Sheet

    private var taskPickerSheet: some View {
        let sortedTasks = project.tasks.sorted { $0.displayOrder < $1.displayOrder }
        return NavigationView {
            ScrollView {
                VStack(spacing: 8) {
                    // Deselect option (only if a task is currently selected)
                    if viewModel.selectedTask != nil {
                        Button(action: {
                            withAnimation(OPSStyle.Animation.fast) {
                                viewModel.selectedTask = nil
                            }
                            showingTaskPicker = false
                        }) {
                            HStack(spacing: 12) {
                                Circle()
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                    .frame(width: 10, height: 10)

                                Text("DESELECT")
                                    .font(.custom("Kosugi-Regular", size: 12))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider()
                            .background(OPSStyle.Colors.cardBorder)
                            .padding(.vertical, 4)
                    }

                    // Task list
                    ForEach(sortedTasks, id: \.id) { task in
                        Button(action: {
                            withAnimation(OPSStyle.Animation.fast) {
                                viewModel.selectedTask = task
                            }
                            showingTaskPicker = false
                        }) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent)
                                    .frame(width: 10, height: 10)

                                Text(task.displayTitle.uppercased())
                                    .font(.custom("Kosugi-Regular", size: 12))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .lineLimit(1)

                                StatusBadgePill(
                                    text: task.status.displayName.uppercased(),
                                    color: task.status.color,
                                    size: .small
                                )

                                Spacer()

                                if viewModel.selectedTask?.id == task.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(viewModel.selectedTask?.id == task.id ? OPSStyle.Colors.primaryAccent.opacity(0.1) : Color.clear)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle("SELECT TASK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingTaskPicker = false
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
    }

    private func setupNotesViewModel() {
        guard let currentUser = dataController.currentUser,
              let companyId = currentUser.companyId,
              let company = dataController.getCurrentUserCompany(),
              let modelContext = dataController.modelContext else { return }

        notesViewModel.setup(
            companyId: companyId,
            currentUserId: currentUser.id,
            teamMembers: company.teamMembers,
            modelContext: modelContext
        )
        Task { await notesViewModel.loadNotes() }
    }
}

