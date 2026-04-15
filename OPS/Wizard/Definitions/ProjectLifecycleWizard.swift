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
    let displayDescription = "Create a client, build a project, assign your crew. Real data — not a demo."
    let bulletPoints = [
        "Add a client",
        "Build a project with tasks",
        "Assign dates and crew",
        "Swipe to change status"
    ]
    let iconName = "hammer.circle"
    let triggerType: WizardTriggerType = .sequenced
    let minimumTier: WizardAccessTier = .field
    let requiredPermission: String? = "projects.create"
    let bannerText = "Let's build your first project."
    let estimatedMinutes = 3

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
            description: "Give this job a name.",
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
            description: "There it is. Swipe right to move it forward.",
            targetScreen: "JobBoard",
            canSkip: true,
            completionNotification: "WizardProjectStatusChanged"
        )
    ]
}
