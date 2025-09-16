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
        .sheet(isPresented: $appState.showProjectDetails, onDismiss: {
            // print("📋 ProjectSheetContainer: Project details sheet dismissed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appState.dismissProjectDetails()
            }
        }) {
            if let project = appState.activeProject {
                NavigationView {
                    ProjectDetailsView(project: project)
                        .onAppear {
                            // print("📋 ProjectSheetContainer: Showing PROJECT details for: \(project.title)")
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
                           let project = dataController.getProject(id: projectID) {
                            DispatchQueue.main.async {
                                appState.activeProject = project
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
            NavigationView {
                TaskDetailsView(task: taskDetail.task, project: taskDetail.project)
                    .environmentObject(dataController)
                    .environmentObject(appState)
                    .onAppear {
                        // print("📋 ProjectSheetContainer: Showing TASK details for: \(taskDetail.task.displayTitle)")
                    }
            }
            .interactiveDismissDisabled(false)
        }
        // Listen for task details from home
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowTaskDetailsFromHome"))) { notification in
            if let userInfo = notification.userInfo,
               let taskID = userInfo["taskID"] as? String,
               let projectID = userInfo["projectID"] as? String {
                
                // Find the project and task
                if let project = dataController.getProject(id: projectID),
                   let task = project.tasks.first(where: { $0.id == taskID }) {
                    // Show task details
                    selectedTaskDetail = TaskDetailInfo(task: task, project: project)
                }
            }
        }
        // Debug output to track active project changes
        .onChange(of: appState.activeProject) { _, newProject in
            if let project = newProject {
            } else {
            }
        }
    }
}
