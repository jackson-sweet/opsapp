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
    
    // Flag to control whether to show the project details
    var showProjectDetails: Bool = false
    
    // Function to set a project for viewing details (called on long press)
    func viewProjectDetails(_ project: Project) {
        print("AppState: Setting up project for details view: \(project.id) - DETAILS ONLY MODE")
        // Set flag to indicate we're just viewing details, not starting project
        self.isViewingDetailsOnly = true
        self.showProjectDetails = true
        self.setActiveProject(project)
    }
    
    func setActiveProject(_ project: Project) {
        print("AppState: Setting activeProject to \(project.id) - \(project.title), showProjectDetails=\(showProjectDetails)")
        self.activeProjectID = project.id
        
        // Only set activeProject (which triggers sheet) if showProjectDetails is true
        if showProjectDetails {
            self.activeProject = project
            print("AppState: ProjectDetailsView will be shown")
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