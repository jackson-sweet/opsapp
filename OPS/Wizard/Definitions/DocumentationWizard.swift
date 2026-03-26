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
    let displayDescription = "Keep a complete record of every job. Write notes to your crew, capture photos on-site, and review your documentation."
    let bulletPoints = [
        "Write a note with @mentions",
        "Capture photos to document the job",
        "View and review your photos"
    ]
    let iconName = "doc.text.image"
    let triggerType: WizardTriggerType = .contextual
    let minimumTier: WizardAccessTier = .field
    let bannerText = "Want to learn how to document your jobs?"

    let steps: [WizardStepDefinition] = [
        WizardStepDefinition(
            id: "write_note",
            instruction: "WRITE A NOTE",
            description: "Type a note in the compose bar below. Use @ to mention a crew member.",
            targetScreen: "ProjectDetails",
            canSkip: true,
            completionNotification: "WizardNotePosted"
        ),
        WizardStepDefinition(
            id: "capture_photo",
            instruction: "TAKE A PHOTO",
            description: "Tap the camera button to document the job site.",
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
