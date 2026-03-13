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
        WizardStepDefinition(
            id: "open_payment_review",
            instruction: "OPEN PAYMENT REVIEW",
            description: "Tap the payment review button to begin.",
            targetScreen: "JobBoard",
            canSkip: false,
            completionNotification: "WizardPaymentReviewOpened"
        ),
        WizardStepDefinition(
            id: "demo_swipe_right",
            instruction: "SWIPE RIGHT → CLOSE PROJECT",
            description: "Project is paid and done. Swipe right to close it out.",
            targetScreen: "PaymentReview",
            completionNotification: "WizardProjectSwipedRight"
        ),
        WizardStepDefinition(
            id: "demo_swipe_left",
            instruction: "SWIPE LEFT → SKIP",
            description: "Not sure yet? Skip it and come back later.",
            targetScreen: "PaymentReview",
            completionNotification: "WizardProjectSwipedLeft"
        ),
        WizardStepDefinition(
            id: "demo_swipe_up",
            instruction: "SWIPE UP → SEND REMINDER",
            description: "Send a payment reminder to the client.",
            targetScreen: "PaymentReview",
            completionNotification: "WizardProjectSwipedUp"
        ),
        WizardStepDefinition(
            id: "free_review",
            instruction: "YOU'RE ALL SET — KEEP REVIEWING",
            description: "Review the rest of your projects at your own pace.",
            targetScreen: "PaymentReview",
            canSkip: true,
            completionNotification: "WizardPaymentReviewDismissed"
        )
    ]
}
