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
//  Audit fixes (2026-03-30):
//  - view_company_code: "COMPANY CODE" → "CREW CODE" to match UI label
//  - view_company_code: "Tap Invite" → "Tap INVITE TEAM MEMBERS" to match button
//  - assign_role: instruction updated to describe the ··· menu interaction
//  - bulletPoints updated to match corrected step language
//

import Foundation

struct TeamManagementWizard: WizardDefinitionProtocol {
    let wizardId = "team_management"
    let displayName = "TEAM MANAGEMENT"
    let displayDescription = "Build your crew. Invite people, assign roles, control access."
    let bulletPoints = [
        "See your team roster",
        "Share the crew code",
        "Send invites by email or phone",
        "Assign roles"
    ]
    let iconName = "person.3.fill"
    let triggerType: WizardTriggerType = .contextual
    let minimumTier: WizardAccessTier = .office
    let requiredPermission: String? = "team.manage"
    let bannerText = "Let's get your team set up."
    let estimatedMinutes = 1

    let steps: [WizardStepDefinition] = [
        WizardStepDefinition(
            id: "view_team",
            instruction: "BROWSE YOUR TEAM",
            description: "Your team members are grouped by role. Scroll to see everyone.",
            targetScreen: "ManageTeam",
            canSkip: true,
            completionNotification: "WizardTeamListViewed"
        ),
        WizardStepDefinition(
            id: "view_company_code",
            instruction: "FIND YOUR CREW CODE",
            description: "Tap INVITE TEAM MEMBERS to see the crew code your team uses to join.",
            targetScreen: "ManageTeam",
            canSkip: true,
            completionNotification: "WizardCompanyCodeViewed"
        ),
        WizardStepDefinition(
            id: "send_invite",
            instruction: "SEND AN INVITE",
            description: "Enter an email or phone number, then tap Send Invites. They'll get a link to join.",
            targetScreen: "TeamInvite",
            canSkip: true,
            completionNotification: "WizardTeamInviteSent"
        ),
        WizardStepDefinition(
            id: "assign_role",
            instruction: "ASSIGN A ROLE",
            description: "Tap the \u{22EF} menu on a team member, then choose a new role under Change Role.",
            targetScreen: "ManageTeam",
            canSkip: true,
            completionNotification: "WizardTeamRoleAssigned"
        )
    ]
}
