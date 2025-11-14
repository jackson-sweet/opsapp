//
//  ProjectSheetContainer.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-04.
//

import SwiftUI

struct ProjectSheetContainer: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @State private var selectedTaskDetail: TaskDetailInfo? = nil
    
    var body: some View {
        // Using item presentation pattern instead of isPresented
        // This approach is more reliable for presenting sheets based on optional values
        ZStack {
            Color.clear // Empty view that doesn't affect layout
        }
        // Project details sheet - uses isPresented and item together for more reliable presentation
        .sheet(isPresented: $appState.showProjectDetails) {
            if let projectID = appState.activeProjectID,
               let project = dataController.getProject(id: projectID) {
                NavigationView {
                    ProjectDetailsView(project: project)
                        .onAppear {
                        }
                }
                .interactiveDismissDisabled(false)
            } else {
                // Fallback if project isn't available (should rarely happen)
                VStack {
                    Text("Loading project details...")
                    ProgressView()
                }
                .onAppear {
                    
                    // Only auto-dismiss if we don't have an active project ID
                    if appState.activeProjectID == nil {
                        // Auto-dismiss after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            appState.dismissProjectDetails()
                        }
                    } else {
                        // Try to fetch project one more time
                        if let projectID = appState.activeProjectID,
                           let _ = dataController.getProject(id: projectID) {
                            // Project exists, just wait for refresh
                            DispatchQueue.main.async {
                                // Force a refresh of the sheet
                                appState.objectWillChange.send()
                            }
                        } else {
                            // Only dismiss if we still can't find the project
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                appState.dismissProjectDetails()
                            }
                        }
                    }
                }
            }
        }
        // Task details sheet
        .sheet(item: $selectedTaskDetail) { taskDetail in
            // Fetch fresh models using IDs
            if let project = dataController.getProject(id: taskDetail.projectId),
               let task = project.tasks.first(where: { $0.id == taskDetail.taskId }) {
                NavigationView {
                    TaskDetailsView(task: task, project: project)
                        .environmentObject(dataController)
                        .environmentObject(appState)
                        .onAppear {
                        }
                }
                .interactiveDismissDisabled(false)
            } else {
                VStack {
                    Text("Task no longer available")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        // Listen for task details from home
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowTaskDetailsFromHome"))) { notification in
            if let userInfo = notification.userInfo,
               let taskID = userInfo["taskID"] as? String,
               let projectID = userInfo["projectID"] as? String {
                
                // Show task details with just IDs
                selectedTaskDetail = TaskDetailInfo(taskId: taskID, projectId: projectID)
            }
        }
        // Debug output to track active project ID changes
        .onChange(of: appState.activeProjectID) { _, newProjectID in
            if let projectID = newProjectID {
            } else {
            }
        }
    }
}
