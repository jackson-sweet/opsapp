//
//  WizardRegistry.swift
//  OPS
//
//  Central registry of all wizard definitions.
//  Provides access filtered by user role and permissions.
//

import Foundation

struct WizardRegistry {
    /// All wizard definitions in display order
    static let allWizards: [any WizardDefinitionProtocol] = [
        // Sequenced
        ProjectLifecycleWizard(),
        // Contextual
        SchedulingCalendarWizard(),
        JobBoardWizard(),
        DocumentationWizard(),
        TeamManagementWizard(),
        SettingsSecurityWizard(),
        PermissionsRolesWizard(),
        InventorySetupWizard(),
        // Data-condition
        TaskReviewWizard(),
        PaymentReviewWizard()
    ]

    /// Wizards filtered by role and permissions
    static func wizards(
        for role: UserRole,
        permissionCheck: (String) -> Bool
    ) -> [any WizardDefinitionProtocol] {
        let tier = WizardAccessTier.tier(for: role)
        return allWizards.filter { wizard in
            // Check role tier
            guard tier.canAccess(minimumTier: wizard.minimumTier) else { return false }
            // Check permission gating
            if let required = wizard.requiredPermission {
                return permissionCheck(required)
            }
            return true
        }
    }

    /// Look up a wizard by ID
    static func wizard(for id: String) -> (any WizardDefinitionProtocol)? {
        allWizards.first { $0.wizardId == id }
    }

    /// Contextual wizards that should be checked on specific triggers
    static func contextualWizard(for triggerId: String) -> (any WizardDefinitionProtocol)? {
        allWizards.first { $0.wizardId == triggerId && $0.triggerType == .contextual }
    }
}
