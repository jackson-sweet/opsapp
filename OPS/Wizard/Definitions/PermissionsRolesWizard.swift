//
//  PermissionsRolesWizard.swift
//  OPS
//
//  Contextual wizard for the permissions and roles management system.
//  Triggers on first permissions settings visit. Admin-only.
//  Walks users through roles, permission editing, and per-user overrides.
//
//  Audit fixes (2026-03-26):
//  - view_roles: canSkip=false — auto-completes via delayed notification (3s)
//  - Fixed timing race: notification delayed to fire after wizard starts listening
//  - Added deep navigation for CONTINUE GUIDE
//

import Foundation

struct PermissionsRolesWizard: WizardDefinitionProtocol {
    let wizardId = "permissions_roles"
    let displayName = "PERMISSIONS & ROLES"
    let displayDescription = "Control who can do what. Browse preset roles, customize permissions, and set per-person overrides for your team."
    let bulletPoints = [
        "Browse preset and custom roles",
        "See what each role can access",
        "View your team's permission assignments",
        "Set per-person permission overrides"
    ]
    let iconName = "lock.shield"
    let triggerType: WizardTriggerType = .contextual
    let minimumTier: WizardAccessTier = .admin
    let requiredPermission: String? = "settings.company"
    let bannerText = "Want a walkthrough of permissions?"

    let steps: [WizardStepDefinition] = [
        WizardStepDefinition(
            id: "view_roles",
            instruction: "BROWSE THE ROLES",
            description: "These are the preset roles that control what each team member can do.",
            targetScreen: "Permissions",
            canSkip: false,
            completionNotification: "WizardRolesTabViewed"
        ),
        WizardStepDefinition(
            id: "view_role_detail",
            instruction: "TAP A ROLE TO SEE ITS PERMISSIONS",
            description: "Each role has a set of permissions. Tap one to see the details.",
            targetScreen: "Permissions",
            canSkip: true,
            completionNotification: "WizardRoleDetailViewed"
        ),
        WizardStepDefinition(
            id: "switch_to_team",
            instruction: "SWITCH TO THE TEAM TAB",
            description: "See which role each team member has and any custom overrides.",
            targetScreen: "Permissions",
            canSkip: true,
            completionNotification: "WizardTeamPermissionsViewed"
        ),
        WizardStepDefinition(
            id: "view_member_overrides",
            instruction: "TAP A TEAM MEMBER",
            description: "You can grant or deny specific permissions per person.",
            targetScreen: "Permissions",
            canSkip: true,
            completionNotification: "WizardMemberOverrideViewed"
        )
    ]
}
