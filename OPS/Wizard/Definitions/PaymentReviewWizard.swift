//
//  PaymentReviewWizard.swift
//  OPS
//
//  Wizard for the Tinder-style project payment review flow.
//  Triggers when user has 5+ completed projects awaiting close-out.
//  Shows swipe direction animations then lets the user review.
//

import Foundation

struct PaymentReviewWizard: WizardDefinitionProtocol {
    let wizardId = "payment_review"
    let displayName = "PAYMENT REVIEW"
    let displayDescription = "Close out completed projects in one quick flow. Financial actions appear only when a real balance needs attention."
    let bulletPoints = [
        "Swipe right to close a completed project",
        "Swipe left to skip and review later",
        "Outstanding balances show on the project card"
    ]
    let iconName = "creditcard.circle"
    let triggerType: WizardTriggerType = .contextual
    let minimumTier: WizardAccessTier = .office
    let requiredPermission: String? = "projects.edit"
    let bannerText = "You have completed projects to review — want a quick walkthrough?"
    let estimatedMinutes = 2

    let steps: [WizardStepDefinition] = [
        // Step 1: Navigate to payment review through the header action menu.
        WizardStepDefinition(
            id: "open_payment_review",
            instruction: "OPEN PAYMENT REVIEW",
            description: "Open the header actions, then choose Payment review.",
            targetScreen: "JobBoard",
            canSkip: false,
            completionNotification: "WizardPaymentReviewOpened"
        ),
        // Step 2: If no overdue projects, user must tap "REVIEW COMPLETED PROJECTS"
        // to load the card stack. Auto-skips when overdue projects exist (card stack
        // is shown immediately).
        WizardStepDefinition(
            id: "tap_review_completed",
            instruction: "TAP \"REVIEW COMPLETED PROJECTS\"",
            description: "No overdue projects — tap to load your completed projects for review.",
            targetScreen: "PaymentReview",
            canSkip: true,
            completionNotification: "WizardCompletedProjectsLoaded"
        ),
        // Step 3: Demo swipe right (close)
        WizardStepDefinition(
            id: "payment_demo_swipe_right",
            instruction: "SWIPE RIGHT → CLOSE PROJECT",
            description: "Project is paid and done. Swipe right to close it out.",
            targetScreen: "PaymentReview",
            completionNotification: "WizardProjectSwipedRight"
        ),
        // Step 4: Demo swipe left (skip)
        WizardStepDefinition(
            id: "payment_demo_swipe_left",
            instruction: "SWIPE LEFT → SKIP",
            description: "Not sure yet? Skip it and come back later.",
            targetScreen: "PaymentReview",
            completionNotification: "WizardProjectSwipedLeft"
        ),
        // Step 5: Free review — invoice actions are contextual and may not be
        // present, so the walkthrough never blocks on an unavailable gesture.
        WizardStepDefinition(
            id: "payment_free_review",
            instruction: "YOU'RE ALL SET — KEEP REVIEWING",
            description: "Review the rest of your projects at your own pace.",
            targetScreen: "PaymentReview",
            canSkip: true,
            completionNotification: "WizardPaymentReviewDismissed"
        )
    ]
}
