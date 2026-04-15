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
    let displayDescription = "PIN lock, profile, notifications. Takes two minutes."
    let bulletPoints = [
        "Fill in your profile",
        "Check your company details",
        "Enable PIN lock",
        "Set notification preferences"
    ]
    let iconName = "gearshape.fill"
    let triggerType: WizardTriggerType = .contextual
    let minimumTier: WizardAccessTier = .field
    let bannerText = "Set up your profile and lock things down."
    let estimatedMinutes = 1

    let steps: [WizardStepDefinition] = [
        WizardStepDefinition(
            id: "open_profile",
            instruction: "OPEN YOUR PROFILE",
            description: "Name, phone, photo. Your crew sees this.",
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
