//
//  JobBoardWizard.swift
//  OPS
//
//  Contextual wizard for the job board feature.
//  Triggers on first Job Board tab visit. Walks users through
//  browsing, swiping status, filtering, and viewing project details.
//
//  Audit fixes (2026-03-25):
//  - browse_projects: canSkip=false — auto-completes on real scroll (≥50pt)
//  - swipe_status: canSkip=true explicit — crew lacks projects.edit, needs skip path
//  - view_closed: canSkip=true — auto-skipped when no closed projects exist
//
//  Audit fixes (2026-03-30):
//  - open_filters: notification moved to filter sheet onDisappear (was blocking step 3 with open sheet)
//  - open_filters: instruction updated to "OPEN THE FILTER MENU" with clear dismiss guidance
//  - swipe_status: swipeable count now excludes .inProgress with incomplete tasks (completion check blocker)
//  - view_closed: instruction updated to "TAP CLOSED TO SEE FINISHED WORK" with accurate button label
//  - view_closed: description guides user back to project list after step 4 opens detail view
//
//  Bug fix (2026-04-22 — ae77d32a):
//  - swipe_status promoted to step 2 (right after browse) so the core swipe
//    gesture is explained before the more niche filter menu
//  - swipe_status copy rewritten to call out swipe-left (backwards) AND
//    swipe-right (forwards) with explicit status names
//  - view_closed description calls out that view_closed step auto-scrolls
//

import Foundation

struct JobBoardWizard: WizardDefinitionProtocol {
    let wizardId = "job_board"
    let displayName = "JOB BOARD"
    let displayDescription = "All your projects. Swipe, filter, tap in for details."
    let bulletPoints = [
        "Browse active projects",
        "Swipe left or right to change status",
        "Filter by status or crew",
        "Tap a project for details"
    ]
    let iconName = "list.clipboard"
    let triggerType: WizardTriggerType = .contextual
    let minimumTier: WizardAccessTier = .field
    let bannerText = "First time on the board? 2-minute walkthrough."
    let estimatedMinutes = 2

    let steps: [WizardStepDefinition] = [
        WizardStepDefinition(
            id: "browse_projects",
            instruction: "SCROLL THROUGH YOUR PROJECTS",
            description: "Your active projects are listed here. Scroll to browse.",
            targetScreen: "JobBoard",
            canSkip: true,
            completionNotification: "WizardJobBoardScrolled"
        ),
        WizardStepDefinition(
            id: "swipe_status",
            instruction: "SWIPE A PROJECT TO CHANGE STATUS",
            description: "Swipe RIGHT to push a project forward — Accepted, In Progress, Completed. Swipe LEFT to walk it back a step.",
            targetScreen: "JobBoard",
            canSkip: true,
            completionNotification: "WizardProjectStatusChanged"
        ),
        WizardStepDefinition(
            id: "open_filters",
            instruction: "OPEN THE FILTER MENU",
            description: "Tap the filter icon to sort and filter your projects, then close it.",
            targetScreen: "JobBoard",
            canSkip: true,
            completionNotification: "WizardJobBoardFilterOpened"
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
            instruction: "TAP CLOSED TO SEE FINISHED WORK",
            description: "The CLOSED button at the bottom holds your finished jobs. Tap to review, then close the sheet.",
            targetScreen: "JobBoard",
            canSkip: true,
            completionNotification: "WizardJobBoardClosedViewed"
        )
    ]
}
