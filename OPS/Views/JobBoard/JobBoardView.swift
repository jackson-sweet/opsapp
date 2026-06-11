//
//  JobBoardView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-09-26.
//

import SwiftUI
import SwiftData

struct JobBoardView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase
    @Environment(\.wizardTriggerService) private var wizardTriggerService
    @Environment(\.wizardStateManager) private var wizardStateManager
    @State private var selectedSection: JobBoardSection = .projects
    @State private var previousSection: JobBoardSection = .projects
    @State private var searchText = ""
    @State private var showingFilters = false
    @State private var showingProjectFilterSheet = false
    @State private var showingTaskFilterSheet = false
    // Drives the project LIST's own self-contained filter sheet, distinct from
    // showingProjectFilterSheet (which drives the Kanban filter sheet at body level).
    @State private var showingProjectListFilterSheet = false
    @State private var activeOnly = false
    @State private var assignedToMe = false
    @State private var prioritizeMode = false
    @State private var selectedProjectStatuses: Set<Status> = []
    @State private var selectedProjectTeamMemberIds: Set<String> = []
    @AppStorage("projectListSortOrder") private var projectSortOptionRaw: String = ProjectSortOption.latestEdited.rawValue

    // Payment review state
    @State private var showPaymentReview: Bool = false
    @State private var overdueProjects: [Project] = []
    @State private var completedProjects: [Project] = []
    @State private var overdueCount: Int = 0

    // Task review state
    @State private var showTaskReview: Bool = false
    @State private var reviewableTasks: [ProjectTask] = []
    @State private var reviewableTaskCount: Int = 0

    // Unscheduled task review state
    @State private var showUnscheduledReview: Bool = false
    @State private var unscheduledTasks: [ProjectTask] = []
    @State private var unscheduledTaskCount: Int = 0

    // Review unlock thresholds
    private static let paymentReviewThreshold = 5
    private static let taskReviewThreshold = 5

    // First-open dialogue keys
    @State private var showPaymentReviewIntro: Bool = false
    @State private var showTaskReviewIntro: Bool = false

    // Preloading state (legacy — client query now filtered at DB level)
    @State private var isPreloadingClients = false
    @State private var hasPreloadedClients = false

    // Tutorial phases that require projects section
    private var shouldShowProjectsList: Bool {
        guard tutorialMode else { return false }
        switch tutorialPhase {
        case .projectListStatusDemo, .projectListSwipe, .closedProjectsScroll:
            return true
        default:
            return false
        }
    }

    // Permission checks
    private var isFieldCrew: Bool {
        return !permissionStore.can("job_board.manage_sections")
    }

    private var isAdmin: Bool {
        return permissionStore.can("job_board.manage_sections")
    }

    private var completedProjectCount: Int {
        dataController.getProjects().filter { $0.status == .completed || $0.status == .closed }.count
    }

    private var completedTaskCount: Int {
        dataController.getAllTasks().filter { $0.status == .completed }.count
    }

    private var projectSortOption: Binding<ProjectSortOption> {
        Binding<ProjectSortOption>(
            get: { ProjectSortOption(rawValue: projectSortOptionRaw) ?? .latestEdited },
            set: { projectSortOptionRaw = $0.rawValue }
        )
    }

    private var availableProjectTeamMembers: [User] {
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        return dataController.getTeamMembers(companyId: companyId)
    }

    private var hasActiveProjectFilters: Bool {
        !selectedProjectStatuses.isEmpty || !selectedProjectTeamMemberIds.isEmpty
    }

    private var isPaymentReviewLocked: Bool {
        completedProjectCount < Self.paymentReviewThreshold
    }

    private var isTaskReviewLocked: Bool {
        completedTaskCount < Self.taskReviewThreshold
    }

    private var sections: [JobBoardSection] {
        visibleSections(for: dataController.currentUser)
    }

    private var slideTransition: AnyTransition {
        let currentIndex = JobBoardSection.allCases.firstIndex(of: selectedSection) ?? 0
        let previousIndex = JobBoardSection.allCases.firstIndex(of: previousSection) ?? 0

        if currentIndex > previousIndex {
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        }
    }

    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection

                sectionSelectorSection

                actionRowSection

                mainContentSection
            }
        }
        .trackScreen("JobBoard")
        .sheet(isPresented: $appState.showingJobBoardSearch) {
            UniversalSearchSheet()
                .environmentObject(dataController)
                .environmentObject(appState)
                .environmentObject(PermissionStore.shared)
        }
        .sheet(isPresented: $showingProjectFilterSheet) {
            ProjectListFilterSheet(
                selectedStatuses: $selectedProjectStatuses,
                selectedTeamMemberIds: $selectedProjectTeamMemberIds,
                sortOption: projectSortOption,
                availableTeamMembers: availableProjectTeamMembers
            )
            .environmentObject(dataController)
            .onDisappear {
                showingFilters = hasActiveProjectFilters
                NotificationCenter.default.post(name: Notification.Name("WizardJobBoardFilterOpened"), object: nil)
            }
        }
        .sheet(isPresented: $showPaymentReview) {
            ProjectPaymentReviewView(
                overdueProjects: overdueProjects,
                completedProjects: completedProjects
            )
            .environmentObject(appState)
            .environmentObject(permissionStore)
            .wizardBannerIfAvailable(stateManager: wizardStateManager)
            .wizardOverlayIfAvailable(stateManager: wizardStateManager)
        }
        .sheet(isPresented: $showTaskReview) {
            TaskCompletionReviewView(tasks: reviewableTasks)
                .environmentObject(appState)
                .environmentObject(permissionStore)
                .wizardBannerIfAvailable(stateManager: wizardStateManager)
                .wizardOverlayIfAvailable(stateManager: wizardStateManager)
        }
        .sheet(isPresented: $showUnscheduledReview) {
            UnscheduledTaskReviewView(tasks: unscheduledTasks)
                .environmentObject(dataController)
                .environmentObject(appState)
                .environmentObject(permissionStore)
        }
        .alert("Payment Review", isPresented: $showPaymentReviewIntro) {
            Button("Got It") {
                computeReviewProjects()
                showPaymentReview = true
            }
        } message: {
            Text("Completed projects with outstanding payments will show up here for review.")
        }
        .alert("Task Review", isPresented: $showTaskReviewIntro) {
            Button("Got It") {
                computeReviewableTasks()
                showTaskReview = true
            }
        } message: {
            Text("Tasks with end dates in the past will show up here so you can complete, reschedule, or cancel them.")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenPaymentReview"))) { _ in
            computeReviewProjects()
            showPaymentReview = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenTaskReview"))) { _ in
            computeReviewableTasks()
            showTaskReview = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenUnscheduledReview"))) { _ in
            computeUnscheduledTasks()
            showUnscheduledReview = true
        }
        .onChange(of: selectedProjectStatuses) { _, _ in
            showingFilters = hasActiveProjectFilters
        }
        .onChange(of: selectedProjectTeamMemberIds) { _, _ in
            showingFilters = hasActiveProjectFilters
        }
    }

    // MARK: - Body Sections

    // App header with payment / task / unscheduled review entry points.
    @ViewBuilder private var headerSection: some View {
        AppHeader(
            headerType: .jobBoard,
            onPaymentReviewTapped: (permissionStore.can("projects.edit") || permissionStore.hasFullAccess("projects.view")) ? {
                if !UserDefaults.standard.bool(forKey: "review_payment_intro_shown") {
                    UserDefaults.standard.set(true, forKey: "review_payment_intro_shown")
                    showPaymentReviewIntro = true
                } else {
                    computeReviewProjects()
                    showPaymentReview = true
                }
            } : nil,
            paymentReviewBadgeCount: overdueCount,
            isPaymentReviewLocked: isPaymentReviewLocked,
            paymentReviewLockedMessage: "Complete \(Self.paymentReviewThreshold) projects to unlock payment review. You've completed \(completedProjectCount) so far.",
            onTaskReviewTapped: {
                // When a wizard is guiding the user to open task review,
                // bypass the first-open intro alert to avoid an unexpected
                // intermediate step that the wizard doesn't account for.
                let wizardActive = wizardStateManager?.isActive == true
                    && wizardStateManager?.currentStep?.id == "open_task_review"
                if !wizardActive && !UserDefaults.standard.bool(forKey: "review_task_intro_shown") {
                    UserDefaults.standard.set(true, forKey: "review_task_intro_shown")
                    showTaskReviewIntro = true
                } else {
                    UserDefaults.standard.set(true, forKey: "review_task_intro_shown")
                    computeReviewableTasks()
                    showTaskReview = true
                }
            },
            taskReviewBadgeCount: reviewableTaskCount,
            isTaskReviewLocked: isTaskReviewLocked,
            taskReviewLockedMessage: "Complete \(Self.taskReviewThreshold) tasks to unlock task review. You've completed \(completedTaskCount) so far.",
            onUnscheduledReviewTapped: permissionStore.can("tasks.edit") ? {
                computeUnscheduledTasks()
                showUnscheduledReview = true
            } : nil,
            unscheduledReviewBadgeCount: permissionStore.can("tasks.edit") ? unscheduledTaskCount : 0
        )
        .padding(.bottom, 8)
    }

    // Section selector — shown whenever the role has more than one section.
    @ViewBuilder private var sectionSelectorSection: some View {
        if sections.count > 1 {
            JobBoardSectionSelector(sections: sections, selectedSection: $selectedSection)
                .onChange(of: selectedSection) { oldValue, newValue in
                    previousSection = oldValue
                    searchText = ""
                }
                .onChange(of: tutorialPhase) { oldPhase, newPhase in
                    if tutorialMode && newPhase == .projectListStatusDemo {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSection = .projects
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .opacity(tutorialMode && tutorialPhase == .dragToAccepted ? 0.4 : 1.0)
                .allowsHitTesting(!(tutorialMode && tutorialPhase == .dragToAccepted))
        }
    }

    // Action row: filter + active toggle + assigned to me + prioritize.
    @ViewBuilder private var actionRowSection: some View {
        if !tutorialMode && (selectedSection == .projects || selectedSection == .myProjects || selectedSection == .tasks || selectedSection == .kanban) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button(action: {
                        switch selectedSection {
                        case .tasks:
                            showingTaskFilterSheet = true
                        case .kanban:
                            showingProjectFilterSheet = true
                        default:
                            showingProjectListFilterSheet = true
                        }
                    }) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                    }
                    .wizardTarget("open_filters")

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) { activeOnly.toggle() }
                    }) {
                        JobBoardFilterPill(title: "ACTIVE ONLY", isOn: activeOnly)
                    }

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) { assignedToMe.toggle() }
                    }) {
                        JobBoardFilterPill(title: "ASSIGNED TO ME", isOn: assignedToMe)
                    }

                    if selectedSection == .projects && permissionStore.can("projects.edit") {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) { prioritizeMode.toggle() }
                        }) {
                            JobBoardFilterPill(title: "PRIORITIZE", isOn: prioritizeMode)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    // Main content with slide transitions.
    // Tutorial mode overrides section when in project list phases.
    @ViewBuilder private var mainContentSection: some View {
        Group {
            if shouldShowProjectsList {
                // Force show projects list during tutorial
                JobBoardProjectListView(
                    searchText: searchText,
                    showingFilters: $showingFilters,
                    showingFilterSheet: $showingProjectListFilterSheet,
                    activeOnly: activeOnly,
                    assignedToMe: assignedToMe
                )
                .padding(.horizontal, 16)
            } else {
                switch selectedSection {
                case .myTasks:
                    JobBoardMyTasksView()
                case .myProjects:
                    JobBoardProjectListView(
                        searchText: searchText,
                        showingFilters: $showingFilters,
                        showingFilterSheet: $showingProjectListFilterSheet,
                        activeOnly: activeOnly,
                        assignedToMe: assignedToMe
                    )
                    .padding(.horizontal, 16)
                case .projects:
                    if prioritizeMode {
                        PriorityQueueView(displayMode: .inline, dataController: dataController)
                            .padding(.horizontal, 16)
                    } else {
                        JobBoardProjectListView(
                            searchText: searchText,
                            showingFilters: $showingFilters,
                            showingFilterSheet: $showingProjectListFilterSheet,
                            activeOnly: activeOnly,
                            assignedToMe: assignedToMe
                        )
                        .padding(.horizontal, 16)
                    }
                case .tasks:
                    JobBoardTasksView(
                        searchText: searchText,
                        showingFilters: $showingFilters,
                        showingFilterSheet: $showingTaskFilterSheet,
                        assignedToMe: assignedToMe
                    )
                    .padding(.horizontal, 16)
                case .kanban:
                    JobBoardKanbanView(
                        activeOnly: activeOnly,
                        assignedToMe: assignedToMe,
                        selectedStatuses: selectedProjectStatuses,
                        selectedTeamMemberIds: selectedProjectTeamMemberIds
                    )
                }
            }
        }
        .id(selectedSection)
        .transition(slideTransition)
        .animation(.accessibleEaseInOut(duration: 0.2), value: selectedSection)
        .onChange(of: selectedSection) { oldValue, newSection in
            previousSection = oldValue
            // Track section changes within Job Board
            let screenName: ScreenName? = {
                switch newSection {
                case .projects, .myProjects: return .jobBoardProjects
                case .tasks, .myTasks:       return .jobBoardTasks
                default: return nil
                }
            }()
            if let screenName = screenName {
                AnalyticsManager.shared.trackScreenView(screenName: screenName, screenClass: "JobBoardView")
            }
        }
        .task {
            // Wizard system: evaluate job board wizard trigger (requires ≥1 project)
            if let wizard = WizardRegistry.contextualWizard(for: "job_board") {
                let projectCount = await MainActor.run { dataController.getProjects().count }
                await MainActor.run {
                    wizardTriggerService?.evaluateTrigger(for: wizard, context: "job_board_tab_visit", projectCount: projectCount)
                }
            }
        }
        .task {
            // Compute overdue count for badge
            computeReviewProjects()
        }
        .task {
            // Compute reviewable task count for badge
            computeReviewableTasks()
        }
        .task {
            // Compute unscheduled/unassigned task count for badge
            computeUnscheduledTasks()
        }
        .onAppear {
            selectedSection = defaultSection(for: dataController.currentUser)
            AnalyticsManager.shared.trackScreenView(screenName: .jobBoard, screenClass: "JobBoardView")
            AnalyticsService.shared.trackScreenView(screenName: "job_board")
        }
        .onDisappear {
            AnalyticsService.shared.endScreenView(screenName: "job_board")
        }
        // Wizard: listen for section-level navigation requests
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardNavigateToSection"))) { notification in
            guard let sectionRaw = notification.userInfo?["section"] as? String,
                  let target = JobBoardSection(rawValue: sectionRaw),
                  sections.contains(target) else { return }
            withAnimation(.accessibleEaseInOut(duration: 0.2)) {
                selectedSection = target
            }
        }
    }

    // MARK: - Payment Review

    private func computeReviewProjects() {
        let allProjects = dataController.getProjects()
        let threshold: Int
        if let companyId = dataController.currentUser?.companyId,
           let company = dataController.getCompany(id: companyId) {
            threshold = company.overdueReviewThresholdDays
        } else {
            threshold = 14
        }
        let overdue = OverdueProjectDetector.overdueProjects(from: allProjects, thresholdDays: threshold)
        overdueCount = overdue.count
        overdueProjects = overdue
        completedProjects = allProjects.filter { $0.status == .completed && $0.deletedAt == nil }
    }

    // MARK: - Task Review

    private func computeReviewableTasks() {
        let calendar = Calendar.current
        let endOfToday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())

        let allTasks: [ProjectTask]
        if PermissionStore.shared.hasFullAccess("tasks.view") {
            allTasks = dataController.getAllTasks()
        } else if let userId = dataController.currentUser?.id {
            allTasks = dataController.getAllTasks().filter { task in
                task.getTeamMemberIds().contains(userId)
            }
        } else {
            allTasks = []
        }

        reviewableTasks = allTasks.filter { task in
            guard task.status == .active, task.deletedAt == nil else { return false }
            // Prefer scheduled completion (endDate), fall back to startDate if unavailable
            guard let scheduledDate = task.endDate ?? task.startDate else { return false }
            return scheduledDate < endOfToday
        }
        .sorted {
            let a = $0.endDate ?? $0.startDate ?? .distantPast
            let b = $1.endDate ?? $1.startDate ?? .distantPast
            return a < b
        }

        reviewableTaskCount = reviewableTasks.count
    }

    // MARK: - Unscheduled Task Review

    /// The section selector row (shown when the role has more than one section).
    /// Extracted from `body` to keep the main VStack within the type-checker budget.
    @ViewBuilder
    private var sectionSelector: some View {
        if sections.count > 1 {
            JobBoardSectionSelector(sections: sections, selectedSection: $selectedSection)
                .onChange(of: selectedSection) { oldValue, newValue in
                    previousSection = oldValue
                    searchText = ""
                }
                .onChange(of: tutorialPhase) { oldPhase, newPhase in
                    if tutorialMode && newPhase == .projectListStatusDemo {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSection = .projects
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .opacity(tutorialMode && tutorialPhase == .dragToAccepted ? 0.4 : 1.0)
                .allowsHitTesting(!(tutorialMode && tutorialPhase == .dragToAccepted))
        }
    }

    /// The section content area (per-section list/board) plus its lifecycle hooks
    /// (slide transition, screen-view analytics, badge-count tasks, wizard
    /// navigation). Extracted from `body` so its switch and chain of modifiers are
    /// type-checked in isolation — the main VStack was exceeding the Swift
    /// type-checker's budget as one expression.
    private var mainContent: some View {
        Group {
            if shouldShowProjectsList {
                // Force show projects list during tutorial
                projectList
            } else {
                switch selectedSection {
                case .myTasks:
                    JobBoardMyTasksView()
                case .myProjects:
                    projectList
                case .projects:
                    if prioritizeMode {
                        PriorityQueueView(displayMode: .inline, dataController: dataController)
                            .padding(.horizontal, 16)
                    } else {
                        projectList
                    }
                case .tasks:
                    JobBoardTasksView(
                        searchText: searchText,
                        showingFilters: $showingFilters,
                        showingFilterSheet: $showingTaskFilterSheet,
                        assignedToMe: assignedToMe
                    )
                    .padding(.horizontal, 16)
                case .kanban:
                    // JobBoardKanbanView self-derives its status buckets and only
                    // accepts `assignedToMe` now; the prior extra args were a stale
                    // call site (see projectList note).
                    JobBoardKanbanView(assignedToMe: assignedToMe)
                }
            }
        }
        .id(selectedSection)
        .transition(slideTransition)
        .animation(.accessibleEaseInOut(duration: 0.2), value: selectedSection)
        .onChange(of: selectedSection) { oldValue, newSection in
            previousSection = oldValue
            // Track section changes within Job Board
            let screenName: ScreenName? = {
                switch newSection {
                case .projects, .myProjects: return .jobBoardProjects
                case .tasks, .myTasks:       return .jobBoardTasks
                default: return nil
                }
            }()
            if let screenName = screenName {
                AnalyticsManager.shared.trackScreenView(screenName: screenName, screenClass: "JobBoardView")
            }
        }
        .task {
            // Wizard system: evaluate job board wizard trigger (requires ≥1 project)
            if let wizard = WizardRegistry.contextualWizard(for: "job_board") {
                let projectCount = await MainActor.run { dataController.getProjects().count }
                await MainActor.run {
                    wizardTriggerService?.evaluateTrigger(for: wizard, context: "job_board_tab_visit", projectCount: projectCount)
                }
            }
        }
        .task {
            // Compute overdue count for badge
            computeReviewProjects()
        }
        .task {
            // Compute reviewable task count for badge
            computeReviewableTasks()
        }
        .task {
            // Compute unscheduled/unassigned task count for badge
            computeUnscheduledTasks()
        }
        .onAppear {
            selectedSection = defaultSection(for: dataController.currentUser)
            AnalyticsManager.shared.trackScreenView(screenName: .jobBoard, screenClass: "JobBoardView")
            AnalyticsService.shared.trackScreenView(screenName: "job_board")
        }
        .onDisappear {
            AnalyticsService.shared.endScreenView(screenName: "job_board")
        }
        // Wizard: listen for section-level navigation requests
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardNavigateToSection"))) { notification in
            guard let sectionRaw = notification.userInfo?["section"] as? String,
                  let target = JobBoardSection(rawValue: sectionRaw),
                  sections.contains(target) else { return }
            withAnimation(.accessibleEaseInOut(duration: 0.2)) {
                selectedSection = target
            }
        }
    }

    /// The project list (shared by the tutorial-forced list, .myProjects, and
    /// .projects sections). Extracted to a single computed so its seven-argument
    /// initializer is type-checked once in isolation — three inline copies were a
    /// large part of what pushed `body` past the Swift type-checker's budget — and
    /// to DRY up three identical call sites.
    private var projectList: some View {
        // NOTE: JobBoardProjectListView was refactored (commit 9b7742ff and
        // siblings) to self-manage status/team filters (@State) and sort order
        // (@AppStorage) — its initializer now takes only the binding pair below.
        // JobBoardView's call sites were not updated then; recompiling this file
        // surfaced the mismatch. Matched to the current initializer.
        JobBoardProjectListView(
            searchText: searchText,
            showingFilters: $showingFilters,
            showingFilterSheet: $showingProjectFilterSheet,
            activeOnly: activeOnly,
            assignedToMe: assignedToMe
        )
        .padding(.horizontal, 16)
    }

    /// The job-board header (review entry points + badges). Extracted from `body`
    /// so its 11-argument initializer and inline closures are type-checked in
    /// isolation, keeping the main VStack within the Swift type-checker's budget.
    private var jobBoardHeader: some View {
        AppHeader(
            headerType: .jobBoard,
            onPaymentReviewTapped: (permissionStore.can("projects.edit") || permissionStore.hasFullAccess("projects.view")) ? {
                if !UserDefaults.standard.bool(forKey: "review_payment_intro_shown") {
                    UserDefaults.standard.set(true, forKey: "review_payment_intro_shown")
                    showPaymentReviewIntro = true
                } else {
                    computeReviewProjects()
                    showPaymentReview = true
                }
            } : nil,
            paymentReviewBadgeCount: overdueCount,
            isPaymentReviewLocked: isPaymentReviewLocked,
            paymentReviewLockedMessage: "Complete \(Self.paymentReviewThreshold) projects to unlock payment review. You've completed \(completedProjectCount) so far.",
            onTaskReviewTapped: {
                // When a wizard is guiding the user to open task review,
                // bypass the first-open intro alert to avoid an unexpected
                // intermediate step that the wizard doesn't account for.
                let wizardActive = wizardStateManager?.isActive == true
                    && wizardStateManager?.currentStep?.id == "open_task_review"
                if !wizardActive && !UserDefaults.standard.bool(forKey: "review_task_intro_shown") {
                    UserDefaults.standard.set(true, forKey: "review_task_intro_shown")
                    showTaskReviewIntro = true
                } else {
                    UserDefaults.standard.set(true, forKey: "review_task_intro_shown")
                    computeReviewableTasks()
                    showTaskReview = true
                }
            },
            taskReviewBadgeCount: reviewableTaskCount,
            isTaskReviewLocked: isTaskReviewLocked,
            taskReviewLockedMessage: "Complete \(Self.taskReviewThreshold) tasks to unlock task review. You've completed \(completedTaskCount) so far.",
            onUnscheduledReviewTapped: unscheduledReviewTapped,
            unscheduledReviewBadgeCount: unscheduledReviewBadge
        )
        .padding(.bottom, 8)
    }

    /// A pill-style filter toggle (ACTIVE ONLY / ASSIGNED TO ME / PRIORITIZE).
    /// Extracted from the filter row so its ternary-heavy styling doesn't push the
    /// header view-builder past the Swift type-checker's budget — and to DRY up
    /// three byte-identical button bodies.
    @ViewBuilder
    private func filterChip(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(isActive ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(isActive ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBackgroundDark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(isActive ? Color.clear : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
    }

    /// The horizontal filter/sort action row (filter sheet + ACTIVE ONLY /
    /// ASSIGNED TO ME / PRIORITIZE toggles). Extracted from `body` so the VStack
    /// stays within the Swift type-checker's budget.
    @ViewBuilder
    private var filterControls: some View {
        if !tutorialMode && (selectedSection == .projects || selectedSection == .myProjects || selectedSection == .tasks || selectedSection == .kanban) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button(action: {
                        if selectedSection == .tasks {
                            showingTaskFilterSheet = true
                        } else {
                            showingProjectFilterSheet = true
                        }
                    }) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                    }
                    .wizardTarget("open_filters")

                    filterChip("ACTIVE ONLY", isActive: activeOnly) {
                        withAnimation(.easeInOut(duration: 0.2)) { activeOnly.toggle() }
                    }

                    filterChip("ASSIGNED TO ME", isActive: assignedToMe) {
                        withAnimation(.easeInOut(duration: 0.2)) { assignedToMe.toggle() }
                    }

                    if selectedSection == .projects && permissionStore.can("projects.edit") {
                        filterChip("PRIORITIZE", isActive: prioritizeMode) {
                            withAnimation(.easeInOut(duration: 0.2)) { prioritizeMode.toggle() }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    /// Tap handler for the unscheduled-review entry. Nil when the user holds no
    /// calendar.edit grant (scheduling is gated on calendar.edit), which hides the
    /// entry — Crew / Unassigned can't schedule. Extracted from the header
    /// view-builder so that large expression stays within the type-checker budget.
    private var unscheduledReviewTapped: (() -> Void)? {
        guard permissionStore.canEditAnySchedule else { return nil }
        return {
            computeUnscheduledTasks()
            showUnscheduledReview = true
        }
    }

    /// Badge count for the unscheduled-review entry — zero without a calendar.edit grant.
    private var unscheduledReviewBadge: Int {
        permissionStore.canEditAnySchedule ? unscheduledTaskCount : 0
    }

    private func computeUnscheduledTasks() {
        let allTasks: [ProjectTask]
        if PermissionStore.shared.hasFullAccess("tasks.view") {
            allTasks = dataController.getAllTasks()
        } else if let userId = dataController.currentUser?.id {
            allTasks = dataController.getAllTasks().filter { task in
                task.getTeamMemberIds().contains(userId)
            }
        } else {
            allTasks = []
        }

        unscheduledTasks = allTasks.filter { task in
            // Only surface schedulable work for ACTIVE projects. A project that
            // hasn't been accepted yet (`.rfq`/`.estimated`) or is finished
            // (`.completed`/`.closed`/`.archived`) must not feed the review/
            // auto-schedule flow — mirrors `isJobBoardTaskListVisible`.
            task.status == .active
                && task.deletedAt == nil
                && (task.project?.status.isActive ?? false)
                && (task.startDate == nil || task.getTeamMemberIds().isEmpty)
        }
        .sorted { ($0.project?.title ?? "") < ($1.project?.title ?? "") }

        unscheduledTaskCount = unscheduledTasks.count
    }
}

// MARK: - Floating Action Item
struct FloatingActionItem: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                
                Text(label.uppercased())
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 48, height: 48)
                    .background(.clear)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(OPSStyle.Colors.secondaryText, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                
            }
           
            
        }
    }
}

// MARK: - Section Types
enum JobBoardSection: String, CaseIterable {
    // Field crew sections
    case myTasks    = "MY TASKS"
    case myProjects = "MY PROJECTS"
    // Office / Admin sections
    case projects   = "PROJECTS"
    case tasks      = "TASKS"
    case kanban     = "BOARD"

    var icon: String {
        switch self {
        case .myTasks:    return OPSStyle.Icons.task
        case .myProjects: return OPSStyle.Icons.project
        case .projects:   return OPSStyle.Icons.project
        case .tasks:      return OPSStyle.Icons.task
        case .kanban:     return "chart.bar.fill"
        }
    }
}

/// Returns the ordered sections visible based on permissions
func visibleSections(for user: User?) -> [JobBoardSection] {
    guard user != nil else { return [.projects] }
    let store = PermissionStore.shared

    if !store.can("job_board.manage_sections") {
        // Limited access (field crew equivalent)
        return [.myTasks, .myProjects]
    }

    return [.projects, .tasks, .kanban]
}

/// Returns the default landing section based on permissions
func defaultSection(for user: User?) -> JobBoardSection {
    guard user != nil else { return .projects }
    // Users who can see the kanban board land on it by default; everyone else keeps My Tasks.
    return PermissionStore.shared.can("job_board.manage_sections") ? .kanban : .myTasks
}

// MARK: - Filter Pill
/// A single pill-style toggle label used in the Job Board action row.
/// The on/off ternaries are hoisted into typed locals so the modifier chain
/// type-checks cheaply — inlining them in `JobBoardView.body` was a primary
/// contributor to the "unable to type-check this expression" cold-build failure.
private struct JobBoardFilterPill: View {
    let title: String
    let isOn: Bool

    var body: some View {
        let fg: Color = isOn ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.secondaryText
        let bg: Color = isOn ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBackgroundDark
        let stroke: Color = isOn ? Color.clear : OPSStyle.Colors.cardBorder
        Text(title)
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(stroke, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }
}

// MARK: - Section Selector
struct JobBoardSectionSelector: View {
    let sections: [JobBoardSection]
    @Binding var selectedSection: JobBoardSection
    @Environment(\.tutorialMode) private var tutorialMode

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(sections, id: \.self) { section in
                Button(action: {
                    guard !tutorialMode else { return }
                    withAnimation(.accessibleEaseInOut(duration: 0.2)) {
                        selectedSection = section
                    }
                }) {
                    Text(section.rawValue)
                        .font(OPSStyle.Typography.cardBody)
                        .foregroundColor(
                            selectedSection == section
                                ? OPSStyle.Colors.cardBackgroundDark
                                : OPSStyle.Colors.secondaryText
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .fill(selectedSection == section
                                      ? OPSStyle.Colors.primaryText
                                      : .clear)
                        )
                }
            }
        }
    }
}

