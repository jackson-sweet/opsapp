//
//  BackgroundSyncScheduler.swift
//  OPS
//
//  Created by Jackson Sweet on 2026-03-08.
//

import Foundation
import BackgroundTasks

final class BackgroundSyncScheduler {
    /// Singleton — registration must complete before the app finishes launching, but
    /// the SyncEngine that actually services the tasks is created later (after auth).
    /// The singleton lets AppDelegate register task identifiers eagerly and SyncEngine
    /// attach handlers when it spins up. Bug — fix for BGTaskScheduler assertion crash.
    static let shared = BackgroundSyncScheduler()

    static let refreshTaskId = "com.ops.sync.refresh"
    static let processingTaskId = "com.ops.sync.processing"

    /// Called when a refresh task fires — should push pending operations
    var onRefreshTask: (() async -> Void)?

    /// Called when a processing task fires — should do full sync + photo upload + cleanup
    var onProcessingTask: (() async -> Void)?

    private init() {}

    /// Register both task types with BGTaskScheduler. Call from AppDelegate.didFinishLaunching.
    /// Must complete before application(_:didFinishLaunchingWithOptions:) returns or
    /// iOS asserts: "All launch handlers must be registered before application finishes launching".
    func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskId,
            using: nil
        ) { [weak self] task in
            self?.handleRefreshTask(task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingTaskId,
            using: nil
        ) { [weak self] task in
            self?.handleProcessingTask(task as! BGProcessingTask)
        }
    }

    /// Schedule a refresh task. Call when app enters background.
    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BGSync] Scheduled refresh task")
        } catch {
            print("[BGSync] Failed to schedule refresh: \(error)")
        }
    }

    /// Schedule a processing task. Call when app enters background.
    func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: Self.processingTaskId)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BGSync] Scheduled processing task")
        } catch {
            print("[BGSync] Failed to schedule processing: \(error)")
        }
    }

    private func handleRefreshTask(_ task: BGAppRefreshTask) {
        scheduleRefresh() // schedule next

        let syncTask = Task {
            await onRefreshTask?()
        }

        task.expirationHandler = {
            syncTask.cancel()
        }

        Task {
            await syncTask.value
            task.setTaskCompleted(success: true)
        }
    }

    private func handleProcessingTask(_ task: BGProcessingTask) {
        scheduleProcessing() // schedule next

        let syncTask = Task {
            await onProcessingTask?()
        }

        task.expirationHandler = {
            syncTask.cancel()
        }

        Task {
            await syncTask.value
            task.setTaskCompleted(success: true)
        }
    }
}
