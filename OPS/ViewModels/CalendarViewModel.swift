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
    @Published var projectsForSelectedDate: [Project] = []  // Keep for project detail data
    @Published var calendarEventsForSelectedDate: [CalendarEvent] = []  // Primary display data
    @Published var isLoading = false
    @Published var userInitiatedDateSelection = false
    @Published var shouldShowDaySheet = false // New published property for explicit control
    @Published var selectedTeamMemberId: String? = nil
    @Published var availableTeamMembers: [TeamMember] = []
    
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
                
                // Apply team member filter if selected
                if let selectedMemberId = selectedTeamMemberId {
                    calendarEvents = calendarEvents.filter { event in
                        event.getTeamMemberIds().contains(selectedMemberId) ||
                        event.teamMembers.contains(where: { $0.id == selectedMemberId })
                    }
                }
                
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
        
        // Update selected team member filter
        func updateTeamMemberFilter(_ memberId: String?) {
            selectedTeamMemberId = memberId
            clearProjectCountCache()
            loadProjectsForDate(selectedDate)
        }
    
    
    
    // MARK: - Private Methods
    func loadProjectsForDate(_ date: Date) {
        guard let dataController = dataController else { 
            print("❌ loadProjectsForDate: No dataController")
            return 
        }
        
        print("📅 Loading calendar events and projects for date: \(date)")
        isLoading = true
        
        // Get calendar events for the selected date
        var calendarEvents = dataController.getCalendarEventsForCurrentUser(for: date)
        print("📆 Found \(calendarEvents.count) calendar events from dataController")
        
        // Apply team member filter if selected
        if let selectedMemberId = selectedTeamMemberId {
            print("👤 Applying team member filter for: \(selectedMemberId)")
            calendarEvents = calendarEvents.filter { event in
                event.getTeamMemberIds().contains(selectedMemberId) ||
                event.teamMembers.contains(where: { $0.id == selectedMemberId })
            }
            print("📆 After filter: \(calendarEvents.count) calendar events")
        }
        
        // Get unique projects from the calendar events
        let projectIds = Set(calendarEvents.compactMap { $0.projectId })
        var projects: [Project] = []
        for projectId in projectIds {
            if let project = dataController.getProject(id: projectId) {
                projects.append(project)
            }
        }
        print("📊 Found \(projects.count) unique projects from calendar events")
        
        // Force UI update
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
            self?.calendarEventsForSelectedDate = calendarEvents
            self?.projectsForSelectedDate = projects
            self?.isLoading = false
        }
        
        // Update the cache for this date (based on calendar events now)
        let dateKey = formatDateKey(date)
        projectCountCache[dateKey] = calendarEvents.count
        print("💾 Updated cache for \(dateKey): \(calendarEvents.count) calendar events")
        print("🔄 UI update triggered")
    }
    
    // Refresh projects from the data source
    @MainActor
    func refreshProjects() async {
        guard let dataController = dataController else { 
            print("❌ Refresh failed: No dataController")
            return 
        }
        
        print("🔄 Starting project refresh...")
        print("📅 Current selected date: \(selectedDate)")
        
        // Clear the cache to force fresh data
        projectCountCache.removeAll()
        print("🗑️ Cleared project cache")
        
        // Sync with Bubble backend to get latest project data
        print("🌐 Fetching latest data from Bubble...")
        await dataController.refreshProjectsFromBackend()
        
        // Reload projects for the current selected date with fresh data
        loadProjectsForDate(selectedDate)
        
        print("✅ Refresh complete. Found \(projectsForSelectedDate.count) projects")
        for project in projectsForSelectedDate {
            print("  📋 Project: \(project.title) - Status: \(project.status.displayName)")
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