// MARK: - Clients Preview
struct JobBoardClientsPreview: View {
    @EnvironmentObject private var dataController: DataController
    @State private var showingCreateClient = false

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            HStack {
                Text("CLIENT MANAGEMENT")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                Text("VIEW ALL")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                Image(systemName: "chevron.right")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }

            let clients = dataController.getAllClients(for: dataController.currentUser?.companyId ?? "")
            if clients.isEmpty {
                JobBoardEmptyState(
                    icon: OPSStyle.Icons.crew,
                    title: "No Clients Yet",
                    subtitle: "Add your first client to get started"
                )
            } else {
                // Show preview of first 3 clients
                ForEach(clients.prefix(3)) { client in
                    ClientRowView(client: client)
                }

                if clients.count > 3 {
                    Text("+ \(clients.count - 3) more clients")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.top, OPSStyle.Layout.spacing2)
                }
            }
        }
    }
}

// MARK: - Projects Preview
struct JobBoardProjectsPreview: View {
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            HStack {
                Text("PROJECT MANAGEMENT")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                Text("VIEW ALL")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                Image(systemName: "chevron.right")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            
            let projects = dataController.getAllProjects()
            if projects.isEmpty {
                JobBoardEmptyState(
                    icon: OPSStyle.Icons.project,
                    title: "No Projects Yet",
                    subtitle: "Create your first project to get started"
                )
            } else {
                ForEach(projects.sorted(by: { $0.startDate ?? Date() > $1.startDate ?? Date() })) { project in
                    ProjectRowView(project: project)
                }
            }
        }
    }
}

