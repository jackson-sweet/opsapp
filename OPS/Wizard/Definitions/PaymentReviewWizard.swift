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
    let displayDescription = "Close out completed projects in one quick flow. Swipe cards to close, skip, send a payment reminder, or write off bad debt."
    let bulletPoints = [
        "Swipe right to close a project as paid",
        "Swipe left to skip and review later",
        "Swipe up to send a payment reminder",
        "Swipe down to write off as bad debt"
    ]
    let iconName = "creditcard.circle"
    let triggerType: WizardTriggerType = .contextual
    let minimumTier: WizardAccessTier = .office
    let requiredPermission: String? = "finances.view"
    let bannerText = "You have completed projects to review — want a quick walkthrough?"

    let steps: [WizardStepDefinition] = [
        // Step 1: Navigate to the review button in the header
        WizardStepDefinition(
            id: "open_payment_review",
            instruction: "TAP THE REVIEW ICON",
            description: "Tap the card stack icon in the header to open payment review.",
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
        // Step 5: Demo swipe up (send reminder)
        WizardStepDefinition(
            id: "payment_demo_swipe_up",
            instruction: "SWIPE UP → SEND REMINDER",
            description: "Send a payment reminder to the client.",
            targetScreen: "PaymentReview",
            completionNotification: "WizardProjectSwipedUp"
        ),
        // Step 6: Demo swipe down (write off)
        WizardStepDefinition(
            id: "payment_demo_swipe_down",
            instruction: "SWIPE DOWN → WRITE OFF",
            description: "Write off outstanding balance as bad debt. You'll confirm before it's final.",
            targetScreen: "PaymentReview",
            completionNotification: "WizardProjectSwipedDown"
        ),
        // Step 7: Free review — user continues at their own pace
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
