//
//  InventorySetupWizard.swift
//  OPS
//
//  Wizard definition for inventory setup flow.
//  Triggers on first visit to inventory tab when no items exist.
//  Guides user through adding items, setting thresholds, and taking a snapshot.
//

import Foundation

struct InventorySetupWizard: WizardDefinitionProtocol {
    let wizardId = "inventory_setup"
    let displayName = "INVENTORY SETUP"
    let displayDescription = "Track your materials, supplies, and equipment. Get alerts when stock runs low."
    let bulletPoints = [
        "Add items manually or import from a spreadsheet",
        "Set stock alert thresholds",
        "Take your first inventory snapshot"
    ]
    let iconName = "shippingbox.fill"
    let triggerType: WizardTriggerType = .contextual
    let minimumTier: WizardAccessTier = .office
    let requiredPermission: String? = "inventory.manage"
    let bannerText = "Let's set up your inventory"

    let steps: [WizardStepDefinition] = [
        WizardStepDefinition(
            id: "choose_method",
            instruction: "ADD YOUR ITEMS",
            description: "Choose how to add inventory items",
            targetScreen: "Inventory",
            canSkip: true
        ),
        WizardStepDefinition(
            id: "add_items",
            instruction: "ADD YOUR ITEMS",
            description: "Add materials, supplies, and equipment",
            targetScreen: "Inventory",
            canSkip: true
        ),
        WizardStepDefinition(
            id: "set_thresholds",
            instruction: "SET STOCK ALERTS",
            description: "Get notified when items run low",
            targetScreen: "Inventory",
            canSkip: true
        ),
        WizardStepDefinition(
            id: "take_snapshot",
            instruction: "TAKE FIRST SNAPSHOT",
            description: "Start tracking usage trends",
            targetScreen: "Inventory",
            canSkip: true
        ),
    ]
}