struct JobBoardTasksView: View {
    let searchText: String
    @Binding var showingFilters: Bool
    @Binding var showingFilterSheet: Bool
    @EnvironmentObject private var dataController: DataController
    @State private var selectedStatuses: Set<TaskStatus> = []
    @State private var selectedTaskTypeIds: Set<String> = []
    @State private var selectedTeamMemberIds: Set<String> = []
    // Persisted task sort preference, defaulting to .latestEdited (bug ec9f5856)
    // so freshly touched tasks float to the top — mirrors the project list
    // default and matches user mental model. Survives relaunches via
    // @AppStorage. Falls back to .latestEdited if the stored raw is unknown
    // (handles future enum renames).
    @AppStorage("taskListSortOrder") private var sortOptionRaw: String = TaskSortOption.latestEdited.rawValue
    private var sortOption: Binding<TaskSortOption> {
        Binding<TaskSortOption>(
            get: { TaskSortOption(rawValue: sortOptionRaw) ?? .latestEdited },
            set: { sortOptionRaw = $0.rawValue }
        )
    }
    @State private var selectedTaskType: TaskType?
    @State private var showingTaskTypeDetails = false
    @State private var showingCompletedSheet = false
    @State private var showingCancelledSheet = false
    var assignedToMe: Bool = false

