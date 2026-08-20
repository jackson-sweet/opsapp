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
    /// Bug 56c37df2 — PHOTO opens the standardized batch camera
    /// (same component as site-visit capture).
    @State private var showingCamera = false
    @State private var showingMeasureCapture = false
    @State private var showingDeckCreationPicker = false
    @State private var deckDesignToOpen: DeckDesign?
    @Query private var allDeckDesigns: [DeckDesign]
    @ObservedObject private var permissionStore = PermissionStore.shared
    @State private var isNoteComposing = false
    @State private var showingTaskPicker = false
    @State private var taskDetailTask: ProjectTask? = nil
    @State private var lastTeamEditTask: ProjectTask? = nil
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var allTeamMembers: [TeamMember] = []
    @State private var showingClientPicker = false
    /// Bug a3c4e216 — the project side of lead matching.
    @State private var showingLeadMatchPicker = false
    @Query private var companyLeads: [Opportunity]
    @State private var dismissDragOffset: CGFloat = 0
    @State private var isKeyboardVisible = false
    @State private var shareSource: ProjectShareItemSource?
    @State private var isPreparingShare = false

    // Deck fullscreen viewer — overscroll-to-expand focus mode.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var deckToolState = DeckViewerToolState()
    @State private var deckViewMode: DeckTabViewMode = .threeD
    @State private var isDeckFullscreen = false
    /// Live top-overscroll distance while the Deck tab is active (points).
    @State private var deckPull: CGFloat = 0
    /// Guards the one-shot commit so it fires once per pull.
    @State private var deckPullArmed = false
    /// Scroll viewport + content heights — used to compute bottom-overscroll
    /// correctly whether the deck content is taller or shorter than the screen.
    @State private var deckViewportHeight: CGFloat = 0
    @State private var deckContentHeight: CGFloat = 0

    init(project: Project, isEditMode: Bool = false, initialSelectedTask: ProjectTask? = nil) {
        self._project = Bindable(wrappedValue: project)
        self.isEditMode = isEditMode
        self.initialSelectedTask = initialSelectedTask

        self._viewModel = StateObject(wrappedValue: ProjectDetailsViewModel(
            project: project,
            initialSelectedTask: initialSelectedTask
        ))
        self._notesViewModel = StateObject(wrappedValue: ProjectNotesViewModel(projectId: project.id))

        // Scope to this project — deck_designs is realtime-subscribed, so an
        // unfiltered @Query invalidated this whole container on ANY company
        // deck save. DeckDesign.projectId is optional; compare via optional.
        let pid: String? = project.id
        self._allDeckDesigns = Query(
            filter: #Predicate<DeckDesign> { $0.projectId == pid }
        )

        // Live leads for this company. Stage, link state and address matching
        // are decided in ProjectLeadRow — #Predicate can express none of them
        // (stored enum comparison and address normalization both).
        let cid = project.companyId
        self._companyLeads = Query(
            filter: #Predicate<Opportunity> {
                $0.companyId == cid && $0.deletedAt == nil
            }
        )
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
                    .fullScreenCover(isPresented: $showingCamera) {
                        cameraContent
                    }
                    .fullScreenCover(isPresented: $showingMeasureCapture) {
                        // LiDAR Dimensioned Photo Capture (spec §3.1) — same
                        // capture/save behavior as Home's MeasureActionButton.
                        // Calibration continuity is owned inside the capture
                        // view so this container never tears down annotation
                        // state mid-flow.
                        DimensionedCaptureView(
                            projectId: project.id,
                            projectName: project.title,
                            companyId: project.companyId,
                            userId: dataController.currentUser?.id ?? "",
                            developerFlagOverride: MeasureActionButton.usesDeveloperFlagOverride(
                                flagEnabled: permissionStore.isFeatureEnabled(MeasurementFlag.dimensionedCapture),
                                capability: CaptureCapability.detect().capability
                            ),
                            onSavedSuccessfully: { _ in
                                showingMeasureCapture = false
                            },
                            onError: { _ in
                                showingMeasureCapture = false
                            }
                        )
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
                    .sheet(isPresented: $showingLeadMatchPicker) {
                        ProjectLeadMatchSheet(
                            project: project,
                            candidates: leadMatchCandidates
                        )
                        .environmentObject(dataController)
                    }
                    .sheet(item: $selectedTeamMember) { member in
                        ContactDetailView(user: member)
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
                                    // Gated on calendar.edit, scope-aware on the task.
                                    guard task.canEditSchedule else { return }
                                    // Bug f3604d52 — allow clearing the task's
                                    // dates from the scheduler sheet toolbar.
                                    // Mirrors CalendarEventCard.clearTaskDates.
                                    task.startDate = nil
                                    task.endDate = nil
                                    task.duration = 0
                                    task.needsSync = true
                                    try? dataController.modelContext?.save()
                                    dataController.scheduledTasksDidChange.toggle()
                                    let taskId = task.id
                                    Task {
                                        try? await dataController.updateTaskFields(
                                            taskId: taskId,
                                            fields: [
                                                "start_date": .null,
                                                "end_date": .null,
                                                "duration": .integer(0)
                                            ]
                                        )
                                    }
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
                    //
                    // Bugs 0aa825fe + 62481022 — `saveTaskTeamChanges` MUST NOT
                    // fire on sheet dismiss. The async updateTaskTeamMembers
                    // path issues several modelContext.save() calls (task
                    // mutation, then project syncProjectTeamMembersFromTasks);
                    // when those notifications fire DURING the inner sheet's
                    // dismiss animation, they tear down ProjectDetails' sheet
                    // — either as a glitch close or, in the worst case, as
                    // an outright crash from the @Bindable project being
                    // re-evaluated mid-transition. Commit + save now happens
                    // only on the explicit DONE button in TaskDetailPopupSheet's
                    // inline picker (via `onCommitTeam`). The sheet's
                    // dismissal is now purely UI cleanup.
                    .sheet(item: $taskDetailTask) { task in
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
                                guard t.canEditSchedule else { return }
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
                                guard t.canEditSchedule else { return }
                                viewModel.selectedTask = t
                                taskDetailTask = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    viewModel.showingTaskScheduler = true
                                }
                            },
                            selectedTeamMemberIds: $selectedTeamMemberIds,
                            allTeamMembers: allTeamMembers,
                            isProjectCompleted: project.status == .completed,
                            onCommitTeam: { committedIds in
                                commitTaskTeamChanges(memberIds: committedIds)
                            },
                            onCommitTaskType: { picked in
                                commitTaskTypeChange(task: task, taskType: picked)
                            },
                            onCommitDescription: { notes in
                                commitTaskDescriptionChange(task: task, notes: notes)
                            }
                        )
                    }
                    .confirmationDialog("Unsaved Changes", isPresented: $viewModel.showingUnsavedChangesAlert, titleVisibility: .visible) {
                        Button("Discard Changes", role: .destructive) { dismiss() }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("You have unsaved changes. Discard them?")
                    }
                    .errorToast($viewModel.networkError, label: Feedback.Err.operationFailed)
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
                        // Bug 138b0065 — both of these land real work inside the
                        // dismissal transaction: `projectDetailsDidDisappear`
                        // un-pauses the Mapbox render loop underneath, and the
                        // wizard broadcast re-evaluates step state. Run them one
                        // main-loop turn later so the close animation finishes
                        // first. Nothing about WHAT is broadcast changes.
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .projectDetailsDidDisappear, object: nil)
                            // Wizard system: notify that project details was closed
                            NotificationCenter.default.post(
                                name: Notification.Name("WizardScreenDismissed"),
                                object: nil,
                                userInfo: ["screen": "ProjectDetails"]
                            )
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardEvaluatePrerequisites"))) { _ in
                        // Re-evaluate prerequisites with current photo count
                        wizardStateManager?.evaluateStepPrerequisites(
                            projectPhotoCount: dataController.modelContext.map { viewModel.project.mergedGalleryImageURLs(using: $0).count } ?? viewModel.project.getProjectImages().count
                        )
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .opsExpensesDidChange)) { _ in
                        // An expense was added/edited (this project's add sheet, the
                        // global FAB) or arrived via realtime. The expenses tab reads
                        // `projectExpenses` — a separate cache from
                        // ExpenseViewModel.expenses — so refetch it live instead of
                        // waiting for the tab's onAppear `.task` to re-run on reopen.
                        Task { await viewModel.loadExpenses() }
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
                ProjectMapHeaderSection(
                    project: project,
                    taskColorHexes: viewModel.projectTaskColorHexes,
                    pinLabel: viewModel.pinLabel,
                    onMapTap: { viewModel.openDirections() }
                )
                Spacer()
            }

            // Layer 2: Scrollable content that slides up over the map
            ScrollViewReader { projectScrollProxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // Initial spacer — positions content in lower portion of map.
                    // Pulled down 40pt so the gradient starts later, revealing
                    // more map above the title (Bug a2f7e6fa).
                    //
                    // This spacer sits on top of the ProjectMapHeader in the
                    // outer ZStack, so taps over the visible map area land here
                    // first and never reach ProjectMapHeader.onTapGesture. Wire
                    // the same openDirections() the map tap calls so tapping
                    // anywhere over the visible map (whether technically on the
                    // map view or this spacer) opens native maps. Bug 6904755e.
                    Color.clear
                        .frame(height: ProjectMapHeader.mapHeight - 130)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.openDirections() }

                    // Gradient scrolls with content (not pinned — avoids content peeking through)
                    mapScrollGradient

                    // Pinned header: title + tab bar (solid background blocks content behind it)
                    Section(header: stickyHeader) {
                        tabContent(scrollProxy: projectScrollProxy)
                            .padding(.bottom, 100)
                            .background(OPSStyle.Colors.background)
                    }

                    // Deck overscroll probe — a zero-height reader at the BOTTOM of
                    // the content. Scrolling to the end and pulling UP pulls this
                    // child above the viewport bottom; bottomOverscroll =
                    // min(content, viewport) − its maxY. Drives pull-up-to-expand.
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .named(deckScrollSpace)).maxY) { _, maxY in
                                let restBottom = min(deckContentHeight, deckViewportHeight)
                                updateDeckPull(max(0, restBottom - maxY))
                            }
                    }
                    .frame(height: 0)
                }
                    .background(
                        GeometryReader { g in
                            Color.clear.onChange(of: g.size.height, initial: true) { _, h in
                                deckContentHeight = h
                            }
                        }
                    )
                }
                .coordinateSpace(name: deckScrollSpace)
                // Force the bottom rubber-band even when the deck tab's content fits the
                // viewport, so the pull-up-to-expand gesture is always available.
                .scrollBounceBehavior(.always, axes: .vertical)
                .scrollDismissesKeyboard(.interactively)
                .background(
                    GeometryReader { g in
                        Color.clear.onChange(of: g.size.height, initial: true) { _, h in
                            deckViewportHeight = h
                        }
                    }
                )
            }

            // Layer 3: Task picker overlay (below nav bar)
            if showingTaskPicker {
                taskPickerOverlay
                    .zIndex(15)
            }

            // Layer 4: Nav bar (above everything — CANCEL badge visible over gradient)
            projectNavBar
                .zIndex(20)

            // Layer 6: Deck pull-to-expand cue — appears over the map while the
            // user overscrolls the top of the Deck tab.
            if isDeckOverscrolling {
                deckPullCue
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 120)
                    .allowsHitTesting(false)
                    .zIndex(24)
            }


            // Layer 7: Deck fullscreen focus mode (covers nav + global tab bar).
            if isDeckFullscreen, let design = displayedDeckDesign {
                DeckFullscreenViewer(
                    title: project.title,
                    drawingData: design.drawingData,
                    drawingIdentity: design.drawingDataJSON,
                    viewMode: $deckViewMode,
                    toolState: deckToolState,
                    onClose: { dismissDeckFullscreen() },
                    onEdit: canEditDeckDesign
                        ? { editDeckDesignFromFullscreen(design) }
                        : nil
                )
                .zIndex(30)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
            }

            // Layer 5: Floating toolbar — quick actions (hidden when composing notes or keyboard visible)
            if !isNoteComposing && !isKeyboardVisible {
                VStack {
                    Spacer()
                    ProjectQuickActionsBar(
                        selectedTask: viewModel.selectedTask,
                        hasClientContact: viewModel.hasClientContact,
                        canEdit: viewModel.canEditProject,
                        isMentionOnly: viewModel.isMentionOnlyAccess,
                        onPhoto: {
                            openProjectPhotoCapture()
                        },
                        onNote: {
                            viewModel.selectedTab = .activity
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                isNoteComposing = true
                            }
                        },
                        onExpense: { openNewExpenseSheet() },
                        onComplete: { viewModel.toggleTaskStatus() },
                        onReschedule: {
                            guard viewModel.selectedTask?.canEditSchedule == true else { return }
                            viewModel.showingTaskScheduler = true
                        },
                        onContact: { viewModel.showingClientContact = true },
                        onAddTask: { viewModel.showingAddTaskSheet = true },
                        onDeckDesign: ProjectQuickActionPermissionGate.canShowDeckAction(
                            featureEnabled: permissionStore.isFeatureEnabled("deck_builder"),
                            canCreate: permissionStore.can("deck_builder.create", requiredScope: "assigned"),
                            canEdit: permissionStore.can("deck_builder.edit", requiredScope: "assigned")
                        ) ? { openDeckDesignFromActionBar() } : nil,
                        // LiDAR Dimensioned Photo Capture (spec §3.1) — gated
                        // by `MeasureActionButton.shouldRender` so rollout,
                        // debug override, and hardware-limit states stay in
                        // one place. Same logic as Home's ProjectActionBar entry.
                        onMeasure: MeasureActionButton.shouldRender(
                            flagEnabled: permissionStore.isFeatureEnabled(MeasurementFlag.dimensionedCapture),
                            capability: CaptureCapability.detect().capability
                        ) ? {
                            showingMeasureCapture = true
                        } : nil,
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
                    .padding(.bottom, OPSStyle.Layout.spacing3)
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
        .opacity(
            dismissDragOffset > 0
                ? 1.0 - Double(dismissDragOffset) / Self.dismissFadeDistance
                : 1.0
        )
        .simultaneousGesture(
            // Bug 138b0065 — swipe-to-close was measured in the DEFAULT local
            // space, which is the space this view's own `.offset` moves. Every
            // point the sheet travelled was therefore subtracted from the next
            // translation: the content chased the finger, gave back what it had
            // just taken, and stuttered. `dismissDragSpace` is named on the
            // wrapper below, whose frame the offset never touches, so the drag
            // now reads true finger movement.
            DragGesture(
                minimumDistance: 50,
                coordinateSpace: .named(dismissDragSpace)
            )
                .onChanged { value in
                    // Only the top grab band closes the sheet; everywhere else
                    // the drag belongs to the scroll view.
                    guard value.startLocation.y < Self.dismissGrabBandHeight else { return }
                    dismissDragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    guard value.startLocation.y < Self.dismissGrabBandHeight else { return }
                    if value.translation.height > Self.dismissCommitDistance {
                        // Hand the close straight to the sheet's own dismissal.
                        // The old path animated the content off-screen over a
                        // quarter second and only THEN called dismiss(), so the
                        // operator watched two animations back to back — the
                        // second one on an already-empty frame. Leaving the
                        // offset where the finger left it lets the system
                        // dismissal continue the same movement without a seam.
                        dismiss()
                    } else {
                        withAnimation(OPSStyle.Animation.standard) {
                            dismissDragOffset = 0
                        }
                    }
                }
        )
        .coordinateSpace(name: dismissDragSpace)
    }

    // MARK: - Swipe-to-close

    /// Stable space for the dismiss drag — named on the wrapper ABOVE the
    /// `.offset`, so translations are not fed back through the offset they
    /// produce.
    private var dismissDragSpace: String { "projectDetailsDismissDrag" }

    /// Only a drag that starts inside this top band closes the sheet. Below it
    /// the map spacer and the scroll view own the gesture.
    private static let dismissGrabBandHeight: CGFloat = 120

    /// How far the sheet must travel before the release commits to closing.
    private static let dismissCommitDistance: CGFloat = 150

    /// Travel over which the sheet fades to fully transparent while dragging.
    private static let dismissFadeDistance: Double = 600

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
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .padding(.vertical, 6)
                    .background(OPSStyle.Colors.primaryText)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
            }

            Spacer()

            // Task badge — tappable to open/close picker
            if showingTaskPicker {
                // When picker is open, badge becomes CANCEL button
                Button(action: {
                    withAnimation(OPSStyle.Animation.standard) {
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
                    withAnimation(OPSStyle.Animation.standard) {
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
                    withAnimation(OPSStyle.Animation.standard) {
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
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
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
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing1)
        }
        .background(OPSStyle.Colors.background)
    }

    // MARK: - Tab Visibility

    private var visibleTabs: [ProjectDetailTab] {
        var tabs: [ProjectDetailTab] = [.activity, .details, .expenses]
        if permissionStore.isFeatureEnabled("deck_builder") && permissionStore.can("deck_builder.view", requiredScope: "assigned") {
            tabs.append(.deck)
        }
        return tabs
    }

    // MARK: - Deck Fullscreen (overscroll-to-expand)

    private let deckScrollSpace = "projectDetailsDeckScroll"

    /// The deck design the tab is currently showing (mirrors DeckTabView).
    private var displayedDeckDesign: DeckDesign? {
        DeckDesign.displayCandidate(in: allDeckDesigns, forProjectId: project.id)
    }
    private var hasRenderableDeck: Bool {
        displayedDeckDesign?.hasRenderableGeometry == true
    }
    /// The Deck tab is at the top and being pulled past it (cue-visible window).
    private var isDeckOverscrolling: Bool {
        !isDeckFullscreen && viewModel.selectedTab == .deck && hasRenderableDeck
            && deckViewMode != .materials && deckPull > 1
    }
    private var deckExpandProgress: CGFloat { DeckOverscrollMath.progress(pull: deckPull) }

    /// Called on every scroll change with the top-edge overscroll amount (points).
    /// On the Deck tab, the instant the pull crosses the threshold, fire the haptic
    /// and open fullscreen (one-shot via `deckPullArmed`); below the threshold the
    /// scroll rubber-bands back on its own. Inert off the Deck tab.
    private func updateDeckPull(_ pull: CGFloat) {
        // Pull-to-expand is a CANVAS affordance — fullscreen has no materials
        // form. Gating on the mode also absorbs the content-height collapse
        // when the tall viewport swaps for the shorter materials card: the
        // probe reads that reflow as a huge "pull" for a frame and would
        // otherwise commit fullscreen on a plain segment tap.
        guard viewModel.selectedTab == .deck, hasRenderableDeck, !isDeckFullscreen,
              deckViewMode != .materials else {
            if deckPull != 0 { deckPull = 0 }
            deckPullArmed = false
            return
        }
        deckPull = pull
        if DeckOverscrollMath.isCommitted(pull: pull), !deckPullArmed {
            deckPullArmed = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            presentDeckFullscreen()
        } else if pull < DeckOverscrollMath.commitThreshold {
            deckPullArmed = false
        }
    }

    private func presentDeckFullscreen() {
        // Fullscreen is a canvas surface; the MATERIALS tab has no fullscreen
        // form. Land on the 2D plan so the viewer and its 3D/2D control open
        // in a coherent state.
        if deckViewMode == .materials { deckViewMode = .twoD }
        withAnimation(reduceMotion ? OPSStyle.Animation.faster : OPSStyle.Animation.standard) {
            isDeckFullscreen = true
        }
    }

    private func dismissDeckFullscreen() {
        withAnimation(reduceMotion ? OPSStyle.Animation.faster : OPSStyle.Animation.standard) {
            isDeckFullscreen = false
        }
        // Clean slate for the next open (invisible during the animate-out).
        deckToolState.mode = .none
        deckToolState.clearSelection()
        deckToolState.isolatedLevelId = nil
        deckToolState.showDimensions = true
    }

    /// May this operator edit THIS project's deck? The SAME rule the deck
    /// tab's own EDIT verb and the quick-action gate already make (see
    /// `onDeckDesign:` on the quick-actions bar) — behind the feature flag the
    /// tab itself is gated on. No new project rule is invented here.
    private var canEditDeckDesign: Bool {
        permissionStore.isFeatureEnabled("deck_builder")
            && permissionStore.can("deck_builder.edit", requiredScope: "assigned")
    }

    /// EDIT from the fullscreen viewer: close the viewer, THEN open the
    /// builder. The builder is a `.fullScreenCover` and iOS will not present a
    /// modal while another presentation is still animating (the same trap the
    /// creation picker hit — see `deckCreationPickerContent`), so the handoff
    /// waits out the dismiss rather than nesting covers.
    private func editDeckDesignFromFullscreen(_ design: DeckDesign) {
        dismissDeckFullscreen()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            deckDesignToOpen = design
        }
    }

    /// Pull cue shown over the map during a top-overscroll on the Deck tab.
    @ViewBuilder
    private var deckPullCue: some View {
        let committed = deckExpandProgress >= 1
        VStack(spacing: OPSStyle.Layout.spacing1) {
            Image(systemName: "chevron.up")
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(committed ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
            Text(committed ? "RELEASE TO EXPAND" : "PULL TO EXPAND")
                .font(OPSStyle.Typography.metadata)
                .tracking(1)
                .foregroundColor(committed ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(Capsule().fill(Color.black.opacity(0.7)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .opacity(Double(min(1, deckExpandProgress * 1.4)))
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(scrollProxy: ScrollViewProxy) -> some View {
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
                scrollProxy: scrollProxy,
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
                onDuplicateTask: { task in
                    viewModel.duplicateTask(task)
                },
                onDeleteTask: { task in
                    viewModel.selectedTask = task
                    viewModel.showingTaskDeleteConfirmation = true
                },
                onClientLongPress: { showingClientPicker = true },
                onChangeStatus: { showingStatusPicker = true },
                leadRowPresentation: leadRowPresentation,
                onOpenLead: openLinkedLead,
                onMatchLead: { showingLeadMatchPicker = true }
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
                owner: .project(project),
                onCreateDeckDesign: { showingDeckCreationPicker = true },
                onEditDeckDesign: { design in deckDesignToOpen = design },
                viewMode: $deckViewMode,
                onRequestFullscreen: { presentDeckFullscreen() }
            )
        }
    }

    // MARK: - Sheet Contents

    private var photoViewerContent: some View {
        // Same merged gallery list the carousel renders (synced project_photos ∪
        // legacy CSV) so selectedPhotoIndex maps to the correct photo.
        let photos = dataController.modelContext.map { project.mergedGalleryImageURLs(using: $0) }
            ?? project.getProjectImages()
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

    private var cameraContent: some View {
        // Bug 56c37df2 — the standardized batch camera (same component
        // as site-visit capture): live multi-shot, real lens stops, and
        // library import built into the camera HUD.
        CameraBatchView { images in
            showingCamera = false
            guard !images.isEmpty else { return }
            viewModel.selectedImages = images
            viewModel.addPhotosToProject(tutorialMode: tutorialMode)
            NotificationCenter.default.post(
                name: Notification.Name("WizardPhotoCaptured"),
                object: nil
            )
        }
    }

    private func openProjectPhotoCapture() {
        showingCamera = true
    }

    private func openDeckDesignFromActionBar() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        switch ProjectDeckActionResolver.resolve(designs: allDeckDesigns, forProjectId: project.id) {
        case .open(let design):
            deckDesignToOpen = design
        case .create:
            showingDeckCreationPicker = true
        }
    }

    private var noteImagePickerContent: some View {
        ImagePicker(
            images: $noteSelectedImages,
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
                // Bug 1 fix: dismiss the picker sheet BEFORE presenting the
                // fullScreenCover. iOS cannot present two modals simultaneously;
                // setting deckDesignToOpen while the sheet is still visible
                // caused DeckBuilderView to silently not appear. Close the
                // picker first, then open the builder on the next run-loop turn.
                showingDeckCreationPicker = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    deckDesignToOpen = design
                }
            }
        )
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func deckBuilderContent(design: DeckDesign) -> some View {
        if let modelContext = dataController.modelContext {
            DeckBuilderView(
                deckDesign: design,
                modelContext: modelContext,
                syncEngine: dataController.syncEngine,
                projectName: project.title
            )
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
                withAnimation(OPSStyle.Animation.standard) {
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
                                withAnimation(OPSStyle.Animation.standard) {
                                    showingTaskPicker = false
                                }
                            }) {
                                HStack(spacing: OPSStyle.Layout.spacing2) {
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
                                            .foregroundColor(OPSStyle.Colors.text)
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
                                .padding(.vertical, OPSStyle.Layout.spacing1)

                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(OPSStyle.Animation.fast) {
                                    viewModel.selectedTask = nil
                                }
                                withAnimation(OPSStyle.Animation.standard) {
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
                    .padding(.top, OPSStyle.Layout.spacing2)
                    .padding(.bottom, OPSStyle.Layout.spacing3)
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
            .padding(.trailing, OPSStyle.Layout.spacing3)
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

    /// Commit a confirmed team selection from `TaskDetailPopupSheet`'s
    /// inline picker. The DONE button there fires this with the already
    /// canonicalized id set so we don't have to depend on `lastTeamEditTask`
    /// or `selectedTeamMemberIds` being in any particular state when this
    /// runs. The save itself is intentionally launched as a detached Task
    /// (and on the next runloop turn) so the SwiftData notification cascade
    /// from `updateTaskTeamMembers`' multiple modelContext saves never
    /// overlaps a sheet animation — that overlap was the root cause of the
    /// ProjectDetails crash + glitch-close on inline team assignment
    /// (Bugs 0aa825fe + 62481022).
    private func commitTaskTeamChanges(memberIds: Set<String>) {
        guard let task = lastTeamEditTask else { return }
        let currentIds = Set(task.getTeamMemberIds())
        guard memberIds != currentIds else { return }

        let newMemberIds = Array(memberIds)

        DispatchQueue.main.async {
            Task {
                do {
                    try await dataController.updateTaskTeamMembers(task: task, memberIds: newMemberIds)
                    print("[PROJECT_DETAILS] ✅ Task team update complete")
                } catch {
                    print("[PROJECT_DETAILS] ⚠️ Team update failed: \(error)")
                }
            }
        }
    }

    // MARK: - LEAD provenance (bug a3c4e216)

    /// Every company-scoped won, unconverted lead the operator may choose.
    /// Address and client identity order likely provenance first; they never
    /// remove a manual choice.
    private var leadMatchCandidates: [Opportunity] {
        let matchable = ProjectLeadRow.matchableLeads(
            project: ProjectLeadRow.ProjectContext(
                companyId: project.companyId,
                clientId: project.clientId,
                address: project.address
            ),
            leads: companyLeads.map {
                ProjectLeadRow.LeadCandidate(
                    id: $0.id,
                    companyId: $0.companyId,
                    clientId: $0.clientId,
                    address: $0.address,
                    stage: $0.stage,
                    projectId: $0.projectId,
                    label: $0.title ?? $0.contactName
                )
            }
        )
        // Preserve matchableLeads' ordering (same-client first) — filtering
        // companyLeads by an id SET would silently restore store order.
        let byId = Dictionary(uniqueKeysWithValues: companyLeads.map { ($0.id, $0) })
        return matchable.compactMap { byId[$0.id] }
    }

    private var linkedLead: Opportunity? {
        guard let oid = project.opportunityId,
              !oid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return companyLeads.first { $0.id == oid }
    }

    private var leadRowPresentation: ProjectLeadRow.Presentation {
        ProjectLeadRow.presentation(
            opportunityId: project.opportunityId,
            leadLabel: linkedLead.map { $0.title ?? $0.contactName },
            candidateCount: leadMatchCandidates.count,
            // Matching runs the guarded conversion, which is a pipeline write.
            canMatch: permissionStore.can("pipeline.manage", requiredScope: "assigned")
        )
    }

    /// How long to wait after asking this sheet to close before firing an
    /// app-wide route that targets a surface BELOW it. Long enough for the
    /// sheet's own dismissal to finish so the tab swap and detail push are not
    /// racing a view that is still on screen. Matches the notification rail's
    /// shipped hand-off (`NotificationListView.openLead`).
    private static let crossEntityRouteDelay: TimeInterval = 0.3

    /// LEAD row tap — the app-wide lead route, the same channel notifications
    /// and Spotlight use.
    ///
    /// Bug 80dab840: that route lands on the LEADS TAB, and the tab lives
    /// UNDER this sheet — LeadsTabView PUSHES LeadDetailView onto its own
    /// navigation stack, so it can never rise above a presented sheet. Posting
    /// while project details was still up opened the lead behind it. Close this
    /// sheet first and post once it is gone, the same order the notification
    /// rail already uses for its own lead taps (NotificationListView.openLead).
    private func openLinkedLead() {
        guard let oid = project.opportunityId,
              !oid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.crossEntityRouteDelay) {
            NotificationCenter.default.post(
                name: Notification.Name("OpenLeadDetails"),
                object: nil,
                userInfo: ["leadId": oid]
            )
        }
    }

    /// Bug 10b66fce - a confirmed task-type change from the task detail
    /// sheet's type eyebrow. Deferred off the sheet's critical path for the
    /// same reason as `commitTaskTeamChanges`: `updateTaskFields` saves the
    /// model context, and that notification cascade landing mid sheet
    /// animation is what tore down ProjectDetails in bugs 0aa825fe / 62481022.
    /// Routed through DataController so the edit is queued for sync - a bare
    /// modelContext.save() would strand it on this device.
    private func commitTaskTypeChange(task: ProjectTask, taskType: TaskType) {
        guard task.taskTypeId != taskType.id else { return }
        let taskId = task.id
        let newTypeId = taskType.id

        DispatchQueue.main.async {
            Task {
                do {
                    try await dataController.updateTaskFields(
                        taskId: taskId,
                        fields: ["task_type_id": .string(newTypeId)]
                    )
                    // The type drives the job's colour and title on every
                    // calendar surface, so the calendars must repaint.
                    dataController.notifyReviewSourcesChanged()
                } catch {
                    print("[PROJECT_DETAILS] Task type update failed: \(error)")
                }
            }
        }
    }

    /// Bug 10b66fce - a confirmed description edit. Same deferred-write
    /// contract as the type and crew commits above.
    private func commitTaskDescriptionChange(task: ProjectTask, notes: String) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = (task.taskNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != current else { return }
        let taskId = task.id

        DispatchQueue.main.async {
            Task {
                do {
                    try await dataController.updateTaskFields(
                        taskId: taskId,
                        fields: ["task_notes": trimmed.isEmpty ? .null : .string(trimmed)]
                    )
                } catch {
                    print("[PROJECT_DETAILS] Task notes update failed: \(error)")
                }
            }
        }
    }

    private func handleOnAppear() {
        NotificationCenter.default.post(name: .projectDetailsDidAppear, object: nil)
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

        // Bug 7b43be32 — refresh per-photo client visibility from
        // Supabase so the eye toggle in the photo viewer reflects what
        // the customer actually sees in the portal, even after another
        // crew member changed it on a different device.
        if let imageSyncManager = dataController.imageSyncManager {
            Task { await imageSyncManager.refreshClientVisibility(for: project) }
        }

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
            let photoCount = dataController.modelContext.map { project.mergedGalleryImageURLs(using: $0).count } ?? project.getProjectImages().count
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
            modelContext: modelContext,
            dataController: dataController
        )
        Task { await notesViewModel.loadNotes() }
    }
}


// MARK: - Presentation notifications

extension Notification.Name {
    /// Posted on appear/disappear of the project-details screen. The
    /// workspace map (still mapped behind the details .sheet on the home
    /// tab) observes these to pause its puck + drawing while covered.
    static let projectDetailsDidAppear = Notification.Name("projectDetailsDidAppear")
    static let projectDetailsDidDisappear = Notification.Name("projectDetailsDidDisappear")
}
