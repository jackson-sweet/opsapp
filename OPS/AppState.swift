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
    @Published var activeTaskID: String? // Store only task ID, not the model

    // New flag to differentiate between showing details and starting project
    @Published var isViewingDetailsOnly: Bool = false

    // Track when home view is loading projects
    @Published var isLoadingProjects: Bool = false

    // Tutorial restart flag - when true, ContentView should show the tutorial
    @Published var shouldRestartTutorial: Bool = false

    // MARK: - Centralized Project Completion Cascade
    // These properties allow any view to trigger the completion checklist sheet
    @Published var projectPendingCompletion: Project?
    @Published var showingGlobalCompletionChecklist: Bool = false

    /// Centralized function to request project completion.
    /// Call this BEFORE updating project status to .completed.
    /// Returns true if completion can proceed directly, false if checklist sheet will be shown.
    @discardableResult
    func requestProjectCompletion(_ project: Project) -> Bool {
        // Check for incomplete tasks (excluding cancelled)
        let incompleteTasks = project.tasks.filter { $0.status != .completed && $0.status != .cancelled }

        if !incompleteTasks.isEmpty {
            // Has incomplete tasks - show checklist sheet
            print("[PROJECT_COMPLETION] 📋 Project '\(project.title)' has \(incompleteTasks.count) incomplete task(s) - showing checklist")
            self.projectPendingCompletion = project
            self.showingGlobalCompletionChecklist = true
            return false
        }

        // No incomplete tasks - can complete directly
        print("[PROJECT_COMPLETION] ✅ Project '\(project.title)' has no incomplete tasks - can complete directly")
        return true
    }

    /// Clear the completion request (called after sheet is dismissed or completion is done)
    func clearCompletionRequest() {
        self.projectPendingCompletion = nil
        self.showingGlobalCompletionChecklist = false
    }
    
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
        viewProjectDetailsById(project.id)
    }
    
    func viewProjectDetailsById(_ projectId: String) {
        // IMPORTANT: Make sure we're not already showing this project to avoid sheet flicker
        if self.showProjectDetails && self.activeProjectID == projectId {
            return
        }
        
        // Step 1: Reset sheet state if needed to avoid transition conflicts
        if self.showProjectDetails {
            self.showProjectDetails = false
            
            // Use a delay before showing the new project to allow animation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showProjectDetailsAfterResetById(projectId)
            }
            return
        }
        
        // Normal case - no sheet is currently showing
        self.showProjectDetailsAfterResetById(projectId)
    }
    
    // Helper method to show project details after any needed reset
    private func showProjectDetailsAfterResetById(_ projectId: String) {
        
        // Check if we're already in project mode for this project
        let wasInProjectMode = self.activeProjectID == projectId && !self.isViewingDetailsOnly
        
        // Check if we're in project mode for a different project
        let isInProjectModeForDifferentProject = self.activeProjectID != nil && 
                                                 self.activeProjectID != projectId && 
                                                 !self.isViewingDetailsOnly
        
        // If we're in project mode for a different project, don't change activeProjectID
        if isInProjectModeForDifferentProject {
            // Just show the details without changing the active project
            self.activeProjectID = projectId
            self.showProjectDetails = true
            return
        }
        
        // Only set isViewingDetailsOnly if we're not already in project mode for this project
        if !wasInProjectMode {
            self.isViewingDetailsOnly = true
        }
        
        // Set active project ID BEFORE showing the sheet
        self.activeProjectID = projectId
        
        // Use a very short delay to ensure UI updates properly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.showProjectDetails = true
        }
    }
    
    func viewTaskDetails(task: ProjectTask, project: Project) {
        // Post notification to show task details
        let userInfo: [String: Any] = [
            "taskID": task.id,
            "projectID": project.id
        ]
        
        NotificationCenter.default.post(
            name: Notification.Name("ShowTaskDetailsFromHome"),
            object: nil,
            userInfo: userInfo
        )
    }
    
    func setActiveProject(_ project: Project) {
        self.activeProjectID = project.id
        
        // Only trigger sheet display if showProjectDetails is true
        if showProjectDetails {
            self.showProjectDetails = true
        }
    }
    
    func exitProjectMode() {
        self.showProjectDetails = false // Reset the details flag
        self.isViewingDetailsOnly = false // Reset viewing details flag
        self.activeProjectID = nil
        self.activeTaskID = nil // Clear active task ID
    }
    
    // Reset all state on logout to prevent stale references
    func resetForLogout() {
        self.showProjectDetails = false
        self.isViewingDetailsOnly = false
        self.activeProjectID = nil
        self.activeTaskID = nil
        self.isLoadingProjects = false
        self.projectPendingCompletion = nil
        self.showingGlobalCompletionChecklist = false
    }
    
    // Helper method to dismiss project details without exiting project mode
    func dismissProjectDetails() {
        self.showProjectDetails = false
        
        // Store the current active project ID if we're in project mode
        let currentActiveProjectID = self.isInProjectMode ? self.activeProjectID : nil
        
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