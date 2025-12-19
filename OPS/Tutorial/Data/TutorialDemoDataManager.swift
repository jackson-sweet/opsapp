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

    init(context: ModelContext) {
        self.context = context
        self.dateCalculator = DemoDateCalculator()
    }

    // MARK: - Public API

    /// Seeds all demo data to SwiftData
    /// Order matters due to relationships: TaskTypes -> Users -> Clients -> Projects (with Tasks and CalendarEvents)
    func seedAllDemoData() async throws {
        print("[TUTORIAL_SEED] Starting demo data seeding...")

        // Seed in order of dependencies
        try await seedTaskTypes()
        try await seedUsers()
        try await seedClients()
        try await seedProjects()

        // Save all changes
        try context.save()

        print("[TUTORIAL_SEED] Demo data seeding complete!")
    }

    /// Cleans up all demo data from SwiftData
    /// Deletes in reverse order of creation to respect relationships
    func cleanupAllDemoData() async throws {
        print("[TUTORIAL_CLEANUP] Starting demo data cleanup...")

        // Delete in reverse order of creation
        try await deleteCalendarEvents()
        try await deleteTasks()
        try await deleteProjects()
        try await deleteClients()
        try await deleteTaskTypes()
        try await deleteUsers()

        // Save all changes
        try context.save()

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
                companyId: DemoIDs.demoCompany,
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
                companyId: DemoIDs.demoCompany
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

    private func seedClients() async throws {
        print("[TUTORIAL_SEED] Seeding clients...")

        for data in DemoClientData.all {
            let client = Client(
                id: data.id,
                name: data.name,
                address: data.address,
                companyId: DemoIDs.demoCompany
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
            project.companyId = DemoIDs.demoCompany

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
                    companyId: DemoIDs.demoCompany,
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

                let calendarEvent = CalendarEvent(
                    id: calendarEventId,
                    projectId: project.id,
                    companyId: DemoIDs.demoCompany,
                    title: eventTitle,
                    startDate: scheduledDate,
                    endDate: scheduledDate,  // Single-day events for demo
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
        let demoPrefix = "DEMO_"
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.id.starts(with: demoPrefix) }
        )
        let events = try context.fetch(descriptor)
        print("[TUTORIAL_CLEANUP] Deleting \(events.count) calendar events")
        events.forEach { context.delete($0) }
    }

    private func deleteTasks() async throws {
        let demoPrefix = "DEMO_"
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate { $0.id.starts(with: demoPrefix) }
        )
        let tasks = try context.fetch(descriptor)
        print("[TUTORIAL_CLEANUP] Deleting \(tasks.count) tasks")
        tasks.forEach { context.delete($0) }
    }

    private func deleteProjects() async throws {
        let demoPrefix = "DEMO_"
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id.starts(with: demoPrefix) }
        )
        let projects = try context.fetch(descriptor)
        print("[TUTORIAL_CLEANUP] Deleting \(projects.count) projects")
        projects.forEach { context.delete($0) }
    }

    private func deleteClients() async throws {
        let demoPrefix = "DEMO_"
        let descriptor = FetchDescriptor<Client>(
            predicate: #Predicate { $0.id.starts(with: demoPrefix) }
        )
        let clients = try context.fetch(descriptor)
        print("[TUTORIAL_CLEANUP] Deleting \(clients.count) clients")
        clients.forEach { context.delete($0) }
    }

    private func deleteTaskTypes() async throws {
        let demoPrefix = "DEMO_"
        let descriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate { $0.id.starts(with: demoPrefix) }
        )
        let taskTypes = try context.fetch(descriptor)
        print("[TUTORIAL_CLEANUP] Deleting \(taskTypes.count) task types")
        taskTypes.forEach { context.delete($0) }
    }

    private func deleteUsers() async throws {
        let demoPrefix = "DEMO_"
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.id.starts(with: demoPrefix) }
        )
        let users = try context.fetch(descriptor)
        print("[TUTORIAL_CLEANUP] Deleting \(users.count) users")
        users.forEach { context.delete($0) }
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
    func getDemoDataCounts() -> (projects: Int, tasks: Int, clients: Int, taskTypes: Int, users: Int, events: Int) {
        let demoPrefix = "DEMO_"
        let projectCount = (try? context.fetchCount(FetchDescriptor<Project>(predicate: #Predicate { $0.id.starts(with: demoPrefix) }))) ?? 0
        let taskCount = (try? context.fetchCount(FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id.starts(with: demoPrefix) }))) ?? 0
        let clientCount = (try? context.fetchCount(FetchDescriptor<Client>(predicate: #Predicate { $0.id.starts(with: demoPrefix) }))) ?? 0
        let taskTypeCount = (try? context.fetchCount(FetchDescriptor<TaskType>(predicate: #Predicate { $0.id.starts(with: demoPrefix) }))) ?? 0
        let userCount = (try? context.fetchCount(FetchDescriptor<User>(predicate: #Predicate { $0.id.starts(with: demoPrefix) }))) ?? 0
        let eventCount = (try? context.fetchCount(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.id.starts(with: demoPrefix) }))) ?? 0

        return (projectCount, taskCount, clientCount, taskTypeCount, userCount, eventCount)
    }
}
