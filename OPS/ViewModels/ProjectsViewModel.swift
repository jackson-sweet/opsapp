//
//  ProjectsViewModel.swift
//  OPS
//
//  Created by OPS Team.
//

//
//  ProjectsViewModel.swift
//  Manages project data loading and sync via DataController.
//

import Foundation
import SwiftData
import Combine

/// ViewModel for handling Project-related operations
class ProjectsViewModel: ObservableObject {
    private let dataController: DataController

    @Published var projects: [Project] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var syncStatus: SyncStatus = .idle

    enum SyncStatus {
        case idle
        case syncing
        case completed
        case failed
    }

    private var cancellables = Set<AnyCancellable>()

    init(dataController: DataController) {
        self.dataController = dataController
    }

    /// Load projects from database and trigger sync if needed
    @MainActor
    func loadProjects(context: ModelContext) {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        Task {
            // Always load from local database first for immediate response
            await loadFromLocalDatabase(context: context)

            // Then try sync if we have connectivity
            if dataController.isConnected {
                 await performSync()
            }

            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    @MainActor
    private func loadFromLocalDatabase(context: ModelContext) async {
        do {
            // Optimize fetch with relevant sorting
            let descriptor = FetchDescriptor<Project>(
                sortBy: [SortDescriptor(\.startDate, order: .forward)]
            )

            self.projects = try context.fetch(descriptor)
        } catch {
            self.error = "Unable to load projects"
        }
    }

    private func performSync() async {
        await MainActor.run {
            syncStatus = .syncing
        }

        do {
            // Trigger background sync via DataController
            await MainActor.run {
                dataController.triggerBackgroundSync()
            }

            // Wait for completion or timeout
            for _ in 0..<20 {
                if !dataController.isSyncing {
                    break
                }
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
            }

            // Refresh from database on main thread
            await MainActor.run {
                syncStatus = .completed

                if let context = dataController.modelContext {
                    Task {
                        await loadFromLocalDatabase(context: context)
                    }
                }
            }
        } catch {
            await MainActor.run {
                syncStatus = .failed
                self.error = "Sync failed: \(error.localizedDescription)"
            }
        }
    }

    /// Update project status
    @MainActor func updateProjectStatus(projectId: String, status: Status, context: ModelContext) {
        // Define a reusable predicate
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

            // Trigger sync via DataController
            dataController.triggerBackgroundSync()

        } catch {
            self.error = "Failed to update project status."
        }
    }
}
