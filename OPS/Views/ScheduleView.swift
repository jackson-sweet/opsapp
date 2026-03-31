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
    @State private var showScopeSheet = false
    @State private var showScheduleBanner = false
    @State private var scheduleBannerText = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header with its own internal padding of 20
                    AppHeader(
                        headerType: .schedule,
                        onFilterTapped: {
                            showFilterSheet = true
                        },
                        onMonthTapped: { viewModel.toggleMonthExpanded() },
                        onScopeToggled: {
                            showScopeSheet = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        },
                        isScopeAll: viewModel.scheduleScope == .all && viewModel.selectedTeamMemberIds.isEmpty,
                        hasActiveFilters: viewModel.hasActiveFilters,
                        filterCount: viewModel.activeFilterCount
                    )
                    .padding(.bottom, 8)
                
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
                        DayCanvasView(viewModel: viewModel)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(OPSStyle.Animation.standard, value: viewModel.isMonthExpanded)
                .padding(.bottom, viewModel.isMonthExpanded ? (wizardActive ? 80 : 0) : 90) // tab bar + wizard bar clearance
                //.frame(maxWidth: 50)
            }
            }
        }
        .trackScreen("Schedule")
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

        // Filter sheet
        .sheet(isPresented: $showFilterSheet) {
            CalendarFilterView(viewModel: viewModel)
                .environmentObject(dataController)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // Team member scope sheet
        .sheet(isPresented: $showScopeSheet) {
            ScheduleTeamScopeSheet(viewModel: viewModel)
                .environmentObject(dataController)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
}

// Extension to set dataController after initialization
extension CalendarViewModel {
    func updateDataController(_ controller: DataController) {
        self.dataController = controller
        // Refresh data
        loadProjectsForDate(selectedDate)
    }
}
