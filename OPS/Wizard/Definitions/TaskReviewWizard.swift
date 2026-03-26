//
//  TaskReviewWizard.swift
//  OPS
//
//  Wizard for the Tinder-style task review flow.
//  Triggers when user has 5+ active tasks with end dates in the past.
//  Shows swipe direction animations then lets the user review.
//

import Foundation

struct TaskReviewWizard: WizardDefinitionProtocol {
    let wizardId = "task_review"
    let displayName = "TASK REVIEW"
    let displayDescription = "Review your overdue tasks in one quick flow. Swipe cards to complete, skip, reschedule, or cancel tasks that need attention."
    let bulletPoints = [
        "Swipe right to mark a task complete",
        "Swipe left to skip and come back later",
        "Swipe up to reschedule to a new date",
        "Swipe down to cancel a task"
    ]
    let iconName = "rectangle.stack.fill"
    let triggerType: WizardTriggerType = .contextual
    let minimumTier: WizardAccessTier = .field
    let requiredPermission: String? = "tasks.view"
    let bannerText = "You have overdue tasks — want a quick walkthrough of task review?"

    let steps: [WizardStepDefinition] = [
        WizardStepDefinition(
            id: "open_task_review",
            instruction: "OPEN TASK REVIEW",
            description: "Tap the task review button to begin.",
            targetScreen: "JobBoard",
            canSkip: false,
            completionNotification: "WizardTaskReviewOpened"
        ),
        WizardStepDefinition(
            id: "demo_swipe_right",
            instruction: "SWIPE RIGHT → COMPLETE",
            description: "Swipe a card right to mark the task as done.",
            targetScreen: "TaskReview",
            completionNotification: "WizardTaskSwipedRight"
        ),
        WizardStepDefinition(
            id: "demo_swipe_left",
            instruction: "SWIPE LEFT → SKIP",
            description: "Not ready to decide? Swipe left to skip for now.",
            targetScreen: "TaskReview",
            completionNotification: "WizardTaskSwipedLeft"
        ),
        WizardStepDefinition(
            id: "demo_swipe_up",
            instruction: "SWIPE UP → RESCHEDULE",
            description: "Push the task to a new date — choose +1 day, +1 week, or pick a date.",
            targetScreen: "TaskReview",
            completionNotification: "WizardTaskSwipedUp"
        ),
        WizardStepDefinition(
            id: "free_review",
            instruction: "YOU'RE ALL SET — KEEP REVIEWING",
            description: "You've got the hang of it. Review the rest at your own pace.",
            targetScreen: "TaskReview",
            canSkip: true,
            completionNotification: "WizardTaskReviewDismissed"
        )
    ]
}
