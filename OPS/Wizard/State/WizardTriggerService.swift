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
    private var isTutorialComplete: (() -> Bool)?

    /// Keys tracking which trigger contexts have been seen this session
    /// Prevents repeated banner shows within a single app session
    private var triggeredThisSession: Set<String> = []

    func configure(
        stateManager: WizardStateManager,
        userRole: UserRole,
        permissionCheck: @escaping (String) -> Bool,
        isTutorialComplete: @escaping () -> Bool = { true }
    ) {
        self.stateManager = stateManager
        self.userRole = userRole
        self.permissionCheck = permissionCheck
        self.isTutorialComplete = isTutorialComplete
    }

    /// Call this when the user enters a feature area.
    /// Evaluates whether the corresponding wizard should be triggered.
    ///
    /// - Parameters:
    ///   - wizard: The wizard to potentially trigger
    ///   - context: Description of what triggered it (e.g., "calendar_tab_visit")
    ///   - projectCount: Number of visible projects for the current user (scoped). Pass -1 to skip the check.
    func evaluateTrigger(for wizard: any WizardDefinitionProtocol, context: String, projectCount: Int = -1) {
        guard let stateManager, stateManager.isEnabled else { return }
        guard !stateManager.isActive else { return } // Don't interrupt an active wizard

        // Don't show wizards while the 25-phase interactive tutorial is still in progress
        guard isTutorialComplete?() != false else { return }

        // Check role access — unassigned users skip all wizards (pre-role-assignment)
        guard let role = userRole, role != .unassigned else { return }
        let tier = WizardAccessTier.tier(for: role)
        guard tier.canAccess(minimumTier: wizard.minimumTier) else { return }

        // Check permission gating
        if let required = wizard.requiredPermission {
            guard permissionCheck?(required) == true else { return }
        }

        // Data prerequisite: job_board wizard requires at least 1 project to be meaningful
        if wizard.wizardId == "job_board" && projectCount == 0 {
            return
        }

        // Check if already triggered this session
        guard !triggeredThisSession.contains(wizard.wizardId) else { return }

        // Check global cooldown (user said "Never" or "Not Now" too many times)
        guard !stateManager.isInGlobalCooldown else { return }

        // Check wizard state
        guard let state = stateManager.wizardState(for: wizard.wizardId) else { return }

        // Don't show if doNotShow is set
        guard !state.doNotShow else { return }

        // Don't show if already completed (unless they explicitly restart from settings)
        guard state.status != .completed else { return }

        // Don't re-trigger banner if user is already mid-wizard
        guard state.status != .inProgress else { return }

        // Show the banner
        triggeredThisSession.insert(wizard.wizardId)
        stateManager.showBanner(for: wizard)
    }

    /// Evaluate sequenced wizards that trigger proactively based on user lifecycle.
    /// Call this after the main view appears and data has loaded.
    ///
    /// - Parameter projectCount: Number of projects the user has
    func evaluateSequencedWizards(projectCount: Int) {
        let sequenced = WizardRegistry.allWizards.filter { $0.triggerType == .sequenced }
        for wizard in sequenced {
            // ProjectLifecycleWizard: trigger when user has no projects
            // Requires clients.create (steps 2-3 create a client) and projects.edit
            // (final step swipes project status) in addition to the wizard-level
            // projects.create gate. Without clients.create the user is hard-stuck
            // at step 2 because the "New Client" FAB menu item is hidden.
            if wizard.wizardId == "project_lifecycle" && projectCount == 0 {
                guard permissionCheck?("clients.create") == true else { continue }
                evaluateTrigger(for: wizard, context: "no_projects_first_session")
            }
        }
    }

    /// Evaluate data-condition wizards that trigger based on accumulated state.
    /// Call this periodically (e.g., after sync, or when Job Board appears).
    ///
    /// - Parameters:
    ///   - overdueTaskCount: Number of active tasks with end dates in the past
    ///   - completedProjectCount: Number of projects in .completed status
    ///   - completedTaskCount: Number of tasks in .completed status (used to gate task review unlock)
    func evaluateDataConditions(overdueTaskCount: Int, completedProjectCount: Int, completedTaskCount: Int = 0) {
        // Task Review: 5+ overdue tasks AND 5+ completed tasks (button unlock threshold).
        // Without the completed-task gate the wizard triggers while the review button
        // is still locked, leaving the user hard-stuck on the non-skippable first step.
        if overdueTaskCount >= 5 && completedTaskCount >= 5 {
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
