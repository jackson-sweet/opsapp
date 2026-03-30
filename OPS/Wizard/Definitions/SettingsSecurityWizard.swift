//
//  SettingsSecurityWizard.swift
//  OPS
//
//  Contextual wizard for app settings and security setup.
//  Triggers on first settings visit. Walks users through
//  profile completion, company info, PIN lock, and notifications.
//
//  Audit fixes (2026-03-26):
//  - open_profile: canSkip=false — auto-completes by opening the screen
//  - enable_pin: canSkip=true — auto-skipped when PIN already enabled
//

import Foundation

struct SettingsSecurityWizard: WizardDefinitionProtocol {
    let wizardId = "settings_security"
    let displayName = "SETTINGS & SECURITY"
    let displayDescription = "Lock down your app and personalize your experience. Set up a PIN, complete your profile, and configure how you get notified."
    let bulletPoints = [
        "Complete your profile information",
        "Set up your company details",
        "Enable PIN lock for security",
        "Configure notification preferences"
    ]
    let iconName = "gearshape.fill"
    let triggerType: WizardTriggerType = .contextual
    let minimumTier: WizardAccessTier = .field
    let bannerText = "Want to set up your profile and security?"

    let steps: [WizardStepDefinition] = [
        WizardStepDefinition(
            id: "open_profile",
            instruction: "OPEN YOUR PROFILE",
            description: "Add your name, phone, and photo so your crew knows who you are.",
            targetScreen: "Settings",
            canSkip: false,
            completionNotification: "WizardProfileViewed"
        ),
        WizardStepDefinition(
            id: "open_company",
            instruction: "VIEW YOUR ORGANIZATION",
            description: "Check your organization name, logo, and contact information.",
            targetScreen: "Settings",
            canSkip: true,
            completionNotification: "WizardCompanyInfoViewed"
        ),
        WizardStepDefinition(
            id: "enable_pin",
            instruction: "SET UP A PIN",
            description: "Go to Security & Privacy and enable PIN lock to protect your data.",
            targetScreen: "SecuritySettings",
            canSkip: true,
            completionNotification: "WizardPINEnabled"
        ),
        WizardStepDefinition(
            id: "configure_notifications",
            instruction: "CONFIGURE NOTIFICATIONS",
            description: "Choose which alerts you get and set quiet hours.",
            targetScreen: "NotificationSettings",
            canSkip: true,
            completionNotification: "WizardNotificationsConfigured"
        )
    ]
}
