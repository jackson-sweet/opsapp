//
//  TutorialDemoDataManager.swift
//  OPS
//
//  Manager for seeding and cleaning up demo data for the interactive tutorial.
//  Creates SwiftData entities from demo constants and manages relationships.
//

import Foundation
import SwiftData
import UIKit

/// Manager for seeding and cleaning up tutorial demo data
@MainActor
class TutorialDemoDataManager {
    private let context: ModelContext
    private let dateCalculator: DemoDateCalculator
    private let companyId: String

    /// IDs of projects created by the user during the tutorial (not pre-seeded)
    private var userCreatedProjectIds: [String] = []

    init(context: ModelContext, companyId: String) {
        self.context = context
        self.companyId = companyId
        self.dateCalculator = DemoDateCalculator()
    }

    /// Register a user-created project ID for cleanup
    func registerUserCreatedProject(id: String) {
        userCreatedProjectIds.append(id)
        print("[TUTORIAL_CLEANUP] Registered user-created project for cleanup: \(id)")
    }

    // MARK: - Public API

    /// Seeds all demo data to SwiftData
    /// Order matters due to relationships: TaskTypes -> Users -> TeamMembers -> Clients -> Projects (with Tasks and CalendarEvents)
    func seedAllDemoData() async throws {
        print("[TUTORIAL_SEED] Starting demo data seeding...")

        // Seed in order of dependencies
        try await seedTaskTypes()
        try await seedUsers()
        try await seedTeamMembers()
        try await seedClients()
        try await seedProjects()

        // Save all changes
        try context.save()

        print("[TUTORIAL_SEED] Demo data seeding complete!")
    }

    /// Cleans up all demo data from SwiftData
    /// Deletes in reverse order of creation to respect relationships
    /// Each deletion method saves immediately to ensure data is removed
    func cleanupAllDemoData() async throws {
        print("[TUTORIAL_CLEANUP] Starting demo data cleanup...")
        print("[TUTORIAL_CLEANUP] User-created project IDs to delete: \(userCreatedProjectIds)")

        // Delete in reverse order of creation (each method saves after deletion)
        try await deleteCalendarEvents()
        try await deleteTasks()
        try await deleteProjects()
        try await deleteClients()
        try await deleteTeamMembers()
        try await deleteTaskTypes()
        try await deleteUsers()

        // Final save to ensure everything is committed
        try context.save()

        // Verify cleanup
        let remainingCounts = getDemoDataCounts()
        print("[TUTORIAL_CLEANUP] Remaining after cleanup - Projects: \(remainingCounts.projects), Tasks: \(remainingCounts.tasks), Events: \(remainingCounts.events)")

        print("[TUTORIAL_CLEANUP] Demo data cleanup complete!")
    }

    /// Assigns the current user to today's demo tasks for the employee flow
    /// This allows the employee to see tasks assigned to them
    func assignCurrentUserToTasks(userId: String) async throws {
        print("[TUTORIAL_ASSIGN] Assigning user \(userId) to demo tasks...")

        // Get the current user
        guard let currentUser = fetchUser(id: userId) else {
            print("[TUTORIAL_ASSIGN] Warning: User not found with ID: \(userId)")
            return
        }

        // Find tasks scheduled for today (IN_PROGRESS status from demo data)
        let todayTasks = try fetchTodayDemoTasks()
        print("[TUTORIAL_ASSIGN] Found \(todayTasks.count) tasks for today")

        // Assign current user to first 3 tasks (intentional limit per tutorial spec)
        // Employee tutorial flow only needs 2-3 tasks for the demo experience
        let tasksToAssign = Array(todayTasks.prefix(3))

        for task in tasksToAssign {
            // Add to team members if not already present
            if !task.teamMembers.contains(where: { $0.id == userId }) {
                task.teamMembers.append(currentUser)
                var ids = task.getTeamMemberIds()
                ids.append(userId)
                task.setTeamMemberIds(ids)

                print("[TUTORIAL_ASSIGN] Assigned user to task: \(task.displayTitle)")
            }

            // Update calendar event team members as well
            if let event = task.calendarEvent {
                if !event.teamMembers.contains(where: { $0.id == userId }) {
                    event.teamMembers.append(currentUser)
                    var eventIds = event.getTeamMemberIds()
                    eventIds.append(userId)
                    event.setTeamMemberIds(eventIds)
                }
            }
        }

        try context.save()
        print("[TUTORIAL_ASSIGN] User assignment complete!")
    }

    // MARK: - Seeding Methods

    private func seedTaskTypes() async throws {
        print("[TUTORIAL_SEED] Seeding task types...")

        for data in DemoTaskTypeData.all {
            let taskType = TaskType(
                id: data.id,
                display: data.display,
                color: data.color,
                companyId: companyId,
                isDefault: false,
                icon: data.icon
            )
            context.insert(taskType)
        }

        print("[TUTORIAL_SEED] Seeded \(DemoTaskTypeData.all.count) task types")
    }

