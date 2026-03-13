//
//  ProjectLifecycleWizard.swift
//  OPS
//
//  The first and primary wizard: guides users through creating
//  a client, project, task, assigning dates and team, and
//  moving through the status workflow.
//

import Foundation

struct ProjectLifecycleWizard: WizardDefinitionProtocol {
    let wizardId = "project_lifecycle"
    let displayName = "PROJECT LIFECYCLE"
    let displayDescription = "Learn how to create and manage a project from start to finish. You'll create real data — a client, a project with tasks, assign your crew, and see how status tracking works."
    let bulletPoints = [
        "Create a client for your jobs",
        "Build a project with tasks",
        "Assign dates and crew members",
        "Move a project through its lifecycle"
    ]
    let iconName = "hammer.circle"
    let triggerType: WizardTriggerType = .sequenced
    let minimumTier: WizardAccessTier = .field
    let bannerText = "Want help creating your first project?"

    let steps: [WizardStepDefinition] = [
        WizardStepDefinition(
            id: "open_fab",
            instruction: "TAP THE + BUTTON",
            description: "This is where you create projects, clients, and more.",
            targetScreen: "JobBoard",
            completionNotification: "WizardFABTapped"
        ),
        WizardStepDefinition(
            id: "select_create_client",
            instruction: "TAP \"CREATE CLIENT\"",
            description: "Let's start by adding a client — the customer this job is for.",
            targetScreen: "FABMenu",
            completionNotification: "WizardCreateClientTapped"
        ),
        WizardStepDefinition(
            id: "fill_client_name",
            instruction: "ENTER THE CLIENT'S NAME",
            description: "Type the name of a real customer or company.",
            targetScreen: "ClientForm",
            completionNotification: "WizardClientSaved"
        ),
        WizardStepDefinition(
            id: "open_fab_project",
            instruction: "TAP THE + BUTTON AGAIN",
            description: "Now let's create a project for this client.",
            targetScreen: "JobBoard",
            completionNotification: "WizardFABTapped"
        ),
        WizardStepDefinition(
            id: "select_create_project",
            instruction: "TAP \"CREATE PROJECT\"",
            description: nil,
            targetScreen: "FABMenu",
            completionNotification: "WizardCreateProjectTapped"
        ),
        WizardStepDefinition(
            id: "select_client",
            instruction: "SELECT YOUR CLIENT",
            description: "Pick the client you just created.",
            targetScreen: "ProjectForm",
            completionNotification: "WizardProjectClientSelected"
        ),
        WizardStepDefinition(
            id: "enter_project_name",
            instruction: "ENTER A PROJECT NAME",
            description: "Name this job — something like \"Kitchen Renovation\" or \"Office Build.\"",
            targetScreen: "ProjectForm",
            completionNotification: "WizardProjectNameEntered"
        ),
        WizardStepDefinition(
            id: "add_task",
            instruction: "ADD A TASK",
            description: "Tasks break the job into individual pieces of work.",
            targetScreen: "ProjectForm",
            completionNotification: "WizardTaskAdded"
        ),
        WizardStepDefinition(
            id: "assign_date",
            instruction: "SET A DATE FOR THE TASK",
            description: "Pick when this work should happen.",
            targetScreen: "TaskForm",
            completionNotification: "WizardTaskDateSet"
        ),
        WizardStepDefinition(
            id: "assign_crew",
            instruction: "ASSIGN A CREW MEMBER",
            description: "They'll see this task on their schedule.",
            targetScreen: "TaskForm",
            canSkip: true,
            completionNotification: "WizardTaskCrewAssigned"
        ),
        WizardStepDefinition(
            id: "save_project",
            instruction: "SAVE YOUR PROJECT",
            description: "Tap Create to save everything.",
            targetScreen: "ProjectForm",
            completionNotification: "WizardProjectSaved"
        ),
        WizardStepDefinition(
            id: "view_on_board",
            instruction: "FIND YOUR PROJECT ON THE BOARD",
            description: "Your new project appears in the job board. Swipe right to advance its status.",
            targetScreen: "JobBoard",
            completionNotification: "WizardProjectStatusChanged"
        )
    ]
}
