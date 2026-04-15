//
//  DocumentationWizard.swift
//  OPS
//
//  Contextual wizard for project documentation features.
//  Auto-opens the most recent project, then guides the user through
//  writing a note, taking a photo, and viewing photos.
//

import Foundation

struct DocumentationWizard: WizardDefinitionProtocol {
    let wizardId = "documentation"
    let displayName = "DOCUMENTATION & DETAILS"
    let displayDescription = "Notes and photos — everything your crew needs to see, right on the project."
    let bulletPoints = [
        "Write a note, @ your crew",
        "Capture photos on site",
        "View photos full screen"
    ]
    let iconName = "doc.text.image"
    let triggerType: WizardTriggerType = .contextual
    let minimumTier: WizardAccessTier = .field
    let bannerText = "Capture notes and photos on your projects."
    let estimatedMinutes = 1

    let steps: [WizardStepDefinition] = [
        WizardStepDefinition(
            id: "write_note",
            instruction: "WRITE A NOTE",
            description: "Type a note and tap send. Use @ to mention a crew member.",
            targetScreen: "ProjectDetails",
            canSkip: true,
            completionNotification: "WizardNotePosted"
        ),
        WizardStepDefinition(
            id: "capture_photo",
            instruction: "TAKE A PHOTO",
            description: "Tap PHOTO in the action bar to capture job site photos.",
            targetScreen: "ProjectDetails",
            canSkip: true,
            completionNotification: "WizardPhotoCaptured"
        ),
        WizardStepDefinition(
            id: "view_photo",
            instruction: "TAP A PHOTO TO VIEW IT",
            description: "Open any photo to see it full screen.",
            targetScreen: "ProjectDetails",
            canSkip: true,
            completionNotification: "WizardPhotoViewed"
        )
    ]
}
