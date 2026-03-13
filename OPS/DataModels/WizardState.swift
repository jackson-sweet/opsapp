//
//  WizardState.swift
//  OPS
//
//  SwiftData model persisting per-wizard progress.
//  Synced to Supabase for cross-device persistence.
//

import Foundation
import SwiftData

@Model
final class WizardState {
    /// The wizard identifier (e.g., "project_lifecycle")
    var wizardId: String

    /// Current status
    var statusRaw: String  // Backed by WizardStatus enum

    /// Current step index (0-based) — resume position
    var currentStepIndex: Int

    /// Whether the user checked "Don't show again"
    var doNotShow: Bool

    /// Timestamp when wizard was completed (nil if not completed)
    var completedAt: Date?

    /// Cumulative time spent across all sessions (milliseconds)
    var totalDurationMs: Int

    /// Number of steps the user skipped
    var stepsSkipped: Int

    /// Last interaction timestamp (used for conflict resolution)
    var lastActiveAt: Date?

    /// UUID for the current wizard session (generated on start, preserved on resume, reset on restart)
    var currentSessionId: String

    /// The user ID this state belongs to
    var userId: String

    /// Sync tracking
    var needsSync: Bool
    var lastSyncedAt: Date?

    // MARK: - Computed Properties

    var status: WizardStatus {
        get { WizardStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    // MARK: - Init

    init(wizardId: String, userId: String) {
        self.wizardId = wizardId
        self.userId = userId
        self.statusRaw = WizardStatus.notStarted.rawValue
        self.currentStepIndex = 0
        self.doNotShow = false
        self.completedAt = nil
        self.totalDurationMs = 0
        self.stepsSkipped = 0
        self.lastActiveAt = nil
        self.currentSessionId = UUID().uuidString
        self.needsSync = false
        self.lastSyncedAt = nil
    }

    // MARK: - State Transitions

    /// Start or resume the wizard
    func start() {
        status = .inProgress
        lastActiveAt = Date()
        needsSync = true
    }

    /// Restart from the beginning
    func restart() {
        status = .inProgress
        currentStepIndex = 0
        completedAt = nil
        stepsSkipped = 0
        currentSessionId = UUID().uuidString
        lastActiveAt = Date()
        needsSync = true
        // Note: totalDurationMs accumulates across sessions — not reset
    }

    /// Mark as completed
    func markCompleted() {
        status = .completed
        completedAt = Date()
        lastActiveAt = Date()
        needsSync = true
    }

    /// Advance to the next step
    func advanceStep(totalSteps: Int) {
        if currentStepIndex < totalSteps - 1 {
            currentStepIndex += 1
        }
        lastActiveAt = Date()
        needsSync = true
    }

    /// Record a skipped step
    func recordSkip(totalSteps: Int) {
        stepsSkipped += 1
        advanceStep(totalSteps: totalSteps)
    }

    /// Add elapsed time to cumulative duration
    func addDuration(_ ms: Int) {
        totalDurationMs += ms
        needsSync = true
    }
}
