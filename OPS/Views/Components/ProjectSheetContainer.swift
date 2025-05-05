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
    @State private var selectedProject: Project?
    @State private var showProjectDetails: Bool = false
    
    var body: some View {
        ZStack {
            // Empty view that monitors the appState for changes
            Color.clear
                .onChange(of: appState.activeProjectID) { _, newProjectID in
                    if let projectID = newProjectID {
                        // Find the project in the data controller
                        if let project = dataController.getProject(id: projectID) {
                            selectedProject = project
                            showProjectDetails = true
                        } else {
                            print("ProjectSheetContainer: Could not find project with ID: \(projectID)")
                            // Reset app state if project not found
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                appState.exitProjectMode()
                            }
                        }
                    } else {
                        // When activeProjectID is set to nil
                        showProjectDetails = false
                    }
                }
        }
        .sheet(isPresented: $showProjectDetails, onDismiss: {
            // Reset the app state when sheet is dismissed
            appState.exitProjectMode()
        }) {
            if let project = selectedProject {
                NavigationView {
                    ProjectDetailsView(project: project)
                }
                .interactiveDismissDisabled(false)
            }
        }
    }
}