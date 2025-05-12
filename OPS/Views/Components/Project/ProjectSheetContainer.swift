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
    
    var body: some View {
        // Using item presentation pattern instead of isPresented
        // This approach is more reliable for presenting sheets based on optional values
        ZStack {
            Color.clear // Empty view that doesn't affect layout
        }
        // Project details sheet - uses isPresented and item together for more reliable presentation
        .sheet(isPresented: $appState.showProjectDetails, onDismiss: {
            print("ProjectSheetContainer: Sheet dismissed via isPresented")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appState.dismissProjectDetails()
            }
        }) {
            if let project = appState.activeProject {
                NavigationView {
                    ProjectDetailsView(project: project)
                }
                .interactiveDismissDisabled(false)
            } else {
                // Fallback if project isn't available (should rarely happen)
                VStack {
                    Text("Loading project details...")
                    ProgressView()
                }
                .onAppear {
                    print("⚠️ ProjectSheetContainer: Tried to show details but project is nil")
                    
                    // Only auto-dismiss if we don't have an active project ID
                    if appState.activeProjectID == nil {
                        print("ProjectSheetContainer: No active project ID, will auto-dismiss")
                        // Auto-dismiss after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            appState.dismissProjectDetails()
                        }
                    } else {
                        print("ProjectSheetContainer: Have active project ID but nil project: \(appState.activeProjectID!)")
                        // Try to fetch project one more time
                        if let projectID = appState.activeProjectID,
                           let project = dataController.getProject(id: projectID) {
                            print("ProjectSheetContainer: Successfully fetched project on second try")
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
        
        // Debug output to track active project changes
        .onChange(of: appState.activeProject) { _, newProject in
            if let project = newProject {
                print("ProjectSheetContainer: activeProject changed to \(project.id) - showing details")
            } else {
                print("ProjectSheetContainer: activeProject cleared")
            }
        }
    }
}
