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
        if Calendar.current.isDate(date, inSameDayAs: selectedDate) {
            return projectsForSelectedDate.count
        }
        return 0 // For simplicity; could be enhanced to show actual counts
    }
    
    // MARK: - Private Methods
    func loadProjectsForDate(_ date: Date) {
        guard let dataController = dataController, let context = dataController.modelContext else {
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: date)
                
                // Fetch all projects for now - we'll filter in memory for simplicity
                let descriptor = FetchDescriptor<Project>()
                let projects = try context.fetch(descriptor)
                
                // Filter projects for the selected date
                let filteredProjects = projects.filter { project in
                    guard let projectDate = project.startDate else { return false }
                    return calendar.isDate(projectDate, inSameDayAs: date)
                }
                
                await MainActor.run {
                    self.projectsForSelectedDate = filteredProjects
                    self.isLoading = false
                }
            } catch {
                print("Error fetching projects: \(error.localizedDescription)")
                
                await MainActor.run {
                    self.projectsForSelectedDate = []
                    self.isLoading = false
                }
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
