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
        
        // IMPORTANT: Make sure we're not already showing this project to avoid sheet flicker
        if self.showProjectDetails && self.activeProject?.id == project.id {
            return
        }
        
        // Step 1: Reset sheet state if needed to avoid transition conflicts
        if self.showProjectDetails {
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
        
        // Check if we're already in project mode for this project
        let wasInProjectMode = self.activeProjectID == project.id && !self.isViewingDetailsOnly
        
        // Check if we're in project mode for a different project
        let isInProjectModeForDifferentProject = self.activeProjectID != nil && 
                                                 self.activeProjectID != project.id && 
                                                 !self.isViewingDetailsOnly
        
        // If we're in project mode for a different project, don't change activeProjectID
        if isInProjectModeForDifferentProject {
            // Just show the details without changing the active project
            self.activeProject = project
            self.showProjectDetails = true
            return
        }
        
        // Only set isViewingDetailsOnly if we're not already in project mode for this project
        if !wasInProjectMode {
            self.isViewingDetailsOnly = true
        }
        
        // Set active project ID and project object BEFORE showing the sheet
        self.activeProjectID = project.id
        self.activeProject = project
        
        // Use a very short delay to ensure UI updates properly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.showProjectDetails = true
        }
    }
    
    func setActiveProject(_ project: Project) {
        self.activeProjectID = project.id
        
        // Only set activeProject (which triggers sheet) if showProjectDetails is true
        if showProjectDetails {
            self.activeProject = project
        } else {
            // Don't set activeProject, only set ID - prevents sheet from showing
            self.activeProject = nil
        }
    }
    
    func exitProjectMode() {
        self.showProjectDetails = false // Reset the details flag
        self.isViewingDetailsOnly = false // Reset viewing details flag
        self.activeProject = nil
        self.activeProjectID = nil
    }
    
    // Helper method to dismiss project details without exiting project mode
    func dismissProjectDetails() {
        self.showProjectDetails = false
        
        // Store the current active project ID if we're in project mode
        let currentActiveProjectID = self.isInProjectMode ? self.activeProjectID : nil
        
        // Clear the displayed project
        self.activeProject = nil
        
        // If we were just viewing details and there's no active project mode, clear everything
        if isViewingDetailsOnly && currentActiveProjectID == nil {
            self.isViewingDetailsOnly = false
            self.activeProjectID = nil
        }
        // If we were viewing details of a different project while in project mode, restore the active project
        else if currentActiveProjectID != nil && self.activeProjectID != currentActiveProjectID {
            self.activeProjectID = currentActiveProjectID
            self.isViewingDetailsOnly = false
        }
        // If we were viewing details of the same project we're working on, keep project mode
        else if !isViewingDetailsOnly {
            // Keep activeProjectID as is - we're still in project mode
        }
    }
}