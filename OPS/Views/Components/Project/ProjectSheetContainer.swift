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
        // Re-enable sheet, but now it will only show when appState.activeProject is set AND
        // appState.showProjectDetails is true (controlled by AppState.setActiveProject)
        .sheet(item: $appState.activeProject) { project in
            NavigationView {
                ProjectDetailsView(project: project)
            }
            .interactiveDismissDisabled(false)
            .onDisappear {
                print("ProjectSheetContainer: Sheet dismissed")
                // Don't exit project mode when details are dismissed - just close the sheet
                // This allows us to view details for active projects without stopping them
                appState.dismissProjectDetails()
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