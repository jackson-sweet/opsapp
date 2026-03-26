//
//  JobBoardWizard.swift
//  OPS
//
//  Contextual wizard for the job board feature.
//  Triggers on first Job Board tab visit. Walks users through
//  browsing, filtering, swiping status, and viewing project details.
//
//  Audit fixes (2026-03-25):
//  - browse_projects: canSkip=false — auto-completes on real scroll (≥50pt)
//  - swipe_status: canSkip=true explicit — crew lacks projects.edit, needs skip path
//  - view_closed: canSkip=true — auto-skipped when no closed projects exist
//

import Foundation

struct JobBoardWizard: WizardDefinitionProtocol {
    let wizardId = "job_board"
    let displayName = "JOB BOARD"
    let displayDescription = "Your command center for every project. Browse, filter, swipe to change status, and tap into project details."
    let bulletPoints = [
        "Browse your active projects",
        "Filter by status or crew member",
        "Swipe a card to advance its status",
        "Tap a project for full details"
    ]
    let iconName = "list.clipboard"
    let triggerType: WizardTriggerType = .contextual
    let minimumTier: WizardAccessTier = .field
    let bannerText = "Want a quick tour of the job board?"

    let steps: [WizardStepDefinition] = [
        WizardStepDefinition(
            id: "browse_projects",
            instruction: "SCROLL THROUGH YOUR PROJECTS",
            description: "Your active projects are listed here. Scroll to browse.",
            targetScreen: "JobBoard",
            canSkip: false,
            completionNotification: "WizardJobBoardScrolled"
        ),
        WizardStepDefinition(
            id: "open_filters",
            instruction: "TAP THE FILTER BUTTON",
            description: "Filter projects by status, team member, or sort order.",
            targetScreen: "JobBoard",
            canSkip: true,
            completionNotification: "WizardJobBoardFilterOpened"
        ),
        WizardStepDefinition(
            id: "swipe_status",
            instruction: "SWIPE A PROJECT CARD RIGHT",
            description: "Swipe right to advance the project to its next status.",
            targetScreen: "JobBoard",
            canSkip: true,
            completionNotification: "WizardProjectStatusChanged"
        ),
        WizardStepDefinition(
            id: "tap_project",
            instruction: "TAP A PROJECT TO OPEN IT",
            description: "View the full project — tasks, notes, photos, and more.",
            targetScreen: "JobBoard",
            canSkip: true,
            completionNotification: "WizardJobBoardProjectTapped"
        ),
        WizardStepDefinition(
            id: "view_closed",
            instruction: "CHECK YOUR CLOSED PROJECTS",
            description: "Scroll down and tap the Closed section to see completed work.",
            targetScreen: "JobBoard",
            canSkip: true,
            completionNotification: "WizardJobBoardClosedViewed"
        )
    ]
}
