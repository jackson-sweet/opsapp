//
//  CalendarViewModel.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//


// CalendarViewModel.swift
import Foundation
import SwiftData
import Combine

class CalendarViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedDate: Date = Date()
    @Published var viewMode: CalendarViewMode = .week
    @Published var visibleMonth: Date = Date() // Track visible month in month grid view
    @Published var projectIdsForSelectedDate: [String] = []  // Store IDs to avoid invalidation
    @Published var calendarEventIdsForSelectedDate: [String] = []  // Store IDs to avoid invalidation
    
    // Computed properties to get fresh models
    var projectsForSelectedDate: [Project] {
        guard let dataController = dataController else { return [] }
        return projectIdsForSelectedDate.compactMap { dataController.getProject(id: $0) }
    }
    
    var calendarEventsForSelectedDate: [CalendarEvent] {
        guard let dataController = dataController else { return [] }
        return calendarEventIdsForSelectedDate.compactMap { dataController.getCalendarEvent(id: $0) }
    }
    @Published var isLoading = false
    @Published var userInitiatedDateSelection = false
    @Published var shouldShowDaySheet = false // New published property for explicit control
    @Published var selectedTeamMemberId: String? = nil  // Single selection for backward compatibility
    @Published var availableTeamMembers: [TeamMember] = []
    
    // New comprehensive filter properties
    @Published var selectedTeamMemberIds: Set<String> = []
    @Published var selectedTaskTypeIds: Set<String> = []
    @Published var selectedClientIds: Set<String> = []
    
    // MARK: - Private Properties
    var dataController: DataController?
    
    // MARK: - Enums
    enum CalendarViewMode {
        case week
        case month
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
    }
    
    // Check if current user should see team member filter
    var shouldShowTeamMemberFilter: Bool {
        guard let dataController = dataController,
              let user = dataController.currentUser else { return false }
        return user.role == .admin || user.role == .officeCrew
    }
    
    // Load team members for filtering
    private func loadTeamMembersIfNeeded() {
        guard shouldShowTeamMemberFilter,
              let dataController = dataController,
              let companyId = dataController.currentUser?.companyId,
              let company = dataController.getCompany(id: companyId) else {
            return
        }
        
        availableTeamMembers = company.teamMembers.sorted { $0.fullName < $1.fullName }
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
            
            // Explicitly trigger day sheet for month view user selections
            if userInitiated && self.viewMode == .month {
                self.shouldShowDaySheet = true
            }
        }
        
        
        selectedDate = date
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
        // Reset flags when changing view mode to prevent unwanted sheets
        userInitiatedDateSelection = false
        shouldShowDaySheet = false
        viewMode = viewMode == .week ? .month : .week
    }
    
    // Method to reset day sheet state after it's been shown
    func resetDaySheetState() {
        shouldShowDaySheet = false
    }
    
    // Navigation methods for months and weeks
    func navigateNextPeriod() {
        let calendar = Calendar.current
        
        // Reset any sheet-related flags
        shouldShowDaySheet = false
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
        
        // Reset any sheet-related flags
        shouldShowDaySheet = false
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
    
    // Get calendar events for a specific date (for border display)
    func calendarEvents(for date: Date) -> [CalendarEvent] {
        // If it's the currently selected date, return cached events
        if Calendar.current.isDate(date, inSameDayAs: selectedDate) {
            return calendarEventsForSelectedDate
        }
        
        // Otherwise fetch from DataController
        if let dataController = dataController {
            var events = dataController.getCalendarEventsForCurrentUser(for: date)
            
            // Apply comprehensive filters
            events = applyEventFilters(to: events)
            
            // Filter by shouldDisplay
            return events.filter { $0.shouldDisplay }
        }
        
        return []
    }
    
    func projectCount(for date: Date) -> Int {
        // If it's the currently selected date, we already have the data
        if Calendar.current.isDate(date, inSameDayAs: selectedDate) {
            return calendarEventsForSelectedDate.count
        }
        
        // Check the cache first
        let dateKey = formatDateKey(date)
        if let cachedCount = projectCountCache[dateKey] {
            return cachedCount
        }
        
        // For other dates, get the count from DataController
        if let dataController = dataController {
            // Get all calendar events active on this date
            var calendarEvents = dataController.getCalendarEventsForCurrentUser(for: date)
            
            // Apply comprehensive filters
            calendarEvents = applyEventFilters(to: calendarEvents)
            
            let count = calendarEvents.count
            
            // Cache the result
            projectCountCache[dateKey] = count
            return count
        }
        
        return 0
    }
    
    private func formatDateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    func clearProjectCountCache() {
        projectCountCache = [:]
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
    
    // Apply comprehensive filters
    func applyFilters(teamMemberIds: Set<String>, taskTypeIds: Set<String>, clientIds: Set<String>) {
        selectedTeamMemberIds = teamMemberIds
        selectedTaskTypeIds = taskTypeIds
        selectedClientIds = clientIds
        
        // Update legacy single selection for compatibility
        selectedTeamMemberId = teamMemberIds.first
        
        clearProjectCountCache()
        loadProjectsForDate(selectedDate)
    }
    
    // Check if any filters are active
    var hasActiveFilters: Bool {
        !selectedTeamMemberIds.isEmpty || !selectedTaskTypeIds.isEmpty || !selectedClientIds.isEmpty
    }
    
    // Count of active filters
    var activeFilterCount: Int {
        var count = 0
        if !selectedTeamMemberIds.isEmpty { count += 1 }
        if !selectedTaskTypeIds.isEmpty { count += 1 }
        if !selectedClientIds.isEmpty { count += 1 }
        return count
    }
    
    // Helper method to apply all filters to calendar events
    func applyEventFilters(to events: [CalendarEvent]) -> [CalendarEvent] {
        var filteredEvents = events
        
        // Apply team member filter
        if !selectedTeamMemberIds.isEmpty {
            filteredEvents = filteredEvents.filter { event in
                // Check event team members
                let hasInEvent = event.teamMembers.contains { selectedTeamMemberIds.contains($0.id) } ||
                    event.getTeamMemberIds().contains { selectedTeamMemberIds.contains($0) }
                
                // Check task team members
                let hasInTask = event.task?.teamMembers.contains { selectedTeamMemberIds.contains($0.id) } == true ||
                    event.task?.getTeamMemberIds().contains { selectedTeamMemberIds.contains($0) } == true
                
                // Check project team members
                let hasInProject = event.project?.teamMembers.contains { selectedTeamMemberIds.contains($0.id) } == true ||
                    event.project?.getTeamMemberIds().contains { selectedTeamMemberIds.contains($0) } == true
                
                return hasInEvent || hasInTask || hasInProject
            }
        }
        
        // Apply task type filter
        if !selectedTaskTypeIds.isEmpty {
            filteredEvents = filteredEvents.filter { event in
                // Check if event's task has a matching task type
                if let taskTypeId = event.task?.taskTypeId {
                    return selectedTaskTypeIds.contains(taskTypeId)
                }
                // For project events without tasks, include them if no task filter is applied
                // or exclude them if a specific task type filter is active
                return false
            }
        }
        
        // Apply client filter
        if !selectedClientIds.isEmpty {
            filteredEvents = filteredEvents.filter { event in
                // Check if event's project has a matching client
                if let clientId = event.project?.clientId {
                    return selectedClientIds.contains(clientId)
                }
                return false
            }
        }
        
        return filteredEvents
    }
    
    // Get filter summary text
    var filterSummaryText: String {
        var components: [String] = []
        
        if !selectedTeamMemberIds.isEmpty {
            components.append("\(selectedTeamMemberIds.count) team member\(selectedTeamMemberIds.count == 1 ? "" : "s")")
        }
        if !selectedTaskTypeIds.isEmpty {
            components.append("\(selectedTaskTypeIds.count) task type\(selectedTaskTypeIds.count == 1 ? "" : "s")")
        }
        if !selectedClientIds.isEmpty {
            components.append("\(selectedClientIds.count) client\(selectedClientIds.count == 1 ? "" : "s")")
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
        
        // First run the diagnostic if we're looking for Aug 17 or Aug 19
        let calendar = Calendar.current
        if calendar.component(.month, from: date) == 8 &&
            (calendar.component(.day, from: date) == 17 || calendar.component(.day, from: date) == 19) &&
            calendar.component(.year, from: date) == 2025 {
            dataController.diagnoseRailingsVinylProject()
        }
        
        // Get calendar events for the selected date
        var calendarEvents = dataController.getCalendarEventsForCurrentUser(for: date)
        
        // Commented out verbose event logging for performance
        /*
         // Debug the events we got with detailed shouldDisplay analysis
         for (index, event) in calendarEvents.enumerated() {
         }
         */
        
        // Apply comprehensive filters
        calendarEvents = applyEventFilters(to: calendarEvents)
        
        // Get unique projects from the calendar events
        let projectIds = Set(calendarEvents.compactMap { $0.projectId })
        
        var projects: [Project] = []
        for projectId in projectIds {
            if let project = dataController.getProject(id: projectId) {
                projects.append(project)
            } else {
            }
        }
        
        // Force UI update - Store IDs instead of models to avoid invalidation
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
            self?.calendarEventIdsForSelectedDate = calendarEvents.map { $0.id }
            self?.projectIdsForSelectedDate = projects.map { $0.id }
            self?.isLoading = false
        }
        
        // Update the cache for this date (based on calendar events now)
        let dateKey = formatDateKey(date)
        projectCountCache[dateKey] = calendarEvents.count
    }
    
    // Refresh projects from the data source
    @MainActor
    func refreshProjects() async {
        guard let dataController = dataController else {
            return
        }
        
        
        // Clear the cache to force fresh data
        projectCountCache.removeAll()
        
        // Sync with Bubble backend to get latest project data
        await dataController.refreshProjectsFromBackend()
        
        // Reload projects for the current selected date with fresh data
        loadProjectsForDate(selectedDate)
        
        for project in projectsForSelectedDate {
        }
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
