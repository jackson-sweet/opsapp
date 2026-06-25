//
//  ScheduleView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// ScheduleView.swift
import SwiftUI
import SwiftData

// Helper struct to hold task and project IDs together (not the models themselves)
struct TaskDetailInfo: Identifiable {
    let id = UUID()
    let taskId: String
    let projectId: String
}

struct ScheduleView: View {
    // This view no longer uses NavigationLink for project details
    // All project presentations are done via the sheet in ProjectSheetContainer
    // Notification observers for direct project and task list selection
    private let projectSelectionObserver = NotificationCenter.default
        .publisher(for: Notification.Name("ShowCalendarProjectDetails"))
    
    private let taskSelectionObserver = NotificationCenter.default
        .publisher(for: Notification.Name("ShowCalendarTaskDetails"))
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase
    @Environment(\.wizardTriggerService) private var wizardTriggerService
    @Environment(\.wizardActive) private var wizardActive
    @Environment(\.wizardStateManager) private var wizardStateManager
    @StateObject private var viewModel = CalendarViewModel()
    @State private var hasPostedWeekScrollNotification = false
    @State private var hasPostedMonthExploredNotification = false
    @State private var hasPostedWizardWeekScroll = false
    @State private var hasUserScrolledInWeekView = false
    @State private var hasUserScrolledInMonthView = false
    @State private var hasUserPinchedInMonthView = false
    @State private var selectedProjectID: String? = nil
    @State private var selectedTaskDetail: TaskDetailInfo? = nil
    @State private var showSearchSheet = false
    @State private var showingRefreshAlert = false
    @State private var showFilterSheet = false
    @State private var showSyncMessage = false
    @State private var syncedProjectsCount = 0
    @State private var showScopeMessage = false
    @State private var scopeMessageText = ""
    @State private var showScheduleBanner = false
    @State private var scheduleBannerText = ""

    // Drag-and-drop reschedule — one session shared by the month grid + week strip,
    // injected via `.environment` so both surfaces and the live target banner read it.
    @State private var dragSession = ScheduleDragSession()

    // Bug 68123654 — iPhone Calendar Mirror state
    @StateObject private var mirrorService = CalendarMirrorService.shared
    @AppStorage("ops.calendar.mirror.bannerDismissCount") private var mirrorBannerDismissCount: Int = 0

    // Phase-C suggested events (item 63144953)
    @State private var showSuggestedEventsSheet = false

    private var shouldShowMirrorBanner: Bool {
        mirrorService.hasShownPrompt
            && !mirrorService.isEnabled
            && mirrorService.authorizationStatus != .denied
            && mirrorBannerDismissCount < 2
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header with its own internal padding of 20
                    AppHeader(
                        headerType: .schedule,
                        onFilterTapped: {
                            showFilterSheet = true
                        },
                        onMonthTapped: { viewModel.toggleMonthExpanded() },
                        // Bug 294ea224 — quick in-place ALL/MINE flip. The
                        // legacy ScheduleTeamScopeSheet was removed; team
                        // member multi-select lives in the unified filter
                        // sheet now. Long-press could open it but a single
                        // tap should always be fast.
                        onScopeToggled: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            let isCurrentlyAll = viewModel.scheduleScope == .all && viewModel.selectedTeamMemberIds.isEmpty
                            viewModel.updateScheduleScope(isCurrentlyAll ? .mine : .all)
                            scopeMessageText = isCurrentlyAll ? "[ MY TASKS ]" : "[ ALL TEAM ]"
                            showScopeMessage = true
                        },
                        isScopeAll: viewModel.scheduleScope == .all && viewModel.selectedTeamMemberIds.isEmpty,
                        hasActiveFilters: viewModel.hasActiveFilters,
                        filterCount: viewModel.activeFilterCount
                    )
                    .padding(.bottom, OPSStyle.Layout.spacing2)

                    // Persistent offline / weak-signal status. Self-hides when the
                    // connection is good, so it earns its space only while the
                    // on-screen schedule might be stale.
                    if let connectivity = dataController.connectivity {
                        ScheduleConnectivityStrip(connectivity: connectivity)
                            .animation(OPSStyle.Animation.standard, value: connectivity.shouldAttemptSync)
                    }

