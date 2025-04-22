//
//  ProjectsViewModel.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
//
//  ProjectsViewModel.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import Foundation
import SwiftData
import Combine

/// ViewModel for handling Project-related operations
class ProjectsViewModel: ObservableObject {
    private let syncManager: SyncManager
    
    @Published var projects: [Project] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    init(syncManager: SyncManager) {
        self.syncManager = syncManager
    }
    
    /// Load projects from database and trigger sync if needed
    func loadProjects(context: ModelContext) {
        isLoading = true
        error = nil
        
        do {
            // Fetch all projects from local database
            let descriptor = FetchDescriptor<Project>()
            let localProjects = try context.fetch(descriptor)
            
            // Update UI
            self.projects = localProjects
            
            // Trigger sync if we have network connectivity
            Task {
                await syncManager.triggerBackgroundSync()
                
                // Refresh projects from database after sync
                await MainActor.run {
                    do {
                        let updatedProjects = try context.fetch(descriptor)
                        self.projects = updatedProjects
                        self.isLoading = false
                    } catch {
                        self.error = "Failed to fetch updated projects."
                        self.isLoading = false
                    }
                }
            }
        } catch {
            self.error = "Failed to load projects."
            self.isLoading = false
        }
    }
    
    /// Update project status
    @MainActor func updateProjectStatus(projectId: String, status: Status, context: ModelContext) {
        let predicate = #Predicate<Project> { $0.id == projectId }
        let descriptor = FetchDescriptor<Project>(predicate: predicate)
        
        do {
            let projects = try context.fetch(descriptor)
            guard let project = projects.first else {
                self.error = "Project not found."
                return
            }
            
            // Update the status
            project.status = status
            project.needsSync = true
            project.syncPriority = 3 // Highest priority
            
            // Update timestamps based on status
            if status == .inProgress && project.startDate == nil {
                project.startDate = Date()
            } else if status == .completed && project.endDate == nil {
                project.endDate = Date()
            }
            
            // Save changes
            try context.save()
            
            // Trigger sync
            syncManager.triggerBackgroundSync()
            
        } catch {
            self.error = "Failed to update project status."
        }
    }
}