    private func seedUsers() async throws {
        print("[TUTORIAL_SEED] Seeding users...")

        for data in DemoTeamMemberData.all {
            let user = User(
                id: data.id,
                firstName: data.firstName,
                lastName: data.lastName,
                role: .fieldCrew,
                companyId: companyId
            )

            // Load avatar image from asset catalog and store as Data
            // This ensures UserAvatar component can display it properly
            if let uiImage = UIImage(named: data.avatarAssetName),
               let imageData = uiImage.jpegData(compressionQuality: 0.8) {
                user.profileImageData = imageData
                print("[TUTORIAL_SEED] Loaded avatar for \(data.firstName)")
            } else {
                print("[TUTORIAL_SEED] Warning: Could not load avatar asset '\(data.avatarAssetName)'")
            }

            context.insert(user)
        }

        print("[TUTORIAL_SEED] Seeded \(DemoTeamMemberData.all.count) users")
    }

    private func seedTeamMembers() async throws {
        print("[TUTORIAL_SEED] Seeding team members...")

        for data in DemoTeamMemberData.all {
            let teamMember = TeamMember(
                id: data.id,
                firstName: data.firstName,
                lastName: data.lastName,
                role: "Field Crew",
                avatarURL: data.avatarAssetName  // Use asset name for local lookup
            )
            context.insert(teamMember)
        }

        print("[TUTORIAL_SEED] Seeded \(DemoTeamMemberData.all.count) team members")
    }

    private func seedClients() async throws {
        print("[TUTORIAL_SEED] Seeding clients...")

        for data in DemoClientData.all {
            let client = Client(
                id: data.id,
                name: data.name,
                address: data.address,
                companyId: companyId
            )
            client.latitude = data.latitude
            client.longitude = data.longitude
            context.insert(client)
        }

        print("[TUTORIAL_SEED] Seeded \(DemoClientData.all.count) clients")
    }

    private func seedProjects() async throws {
        print("[TUTORIAL_SEED] Seeding projects...")

        for projectData in DemoProjectData.all {
            // Create project with initial status (will be computed based on tasks)
            let project = Project(
                id: projectData.id,
                title: projectData.title,
                status: .accepted  // Initial status, will be updated based on tasks
            )
            project.projectDescription = projectData.description
            project.notes = projectData.notes
            project.companyId = companyId

            // Set project images if available
            if !projectData.imageAssets.isEmpty {
                project.setProjectImageURLs(projectData.imageAssets)
            }

            // Link client
            if let client = fetchClient(id: projectData.clientId) {
                project.client = client
                project.clientId = client.id
                project.address = client.address
                project.latitude = client.latitude
                project.longitude = client.longitude
            }

            context.insert(project)

            // Create tasks for this project
            for (index, taskData) in projectData.tasks.enumerated() {
                let taskId = DemoIDs.taskId(projectId: projectData.id, index: index)
                let scheduledDate = dateCalculator.date(for: taskData.daysFromCurrent)
                let taskStatus = dateCalculator.taskStatus(for: taskData.daysFromCurrent)

                // Get task type for color
                let taskType = fetchTaskType(id: taskData.taskTypeId)
                let taskColor = taskType?.color ?? "#59779F"

                let task = ProjectTask(
                    id: taskId,
                    projectId: project.id,
                    taskTypeId: taskData.taskTypeId,
                    companyId: companyId,
                    status: taskStatus,
                    taskColor: taskColor
                )
                task.taskNotes = taskData.notes
                task.project = project
                task.displayOrder = index

                // Link task type
                if let taskType = taskType {
                    task.taskType = taskType
                }

                // Assign crew
                let crewUsers = taskData.crewIds.compactMap { fetchUser(id: $0) }
                task.teamMembers = crewUsers
                task.setTeamMemberIds(taskData.crewIds)

                // Create calendar event for this task
                let calendarEventId = DemoIDs.calendarEventId(taskId: taskId)
                let eventTitle = "\(project.effectiveClientName) - \(project.title)"

                // Calculate end date based on duration (default 1 day = same day)
                let endDate: Date
                if taskData.durationDays > 1 {
                    endDate = Calendar.current.date(byAdding: .day, value: taskData.durationDays - 1, to: scheduledDate) ?? scheduledDate
                } else {
                    endDate = scheduledDate
                }

                let calendarEvent = CalendarEvent(
                    id: calendarEventId,
                    projectId: project.id,
                    companyId: companyId,
                    title: eventTitle,
                    startDate: scheduledDate,
                    endDate: endDate,
                    color: taskColor
                )
                calendarEvent.taskId = taskId
                calendarEvent.setTeamMemberIds(taskData.crewIds)
                calendarEvent.teamMembers = crewUsers
                calendarEvent.project = project

                context.insert(calendarEvent)

                // Link calendar event to task
                task.calendarEvent = calendarEvent
                task.calendarEventId = calendarEvent.id

                context.insert(task)
                project.tasks.append(task)
            }

            // Update project status based on tasks
            project.status = computeProjectStatus(tasks: project.tasks)

            // Update project dates from tasks
            if let startDate = project.computedStartDate {
                project.startDate = startDate
            }
            if let endDate = project.computedEndDate {
                project.endDate = endDate
            }

            // Update project team members from tasks
            project.updateTeamMembersFromTasks(in: context)
        }

        print("[TUTORIAL_SEED] Seeded \(DemoProjectData.all.count) projects with their tasks")
    }

