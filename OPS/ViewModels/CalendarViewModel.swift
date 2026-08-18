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
    @Published var bookedVisitsForCurrentPeriod: [SiteVisit] = []
    @Published var isMonthExpanded: Bool = false

    /// Phase-C "Suggested events" (item 63144953). Detected commitments the
    /// operator can confirm onto their calendar. Empty is the normal, healthy
    /// state — when it is, the schedule shows no suggestions surface at all, so
    /// the app never depends on the Phase C engine running.
    @Published var suggestedEvents: [SuggestedCalendarEventDTO] = []

    /// Set when the most recent pull-to-refresh could NOT reach the server
    /// (offline / unusable connection). Drives a transient inline banner so the
    /// gesture is acknowledged instead of silently appearing to do nothing.
    /// Self-clears on the next reachable refresh (or after a short timeout).
    @Published var lastRefreshUnreachable = false

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
        loadBookedVisits()
    }

    /// Force reload of calendar data (called after scheduling changes)
    func reloadCalendarData() {
        // Clear caches first to force fresh data
        clearProjectCountCache()
        loadProjectsForDate(selectedDate)
        loadBookedVisits()
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

    /// Delegated so the day keys this view model reads are, by construction, the
    /// same strings the off-main rebuild writes.
    private func formatDateKey(_ date: Date) -> String {
        CalendarDayKey.key(for: date)
    }
    
    /// Invariant: `cachedWeekStart` guards against rebuilding on same-week
    /// NAVIGATION only. Every data-change reload must clear it — a task that
    /// moved, arrived, or was deleted lands inside the week already cached, so
    /// keeping the guard set would leave the canvas showing stale work. The
    /// cost of those rebuilds is partially contained by the predicated fetch in
    /// `rebuildWeekCache` — the per-survivor relationship walk remains — never
    /// by skipping the rebuild.
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
    ///
    /// The single chokepoint for the week canvas (`rebuildWeekCache`), the
    /// per-day cache (`getTasksForDate`), and the month grid
    /// (`MonthGridCache.loadEvents`) — all three funnel through here, so the
    /// status cut below lands on every one of them at once.
    func applyTaskFilters(to tasks: [ProjectTask]) -> [ProjectTask] {
        applyTaskFilters(
            to: tasks,
            hiddenProjectIds: CalendarTaskVisibility.hiddenProjectIds(in: dataController?.modelContext)
        )
    }

    /// Pure variant — the hidden set is resolved once by the caller rather
    /// than per row. See `CalendarTaskVisibility`.
    ///
    /// The rule itself lives in `CalendarTaskScoping` so the DataActor rebuild pass
    /// and this main-actor one run the same code, not two copies of it.
    func applyTaskFilters(
        to tasks: [ProjectTask],
        hiddenProjectIds: Set<String>
    ) -> [ProjectTask] {
        let scope = currentTaskScope()
        return tasks.filter {
            CalendarTaskScoping.passesFilters($0, scope: scope, hiddenProjectIds: hiddenProjectIds)
        }
    }

    /// Freeze this operator's calendar visibility — scope, permissions, and every
    /// active filter — into a value the DataActor can be handed. Resolved here, on
    /// the main actor, because that is where PermissionStore lives; the actor never
    /// re-derives any of it.
    func currentTaskScope() -> CalendarTaskScope {
        let mode: CalendarTaskScope.Mode
        switch scheduleScope {
        case .all: mode = .all
        case .mine: mode = .mine
        case .member(let memberId): mode = .member(memberId)
        }
        return CalendarTaskScope(
            mode: mode,
            userId: dataController?.currentUser?.id ?? "",
            companyId: dataController?.currentUser?.companyId,
            canViewAllCalendar: shouldShowTeamMemberFilter,
            hasFullTaskAccess: PermissionStore.shared.hasFullAccess("tasks.view"),
            selectedTeamMemberIds: selectedTeamMemberIds,
            selectedTaskTypeIds: selectedTaskTypeIds,
            selectedClientIds: selectedClientIds,
            selectedStatuses: selectedStatuses
        )
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

    /// The Monday that anchors the cached window for `centerDate`.
    private func weekCacheAnchor(for centerDate: Date) -> Date? {
        var weekCal = Calendar.current
        weekCal.firstWeekday = 2 // Monday
        return weekCal.dateInterval(of: .weekOfYear, for: centerDate)?.start
    }

    /// Fetches all tasks from DB once and distributes them into a per-day cache.
    /// Covers the current week ± 1 week buffer for smooth DayCanvasView swiping.
    ///
    /// Synchronous, on the main context — this is the NAVIGATION path, guarded by
    /// `cachedWeekStart` so same-week day taps do no work at all. The data-change
    /// path (`reloadCalendarDataOffMain`) runs the identical scope + filter + bucket
    /// code on the DataActor instead; both go through `CalendarTaskScoping` and
    /// `CalendarWeekCacheBuilder`, so they cannot diverge.
    private func rebuildWeekCache(around centerDate: Date) {
        guard let dataController = dataController,
              let context = dataController.modelContext,
              dataController.currentUser != nil else { return }

        var weekCal = Calendar.current
        weekCal.firstWeekday = 2 // Monday
        guard let weekStart = weekCacheAnchor(for: centerDate) else { return }

        // Skip rebuild if same week is already cached
        if let cached = cachedWeekStart, weekCal.isDate(cached, inSameDayAs: weekStart) {
            return
        }

        // One DB hit for the whole window. The soft-delete and dated gates are
        // `#Predicate`s rather than in-memory filters so a row that fails either is
        // never materialized just to be dropped.
        //
        // No date bound. The per-day filter admits a task by OVERLAP, so a task that
        // began long before the window still belongs to it whenever its endDate
        // reaches in. Tasks carry no maximum span, so any lower bound on startDate
        // would silently drop long-running work off the canvas.
        let allTasks: [ProjectTask]
        do {
            allTasks = try context.fetch(
                FetchDescriptor<ProjectTask>(
                    predicate: #Predicate<ProjectTask> {
                        $0.deletedAt == nil && $0.startDate != nil
                    }
                )
            )
        } catch {
            return
        }

        let scope = currentTaskScope()
        let hiddenProjectIds = CalendarTaskVisibility.hiddenProjectIds(in: context)
        let visibleTasks = allTasks.filter {
            CalendarTaskScoping.admitsForWeekCanvas($0, scope: scope)
                && CalendarTaskScoping.passesFilters($0, scope: scope, hiddenProjectIds: hiddenProjectIds)
        }

        applyWeekCache(
            CalendarWeekCacheBuilder.snapshot(tasks: visibleTasks, weekStart: weekStart),
            resolving: visibleTasks
        )
    }

    /// Land a rebuilt window. `tasks` supplies the live models for the ids the
    /// snapshot names — the snapshot itself carries ids because it may have been
    /// built in another context.
    private func applyWeekCache(_ snapshot: CalendarWeekCacheSnapshot, resolving tasks: [ProjectTask]) {
        let byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })

        var newCache: [String: [ProjectTask]] = [:]
        for (dateKey, ids) in snapshot.taskIdsByDay {
            newCache[dateKey] = ids.compactMap { byId[$0] }
        }

        dayTaskCache = newCache
        // Merged, not replaced: days outside this window keep the counts a previous
        // window left behind, exactly as the inline build did.
        for (dateKey, count) in snapshot.countsByDay {
            projectCountCache[dateKey] = count
        }
        cachedWeekStart = snapshot.weekStart
    }

    /// Reload after a schedule change, with the expensive pass on the DataActor.
    ///
    /// Bug 1bade6dd: one reschedule toggles `scheduledTasksDidChange`, and this
    /// rebuild answered it by walking every live dated task on the main context and
    /// faulting `project` / `teamMembers` per row — the screen froze for seconds
    /// right after the toast. The walk still happens; it just no longer happens on
    /// the thread that draws. Falls back to the synchronous path when there is no
    /// actor (pre-login, or the DataActor flag is off).
    @MainActor
    func reloadCalendarDataOffMain() async {
        guard let dataController = dataController,
              let actor = dataController.dataActor,
              let context = dataController.modelContext,
              dataController.currentUser != nil,
              let weekStart = weekCacheAnchor(for: selectedDate) else {
            reloadCalendarData()
            return
        }

        isLoading = true
        let snapshot = await actor.calendarWeekCache(scope: currentTaskScope(), weekStart: weekStart)

        // One id-keyed fetch for exactly the rows this window shows — the models the
        // actor saw belong to its context and can never cross back.
        let ids = Array(Set(snapshot.taskIdsByDay.values.flatMap { $0 }))
        let resolved = (try? context.fetch(
            FetchDescriptor<ProjectTask>(predicate: #Predicate<ProjectTask> { ids.contains($0.id) })
        )) ?? []

        // Invalidate and land in the same main-actor turn — clearing before the
        // await would blank the calendar for the whole round trip. Same clear the
        // synchronous reload does, so counts outside the window cannot go stale.
        clearProjectCountCache()
        applyWeekCache(snapshot, resolving: resolved)
        publishSelectedDate()
        loadBookedVisits()
    }

    /// Republish the selected day's task/project ids from the cache. Shared tail of
    /// `loadProjectsForDate` and the off-main reload.
    @MainActor
    private func publishSelectedDate() {
        guard let dataController = dataController else { return }
        let dateKey = formatDateKey(selectedDate)
        let scheduledTasks = dayTaskCache[dateKey] ?? []

        let projectIds = Set(scheduledTasks.compactMap { $0.projectId })
        var projects: [Project] = []
        for projectId in projectIds {
            if let project = dataController.getProject(id: projectId) {
                projects.append(project)
            }
        }

        objectWillChange.send()
        scheduledTaskIdsForSelectedDate = scheduledTasks.map { $0.id }
        projectIdsForSelectedDate = projects.map { $0.id }
        isLoading = false
        projectCountCache[dateKey] = scheduledTasks.count
    }

    /// Load CalendarUserEvents visible to the current user from local SwiftData store.
    /// Own rows always appear; team-invited personal rows appear for assignees;
    /// users with calendar.view(all) see the company calendar; users with
    /// time_off.approve see company time off so booked crew absences do not
    /// disappear after save.
    func loadUserEvents() {
        guard let dataController = dataController,
              let context = dataController.modelContext,
              let userId = dataController.currentUser?.id,
              let companyId = dataController.currentUser?.companyId else { return }

        let descriptor = FetchDescriptor<CalendarUserEvent>(
            predicate: #Predicate { event in
                event.companyId == companyId && event.deletedAt == nil
            }
        )
        let canViewAllCalendar = PermissionStore.shared.can("calendar.view", requiredScope: "all")
        let canApproveTimeOff = PermissionStore.shared.can("time_off.approve")
        let events = ((try? context.fetch(descriptor)) ?? [])
            .filter { event in
                isUserEventVisible(
                    event,
                    currentUserId: userId,
                    canViewAllCalendar: canViewAllCalendar,
                    canApproveTimeOff: canApproveTimeOff
                )
            }
        DispatchQueue.main.async {
            self.userEventsForCurrentPeriod = events
        }
    }

    private func isUserEventVisible(
        _ event: CalendarUserEvent,
        currentUserId: String,
        canViewAllCalendar: Bool,
        canApproveTimeOff: Bool
    ) -> Bool {
        if canViewAllCalendar { return true }
        if event.userId == currentUserId { return true }
        if event.teamMemberIds?.contains(currentUserId) == true { return true }
        return canApproveTimeOff && event.isTimeOff
    }

    /// User events overlapping a given date
    func userEvents(for date: Date) -> [CalendarUserEvent] {
        userEventsForCurrentPeriod.filter { $0.overlaps(date: date) }
    }

    // MARK: - Booked site visits (calendar third source)

    /// Booked appointments visible to this user: scheduled or on-site, never
    /// walk-ups (their scheduledAt is junk — the legacy guard), never
    /// tombstones. Visibility mirrors user events: your own work always, the
    /// company calendar with calendar.view(all).
    static func visibleBookedVisits(
        _ visits: [SiteVisit],
        currentUserId: String,
        canViewAllCalendar: Bool
    ) -> [SiteVisit] {
        let canonicalUser = currentUserId.lowercased()
        return visits.filter { visit in
            guard visit.isBookedAppointment,
                  visit.deletedAt == nil,
                  visit.status == .scheduled || visit.status == .inProgress
            else { return false }
            if canViewAllCalendar { return true }
            return visit.assigneeIds.contains(canonicalUser)
                || visit.createdBy == canonicalUser
        }
    }

    /// Same-day slotting for the day canvas, earliest appointment first.
    static func bookedVisits(
        in visits: [SiteVisit],
        on date: Date,
        calendar: Calendar = .current
    ) -> [SiteVisit] {
        visits
            .filter { visit in
                guard let scheduledAt = visit.scheduledAt else { return false }
                return calendar.isDate(scheduledAt, inSameDayAs: date)
            }
            .sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
    }

    /// Load booked visits from the local store. Visits are appointments, not
    /// tasks — they never enter the week task cache, cascade, or auto-schedule.
    func loadBookedVisits() {
        guard let dataController = dataController,
              let context = dataController.modelContext,
              let userId = dataController.currentUser?.id,
              let companyId = dataController.currentUser?.companyId else { return }

        let descriptor = FetchDescriptor<SiteVisit>(
            predicate: #Predicate { visit in
                visit.companyId == companyId
                    && visit.bookedAt != nil
                    && visit.deletedAt == nil
            }
        )
        let canViewAllCalendar = PermissionStore.shared.can("calendar.view", requiredScope: "all")
        let visits = Self.visibleBookedVisits(
            (try? context.fetch(descriptor)) ?? [],
            currentUserId: userId,
            canViewAllCalendar: canViewAllCalendar
        )
        DispatchQueue.main.async {
            self.bookedVisitsForCurrentPeriod = visits
        }
    }

    /// Booked visits on a given date, earliest first.
    func bookedVisits(for date: Date) -> [SiteVisit] {
        Self.bookedVisits(in: bookedVisitsForCurrentPeriod, on: date)
    }

    /// Calendar refresh, driven by pull-to-refresh on the day list. Runs a
    /// schedule-scoped backend sync — projects, tasks, task types, and calendar
    /// user events only (a fast "check for schedule updates", the fallback for
    /// when realtime hasn't delivered) — then reloads BOTH layers of the day
    /// view from the freshly-synced local store:
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

        // If the server is unreachable, the full sync silently no-ops — surface
        // that so pull-to-refresh isn't a dead gesture. Otherwise pull the
        // latest of everything from the backend (full sync).
        let reachable = dataController.connectivity?.shouldAttemptSync ?? dataController.isConnected
        if reachable {
            await dataController.refreshScheduleFromBackend()
            if lastRefreshUnreachable {
                withAnimation(OPSStyle.Animation.standard) { lastRefreshUnreachable = false }
            }
        } else {
            withAnimation(OPSStyle.Animation.standard) { lastRefreshUnreachable = true }
            // Auto-clear the transient acknowledgement; the persistent header
            // strip continues to reflect the standing offline state.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                await MainActor.run {
                    withAnimation(OPSStyle.Animation.standard) { self?.lastRefreshUnreachable = false }
                }
            }
        }

        // Invalidate ALL snapshot caches AFTER the sync writes land — not just
        // projectCountCache. dayTaskCache and cachedWeekStart must be cleared
        // too, otherwise rebuildWeekCache() short-circuits on the still-set
        // cachedWeekStart and the freshly-synced dates never re-fetch from
        // SwiftData (the pull-to-refresh stale-calendar bug). Clearing AFTER the
        // await (not before) also prevents an in-flight repaint from
        // repopulating cachedWeekStart mid-sync and re-masking the new data.
        clearProjectCountCache()

        // Reload the task, user-event, and booked-visit layers for the day.
        loadProjectsForDate(selectedDate)
        loadUserEvents()
        loadBookedVisits()

        // Refresh Phase-C suggestions too (item 63144953). Dormant on empty.
        await loadSuggestedEvents()
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
