//
//  ScheduleView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// ScheduleView.swift
import SwiftUI
import SwiftData

// Helper struct to hold task and project IDs together (not the models themselves)
struct TaskDetailInfo: Identifiable {
    let id = UUID()
    let taskId: String
    let projectId: String
}

struct ScheduleView: View {
    // This view no longer uses NavigationLink for project details
    // All project presentations are done via the sheet in ProjectSheetContainer
    // Notification observers for direct project and task list selection
    private let projectSelectionObserver = NotificationCenter.default
        .publisher(for: Notification.Name("ShowCalendarProjectDetails"))
    
    private let taskSelectionObserver = NotificationCenter.default
        .publisher(for: Notification.Name("ShowCalendarTaskDetails"))
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = CalendarViewModel()
    @State private var showDaySheet = false
    @State private var selectedProjectID: String? = nil
    @State private var selectedTaskDetail: TaskDetailInfo? = nil
    @State private var showSearchSheet = false
    @State private var showingRefreshAlert = false
    @State private var showFilterSheet = false
    @State private var showSyncMessage = false
    @State private var syncedProjectsCount = 0
    
    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with its own internal padding of 20
                    AppHeader(
                        headerType: .schedule,
                        onSearchTapped: {
                            showSearchSheet = true
                        },
                        onRefreshTapped: {
                            // Show indicator immediately
                            showingRefreshAlert = true

                            // Refresh projects in background
                            Task {
                                // Count projects before sync (respects field crew permissions)
                                let projectsBefore = dataController.getProjectsForCurrentUser()
                                let countBefore = projectsBefore.count

                                // Perform sync
                                await viewModel.refreshProjects()

                                // Count projects after sync
                                let projectsAfter = dataController.getProjectsForCurrentUser()
                                let countAfter = projectsAfter.count

                                // Calculate new projects count
                                let newProjectsCount = countAfter - countBefore

                                // Hide refresh indicator
                                await MainActor.run {
                                    showingRefreshAlert = false

                                    // Show sync message with count
                                    syncedProjectsCount = max(0, newProjectsCount) // Ensure non-negative
                                    showSyncMessage = true
                                }
                            }
                        },
                        onFilterTapped: {
                            showFilterSheet = true
                        },
                        hasActiveFilters: viewModel.hasActiveFilters,
                        filterCount: viewModel.activeFilterCount
                    )
                    .padding(.bottom, 8)
                
                VStack(spacing: 16) {
                    // View toggle
                    CalendarToggleView(viewModel: viewModel)
                    
                    // Day selector
                    CalendarDaySelector(viewModel: viewModel)
                    
                    // Project list - only shown in week view
                    if viewModel.viewMode == .week {
                        ProjectListView(viewModel: viewModel)
                    } else {
                        // Spacer for month view to push content up
                        //Spacer()
                    }
                    
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 90) // Add padding for tab bar
                //.frame(maxWidth: 50)
            }
            }
        }
        
       // .ignoresSafeArea(.keyboard)
        // Monitor viewMode changes to handle view transitions
        .onChange(of: viewModel.viewMode) { _, newMode in
            // Reset any project selection when switching view modes
            selectedProjectID = nil
        }
        // Observe the explicit shouldShowDaySheet flag
        .onChange(of: viewModel.shouldShowDaySheet) { _, shouldShow in
            if shouldShow {
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
        // Watch for calendar event changes and reload data
        .onChange(of: dataController.calendarEventsDidChange) { _, _ in
            viewModel.reloadCalendarData()
        }
        // Show day project sheet
        .sheet(isPresented: $showDaySheet, onDismiss: {
            // Deselect the day when sheet is dismissed (clear the outline)
            viewModel.shouldShowDaySheet = false
            viewModel.userInitiatedDateSelection = false

            // If we have a selected project ID, navigate to project details after day sheet is dismissed
            if selectedProjectID != nil {
                // Significant delay to ensure complete dismissal BEFORE showing project details
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    // First, update the appState to make sure we know we're in details mode
                    if let project = dataController.getProject(id: selectedProjectID!) {
                        // Display using the global sheet
                        appState.viewProjectDetails(project)
                    } else {
                    }
                }
            }
        }) {
            // Sheet displayed when selecting a day in month view
            DayEventsSheet(
                date: viewModel.selectedDate,
                calendarEvents: viewModel.calendarEventsForSelectedDate,
                onEventSelected: { event in
                    // All events are task events now
                    if let task = event.task {
                        // Show task details
                        let userInfo: [String: String] = [
                            "taskID": task.id,
                            "projectID": task.projectId
                        ]

                        // Dismiss sheet first
                        self.showDaySheet = false

                        // Post notification for task details after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            NotificationCenter.default.post(
                                name: Notification.Name("ShowCalendarTaskDetails"),
                                object: nil,
                                userInfo: userInfo
                            )
                        }
                    } else {
                        // Fallback: set the selected project ID and dismiss this sheet
                        self.selectedProjectID = event.projectId
                        self.showDaySheet = false
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        
        // Search sheet for finding projects
        .sheet(isPresented: $showSearchSheet) {
            ProjectSearchSheet(
                dataController: dataController,
                onProjectSelected: { project in
                    // Navigate to project details
                    showSearchSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        appState.viewProjectDetails(project)
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(false)
        }
        
        
        // We're using navigation instead of a sheet
        // Handle direct project selection from the project list
        .onReceive(projectSelectionObserver) { notification in
            if let projectID = notification.userInfo?["projectID"] as? String {
                
                // Set the project ID
                self.selectedProjectID = projectID
                
                // Get the project and present it via the sheet
                if let project = dataController.getProject(id: projectID) {
                    // Just use viewProjectDetails which handles all the necessary state updates
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        appState.viewProjectDetails(project)
                    }
                } else {
                }
            } else {
            }
        }
        // Handle direct task selection from the calendar
        .onReceive(taskSelectionObserver) { notification in
            if let taskID = notification.userInfo?["taskID"] as? String,
               let projectID = notification.userInfo?["projectID"] as? String {
                
                
                // Create the task detail info with just IDs
                let taskDetail = TaskDetailInfo(taskId: taskID, projectId: projectID)
                // Set it to trigger the sheet
                self.selectedTaskDetail = taskDetail
            } else {
            }
        }
        // Add task details sheet using item binding
        .sheet(item: $selectedTaskDetail) { taskDetail in
            // Fetch fresh models using IDs
            if let project = dataController.getProject(id: taskDetail.projectId),
               let task = project.tasks.first(where: { $0.id == taskDetail.taskId }) {
                TaskDetailsView(task: task, project: project)
                    .environmentObject(dataController)
                    .environmentObject(appState)
                    .environment(\.modelContext, dataController.modelContext!)
            } else {
                Text("Task no longer available")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        // Add refresh indicator
        .refreshIndicator(isPresented: $showingRefreshAlert)

        // Add sync message with fetch count
        .overlay(
            PushInMessage(
                isPresented: $showSyncMessage,
                title: "[ \(syncedProjectsCount) NEW PROJECT\(syncedProjectsCount == 1 ? "" : "S") LOADED ]",
                subtitle: nil,
                type: .info,
                autoDismissAfter: 4.0
            )
            .ignoresSafeArea(edges: .top)
            .zIndex(1000)
        )

        // Filter sheet
        .sheet(isPresented: $showFilterSheet) {
            CalendarFilterView(viewModel: viewModel)
                .environmentObject(dataController)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
