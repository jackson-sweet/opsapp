//
//  TeamManagementWizard.swift
//  OPS
//
//  Contextual wizard for team management features.
//  Triggers on first team settings visit. Walks users through
//  viewing the team, sharing the company code, inviting members,
//  and assigning roles.
//
//  Audit fixes (2026-03-26):
//  - Added requiredPermission "team.manage" — steps 2-4 require it
//  - view_team: canSkip=false — auto-completes on genuine scroll
//  - view_company_code: canSkip=true explicit — requires invite button visibility
//

import Foundation

struct TeamManagementWizard: WizardDefinitionProtocol {
    let wizardId = "team_management"
    let displayName = "TEAM MANAGEMENT"
    let displayDescription = "Build your crew. View your team, invite new members with your company code, and assign roles that control what everyone can see and do."
    let bulletPoints = [
        "View your team roster",
        "Share your company code to invite crew",
        "Send invitations by email or phone",
        "Assign roles to control access"
    ]
    let iconName = "person.3.fill"
    let triggerType: WizardTriggerType = .contextual
    let minimumTier: WizardAccessTier = .office
    let requiredPermission: String? = "team.manage"
    let bannerText = "Want help setting up your team?"

    let steps: [WizardStepDefinition] = [
        WizardStepDefinition(
            id: "view_team",
            instruction: "BROWSE YOUR TEAM",
            description: "Your team members are grouped by role. Scroll to see everyone.",
            targetScreen: "ManageTeam",
            canSkip: false,
            completionNotification: "WizardTeamListViewed"
        ),
        WizardStepDefinition(
            id: "view_company_code",
            instruction: "FIND YOUR COMPANY CODE",
            description: "Tap Invite to see the code your crew uses to join.",
            targetScreen: "ManageTeam",
            canSkip: true,
            completionNotification: "WizardCompanyCodeViewed"
        ),
        WizardStepDefinition(
            id: "send_invite",
            instruction: "INVITE A TEAM MEMBER",
            description: "Send an invite by email or phone. They'll get a link to join.",
            targetScreen: "TeamInvite",
            canSkip: true,
            completionNotification: "WizardTeamInviteSent"
        ),
        WizardStepDefinition(
            id: "assign_role",
            instruction: "ASSIGN A ROLE",
            description: "Tap a team member's role to change it. Roles control what they can access.",
            targetScreen: "ManageTeam",
            canSkip: true,
            completionNotification: "WizardTeamRoleAssigned"
        )
    ]
}
