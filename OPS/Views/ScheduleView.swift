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
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                // User header
                UserHeader()
                
                // Calendar header
                CalendarHeaderView(viewModel: viewModel)
                
                // View toggle
                CalendarToggleView(viewModel: viewModel)
                
                // Day selector
                CalendarDaySelector(viewModel: viewModel)
                
                // Project list - passing appState properly
                ProjectListView(viewModel: viewModel)
                
                Spacer()
            }
            .padding(.top)
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
