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
    @State private var showSearchSheet = false
    @State private var showingRefreshAlert = false
    
    // Get the display text for team member filter
    private var teamMemberFilterText: String {
        if let memberId = viewModel.selectedTeamMemberId,
           let member = viewModel.availableTeamMembers.first(where: { $0.id == memberId }) {
            return member.fullName
        }
        return "All Team Members"
    }
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                // Header without gradient
                AppHeader(
                    headerType: .schedule,
                    onSearchTapped: {
                        showSearchSheet = true
                    },
                    onRefreshTapped: {
                        print("🔘 Refresh button tapped!")
                        // Show indicator immediately
                        showingRefreshAlert = true
                        
                        // Refresh projects in background
                        Task {
                            print("🚀 Starting refresh task...")
                            await viewModel.refreshProjects()
                            print("🏁 Refresh task completed")
                            // Indicator will auto-dismiss after showing success
                        }
                    }
                )
                
                // Calendar header
                CalendarHeaderView(viewModel: viewModel)
                
                // Team member filter (only for admin/office crew)
                if viewModel.shouldShowTeamMemberFilter {
                    HStack {
                        Text("Filter by Team Member:")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Spacer()
                        
                        Menu {
                            Button(action: {
                                viewModel.updateTeamMemberFilter(nil)
                            }) {
                                Text("All Team Members")
                            }
                            
                            Divider()
                            
                            ForEach(viewModel.availableTeamMembers, id: \.id) { member in
                                Button(action: {
                                    viewModel.updateTeamMemberFilter(member.id)
                                }) {
                                    Text(member.fullName)
                                }
                            }
                        } label: {
                            HStack {
                                Text(teamMemberFilterText)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .lineLimit(1)
                                
                                Image(systemName: "chevron.down")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(OPSStyle.Colors.cardBackground)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
            
                    }
                    .padding(.horizontal)
                }
                
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
            .padding(.bottom, 90) // Add padding for tab bar
            
            // No more NavigationLink - we'll use the global sheet instead
        }
        .ignoresSafeArea(.keyboard)
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
        // Show day project sheet
        .sheet(isPresented: $showDaySheet, onDismiss: {
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
            DayProjectSheet(
                date: viewModel.selectedDate,
                projects: viewModel.projectsForSelectedDate,
                onProjectSelected: { project in
                    // Set the selected project ID and dismiss this sheet
                    self.selectedProjectID = project.id
                    self.showDaySheet = false
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
                print("ScheduleView: ⚠️ ERROR - Notification did not contain a projectID")
            }
        }
        // Add refresh indicator
        .refreshIndicator(isPresented: $showingRefreshAlert)
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
