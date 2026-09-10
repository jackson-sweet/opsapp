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
    @Published private(set) var siteVisitLeadDetailsByOpportunityId: [String: CalendarSiteVisitLeadDetails] = [:]
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
        // Reveal the tab first. Every calendar data source is prepared in
        // DataActor; even the small team-filter lookup yields behind the first
        // render so tab selection itself never waits on SwiftData.
        scheduleCalendarLoad(around: selectedDate, force: true)
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.loadTeamMembersIfNeeded()
        }
    }

    /// Force reload of calendar data (called after scheduling changes)
    func reloadCalendarData() {
        invalidateForReload()
        scheduleCalendarLoad(around: selectedDate, force: true)
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
              dataController.getCompany(id: companyId) != nil else {
            return
        }
        
        let users = dataController.getTeamMembers(companyId: companyId)
        availableTeamMembers = users.map { TeamMember.fromUser($0) }.sorted { $0.fullName < $1.fullName }
    }
    
    // Used for both programmatic and user-initiated date selection
    func selectDate(_ date: Date, userInitiated: Bool = false) {
        // Track if this was a user-initiated selection (tapping a day)
        // or a programmatic selection (changing months, initializing)
        // We need to do this on the main thread since it's a @Published property
        DispatchQueue.main.async {
            self.userInitiatedDateSelection = userInitiated

        }

        // Update date immediately for instant UI feedback
        selectedDate = date

        // A cached adjacent week publishes synchronously; any recentering read
        // happens off-main. No gesture path is allowed to query SwiftData.
        scheduleCalendarLoad(around: date)

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
    private var cachedWeekSnapshot: CalendarWeekCacheSnapshot?
    private var cachedAuxiliaryWindow: CalendarAuxiliaryWindow?
    private var calendarLoadGeneration: UInt64 = 0
    private var calendarLoadTask: Task<Void, Never>?
    private var siteVisitLeadScopeKey: String?
    private let siteVisitLeadResolver = CalendarSiteVisitLeadResolver()

    // Get scheduled tasks for a specific date — reads from week cache
    func scheduledTasks(for date: Date) -> [ProjectTask] {
        let dateKey = formatDateKey(date)

        // Rendering is cache-only. A miss means the off-main snapshot has not
        // landed yet; querying here would repeat the old hitch once per cell.
        return dayTaskCache[dateKey] ?? []
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
    
    /// Invariant: `cachedWeekStart` guards against reloading the same week only.
    /// Every data-change reload must clear it — a task that moved, arrived, or
    /// was deleted lands inside the week already cached, so keeping the guard
    /// set would leave the canvas showing stale work. The replacement snapshot
    /// is bounded and assembled by the DataActor; freshness is never traded for
    /// a main-thread shortcut.
    func clearProjectCountCache() {
        invalidateForReload()
        // A scope or filter change alters what a row MEANS, so the displayed
        // caches go with the guard — a stale ALL day under a fresh MINE filter
        // would be a lie for the length of the reload.
        projectCountCache = [:]
        dayTaskCache = [:]
    }

    /// Bug a4225f3f — a data-change reload used to empty the day caches up
    /// front, so every schedule edit blanked the day for the length of the
    /// off-main reload ("all events disappear momentarily"). The last snapshot
    /// now stays on screen and `performCalendarLoad` swaps in the replacement
    /// synchronously; the generation bump still cancels a stale in-flight load
    /// and dropping `cachedWeekStart` means the reload can never be skipped as
    /// "same week".
    func invalidateForReload() {
        calendarLoadGeneration &+= 1
        calendarLoadTask?.cancel()
        calendarLoadTask = nil
        cachedWeekStart = nil
        cachedWeekSnapshot = nil
        cachedAuxiliaryWindow = nil
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
    /// The main-actor filter used by selected-day publishing and month-grid
    /// compatibility paths. The DataActor snapshot uses the same rules through
    /// `CalendarTaskScoping`, keeping both paths behaviorally aligned.
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
        scheduleCalendarLoad(around: date, force: true)
    }

    // MARK: - Week Cache

    /// The Monday that anchors the cached window for `centerDate`.
    private func weekCacheAnchor(for centerDate: Date) -> Date? {
        var weekCal = Calendar.current
        weekCal.firstWeekday = 2 // Monday
        return weekCal.dateInterval(of: .weekOfYear, for: centerDate)?.start
    }

    /// Land a rebuilt window. `tasks` supplies the live models for the ids the
    /// snapshot names — the snapshot itself carries ids because it may have been
    /// built in another context.
    /// Internal (not private) so the reload policy can be proven with a seeded
    /// snapshot instead of a full DataActor load — see
    /// `CalendarReloadKeepsLastSnapshotTests`.
    func applyWeekCache(_ snapshot: CalendarWeekCacheSnapshot, resolving tasks: [ProjectTask]) {
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
        cachedWeekSnapshot = snapshot
    }

    /// Schedule a complete, cancellable calendar snapshot. A cached adjacent
    /// week publishes immediately; recentering and all store work happen in the
    /// background actor. Rapid swipes cancel stale generations rather than
    /// letting old results repaint over the user's latest week.
    private func scheduleCalendarLoad(around date: Date, force: Bool = false) {
        guard let weekStart = weekCacheAnchor(for: date) else { return }
        let weekIsReady = cachedWeekSnapshot?.covers(weekStarting: weekStart) == true
        let auxiliaryIsReady = cachedAuxiliaryWindow?.contains(date) == true

        if weekIsReady {
            publishSelectedDate()
        }
        if !force && weekIsReady && auxiliaryIsReady,
           Calendar.current.isDate(cachedWeekStart ?? .distantPast, inSameDayAs: weekStart) {
            return
        }

        calendarLoadGeneration &+= 1
        let generation = calendarLoadGeneration
        calendarLoadTask?.cancel()
        if !weekIsReady { isLoading = true }
        calendarLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performCalendarLoad(
                around: date,
                weekStart: weekStart,
                generation: generation
            )
        }
    }

    /// Reload after a schedule change. Kept awaitable for refresh flows and
    /// tests; unlike the old fallback it never executes a full fetch on the main
    /// context, even when the long-lived DataActor feature flag is disabled.
    @MainActor
    func reloadCalendarDataOffMain() async {
        invalidateForReload()
        guard let weekStart = weekCacheAnchor(for: selectedDate) else { return }
        calendarLoadGeneration &+= 1
        let generation = calendarLoadGeneration
        isLoading = true
        await performCalendarLoad(
            around: selectedDate,
            weekStart: weekStart,
            generation: generation
        )
    }

    @MainActor
    private func performCalendarLoad(
        around centerDate: Date,
        weekStart: Date,
        generation: UInt64
    ) async {
        guard let dataController = dataController,
              let context = dataController.modelContext,
              let user = dataController.currentUser,
              let companyId = user.companyId else {
            isLoading = false
            return
        }

        // Capture scope before readiness can suspend; a logout may invalidate
        // the old User model while the actor is being prepared.
        let userID = user.id
        let taskScope = currentTaskScope()
        let auxiliaryScope = CalendarAuxiliaryScope(
            userId: userID,
            companyId: companyId,
            canViewAllCalendar: PermissionStore.shared.can("calendar.view", requiredScope: "all"),
            canApproveTimeOff: PermissionStore.shared.can("time_off.approve")
        )
        func isCurrent() -> Bool {
            !Task.isCancelled && generation == calendarLoadGeneration
                && self.dataController === dataController
                && dataController.modelContext === context
                && dataController.currentUser?.id == userID
                && dataController.currentUser?.companyId == companyId
        }
        let actor: DataActor
        if FeatureFlags.useDataActor {
            guard let ready = await dataController.readyDataActor(), isCurrent() else {
                if generation == calendarLoadGeneration { isLoading = false }
                return
            }
            actor = ready
        } else {
            // Flag-off still uses an independent background reader, preserving
            // the calendar's existing off-main fallback contract.
            do {
                actor = try await DataActor.makeBackgroundConfigured(modelContainer: context.container)
            } catch {
                if generation == calendarLoadGeneration { isLoading = false }
                return
            }
            guard isCurrent() else { return }
        }
        guard let snapshot = try? await actor.calendarLoadSnapshot(
            taskScope: taskScope,
            auxiliaryScope: auxiliaryScope,
            weekStart: weekStart,
            centerDate: centerDate
        ) else {
            if isCurrent() { isLoading = false }
            return
        }
        guard isCurrent(), !FeatureFlags.useDataActor || dataController.dataActor === actor else { return }

        // Resolve exactly the actor-approved ids into main-context models. No
        // actor-owned @Model crosses isolation and no unbounded relationship
        // walk can reach the render thread.
        let taskIds = Array(Set(snapshot.week.taskIdsByDay.values.flatMap { $0 }))
        let eventIds = snapshot.auxiliary.userEventIds
        let visitIds = snapshot.auxiliary.bookedVisitIds
        let resolvedTasks: [ProjectTask] = taskIds.isEmpty ? [] : ((try? context.fetch(
            FetchDescriptor<ProjectTask>(predicate: #Predicate<ProjectTask> { taskIds.contains($0.id) })
        )) ?? [])
        let resolvedEvents: [CalendarUserEvent] = eventIds.isEmpty ? [] : ((try? context.fetch(
            FetchDescriptor<CalendarUserEvent>(predicate: #Predicate<CalendarUserEvent> { eventIds.contains($0.id) })
        )) ?? [])
        let resolvedVisits: [SiteVisit] = visitIds.isEmpty ? [] : ((try? context.fetch(
            FetchDescriptor<SiteVisit>(predicate: #Predicate<SiteVisit> { visitIds.contains($0.id) })
        )) ?? [])
        guard !Task.isCancelled, generation == calendarLoadGeneration else { return }

        projectCountCache = [:]
        dayTaskCache = [:]
        applyWeekCache(snapshot.week, resolving: resolvedTasks)
        cachedAuxiliaryWindow = snapshot.auxiliary.window
        userEventsForCurrentPeriod = resolvedEvents.sorted { $0.startDate < $1.startDate }
        bookedVisitsForCurrentPeriod = resolvedVisits.sorted {
            ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture)
        }

        let leadScopeKey = "\(user.id.lowercased())|\(companyId.lowercased())"
        if siteVisitLeadScopeKey != leadScopeKey {
            siteVisitLeadDetailsByOpportunityId = [:]
            siteVisitLeadScopeKey = leadScopeKey
        }
        let visibleOpportunityIds = Set(resolvedVisits.compactMap(\.opportunityId))
        siteVisitLeadDetailsByOpportunityId = siteVisitLeadDetailsByOpportunityId.filter {
            visibleOpportunityIds.contains($0.key)
        }
        publishSelectedDate()

        if !visibleOpportunityIds.isEmpty {
            let details = await siteVisitLeadResolver.refreshDetails(
                opportunityIds: Array(visibleOpportunityIds),
                userId: user.id,
                companyId: companyId
            )
            guard !Task.isCancelled, generation == calendarLoadGeneration else { return }
            siteVisitLeadDetailsByOpportunityId = details
        }
        calendarLoadTask = nil
    }

    /// Republish the selected day's task/project ids from the cache. Shared tail of
    /// `loadProjectsForDate` and the off-main reload.
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

    /// Refresh personal/time-off events through the same bounded actor snapshot
    /// as tasks and booked visits. Safe to call repeatedly after sheet saves;
    /// stale in-flight generations are cancelled.
    func loadUserEvents() {
        scheduleCalendarLoad(around: selectedDate, force: true)
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

    /// Refresh booked visits through the bounded actor snapshot. Visits are
    /// appointments, not tasks — they never enter the week task cache.
    func loadBookedVisits() {
        scheduleCalendarLoad(around: selectedDate, force: true)
    }

    /// Booked visits on a given date, earliest first.
    func bookedVisits(for date: Date) -> [SiteVisit] {
        Self.bookedVisits(in: bookedVisitsForCurrentPeriod, on: date)
    }

    /// Calendar-owned lead projection for a booked appointment. Opportunities
    /// are network-only, so schedule surfaces must never query SwiftData for
    /// this relationship.
    func siteVisitPresentation(for visit: SiteVisit) -> CalendarSiteVisitPresentation {
        let opportunityId = visit.opportunityId?.lowercased()
        return CalendarSiteVisitPresentation(
            visit: visit,
            leadDetails: opportunityId.flatMap { siteVisitLeadDetailsByOpportunityId[$0] }
        )
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

        // Invalidate and await one coherent actor snapshot after sync writes
        // land. Tasks, events, and visits can never repaint from different
        // generations or run three competing fetches on the main context.
        await reloadCalendarDataOffMain()

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
