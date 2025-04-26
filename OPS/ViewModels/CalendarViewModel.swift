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
    @Published var projectsForSelectedDate: [Project] = []
    @Published var isLoading = false
    
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
        loadProjectsForDate(selectedDate)
    }
    
    func selectDate(_ date: Date) {
            let calendar = Calendar.current
            let oldMonth = calendar.component(.month, from: selectedDate)
            let newMonth = calendar.component(.month, from: date)
            
            // If month changed, clear the cache
            if oldMonth != newMonth {
                clearProjectCountCache()
            }
            
            selectedDate = date
            loadProjectsForDate(date)
        }
    
    func toggleViewMode() {
        viewMode = viewMode == .week ? .month : .week
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
                return projectsForSelectedDate.count
            }
            
            // Check the cache first
            let dateKey = formatDateKey(date)
            if let cachedCount = projectCountCache[dateKey] {
                return cachedCount
            }
            
            // For other dates, get the count from DataController
            if let dataController = dataController {
                let count = dataController.getProjects(for: date).count
                
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
    
    
    
    // MARK: - Private Methods
    func loadProjectsForDate(_ date: Date) {
            guard let dataController = dataController else { return }
            
            isLoading = true
            
            Task {
                // Get projects using the centralized method in DataController
                // This ensures we get the same data across the entire app
                let projects = dataController.getProjects(for: date)
                
                await MainActor.run {
                    self.projectsForSelectedDate = projects
                    self.isLoading = false
                }
            }
        }
    
    private func getWeekDays() -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Get the start of the week containing today
        let weekStart = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        let startOfWeek = calendar.date(from: weekStart)!
        
        // Generate an array of the 7 days of the week
        return (0..<7).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: startOfWeek)
        }
    }
    
    private func getMonthDays() -> [Date] {
            let calendar = Calendar.current
            let selectedMonth = calendar.dateComponents([.year, .month], from: selectedDate)
            guard let startOfMonth = calendar.date(from: selectedMonth) else { return [] }
            
            // Get first day of the month
            let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: startOfMonth))!
            
            // Get the weekday of the first day (1 = Sunday, 2 = Monday, etc.)
            let firstWeekday = calendar.component(.weekday, from: firstDay)
            
            // Calculate offset to start grid with appropriate weekday
            // Adjust by subtracting 1 to align with 0-based indexing
            let weekdayOffset = firstWeekday - 1
            
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

