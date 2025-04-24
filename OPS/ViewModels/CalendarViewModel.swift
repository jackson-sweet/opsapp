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
    
    func projectCount(for date: Date) -> Int {
            // If it's the currently selected date, we already have the data
            if Calendar.current.isDate(date, inSameDayAs: selectedDate) {
                return projectsForSelectedDate.count
            }
            
            // For other dates, get the count from DataController
            // We could add caching here if performance becomes an issue
            if let dataController = dataController {
                return dataController.getProjects(for: date).count
            }
            
            return 0
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
        var weekStart = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        let startOfWeek = calendar.date(from: weekStart)!
        
        // Generate an array of the 7 days of the week
        return (0..<7).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: startOfWeek)
        }
    }
    
    private func getMonthDays() -> [Date] {
        let calendar = Calendar.current
        
        // Get the start date of the month containing the selected date
        let selectedMonth = calendar.dateComponents([.year, .month], from: selectedDate)
        guard let startOfMonth = calendar.date(from: selectedMonth) else { return [] }
        
        // Get the range of days in the month
        guard let range = calendar.range(of: .day, in: .month, for: selectedDate) else { return [] }
        
        // Create a date for each day in the month
        return range.compactMap { day in
            calendar.date(bySetting: .day, value: day, of: startOfMonth)
        }
    }
}