    // MARK: - Cleanup Methods

    private func deleteCalendarEvents() async throws {
        // Delete events with DEMO_ prefix (all types: DEMO_EVENT_, etc.)
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate<CalendarEvent> { event in
                event.id.starts(with: "DEMO_")
            }
        )
        let events = try context.fetch(descriptor)
        print("[TUTORIAL_CLEANUP] Deleting \(events.count) calendar events by prefix")
        for event in events {
            context.delete(event)
        }

        // Also delete events linked to demo projects (fallback for any missed)
        let projectDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.id.starts(with: "DEMO_") }
        )
        let demoProjects = try context.fetch(projectDescriptor)
        for project in demoProjects {
            let projectId = project.id
            let eventsByProject = FetchDescriptor<CalendarEvent>(
                predicate: #Predicate<CalendarEvent> { $0.projectId == projectId }
            )
            let linkedEvents = try context.fetch(eventsByProject)
            print("[TUTORIAL_CLEANUP] Deleting \(linkedEvents.count) calendar events for project \(projectId)")
            for event in linkedEvents {
                context.delete(event)
            }
        }

        // Also delete events for user-created projects
        for projectId in userCreatedProjectIds {
            let eventsByProject = FetchDescriptor<CalendarEvent>(
                predicate: #Predicate<CalendarEvent> { $0.projectId == projectId }
            )
            let linkedEvents = try context.fetch(eventsByProject)
            print("[TUTORIAL_CLEANUP] Deleting \(linkedEvents.count) calendar events for user project \(projectId)")
            for event in linkedEvents {
                context.delete(event)
            }
        }

        try context.save()
    }

    private func deleteTasks() async throws {
        // Delete tasks with DEMO_ prefix
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { task in
                task.id.starts(with: "DEMO_")
            }
        )
        let tasks = try context.fetch(descriptor)
        print("[TUTORIAL_CLEANUP] Deleting \(tasks.count) tasks by prefix")
        for task in tasks {
            context.delete(task)
        }

        // Also delete tasks linked to demo projects (fallback)
        let projectDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.id.starts(with: "DEMO_") }
        )
        let demoProjects = try context.fetch(projectDescriptor)
        for project in demoProjects {
            let projectId = project.id
            let tasksByProject = FetchDescriptor<ProjectTask>(
                predicate: #Predicate<ProjectTask> { $0.projectId == projectId }
            )
            let linkedTasks = try context.fetch(tasksByProject)
            print("[TUTORIAL_CLEANUP] Deleting \(linkedTasks.count) tasks for project \(projectId)")
            for task in linkedTasks {
                context.delete(task)
            }
        }

        // Also delete tasks for user-created projects
        for projectId in userCreatedProjectIds {
            let tasksByProject = FetchDescriptor<ProjectTask>(
                predicate: #Predicate<ProjectTask> { $0.projectId == projectId }
            )
            let linkedTasks = try context.fetch(tasksByProject)
            print("[TUTORIAL_CLEANUP] Deleting \(linkedTasks.count) tasks for user project \(projectId)")
            for task in linkedTasks {
                context.delete(task)
            }
        }

        try context.save()
    }

    private func deleteProjects() async throws {
        // Delete demo-prefixed projects
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { project in
                project.id.starts(with: "DEMO_")
            }
        )
        let demoProjects = try context.fetch(descriptor)
        print("[TUTORIAL_CLEANUP] Deleting \(demoProjects.count) demo projects")
        for project in demoProjects {
            context.delete(project)
        }

        // Also delete user-created projects from this tutorial session
        for projectId in userCreatedProjectIds {
            let userProjectDescriptor = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { $0.id == projectId }
            )
            let userProjects = try context.fetch(userProjectDescriptor)
            print("[TUTORIAL_CLEANUP] Deleting \(userProjects.count) user-created project(s) with ID: \(projectId)")
            for project in userProjects {
                context.delete(project)
            }
        }

        try context.save()
    }

    private func deleteClients() async throws {
        let descriptor = FetchDescriptor<Client>(
            predicate: #Predicate<Client> { client in
                client.id.starts(with: "DEMO_")
            }
        )
        let clients = try context.fetch(descriptor)
        print("[TUTORIAL_CLEANUP] Deleting \(clients.count) clients")
        for client in clients {
            context.delete(client)
        }

        try context.save()
    }

    private func deleteTeamMembers() async throws {
        let descriptor = FetchDescriptor<TeamMember>(
            predicate: #Predicate<TeamMember> { member in
                member.id.starts(with: "DEMO_")
            }
        )
        let teamMembers = try context.fetch(descriptor)
        print("[TUTORIAL_CLEANUP] Deleting \(teamMembers.count) team members")
        for member in teamMembers {
            context.delete(member)
        }

        try context.save()
    }

    private func deleteTaskTypes() async throws {
        let descriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate<TaskType> { taskType in
                taskType.id.starts(with: "DEMO_")
            }
        )
        let taskTypes = try context.fetch(descriptor)
        print("[TUTORIAL_CLEANUP] Deleting \(taskTypes.count) task types")
        for taskType in taskTypes {
            context.delete(taskType)
        }

        try context.save()
    }

    private func deleteUsers() async throws {
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate<User> { user in
                user.id.starts(with: "DEMO_")
            }
        )
        let users = try context.fetch(descriptor)
        print("[TUTORIAL_CLEANUP] Deleting \(users.count) users")
        for user in users {
            context.delete(user)
        }

        try context.save()
    }

    // MARK: - Helper Methods

    /// Computes project status based on task statuses
    private func computeProjectStatus(tasks: [ProjectTask]) -> Status {
        if tasks.isEmpty {
            return .accepted
        }

        // If any task is in progress, project is in progress
        if tasks.contains(where: { $0.status == .inProgress }) {
            return .inProgress
        }

        // If all tasks are completed, project is completed
        if tasks.allSatisfy({ $0.status == .completed }) {
            return .completed
        }

        // If all tasks are cancelled, keep as accepted
        if tasks.allSatisfy({ $0.status == .cancelled }) {
            return .accepted
        }

        // Default to accepted (includes future tasks in .booked status)
        return .accepted
    }

    /// Fetches a client by ID
    private func fetchClient(id: String) -> Client? {
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    /// Fetches a task type by ID
    private func fetchTaskType(id: String) -> TaskType? {
        let descriptor = FetchDescriptor<TaskType>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    /// Fetches a user by ID
    private func fetchUser(id: String) -> User? {
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    /// Fetches demo tasks scheduled for today (IN_PROGRESS status)
    private func fetchTodayDemoTasks() throws -> [ProjectTask] {
        let demoPrefix = "DEMO_"
        let inProgressStatus = TaskStatus.inProgress
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { task in
                task.id.starts(with: demoPrefix) && task.status == inProgressStatus
            }
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Utility Methods

    /// Checks if demo data exists in the database
    func hasDemoData() -> Bool {
        let demoPrefix = "DEMO_"
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id.starts(with: demoPrefix) }
        )
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count > 0
    }

    /// Gets a count of all demo entities for debugging
    func getDemoDataCounts() -> (projects: Int, tasks: Int, clients: Int, taskTypes: Int, users: Int, teamMembers: Int, events: Int) {
        let demoPrefix = "DEMO_"
        let projectCount = (try? context.fetchCount(FetchDescriptor<Project>(predicate: #Predicate { $0.id.starts(with: demoPrefix) }))) ?? 0
        let taskCount = (try? context.fetchCount(FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id.starts(with: demoPrefix) }))) ?? 0
        let clientCount = (try? context.fetchCount(FetchDescriptor<Client>(predicate: #Predicate { $0.id.starts(with: demoPrefix) }))) ?? 0
        let taskTypeCount = (try? context.fetchCount(FetchDescriptor<TaskType>(predicate: #Predicate { $0.id.starts(with: demoPrefix) }))) ?? 0
        let userCount = (try? context.fetchCount(FetchDescriptor<User>(predicate: #Predicate { $0.id.starts(with: demoPrefix) }))) ?? 0
        let teamMemberCount = (try? context.fetchCount(FetchDescriptor<TeamMember>(predicate: #Predicate { $0.id.starts(with: demoPrefix) }))) ?? 0
        let eventCount = (try? context.fetchCount(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.id.starts(with: demoPrefix) }))) ?? 0

        return (projectCount, taskCount, clientCount, taskTypeCount, userCount, teamMemberCount, eventCount)
    }
}