                    // Phase-C suggested events (item 63144953) — only when there's
                    // something to review; otherwise fully dormant (no banner).
                    if !viewModel.suggestedEvents.isEmpty {
                        suggestedEventsBanner
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.bottom, OPSStyle.Layout.spacing2)
                    }

                    // Bug 68123654 — iPhone Calendar Mirror reminder banner
                    if shouldShowMirrorBanner {
                        mirrorBanner
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.bottom, OPSStyle.Layout.spacing2)
                    }
                
                VStack(spacing: 0) {
                    // Extra top padding during calendarMonthPrompt to make room for tooltip
                    if tutorialMode && tutorialPhase == .calendarMonthPrompt {
                        Spacer().frame(height: 48)
                    }

                    // Week strip (or month grid when expanded) — always visible
                    CalendarDaySelector(viewModel: viewModel)
                        .padding(.horizontal, viewModel.isMonthExpanded ? 16 : 20)
                        .padding(.bottom, viewModel.isMonthExpanded ? 0 : 16)

                    // Day canvas — only in week mode
                    if !viewModel.isMonthExpanded {
                        if hasNoProjectsAtAll {
                            // First-time user with zero projects — show prompt at schedule level
                            scheduleEmptyStatePrompt
                                .transition(.opacity)
                        } else {
                            DayCanvasView(viewModel: viewModel)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .animation(OPSStyle.Animation.standard, value: viewModel.isMonthExpanded)
                // Live target-date banner while a reschedule drag is in flight —
                // floats at the top of the calendar so the operator sees exactly
                // where the job will land before they let go.
                .overlay(alignment: .top) {
                    RescheduleTargetBanner()
                        .padding(.top, OPSStyle.Layout.spacing1)
                        .allowsHitTesting(false)
                }
                .padding(.bottom, viewModel.isMonthExpanded ? (wizardActive ? 80 : 0) : 90) // tab bar + wizard bar clearance
                //.frame(maxWidth: 50)
            }
            }
        }
        .trackScreen("Schedule")
        .environment(dragSession)
       // .ignoresSafeArea(.keyboard)
        // Monitor viewMode changes to handle view transitions
        .onChange(of: viewModel.viewMode) { _, newMode in
            // Reset any project selection when switching view modes
            selectedProjectID = nil
        }
        // Initialize on appear
        .onAppear {
            // Track screen view for analytics
            AnalyticsManager.shared.trackScreenView(screenName: .schedule, screenClass: "ScheduleView")
            AnalyticsService.shared.trackScreenView(screenName: "schedule")

            // Initialize with proper data controller
            viewModel.setDataController(dataController)

            // Phase-C suggested events (item 63144953) — dormant on empty/error.
            Task { await viewModel.loadSuggestedEvents() }

            // Wizard system: evaluate scheduling/calendar wizard trigger
            if let wizard = WizardRegistry.contextualWizard(for: "scheduling_calendar") {
                wizardTriggerService?.evaluateTrigger(for: wizard, context: "calendar_tab_visit")
            }
        }
        .onDisappear {
            AnalyticsService.shared.endScreenView(screenName: "schedule")
        }
        // Wizard: collapse to week view when the wizard navigates here for a week-mode step.
        // Without this, steps 1-2 (scroll_week, tap_day) are unreachable if the user was
        // already in month view when the wizard started.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardNavigateToTarget"))) { notification in
            guard let targetScreen = notification.userInfo?["targetScreen"] as? String,
                  targetScreen == "Schedule" else { return }
            // If the wizard's current step needs week view and we're in month view, collapse
            if let stepId = wizardStateManager?.currentStep?.id,
               (stepId == "scroll_week" || stepId == "tap_day"),
               viewModel.isMonthExpanded {
                viewModel.toggleMonthExpanded()
            }
        }
        // Watch for calendar event changes and reload data
        .onChange(of: dataController.scheduledTasksDidChange) { _, _ in
            viewModel.reloadCalendarData()
        }
        // Universal search sheet
        .sheet(isPresented: $showSearchSheet) {
            UniversalSearchSheet()
                .environmentObject(dataController)
                .environmentObject(appState)
                .environmentObject(PermissionStore.shared)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // Phase-C suggested events review (item 63144953)
        .sheet(isPresented: $showSuggestedEventsSheet) {
            SuggestedEventsReviewSheet(isPresented: $showSuggestedEventsSheet, viewModel: viewModel)
                .environmentObject(dataController)
        }
        
        
        // We're using navigation instead of a sheet
        // Handle direct project selection from the project list
        .onReceive(projectSelectionObserver) { notification in
            if let projectID = notification.userInfo?["projectID"] as? String {
                
                // Set the project ID
                self.selectedProjectID = projectID
                
                // Get the project and present it via the sheet
                if let project = dataController.getProject(id: projectID) {
                    // Just use viewProjectDetails which handles all the necessary state updates
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        appState.viewProjectDetails(project)
                    }
                } else {
                }
            } else {
            }
        }
        // Handle direct task selection from the calendar
        .onReceive(taskSelectionObserver) { notification in
            if let taskID = notification.userInfo?["taskID"] as? String,
               let projectID = notification.userInfo?["projectID"] as? String {
                
                
                // Create the task detail info with just IDs
                let taskDetail = TaskDetailInfo(taskId: taskID, projectId: projectID)
                // Set it to trigger the sheet
                self.selectedTaskDetail = taskDetail
            } else {
            }
        }
        // Add task details sheet using item binding
        .sheet(item: $selectedTaskDetail) { taskDetail in
            // Fetch fresh models using IDs
            if let project = dataController.getProject(id: taskDetail.projectId),
               let task = project.tasks.first(where: { $0.id == taskDetail.taskId }) {
                NavigationView {
                    ProjectDetailsView(project: project, initialSelectedTask: task)
                        .environmentObject(dataController)
                        .environmentObject(appState)
                        .environment(\.modelContext, dataController.modelContext!)
                }
                .interactiveDismissDisabled(true)
                .wizardBannerIfAvailable(stateManager: wizardStateManager)
                .wizardOverlayIfAvailable(stateManager: wizardStateManager)
            } else {
                Text("Task no longer available")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        // Add refresh indicator
        .refreshIndicator(isPresented: $showingRefreshAlert)

        // Add sync message with fetch count
        .overlay(
            PushInMessage(
                isPresented: $showSyncMessage,
                title: "[ \(syncedProjectsCount) NEW PROJECT\(syncedProjectsCount == 1 ? "" : "S") LOADED ]",
                subtitle: nil,
                type: .info,
                autoDismissAfter: 4.0,
                showDismissButton: false
            )
            .ignoresSafeArea(edges: .top)
            .zIndex(1000)
        )

        // Scope change message
        .overlay(
            PushInMessage(
                isPresented: $showScopeMessage,
                title: scopeMessageText,
                subtitle: nil,
                type: .info,
                autoDismissAfter: 2.0,
                showDismissButton: false
            )
            .ignoresSafeArea(edges: .top)
            .zIndex(1001)
        )

        // Schedule action banner (push/extend feedback)
        .overlay(
            PushInMessage(
                isPresented: $showScheduleBanner,
                title: scheduleBannerText,
                subtitle: nil,
                type: .success,
                autoDismissAfter: 3.0,
                showDismissButton: false
            )
            .ignoresSafeArea(edges: .top)
            .zIndex(1002)
        )
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowScheduleBanner"))) { notification in
            if let title = notification.userInfo?["title"] as? String {
                scheduleBannerText = title
                showScheduleBanner = true
            }
        }

        // Filter sheet — collapsible dropdowns (bug 294ea224). Detents bumped
        // off the half-height default so the compact dropdown header sits
        // visually in the top half without leaving a giant empty void.
        .sheet(isPresented: $showFilterSheet) {
            CalendarFilterView(viewModel: viewModel)
                .environmentObject(dataController)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // Crew/dependency cascade prompt for a drag-drop reschedule (three-way:
        // push their work / move only this / cancel). Reuses CascadePreviewSheet.
        .sheet(item: Binding(
            get: { dragSession.pendingPrompt },
            set: { dragSession.pendingPrompt = $0 }
        )) { prompt in
            if let task = dataController.getTask(id: prompt.taskId) {
                CascadePreviewSheet(
                    pushedTaskName: prompt.taskName,
                    pushedTaskOldStart: prompt.oldStart,
                    pushedTaskNewStart: prompt.newStart,
                    pushedTaskNewEnd: prompt.newEnd,
                    cascadeChanges: prompt.changes,
                    onConfirm: {
                        Task {
                            // Defense-in-depth: re-check the gate at commit time — a
                            // permission/assignment change could land while the sheet
                            // is open. Toast count comes from the applied result, not
                            // the (possibly re-planned-away) drop-time snapshot.
                            guard task.canEditSchedule else {
                                UINotificationFeedbackGenerator().notificationOccurred(.error); return
                            }
                            do {
                                let result = try await dataController.commitDropReschedule(
                                    task, targetStart: prompt.newStart, targetEnd: prompt.newEnd, cascade: true)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                ToastCenter.shared.present(Feedback.Task.scheduleUpdatedCascade(count: result.changes.count + 1))
                            } catch {
                                UINotificationFeedbackGenerator().notificationOccurred(.error)
                            }
                        }
                    },
                    onCancel: { },
                    explanationLines: prompt.explanationLines,
                    primaryLabel: prompt.primaryLabel,
                    onMoveOnly: {
                        Task {
                            guard task.canEditSchedule else {
                                UINotificationFeedbackGenerator().notificationOccurred(.error); return
                            }
                            do {
                                _ = try await dataController.commitDropReschedule(
                                    task, targetStart: prompt.newStart, targetEnd: prompt.newEnd, cascade: false)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                ToastCenter.shared.present(Feedback.Task.scheduledFor(start: prompt.newStart, end: prompt.newEnd))
                            } catch {
                                UINotificationFeedbackGenerator().notificationOccurred(.error)
                            }
                        }
                    }
                )
                .environmentObject(dataController)
                .presentationDetents([.medium])
            }
        }
        // Refresh user events when created from FAB (which owns the sheets)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CalendarUserEventsDidChange"))) { _ in
            viewModel.loadUserEvents()
        }
        // Tutorial mode: Listen for scroll in week view
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CalendarWeekViewScrolled"))) { _ in
            if !hasPostedWizardWeekScroll {
                hasPostedWizardWeekScroll = true
                NotificationCenter.default.post(name: Notification.Name("WizardCalendarWeekScrolled"), object: nil)
            }
            if tutorialMode && tutorialPhase == .calendarWeek && !hasPostedWeekScrollNotification {
                hasUserScrolledInWeekView = true
                hasPostedWeekScrollNotification = true
                NotificationCenter.default.post(
                    name: Notification.Name("TutorialCalendarWeekScrolled"),
                    object: nil
                )
            }
        }
        // Tutorial mode: post notification when view mode changes to month
        .onChange(of: viewModel.viewMode) { _, newMode in
            if newMode == .month {
                NotificationCenter.default.post(name: Notification.Name("WizardCalendarMonthToggled"), object: nil)
            }
            if tutorialMode && newMode == .month {
                NotificationCenter.default.post(
                    name: Notification.Name("TutorialCalendarMonthTapped"),
                    object: nil
                )
            }
        }
        // Tutorial mode: Listen for scroll in month view - advance 2s after user scrolls
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CalendarMonthViewScrolled"))) { _ in
            NotificationCenter.default.post(name: Notification.Name("WizardCalendarMonthExplored"), object: nil)
            if tutorialMode && tutorialPhase == .calendarMonth && !hasUserScrolledInMonthView {
                hasUserScrolledInMonthView = true

                // Wait 2 seconds after user scrolls, then advance
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if tutorialPhase == .calendarMonth && !hasPostedMonthExploredNotification {
                        hasPostedMonthExploredNotification = true
                        NotificationCenter.default.post(
                            name: Notification.Name("TutorialCalendarMonthExplored"),
                            object: nil
                        )
                    }
                }
            }
        }
        // Tutorial mode: Listen for pinch in month view (also triggers advancement if they pinch first)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CalendarMonthViewPinched"))) { _ in
            NotificationCenter.default.post(name: Notification.Name("WizardCalendarMonthExplored"), object: nil)
            if tutorialMode && tutorialPhase == .calendarMonth && !hasUserPinchedInMonthView {
                hasUserPinchedInMonthView = true

                // Wait 2 seconds after user pinches, then advance
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if tutorialPhase == .calendarMonth && !hasPostedMonthExploredNotification {
                        hasPostedMonthExploredNotification = true
                        NotificationCenter.default.post(
                            name: Notification.Name("TutorialCalendarMonthExplored"),
                            object: nil
                        )
                    }
                }
            }
        }
        // Wizard: evaluate prerequisites when a new step activates (auto-skip steps with missing data)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardEvaluatePrerequisites"))) { notification in
            guard let stepId = notification.userInfo?["stepId"] as? String,
                  stepId == "tap_month_day" || stepId == "tap_task" else { return }
            let taskCount = viewModel.scheduledTasks(for: viewModel.selectedDate).count
            wizardStateManager?.evaluateStepPrerequisites(scheduledTaskCount: taskCount)
        }
    }

    // MARK: - Empty State

    private var hasNoProjectsAtAll: Bool {
        !UserDefaults.standard.bool(forKey: "hasDismissedScheduleWizardPrompt") &&
        dataController.getAllProjects().isEmpty
    }

    private var scheduleEmptyStatePrompt: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Image(systemName: OPSStyle.Icons.schedule)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.wizardAccent)

                    Text("YOUR SCHEDULE")
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.bottom, OPSStyle.Layout.spacing3)

                Text("Projects, tasks, and meetings show up here as you create them. Your crew sees their schedule the moment they open OPS.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineSpacing(4)
                    .padding(.bottom, OPSStyle.Layout.spacing3_5)

                VStack(alignment: .leading, spacing: 0) {
                    scheduleEmptyBullet(index: 1, text: "Create your first project")
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorderSubtle)
                        .frame(height: 1)
                        .padding(.leading, 30)
                    scheduleEmptyBullet(index: 2, text: "Add tasks and assign your crew")
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorderSubtle)
                        .frame(height: 1)
                        .padding(.leading, 30)
                    scheduleEmptyBullet(index: 3, text: "Schedule it on the calendar")
                }
                .padding(.bottom, OPSStyle.Layout.spacing4)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if let wizard = WizardRegistry.contextualWizard(for: "project_lifecycle") {
                        NotificationCenter.default.post(
                            name: Notification.Name("WizardStartRequested"),
                            object: nil,
                            userInfo: ["wizardId": wizard.wizardId]
                        )
                    } else {
                        NotificationCenter.default.post(
                            name: Notification.Name("CreateNewProject"),
                            object: nil
                        )
                    }
                } label: {
                    HStack {
                        Text("CREATE YOUR FIRST PROJECT")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.buttonText)

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.buttonText)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(OPSStyle.Colors.wizardAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .padding(.bottom, OPSStyle.Layout.spacing2_5)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    UserDefaults.standard.set(true, forKey: "hasDismissedScheduleWizardPrompt")
                } label: {
                    Text("I'LL EXPLORE ON MY OWN")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetMin)
                }
            }
            .padding(28)
            .glassSurface()
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            Spacer()
        }
    }

    private func scheduleEmptyBullet(index: Int, text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.wizardAccent)
                .frame(width: 20, alignment: .center)

            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(.vertical, 14)
    }

    // MARK: - Phase-C suggested events banner (item 63144953)

    /// Compact, tactical entry point into the suggested-events review. Rendered
    /// only when `viewModel.suggestedEvents` is non-empty, so an idle Phase C
    /// leaves the schedule untouched. Taps open the review sheet.
    private var suggestedEventsBanner: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Text("// SUGGESTED EVENTS · \(viewModel.suggestedEvents.count)")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .glassSurface()
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showSuggestedEventsSheet = true
        }
    }

    // MARK: - iPhone Calendar Mirror banner (Bug 68123654)

    private var mirrorBanner: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Text("// MIRROR DISABLED · TAP TO ENABLE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Button {
                mirrorBannerDismissCount += 1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassSurface()
        .contentShape(Rectangle())
        .onTapGesture {
            Task { try? await mirrorService.enable() }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

// Extension to set dataController after initialization
extension CalendarViewModel {
    func updateDataController(_ controller: DataController) {
        self.dataController = controller
        // Refresh data
        loadProjectsForDate(selectedDate)
    }
}
