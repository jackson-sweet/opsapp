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
            instruction: "YOUR COMMAND CENTER",
            description: "Projects, tasks, and crew — all at a glance.",
            targetScreen: "Home",
            canSkip: false,
            completionNotification: "WelcomeTourAdvance"
        ))

        // Pipeline — gated by pipeline.view
        if permissionStore.can("pipeline.view") {
            built.append(WizardStepDefinition(
                id: "welcome_pipeline",
                instruction: "YOUR PIPELINE",
                description: "Track leads from first contact to closed deal.",
                targetScreen: "Pipeline",
                canSkip: false,
                completionNotification: "WelcomeTourAdvance"
            ))
        }

        // Job Board — always present
        built.append(WizardStepDefinition(
            id: "welcome_job_board",
            instruction: "YOUR JOB BOARD",
            description: "Every active project. Swipe to move work forward.",
            targetScreen: "JobBoard",
            canSkip: false,
            completionNotification: "WelcomeTourAdvance"
        ))

        // Inventory — gated by inventory.view with "all" scope
        if permissionStore.can("inventory.view", requiredScope: "all") {
            built.append(WizardStepDefinition(
                id: "welcome_inventory",
                instruction: "YOUR INVENTORY",
                description: "Your warehouse in your pocket. Track stock and materials.",
                targetScreen: "Inventory",
                canSkip: false,
                completionNotification: "WelcomeTourAdvance"
            ))
        }

        // Schedule — always present
        built.append(WizardStepDefinition(
            id: "welcome_schedule",
            instruction: "YOUR SCHEDULE",
            description: "Your crew's calendar. Who's where, when.",
            targetScreen: "Schedule",
            canSkip: false,
            completionNotification: "WelcomeTourAdvance"
        ))

        // Settings — always present
        built.append(WizardStepDefinition(
            id: "welcome_settings",
            instruction: "YOUR SETTINGS",
            description: "Your company, your crew, your rules.",
            targetScreen: "Settings",
            canSkip: false,
            completionNotification: "WelcomeTourAdvance"
        ))

        self.steps = built
    }
}
