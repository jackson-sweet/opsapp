//
//  ScheduleView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// ScheduleView.swift
import SwiftUI
import SwiftData

struct ScheduleView: View {
    // This view no longer uses NavigationLink for project details
    // All project presentations are done via the sheet in ProjectSheetContainer
    // Notification observer for direct project list selection
    private let projectSelectionObserver = NotificationCenter.default
        .publisher(for: Notification.Name("ShowCalendarProjectDetails"))
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = CalendarViewModel()
    @State private var showDaySheet = false
    @State private var selectedProjectID: String? = nil
    
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
            
            // No more NavigationLink - we'll use the global sheet instead
        }
        // Monitor viewMode changes to handle view transitions
        .onChange(of: viewModel.viewMode) { _, newMode in
            print("ScheduleView: View mode changed to \(newMode)")
            // Reset any project selection when switching view modes
            selectedProjectID = nil
        }
        // Observe the explicit shouldShowDaySheet flag
        .onChange(of: viewModel.shouldShowDaySheet) { _, shouldShow in
            if shouldShow {
                print("ScheduleView: Showing day sheet based on viewModel flag")
                // Show the sheet
                DispatchQueue.main.async {
                    showDaySheet = true
                    // Reset the flag after showing
                    viewModel.resetDaySheetState()
                }
            }
        }
        // Initialize on appear
        .onAppear {
            // Initialize with proper data controller
            viewModel.setDataController(dataController)
        }
        // Show day project sheet
        .sheet(isPresented: $showDaySheet, onDismiss: {
            print("ScheduleView: Day sheet dismissed, selectedProjectID = \(selectedProjectID ?? "nil")")
            print("ScheduleView: userInitiatedDateSelection = \(viewModel.userInitiatedDateSelection), shouldShowDaySheet = \(viewModel.shouldShowDaySheet)")
            // If we have a selected project ID, navigate to project details after day sheet is dismissed
            if selectedProjectID != nil {
                print("ScheduleView: Will navigate to project details after dismissal")
                // Significant delay to ensure complete dismissal BEFORE showing project details
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    print("ScheduleView: NOW showing project details")
                    // First, update the appState to make sure we know we're in details mode
                    if let project = dataController.getProject(id: selectedProjectID!) {
                        print("ScheduleView: Found project, showing via sheet")
                        // Display using the global sheet
                        appState.viewProjectDetails(project)
                    } else {
                        print("ScheduleView: Project not found, cannot show details")
                    }
                }
            }
        }) {
            // Sheet displayed when selecting a day in month view
            DayProjectSheet(
                date: viewModel.selectedDate,
                projects: viewModel.projectsForSelectedDate,
                onProjectSelected: { project in
                    // Set the selected project ID and dismiss this sheet
                    print("ScheduleView: Selected project from day sheet: \(project.title)")
                    self.selectedProjectID = project.id
                    self.showDaySheet = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        
        // We're using navigation instead of a sheet
        // Handle direct project selection from the project list
        .onReceive(projectSelectionObserver) { notification in
            if let projectID = notification.userInfo?["projectID"] as? String {
                print("ScheduleView: Received notification to show project with ID: \(projectID)")
                
                // Set the project ID
                self.selectedProjectID = projectID
                
                // Get the project and present it via the sheet
                if let project = dataController.getProject(id: projectID) {
                    print("ScheduleView: Found project from notification, showing via sheet")
                    // Just use viewProjectDetails which handles all the necessary state updates
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        appState.viewProjectDetails(project)
                    }
                } else {
                    print("ScheduleView: Project not found, cannot show details")
                }
            } else {
                print("ScheduleView: ⚠️ ERROR - Notification did not contain a projectID")
            }
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
