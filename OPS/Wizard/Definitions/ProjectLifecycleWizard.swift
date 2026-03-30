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
    let requiredPermission: String? = "projects.create"
    let bannerText = "Want help creating your first project?"

    let steps: [WizardStepDefinition] = [
        // --- Phase 1: Create a Client ---
        WizardStepDefinition(
            id: "open_fab",
            instruction: "TAP THE ACTION BUTTON",
            description: "The ⚡ button in the bottom-right corner — it's where you create projects, clients, and more.",
            targetScreen: "JobBoard",
            canSkip: false,
            completionNotification: "WizardFABTapped"
        ),
        WizardStepDefinition(
            id: "select_create_client",
            instruction: "TAP \"NEW CLIENT\"",
            description: "Let's start by adding a client — the customer this job is for.",
            targetScreen: "FABMenu",
            canSkip: false,
            completionNotification: "WizardCreateClientTapped"
        ),
        WizardStepDefinition(
            id: "fill_client_name",
            instruction: "CREATE YOUR CLIENT",
            description: "Fill in the client details and tap Create.",
            targetScreen: "ClientForm",
            canSkip: false,
            completionNotification: "WizardClientSaved"
        ),

        // --- Phase 2: Create a Project ---
        WizardStepDefinition(
            id: "open_fab_project",
            instruction: "TAP THE ACTION BUTTON AGAIN",
            description: "Now let's create a project for this client.",
            targetScreen: "JobBoard",
            canSkip: false,
            completionNotification: "WizardFABTapped"
        ),
        WizardStepDefinition(
            id: "select_create_project",
            instruction: "TAP \"NEW PROJECT\"",
            description: nil,
            targetScreen: "FABMenu",
            canSkip: false,
            completionNotification: "WizardCreateProjectTapped"
        ),
        WizardStepDefinition(
            id: "select_client",
            instruction: "SELECT YOUR CLIENT",
            description: "Pick the client you just created.",
            targetScreen: "ProjectForm",
            canSkip: false,
            completionNotification: "WizardProjectClientSelected"
        ),
        WizardStepDefinition(
            id: "enter_project_name",
            instruction: "ENTER A PROJECT NAME",
            description: "Name this job — something like \"Kitchen Renovation\" or \"Office Build.\"",
            targetScreen: "ProjectForm",
            canSkip: false,
            completionNotification: "WizardProjectNameEntered"
        ),

        // --- Phase 3: Add a Task to the Project ---
        WizardStepDefinition(
            id: "add_task",
            instruction: "ADD A TASK",
            description: "Tasks break the job into individual pieces of work.",
            targetScreen: "ProjectForm",
            canSkip: false,
            completionNotification: "WizardTaskAdded"
        ),
        WizardStepDefinition(
            id: "select_task_type",
            instruction: "SELECT A TASK TYPE",
            description: "Pick what kind of work this task is — like Plumbing, Framing, or Electrical.",
            targetScreen: "TaskForm",
            canSkip: false,
            completionNotification: "WizardTaskTypeSelected"
        ),
        WizardStepDefinition(
            id: "assign_date",
            instruction: "SET A DATE FOR THE TASK",
            description: "Pick when this work should happen.",
            targetScreen: "TaskForm",
            canSkip: false,
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
            id: "save_task",
            instruction: "TAP CREATE TO FINISH THE TASK",
            description: "This saves the task and takes you back to the project.",
            targetScreen: "TaskForm",
            canSkip: false,
            completionNotification: "WizardTaskSaved"
        ),

        // --- Phase 4: Save the Project ---
        WizardStepDefinition(
            id: "save_project",
            instruction: "TAP CREATE TO SAVE THE PROJECT",
            description: "Everything's set. Tap Create to save your project.",
            targetScreen: "ProjectForm",
            canSkip: false,
            completionNotification: "WizardProjectSaved"
        ),

        // --- Phase 5: See it on the Board ---
        WizardStepDefinition(
            id: "view_on_board",
            instruction: "FIND YOUR PROJECT ON THE BOARD",
            description: "Your new project appears in the job board. Swipe right to advance its status.",
            targetScreen: "JobBoard",
            canSkip: true,
            completionNotification: "WizardProjectStatusChanged"
        )
    ]
}
