//
//  CalendarViewModel.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//


// CalendarViewModel.swift
import Foundation
import SwiftUI
import SwiftData
import Combine

class CalendarViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedDate: Date = Date()
    @Published var viewMode: CalendarViewMode = .week
    @Published var visibleMonth: Date = Date() // Track visible month in month grid view
    @Published var projectIdsForSelectedDate: [String] = []  // Store IDs to avoid invalidation
    @Published var scheduledTaskIdsForSelectedDate: [String] = []  // Store IDs to avoid invalidation
    @Published var userEventsForCurrentPeriod: [CalendarUserEvent] = []
    @Published var isMonthExpanded: Bool = false

    // Computed properties to get fresh models
    var projectsForSelectedDate: [Project] {
        guard let dataController = dataController else { return [] }
        return projectIdsForSelectedDate.compactMap { dataController.getProject(id: $0) }
    }

    var scheduledTasksForSelectedDate: [ProjectTask] {
        guard let dataController = dataController else { return [] }
        return scheduledTaskIdsForSelectedDate.compactMap { dataController.getTask(id: $0) }
    }
    @Published var isLoading = false
    @Published var userInitiatedDateSelection = false
    @Published var selectedTeamMemberId: String? = nil  // Single selection for backward compatibility
    @Published var availableTeamMembers: [TeamMember] = []
    
    // Schedule scope (ALL / MINE / specific member)
    @Published var scheduleScope: ScheduleScope = .all

    // New comprehensive filter properties
    @Published var selectedTeamMemberIds: Set<String> = []
    @Published var selectedTaskTypeIds: Set<String> = []
    @Published var selectedClientIds: Set<String> = []
    @Published var selectedStatuses: Set<Status> = []

    /// Shared scroll anchor for day pages — keeps cards aligned across day swipes.
    /// Uses slot-based IDs ("slot-0", "slot-1", ...) so all pages share the same ID space.
    @Published var dayScrollAnchor: String? = nil

    // MARK: - Private Properties
    var dataController: DataController?

    // MARK: - Enums
    enum CalendarViewMode {
        case week
        case month
    }

    enum ScheduleScope: Equatable {
        case all
        case mine
        case member(String)  // team member ID
    }
    
    // MARK: - Initialization
    init() {
        // Initialize with today's date
        selectedDate = Date()
    }
    
    // MARK: - Public Methods
    func setDataController(_ controller: DataController) {
        self.dataController = controller
        loadTeamMembersIfNeeded()
        loadProjectsForDate(selectedDate)
        loadUserEvents()
    }

    /// Force reload of calendar data (called after scheduling changes)
    func reloadCalendarData() {
        // Clear caches first to force fresh data
        clearProjectCountCache()
        loadProjectsForDate(selectedDate)
    }
    
    // Check if current user should see team member filter
    var shouldShowTeamMemberFilter: Bool {
        guard dataController != nil else { return false }
        return PermissionStore.shared.can("calendar.view", requiredScope: "all")
    }
    
    // Load team members for filtering
    private func loadTeamMembersIfNeeded() {
        guard shouldShowTeamMemberFilter,
              let dataController = dataController,
              let companyId = dataController.currentUser?.companyId,
              let company = dataController.getCompany(id: companyId) else {
            return
        }
        
        let users = dataController.getTeamMembers(companyId: companyId)
        availableTeamMembers = users.map { TeamMember.fromUser($0) }.sorted { $0.fullName < $1.fullName }
    }
    
    // Used for both programmatic and user-initiated date selection
    func selectDate(_ date: Date, userInitiated: Bool = false) {
        let calendar = Calendar.current
        let oldMonth = calendar.component(.month, from: selectedDate)
        let newMonth = calendar.component(.month, from: date)

        // If month changed, clear the cache
        if oldMonth != newMonth {
            clearProjectCountCache()
        }

        // Track if this was a user-initiated selection (tapping a day)
        // or a programmatic selection (changing months, initializing)
        // We need to do this on the main thread since it's a @Published property
        DispatchQueue.main.async {
            self.userInitiatedDateSelection = userInitiated

        }

        // Update date immediately for instant UI feedback
        selectedDate = date

        // Load project data for the selected date
        // This happens synchronously but only queries for ONE date
        loadProjectsForDate(date)

        // In month view, ensure visible month is synchronized with selected date
        if viewMode == .month {
            let calendar = Calendar.current
            if let monthStart = calendar.dateInterval(of: .month, for: date)?.start {
                if !calendar.isDate(visibleMonth, equalTo: monthStart, toGranularity: .month) {
                    visibleMonth = monthStart
                }
            }
        }
    }
    
    func toggleViewMode() {
        userInitiatedDateSelection = false
        viewMode = viewMode == .week ? .month : .week
    }

    /// Expand/collapse month grid with animation
    func toggleMonthExpanded() {
        withAnimation(.accessibleEaseInOut(duration: 0.35)) {
            isMonthExpanded.toggle()
            viewMode = isMonthExpanded ? .month : .week
        }
    }

    // Navigation methods for months and weeks
    func navigateNextPeriod() {
        let calendar = Calendar.current
        
        userInitiatedDateSelection = false
        
        switch viewMode {
        case .week:
            // Move forward 7 days
            if let newDate = calendar.date(byAdding: .day, value: 7, to: selectedDate) {
                // Use userInitiated: false for programmatic navigation
                selectDate(newDate, userInitiated: false)
            }
        case .month:
            // Move forward one month
            if let newDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) {
                // Use userInitiated: false for programmatic navigation
                selectDate(newDate, userInitiated: false)
            }
        }
    }
    
    func navigatePreviousPeriod() {
        let calendar = Calendar.current
        
        userInitiatedDateSelection = false
        
        switch viewMode {
        case .week:
            // Move backward 7 days
            if let newDate = calendar.date(byAdding: .day, value: -7, to: selectedDate) {
                // Use userInitiated: false for programmatic navigation
                selectDate(newDate, userInitiated: false)
            }
        case .month:
            // Move backward one month
            if let newDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) {
                // Use userInitiated: false for programmatic navigation
                selectDate(newDate, userInitiated: false)
            }
        }
    }
    
    func getVisibleDays() -> [Date] {
        switch viewMode {
        case .week:
            return getWeekDays()
        case .month:
            return getMonthDays()
        }
    }
    
    private var projectCountCache: [String: Int] = [:]
    private var dayTaskCache: [String: [ProjectTask]] = [:]
    private var cachedWeekStart: Date?

    // Get scheduled tasks for a specific date — reads from week cache
    func scheduledTasks(for date: Date) -> [ProjectTask] {
        let dateKey = formatDateKey(date)

        // Return from cache (populated by rebuildWeekCache)
        if let cached = dayTaskCache[dateKey] {
            return cached
        }

        // Cache miss (rare — only for far-off DayCanvasView pages)
        if let dataController = dataController {
            var tasks: [ProjectTask]
            switch scheduleScope {
            case .all:
                if shouldShowTeamMemberFilter {
                    tasks = dataController.getScheduledTasksForCompany(for: date)
                } else {
                    tasks = dataController.getScheduledTasksForCurrentUser(for: date)
                }
            case .mine:
                tasks = dataController.getScheduledTasksForCurrentUser(for: date)
            case .member(let memberId):
                tasks = dataController.getScheduledTasksForMember(for: date, memberId: memberId)
            }
            tasks = applyTaskFilters(to: tasks)
            dayTaskCache[dateKey] = tasks
            return tasks
        }

        return []
    }
    
    func projectCount(for date: Date) -> Int {
        // CRITICAL: NEVER do database queries here - this is called during rendering
        // Always return from cache only, even if 0

        // If it's the currently selected date, we already have the data
        if Calendar.current.isDate(date, inSameDayAs: selectedDate) {
            return scheduledTasksForSelectedDate.count
        }

        // Return from cache or 0 if not cached
        let dateKey = formatDateKey(date)
        return projectCountCache[dateKey] ?? 0
    }
    
    /// Returns tasks for density bar rendering — safe to call during layout.
    func tasksForDensityBars(for date: Date) -> [ProjectTask] {
        return scheduledTasks(for: date)
    }

    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func formatDateKey(_ date: Date) -> String {
        Self.dateKeyFormatter.string(from: date)
    }
    
    func clearProjectCountCache() {
        projectCountCache = [:]
        dayTaskCache = [:]
        cachedWeekStart = nil
    }
    
    // Update schedule scope (ALL / MINE / specific member)
    func updateScheduleScope(_ scope: ScheduleScope) {
        scheduleScope = scope
        // Sync team member filter state with scope
        switch scope {
        case .all:
            selectedTeamMemberIds = []
            selectedTeamMemberId = nil
        case .mine:
            selectedTeamMemberIds = []
            selectedTeamMemberId = nil
        case .member(let memberId):
            selectedTeamMemberIds = [memberId]
            selectedTeamMemberId = memberId
        }
        clearProjectCountCache()
        loadProjectsForDate(selectedDate)
    }

    // Update selected team member filter (legacy single selection)
    func updateTeamMemberFilter(_ memberId: String?) {
        selectedTeamMemberId = memberId
        // Update the new set-based filter
        if let memberId = memberId {
            selectedTeamMemberIds = [memberId]
        } else {
            selectedTeamMemberIds = []
        }
        clearProjectCountCache()
        loadProjectsForDate(selectedDate)
    }

    func applyFilters(teamMemberIds: Set<String>, taskTypeIds: Set<String>, clientIds: Set<String>, statuses: Set<Status>) {
        selectedTeamMemberIds = teamMemberIds
        selectedTaskTypeIds = taskTypeIds
        selectedClientIds = clientIds
        selectedStatuses = statuses

        selectedTeamMemberId = teamMemberIds.first

        // Sync scope with team member filter changes from filter sheet
        if teamMemberIds.isEmpty {
            // No team member filter — revert scope to .all
            if case .member = scheduleScope {
                scheduleScope = .all
            }
        } else if teamMemberIds.count == 1, let memberId = teamMemberIds.first {
            // Single team member selected — match scope
            scheduleScope = .member(memberId)
        }

        clearProjectCountCache()
        loadProjectsForDate(selectedDate)
    }
    
    var hasActiveFilters: Bool {
        scheduleScope != .all || !selectedTaskTypeIds.isEmpty || !selectedClientIds.isEmpty || !selectedStatuses.isEmpty
    }

    var activeFilterCount: Int {
        var count = 0
        if scheduleScope != .all { count += 1 }
        if !selectedTaskTypeIds.isEmpty { count += 1 }
        if !selectedClientIds.isEmpty { count += 1 }
        if !selectedStatuses.isEmpty { count += 1 }
        return count
    }
    
    // Helper method to apply all filters to scheduled tasks
    func applyTaskFilters(to tasks: [ProjectTask]) -> [ProjectTask] {
        var filteredTasks = tasks

        // Apply team member filter
        if !selectedTeamMemberIds.isEmpty {
            filteredTasks = filteredTasks.filter { task in
                task.teamMembers.contains { selectedTeamMemberIds.contains($0.id) } ||
                    task.getTeamMemberIds().contains { selectedTeamMemberIds.contains($0) }
            }
        }

        // Apply task type filter
        if !selectedTaskTypeIds.isEmpty {
            filteredTasks = filteredTasks.filter { task in
                let taskTypeId = task.taskTypeId
                return !taskTypeId.isEmpty && selectedTaskTypeIds.contains(taskTypeId)
            }
        }

        // Apply client filter
        if !selectedClientIds.isEmpty {
            filteredTasks = filteredTasks.filter { task in
                if let clientId = task.project?.clientId {
                    return selectedClientIds.contains(clientId)
                }
                return false
            }
        }

        // Apply status filter
        if !selectedStatuses.isEmpty {
            filteredTasks = filteredTasks.filter { task in
                if let projectStatus = task.project?.status {
                    return selectedStatuses.contains(projectStatus)
                }
                return false
            }
        }

        return filteredTasks
    }
    
    var filterSummaryText: String {
        var components: [String] = []

        if case .mine = scheduleScope {
            components.append("My tasks")
        } else if case .member = scheduleScope {
            components.append("1 team member")
        }
        if !selectedTaskTypeIds.isEmpty {
            components.append("\(selectedTaskTypeIds.count) task type\(selectedTaskTypeIds.count == 1 ? "" : "s")")
        }
        if !selectedClientIds.isEmpty {
            components.append("\(selectedClientIds.count) client\(selectedClientIds.count == 1 ? "" : "s")")
        }
        if !selectedStatuses.isEmpty {
            components.append("\(selectedStatuses.count) status\(selectedStatuses.count == 1 ? "" : "es")")
        }

        if components.isEmpty {
            return "No Filters"
        } else {
            return components.joined(separator: ", ")
        }
    }
    
    
    
    // MARK: - Private Methods
    func loadProjectsForDate(_ date: Date) {
        guard let dataController = dataController else {
            return
        }

        isLoading = true

        // Rebuild the week cache (single DB fetch for entire week + buffer)
        rebuildWeekCache(around: date)

        // Get tasks for selected date from cache
        let dateKey = formatDateKey(date)
        let scheduledTasks = dayTaskCache[dateKey] ?? []

        // Get unique projects from the scheduled tasks
        let projectIds = Set(scheduledTasks.compactMap { $0.projectId })

        var projects: [Project] = []
        for projectId in projectIds {
            if let project = dataController.getProject(id: projectId) {
                projects.append(project)
            }
        }

        // Force UI update - Store IDs instead of models to avoid invalidation
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
            self?.scheduledTaskIdsForSelectedDate = scheduledTasks.map { $0.id }
            self?.projectIdsForSelectedDate = projects.map { $0.id }
            self?.isLoading = false
        }

        // Update the project count cache for this date
        projectCountCache[dateKey] = scheduledTasks.count
    }

    // MARK: - Week Cache

    /// Fetches all tasks from DB once and distributes them into a per-day cache.
    /// Covers the current week ± 1 week buffer for smooth DayCanvasView swiping.
    private func rebuildWeekCache(around centerDate: Date) {
        guard let dataController = dataController,
              let context = dataController.modelContext,
              let user = dataController.currentUser else { return }

        var weekCal = Calendar.current
        weekCal.firstWeekday = 2 // Monday
        guard let weekInterval = weekCal.dateInterval(of: .weekOfYear, for: centerDate) else { return }
        let weekStart = weekInterval.start

        // Skip rebuild if same week is already cached
        if let cached = cachedWeekStart, weekCal.isDate(cached, inSameDayAs: weekStart) {
            return
        }

        let cal = Calendar.current

        // Fetch ALL tasks once (single DB hit)
        let allTasks: [ProjectTask]
        do {
            allTasks = try context.fetch(FetchDescriptor<ProjectTask>())
        } catch {
            return
        }

        // Apply scope/permission filter (no date filter)
        let scopedTasks = allTasks.filter { task in
            guard task.deletedAt == nil else { return false }
            guard task.startDate != nil else { return false }

            switch scheduleScope {
            case .all:
                if shouldShowTeamMemberFilter {
                    return task.companyId == user.companyId
                } else {
                    if PermissionStore.shared.hasFullAccess("tasks.view") {
                        return task.companyId == user.companyId
                    } else {
                        return isUserAssignedToTask(user: user, task: task)
                    }
                }
            case .mine:
                if PermissionStore.shared.hasFullAccess("tasks.view") {
                    return task.companyId == user.companyId
                } else {
                    return isUserAssignedToTask(user: user, task: task)
                }
            case .member(let memberId):
                guard task.companyId == user.companyId else { return false }
                return isMemberAssignedToTask(memberId: memberId, task: task)
            }
        }

        // Apply additional filters (task type, client, status)
        let filteredTasks = applyTaskFilters(to: scopedTasks)

        // Build per-day cache: current week ± 1 week (21 days)
        var newCache: [String: [ProjectTask]] = [:]
        for dayOffset in -7..<14 {
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
            let dayStart = cal.startOfDay(for: date)
            let dateKey = formatDateKey(date)

            let tasksForDay = filteredTasks.filter { task in
                let taskStartDay = cal.startOfDay(for: task.startDate!)
                let taskEndDay = cal.startOfDay(for: task.endDate ?? task.startDate!)
                return taskStartDay <= dayStart && taskEndDay >= dayStart
            }
            .sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }

            newCache[dateKey] = tasksForDay
            projectCountCache[dateKey] = tasksForDay.count
        }

        dayTaskCache = newCache
        cachedWeekStart = weekStart
    }

    private func isUserAssignedToTask(user: User, task: ProjectTask) -> Bool {
        let taskTeamMemberIds = task.getTeamMemberIds()
        if taskTeamMemberIds.contains(user.id) || task.teamMembers.contains(where: { $0.id == user.id }) {
            return true
        }
        if let project = task.project {
            let projectTeamMemberIds = project.getTeamMemberIds()
            return projectTeamMemberIds.contains(user.id)
                || project.teamMembers.contains(where: { $0.id == user.id })
        }
        return false
    }

    private func isMemberAssignedToTask(memberId: String, task: ProjectTask) -> Bool {
        let taskTeamMemberIds = task.getTeamMemberIds()
        if taskTeamMemberIds.contains(memberId) || task.teamMembers.contains(where: { $0.id == memberId }) {
            return true
        }
        if let project = task.project {
            let projectTeamMemberIds = project.getTeamMemberIds()
            return projectTeamMemberIds.contains(memberId)
                || project.teamMembers.contains(where: { $0.id == memberId })
        }
        return false
    }
    
    /// Load CalendarUserEvents for the current user from local SwiftData store
    func loadUserEvents() {
        guard let dataController = dataController,
              let context = dataController.modelContext,
              let userId = dataController.currentUser?.id else { return }

        let descriptor = FetchDescriptor<CalendarUserEvent>(
            predicate: #Predicate { event in
                event.userId == userId && event.deletedAt == nil
            }
        )
        let events = (try? context.fetch(descriptor)) ?? []
        DispatchQueue.main.async {
            self.userEventsForCurrentPeriod = events
        }
    }

    /// User events overlapping a given date
    func userEvents(for date: Date) -> [CalendarUserEvent] {
        userEventsForCurrentPeriod.filter { $0.overlaps(date: date) }
    }

    /// Full calendar refresh, driven by pull-to-refresh on the day list. Runs a
    /// comprehensive backend sync — projects, tasks, and calendar user events
    /// all come down via SyncEngine.fullSync — then reloads BOTH layers of the
    /// day view from the freshly-synced local store:
    ///   • loadProjectsForDate rebuilds the week task cache, so newly-assigned
    ///     and rescheduled tasks surface on the day.
    ///   • loadUserEvents refreshes the published user-event array, so new or
    ///     rescheduled time-off / personal events surface too.
    /// Reloading only projects (the old behavior) left synced user events stale
    /// until another trigger fired.
    @MainActor
    func refreshCalendar() async {
        guard let dataController = dataController else {
            return
        }

        // Clear the count cache so freshly-synced data isn't masked.
        projectCountCache.removeAll()

        // Pull the latest of everything from the backend (full sync).
        await dataController.refreshProjectsFromBackend()

        // Reload both the task layer and the user-event layer for the day.
        loadProjectsForDate(selectedDate)
        loadUserEvents()
    }
    
    private func getWeekDays() -> [Date] {
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: selectedDate)
        
        // Get the start of the week containing the selected date
        let weekStart = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDay)
        let startOfWeek = calendar.date(from: weekStart)!
        
        // Generate an array of the 7 days of the week
        return (0..<7).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: startOfWeek)
        }
    }
    
    private func getMonthDays() -> [Date] {
        var calendar = Calendar.current
        // Set first weekday to Monday
        calendar.firstWeekday = 2
        
        let selectedMonth = calendar.dateComponents([.year, .month], from: selectedDate)
        guard let startOfMonth = calendar.date(from: selectedMonth) else { return [] }
        
        // Get first day of the month
        let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: startOfMonth))!
        
        // Get the weekday of the first day (1 = Sunday, 2 = Monday, etc.)
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        
        // Calculate offset to start grid with Monday as first day
        // Convert to Monday-based index (0 = Monday, 6 = Sunday)
        let mondayBasedWeekday = (firstWeekday + 5) % 7
        let weekdayOffset = mondayBasedWeekday
        
        // Get number of days in the month
        let daysInMonth = calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 30
        
        // Generate dates for a full 42-day grid (6 weeks)
        // Start with days from previous month to fill first week
        var dayComponents = DateComponents()
        var allDates: [Date] = []
        
        // Add days from previous month if needed
        for i in -weekdayOffset..<0 {
            dayComponents.day = i
            if let date = calendar.date(byAdding: dayComponents, to: firstDay) {
                allDates.append(date)
            }
        }
        
        // Add all days in current month
        for i in 0..<daysInMonth {
            dayComponents.day = i
            if let date = calendar.date(byAdding: dayComponents, to: firstDay) {
                allDates.append(date)
            }
        }
        
        // Fill remaining grid with days from next month
        let remainingDays = 42 - allDates.count
        for i in 0..<remainingDays {
            dayComponents.day = daysInMonth + i
            if let date = calendar.date(byAdding: dayComponents, to: firstDay) {
                allDates.append(date)
            }
        }
        
        return allDates
    }
    
}
