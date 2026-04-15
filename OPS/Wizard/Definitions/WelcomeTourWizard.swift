//
//  WelcomeTourWizard.swift
//  OPS
//
//  Permission-responsive feature tour. Steps are built dynamically
//  based on the user's current permissions — different users see
//  different tabs.
//

import Foundation

struct WelcomeTourWizard: WizardDefinitionProtocol {
    let wizardId = "welcome_tour"
    let displayName = "WELCOME TOUR"
    let displayDescription = "A quick look at what you can do."
    let bulletPoints: [String] = []
    let iconName = "hand.wave"
    let triggerType: WizardTriggerType = .sequenced
    let minimumTier: WizardAccessTier = .field
    let requiredPermission: String? = nil
    let bannerText = "Take a quick tour of your workspace."
    let estimatedMinutes = 1

    /// Steps built dynamically based on current permissions.
    /// Order matches MainTabView tab order.
    let steps: [WizardStepDefinition]

    init(permissionStore: PermissionStore = .shared) {
        var built: [WizardStepDefinition] = []

        // Home — always present
        built.append(WizardStepDefinition(
            id: "welcome_home",
            instruction: "HOME",
            description: "Today's jobs on the map. Tap a pin, navigate to site.",
            targetScreen: "Home",
            canSkip: false,
            completionNotification: nil  // Advanced via NEXT button, not notification
        ))

        // Pipeline — gated by pipeline.view
        if permissionStore.can("pipeline.view") {
            built.append(WizardStepDefinition(
                id: "welcome_pipeline",
                instruction: "PIPELINE",
                description: "Leads, estimates, invoices. The money side of your business.",
                targetScreen: "Pipeline",
                canSkip: false,
                completionNotification: nil  // Advanced via NEXT button, not notification
            ))
        }

        // Job Board — always present
        built.append(WizardStepDefinition(
            id: "welcome_job_board",
            instruction: "JOB BOARD",
            description: "Every project in one place. Swipe to change status.",
            targetScreen: "JobBoard",
            canSkip: false,
            completionNotification: nil  // Advanced via NEXT button, not notification
        ))

        // Inventory — gated by inventory.view with "all" scope
        if permissionStore.can("inventory.view", requiredScope: "all") {
            built.append(WizardStepDefinition(
                id: "welcome_inventory",
                instruction: "INVENTORY",
                description: "Track what you have, what you need, what's running low.",
                targetScreen: "Inventory",
                canSkip: false,
                completionNotification: nil  // Advanced via NEXT button, not notification
            ))
        }

        // Schedule — always present
        built.append(WizardStepDefinition(
            id: "welcome_schedule",
            instruction: "SCHEDULE",
            description: "Who's working where, and when. Day, week, or month.",
            targetScreen: "Schedule",
            canSkip: false,
            completionNotification: nil  // Advanced via NEXT button, not notification
        ))

        // Settings — always present
        built.append(WizardStepDefinition(
            id: "welcome_settings",
            instruction: "SETTINGS",
            description: "Team, permissions, security. Set it up once.",
            targetScreen: "Settings",
            canSkip: false,
            completionNotification: nil  // Advanced via NEXT button, not notification
        ))

        self.steps = built
    }
}