    private var allTasks: [ProjectTask] {
        let projects = dataController.getAllProjects()
        return JobBoardTaskFiltering.visibleTasks(from: projects)
    }

    private var availableTaskTypes: [TaskType] {
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        return dataController.getAllTaskTypes(for: companyId)
    }

    private var availableTeamMembers: [User] {
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        return dataController.getTeamMembers(companyId: companyId)
    }

    private var filteredTasks: [ProjectTask] {
        // PERFORMANCE FIX: Cache lookups to avoid O(n*m) complexity
        let allProjects = dataController.getAllProjects()
        let projectsById = Dictionary(uniqueKeysWithValues: allProjects.map { ($0.id, $0) })

        guard let companyId = dataController.currentUser?.companyId else { return [] }
        let allTaskTypes = dataController.getAllTaskTypes(for: companyId)
        let taskTypesById = Dictionary(uniqueKeysWithValues: allTaskTypes.map { ($0.id, $0) })

        var filtered = allTasks

        // Task-only scheduling migration: eventType filter removed (all projects use tasks)
        filtered = filtered.filter { task in
            projectsById[task.projectId] != nil
        }

        // Quick filter: assigned to me
        if assignedToMe, let userId = dataController.currentUser?.id {
            filtered = filtered.filter { task in
                task.getTeamMemberIds().contains(userId)
            }
        }

        // Filter by status
        if !selectedStatuses.isEmpty {
            filtered = filtered.filter { selectedStatuses.contains($0.status) }
        }

        // Filter by task type
        if !selectedTaskTypeIds.isEmpty {
            filtered = filtered.filter { selectedTaskTypeIds.contains($0.taskTypeId) }
        }

        // Filter by team members
        if !selectedTeamMemberIds.isEmpty {
            filtered = filtered.filter { task in
                let taskTeamMemberIds = Set(task.getTeamMemberIds())
                return !taskTeamMemberIds.intersection(selectedTeamMemberIds).isEmpty
            }
        }

        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { task in
                let taskTypeName = taskTypesById[task.taskTypeId]?.display ?? ""
                let projectName = projectsById[task.projectId]?.title ?? ""

                return taskTypeName.localizedCaseInsensitiveContains(searchText) ||
                       projectName.localizedCaseInsensitiveContains(searchText) ||
                       (task.taskNotes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // Sort
        switch sortOption.wrappedValue {
        case .latestEdited:
            // Mirror the project-list "latestEdited" rule: most recent of
            // lastSyncedAt or scheduledDate. lastSyncedAt is updated on every
            // outbound sync, so it tracks "user just touched this".
            return filtered.sorted(by: { t1, t2 in
                let s1 = t1.lastSyncedAt ?? t1.scheduledDate ?? Date.distantPast
                let s2 = t2.lastSyncedAt ?? t2.scheduledDate ?? Date.distantPast
                return s1 > s2
            })
        case .earliestEdited:
            return filtered.sorted(by: { t1, t2 in
                let s1 = t1.lastSyncedAt ?? t1.scheduledDate ?? Date.distantFuture
                let s2 = t2.lastSyncedAt ?? t2.scheduledDate ?? Date.distantFuture
                return s1 < s2
            })
        case .scheduledDateDescending:
            return filtered.sorted(by: { ($0.scheduledDate ?? Date.distantPast) > ($1.scheduledDate ?? Date.distantPast) })
        case .scheduledDateAscending:
            return filtered.sorted(by: { ($0.scheduledDate ?? Date.distantPast) < ($1.scheduledDate ?? Date.distantPast) })
        case .statusAscending:
            return filtered.sorted(by: { $0.status.sortOrder < $1.status.sortOrder })
        case .statusDescending:
            return filtered.sorted(by: { $0.status.sortOrder > $1.status.sortOrder })
        }
    }

    private var activeTasks: [ProjectTask] {
        filteredTasks.filter { $0.status != .cancelled && $0.status != .completed }
    }

    private var completedTasks: [ProjectTask] {
        filteredTasks.filter { $0.status == .completed }
    }

    private var cancelledTasks: [ProjectTask] {
        filteredTasks.filter { $0.status == .cancelled }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingFilters && hasActiveFilters {
                activeFilterBadges
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }

            if allTasks.isEmpty {
                JobBoardEmptyState(
                    icon: OPSStyle.Icons.task,
                    title: "No Tasks Yet",
                    subtitle: "Create tasks from projects to get started"
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(activeTasks) { task in
                            UniversalJobBoardCard(cardType: .task(task))
                                .environmentObject(dataController)
                                .environment(\.modelContext, dataController.modelContext!)
                        }

                        // Completed and Cancelled section buttons
                        if !completedTasks.isEmpty || !cancelledTasks.isEmpty {
                            HStack(spacing: 12) {
                                if !completedTasks.isEmpty {
                                    SectionButton(
                                        title: "COMPLETED",
                                        count: completedTasks.count,
                                        color: TaskStatus.completed.color
                                    ) {
                                        showingCompletedSheet = true
                                    }
                                }

                                if !cancelledTasks.isEmpty {
                                    SectionButton(
                                        title: "CANCELLED",
                                        count: cancelledTasks.count,
                                        color: TaskStatus.cancelled.color
                                    ) {
                                        showingCancelledSheet = true
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
            }
        }
        .sheet(isPresented: $showingTaskTypeDetails) {
            if let taskType = selectedTaskType {
                TaskTypeDetailSheet(taskType: taskType)
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            TaskListFilterSheet(
                selectedStatuses: $selectedStatuses,
                selectedTaskTypeIds: $selectedTaskTypeIds,
                selectedTeamMemberIds: $selectedTeamMemberIds,
                sortOption: sortOption,
                availableTaskTypes: availableTaskTypes,
                availableTeamMembers: availableTeamMembers
            )
            .environmentObject(dataController)
            .onDisappear {
                updateFilterVisibility()
            }
        }
        .sheet(isPresented: $showingCompletedSheet) {
            TaskListSheet(
                title: "Completed Tasks",
                tasks: completedTasks,
                dataController: dataController
            )
        }
        .sheet(isPresented: $showingCancelledSheet) {
            TaskListSheet(
                title: "Cancelled Tasks",
                tasks: cancelledTasks,
                dataController: dataController
            )
        }
        .onChange(of: selectedStatuses) { _, _ in
            updateFilterVisibility()
        }
        .onChange(of: selectedTaskTypeIds) { _, _ in
            updateFilterVisibility()
        }
        .onChange(of: selectedTeamMemberIds) { _, _ in
            updateFilterVisibility()
        }
    }

    private var filterButton: some View {
        Button(action: {
            showingFilterSheet = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                Text("FILTER & SORT")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                if hasActiveFilters {
                    let filterCount = selectedStatuses.count + selectedTaskTypeIds.count + selectedTeamMemberIds.count
                    Text("\(filterCount)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Circle()
                                .fill(OPSStyle.Colors.primaryAccent)
                        )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(hasActiveFilters ? OPSStyle.Colors.primaryAccent.opacity(0.3) : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            )
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showingFilterSheet) {
            TaskListFilterSheet(
                selectedStatuses: $selectedStatuses,
                selectedTaskTypeIds: $selectedTaskTypeIds,
                selectedTeamMemberIds: $selectedTeamMemberIds,
                sortOption: sortOption,
                availableTaskTypes: availableTaskTypes,
                availableTeamMembers: availableTeamMembers
            )
            .environmentObject(dataController)
        }
    }

    private var activeFilterBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedStatuses), id: \.self) { status in
                    TaskFilterBadge(
                        text: status.displayName,
                        color: statusColor(for: status),
                        onRemove: {
                            selectedStatuses.remove(status)
                        }
                    )
                }

                ForEach(Array(selectedTaskTypeIds), id: \.self) { taskTypeId in
                    if let taskType = availableTaskTypes.first(where: { $0.id == taskTypeId }) {
                        TaskFilterBadge(
                            text: taskType.display,
                            color: Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent,
                            onRemove: {
                                selectedTaskTypeIds.remove(taskTypeId)
                            }
                        )
                    }
                }

                ForEach(Array(selectedTeamMemberIds), id: \.self) { memberId in
                    if let member = availableTeamMembers.first(where: { $0.id == memberId }) {
                        TaskFilterBadge(
                            text: "\(member.firstName) \(member.lastName)",
                            color: OPSStyle.Colors.primaryAccent,
                            onRemove: {
                                selectedTeamMemberIds.remove(memberId)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var hasActiveFilters: Bool {
        !selectedStatuses.isEmpty || !selectedTaskTypeIds.isEmpty || !selectedTeamMemberIds.isEmpty || assignedToMe
    }

    private func updateFilterVisibility() {
        if hasActiveFilters {
            showingFilters = true
        } else {
            showingFilters = false
        }
    }

    private func statusColor(for status: TaskStatus) -> Color {
        return status.color
    }
}

// MARK: - Job Board Empty State View
struct JobBoardEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text(title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text(subtitle)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing5)
    }
}

// MARK: - Row Views
struct ClientRowView: View {
    let client: Client
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(client.name)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                if let email = client.email {
                    Text(email)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

struct ProjectRowView: View {
    let project: Project
    
    var body: some View {
        HStack {
            Circle()
                .fill(project.status.color)
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(project.effectiveClientName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

struct TaskTypeRowView: View {
    let taskType: TaskType
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: taskType.icon ?? "checklist")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(taskType.display)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(taskType.isDefault ? "Default" : "Custom")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Create Menu
struct JobBoardCreateMenu: View {
    let selectedSection: JobBoardSection
    @Environment(\.dismiss) private var dismiss
    @State private var showingCreateClient = false
    @State private var showingCreateProject = false

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: OPSStyle.Layout.spacing3) {
                    Text("CREATE NEW")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)

                    VStack(spacing: 0) {
                        CreateMenuItem(
                            icon: OPSStyle.Icons.addContact,
                            title: "New Client",
                            action: {
                                showingCreateClient = true
                            }
                        )

                        Divider()
                            .background(OPSStyle.Colors.secondaryText.opacity(0.2))

                        CreateMenuItem(
                            icon: OPSStyle.Icons.addProject,
                            title: "New Project",
                            action: {
                                showingCreateProject = true
                            }
                        )

                        Divider()
                            .background(OPSStyle.Colors.secondaryText.opacity(0.2))

                        CreateMenuItem(
                            icon: OPSStyle.Icons.task,
                            title: "New Task Type",
                            action: {
                                // TODO: Navigate to create task type
                                dismiss()
                            }
                        )
                    }
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    Spacer()
                }
                .padding(.top, OPSStyle.Layout.spacing3)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .sheet(isPresented: $showingCreateClient) {
            ClientSheet(mode: .create) { _ in
                dismiss()
            }
        }
        .sheet(isPresented: $showingCreateProject) {
            // TODO: Add ProjectFormSheet when implemented
            Text("Project creation coming soon")
                .navigationTitle("NEW PROJECT")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct CreateMenuItem: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: 28)

                Text(title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(OPSStyle.Layout.spacing3)
            .contentShape(Rectangle())
        }
    }
}

struct TaskFilterBadge: View {
    let text: String
    let color: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 3, height: 12)

            Text(text.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: 20, height: 20)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: OPSStyle.Layout.Border.standard)
                )
        )
    }
}

// MARK: - Task List Sheet
/// Sheet displaying a list of tasks (used for Completed/Cancelled)
struct TaskListSheet: View {
    let title: String
    let tasks: [ProjectTask]
    let dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filteredTasks: [ProjectTask] {
        if searchText.isEmpty {
            return tasks
        }
        return tasks.filter { task in
            task.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            (task.taskNotes?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (task.project?.title.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (task.project?.effectiveClientName.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 12) {
                        Image(systemName: OPSStyle.Icons.search)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))

                        TextField("Search tasks...", text: $searchText)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .autocorrectionDisabled()

                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    if filteredTasks.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: OPSStyle.Icons.task)
                                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(searchText.isEmpty ? "No tasks" : "No matching tasks")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredTasks) { task in
                                    UniversalJobBoardCard(cardType: .task(task), disableSwipe: true)
                                        .environmentObject(dataController)
                                        .environment(\.modelContext, dataController.modelContext!)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title.uppercased())
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

#Preview {
    JobBoardView()
        .environmentObject(DataController())
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
