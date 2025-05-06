//
//  ScheduleView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// ScheduleView.swift
import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = CalendarViewModel()
    @State private var showDaySheet = false
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                // Header without gradient
                AppHeader(headerType: .schedule)
                
                // Calendar header
                CalendarHeaderView(viewModel: viewModel)
                
                // View toggle
                CalendarToggleView(viewModel: viewModel)
                
                // Day selector
                CalendarDaySelector(viewModel: viewModel)
                
                // Project list - only shown in week view
                if viewModel.viewMode == .week {
                    ProjectListView(viewModel: viewModel)
                } else {
                    // Spacer for month view to push content up
                    Spacer()
                }
                
                Spacer()
            }
            .padding(.top)
            
            // Add the ProjectSheetContainer to enable project details display
            ProjectSheetContainer()
        }
        .onChange(of: viewModel.selectedDate) { oldDate, newDate in
            // Show sheet when day selected in month view
            if viewModel.viewMode == .month && !DateHelper.isSameDay(oldDate, newDate) {
                showDaySheet = true
            }
        }
        .sheet(isPresented: $showDaySheet) {
            // Sheet displayed when selecting a day in month view
            DayProjectSheet(
                date: viewModel.selectedDate,
                projects: viewModel.projectsForSelectedDate
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            // Initialize with proper data controller
            viewModel.setDataController(dataController)
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
