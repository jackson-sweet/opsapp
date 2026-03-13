//
//  WizardTriggerService.swift
//  OPS
//
//  Monitors trigger conditions for contextual wizards.
//  Evaluates whether a wizard should be shown when the user
//  enters a feature area for the first time.
//

import Foundation
import SwiftUI

@MainActor
class WizardTriggerService: ObservableObject {

    // Required: nonisolated init so @StateObject can construct this
    // in a non-@MainActor View struct.
    nonisolated init() {}

    private weak var stateManager: WizardStateManager?
    private var userRole: UserRole?
    private var permissionCheck: ((String) -> Bool)?

    /// Keys tracking which trigger contexts have been seen this session
    /// Prevents repeated banner shows within a single app session
    private var triggeredThisSession: Set<String> = []

    func configure(
        stateManager: WizardStateManager,
        userRole: UserRole,
        permissionCheck: @escaping (String) -> Bool
    ) {
        self.stateManager = stateManager
        self.userRole = userRole
        self.permissionCheck = permissionCheck
    }

    /// Call this when the user enters a feature area.
    /// Evaluates whether the corresponding wizard should be triggered.
    ///
    /// - Parameters:
    ///   - wizardId: The wizard to potentially trigger
    ///   - context: Description of what triggered it (e.g., "calendar_tab_visit")
    func evaluateTrigger(for wizard: any WizardDefinitionProtocol, context: String) {
        guard let stateManager, stateManager.isEnabled else { return }
        guard !stateManager.isActive else { return } // Don't interrupt an active wizard

        // Check role access
        guard let role = userRole else { return }
        let tier = WizardAccessTier.tier(for: role)
        guard tier.canAccess(minimumTier: wizard.minimumTier) else { return }

        // Check permission gating
        if let required = wizard.requiredPermission {
            guard permissionCheck?(required) == true else { return }
        }

        // Check if already triggered this session
        guard !triggeredThisSession.contains(wizard.wizardId) else { return }

        // Check wizard state
        guard let state = stateManager.wizardState(for: wizard.wizardId) else { return }

        // Don't show if doNotShow is set
        guard !state.doNotShow else { return }

        // Don't show if already completed (unless they explicitly restart from settings)
        guard state.status != .completed else { return }

        // Show the banner
        triggeredThisSession.insert(wizard.wizardId)
        stateManager.showBanner(for: wizard)
    }

    /// Evaluate data-condition wizards that trigger based on accumulated state.
    /// Call this periodically (e.g., after sync, or when Job Board appears).
    ///
    /// - Parameters:
    ///   - overdueTaskCount: Number of active tasks with end dates in the past
    ///   - completedProjectCount: Number of projects in .completed status
    func evaluateDataConditions(overdueTaskCount: Int, completedProjectCount: Int) {
        // Task Review: 5+ overdue tasks
        if overdueTaskCount >= 5 {
            if let wizard = WizardRegistry.wizard(for: "task_review") {
                evaluateTrigger(for: wizard, context: "overdue_tasks_\(overdueTaskCount)")
            }
        }

        // Payment Review: 5+ completed projects
        if completedProjectCount >= 5 {
            if let wizard = WizardRegistry.wizard(for: "payment_review") {
                evaluateTrigger(for: wizard, context: "completed_projects_\(completedProjectCount)")
            }
        }
    }

    /// Reset session tracking (e.g., on app launch)
    func resetSessionTracking() {
        triggeredThisSession.removeAll()
    }
}
