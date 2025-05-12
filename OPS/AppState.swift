//
//  AppState.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// AppState.swift
import Foundation
import Combine
import SwiftUI
import SwiftData

class AppState: ObservableObject {
    @Published var activeProjectID: String?
    @Published var activeProject: Project?
    
    // New flag to differentiate between showing details and starting project
    @Published var isViewingDetailsOnly: Bool = false
    
    var isInProjectMode: Bool {
        // Only consider in project mode if we're not just viewing details
        activeProjectID != nil && !isViewingDetailsOnly
    }
    
    func enterProjectMode(projectID: String) {
        print("AppState: Setting activeProjectID to \(projectID) - STARTING PROJECT")
        self.isViewingDetailsOnly = false // Make sure we're in project mode
        self.activeProjectID = projectID
        
        // When using this function directly, we need to make sure
        // the DataController retrieves the project
        NotificationCenter.default.post(
            name: Notification.Name("FetchActiveProject"),
            object: nil,
            userInfo: ["projectID": projectID]
        )
    }
    
    // Flag to control whether to show the project details - published so it can be observed
    @Published var showProjectDetails: Bool = false
    
    // Function to set a project for viewing details
    func viewProjectDetails(_ project: Project) {
        print("AppState: Setting up project for details view: \(project.id) - DETAILS ONLY MODE")
        
        // IMPORTANT: Make sure we're not already showing this project to avoid sheet flicker
        if self.showProjectDetails && self.activeProject?.id == project.id {
            print("AppState: Already showing this project, not resetting the sheet")
            return
        }
        
        // Step 1: Reset sheet state if needed to avoid transition conflicts
        if self.showProjectDetails {
            print("AppState: Sheet is already showing, resetting state first")
            self.showProjectDetails = false
            self.activeProject = nil
            
            // Use a delay before showing the new project to allow animation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showProjectDetailsAfterReset(project)
            }
            return
        }
        
        // Normal case - no sheet is currently showing
        self.showProjectDetailsAfterReset(project)
    }
    
    // Helper method to show project details after any needed reset
    private func showProjectDetailsAfterReset(_ project: Project) {
        print("AppState: Setting up project after reset: \(project.id)")
        
        // First set flags before setting the project to ensure proper order
        self.isViewingDetailsOnly = true
        
        // Set active project ID and project object BEFORE showing the sheet
        self.activeProjectID = project.id
        self.activeProject = project
        
        // Use a very short delay to ensure UI updates properly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("AppState: Now setting showProjectDetails=true with activeProject=\(String(describing: self.activeProject?.id))")
            self.showProjectDetails = true
        }
    }
    
    func setActiveProject(_ project: Project) {
        print("AppState: Setting activeProject to \(project.id) - \(project.title), showProjectDetails=\(showProjectDetails)")
        self.activeProjectID = project.id
        
        // Only set activeProject (which triggers sheet) if showProjectDetails is true
        if showProjectDetails {
            print("AppState: ProjectDetailsView will be shown - setting activeProject")
            self.activeProject = project
        } else {
            // Don't set activeProject, only set ID - prevents sheet from showing
            print("AppState: ProjectDetailsView will NOT be shown (details disabled)")
            self.activeProject = nil
        }
    }
    
    func exitProjectMode() {
        print("AppState: Clearing activeProject and activeProjectID")
        self.showProjectDetails = false // Reset the details flag
        self.isViewingDetailsOnly = false // Reset viewing details flag
        self.activeProject = nil
        self.activeProjectID = nil
    }
    
    // Helper method to dismiss project details without exiting project mode
    func dismissProjectDetails() {
        print("AppState: Dismissing project details")
        self.showProjectDetails = false
        
        // If we were just viewing details, clear the project ID to exit "details" mode
        if isViewingDetailsOnly {
            print("AppState: Was in details-only mode, clearing project ID")
            self.isViewingDetailsOnly = false
            self.activeProjectID = nil
            self.activeProject = nil
        } else {
            // Otherwise, just close the sheet while keeping active project
            self.activeProject = nil
        }
    }
}