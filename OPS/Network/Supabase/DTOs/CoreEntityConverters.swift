//
//  CoreEntityConverters.swift
//  OPS
//
//  Converts Supabase DTOs to SwiftData model objects.
//  Following the same pattern as OpportunityDTOs.swift (toModel() inline method).
//
//  IMPORTANT: Every converter here was written against the ACTUAL Swift model
//  initializer signatures found in OPS/DataModels/. The plan's template was
//  significantly adjusted — see comments for each deviation.
//

import Foundation

// MARK: - SupabaseCompanyDTO → Company

extension SupabaseCompanyDTO {
    /// Converts to a Company SwiftData model.
    ///
    /// Deviations from plan template:
    /// - Company.init(id:name:) — correct, matches actual signature.
    /// - Company stores adminIds as `adminIdsString` (comma-separated), NOT [String].
    /// - Company stores seatedEmployeeIds as `seatedEmployeeIds` (comma-separated String), NOT [String].
    /// - Company.subscriptionStatus and .subscriptionPlan are plain String?, NOT enums.
    /// - Company.subscriptionEnd, .trialStartDate, .trialEndDate are Date? stored properties.
    /// - Company.logoURL (not .logoUrl — different capitalization).
    func toModel() -> Company {
        let company = Company(id: id, name: name)
        company.logoURL = logoUrl
        company.companyDescription = description
        company.website = website
        company.phone = phone
        company.email = email
        company.address = address
        company.latitude = latitude
        company.longitude = longitude
        company.defaultProjectColor = defaultProjectColor ?? "#9CA3AF"
        company.adminIdsString = (adminIds ?? []).joined(separator: ",")
        company.seatedEmployeeIds = (seatedEmployeeIds ?? []).joined(separator: ",")
        company.maxSeats = maxSeats ?? 10
        company.subscriptionStatus = subscriptionStatus
        company.subscriptionPlan = subscriptionPlan
        company.subscriptionEnd = subscriptionEnd.flatMap { SupabaseDate.parse($0) }
        company.subscriptionPeriod = subscriptionPeriod
        company.trialStartDate = trialStartDate.flatMap { SupabaseDate.parse($0) }
        company.trialEndDate = trialEndDate.flatMap { SupabaseDate.parse($0) }
        company.hasPrioritySupport = hasPrioritySupport ?? false
        company.stripeCustomerId = stripeCustomerId
        company.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return company
    }
}

// MARK: - SupabaseUserDTO → User

extension SupabaseUserDTO {
    /// Converts to a User SwiftData model.
    ///
    /// Deviations from plan template:
    /// - User.init requires (id:firstName:lastName:role:companyId:) — role and companyId are NOT optional.
    /// - User.profileImageURL (not profileImageUrl).
    /// - User.hasCompletedAppOnboarding / hasCompletedAppTutorial (not hasCompletedOnboarding/Tutorial).
    func toModel() -> User {
        let resolvedRole = role.flatMap { UserRole(rawValue: $0) } ?? .fieldCrew
        let resolvedCompanyId = companyId ?? ""
        let user = User(
            id: id,
            firstName: firstName,
            lastName: lastName,
            role: resolvedRole,
            companyId: resolvedCompanyId
        )
        user.email = email
        user.phone = phone
        user.homeAddress = homeAddress
        user.profileImageURL = profileImageUrl
        user.userColor = userColor
        user.userType = userType.flatMap { UserType(rawValue: $0) }
        user.isCompanyAdmin = isCompanyAdmin ?? false
        user.hasCompletedAppOnboarding = hasCompletedOnboarding ?? false
        user.hasCompletedAppTutorial = hasCompletedTutorial ?? false
        user.devPermission = devPermission ?? false
        user.latitude = latitude
        user.longitude = longitude
        user.locationName = locationName
        user.isActive = isActive ?? true
        user.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return user
    }
}

// MARK: - SupabaseClientDTO → Client

extension SupabaseClientDTO {
    /// Converts to a Client SwiftData model.
    ///
    /// Deviations from plan template:
    /// - Client.init(id:name:...) — all params optional except id and name.
    ///   companyId is optional in init but stored separately.
    /// - Client stores phone as `phoneNumber` (not `phone`).
    func toModel() -> Client {
        let client = Client(
            id: id,
            name: name,
            email: email,
            phoneNumber: phoneNumber,
            address: address,
            companyId: companyId,
            notes: notes
        )
        client.latitude = latitude
        client.longitude = longitude
        client.profileImageURL = profileImageUrl
        client.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return client
    }
}

// MARK: - SupabaseSubClientDTO → SubClient

extension SupabaseSubClientDTO {
    /// Converts to a SubClient SwiftData model.
    ///
    /// Deviations from plan template:
    /// - SubClient has NO clientId stored property — the plan's `init(id:name:clientId:)` doesn't exist.
    ///   SubClient.init(id:name:title:email:phoneNumber:address:) is the actual signature.
    /// - SubClient has NO companyId property at all.
    /// - SubClient stores phone as `phoneNumber` (not `phone`).
    /// - The clientId from the DTO cannot be set directly — the Client relationship
    ///   must be established by the repository/sync layer after fetching the parent Client.
    func toModel() -> SubClient {
        let sub = SubClient(
            id: id,
            name: name,
            title: title,
            email: email,
            phoneNumber: phoneNumber,
            address: address
        )
        sub.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return sub
    }

    /// The Supabase clientId that this SubClient belongs to.
    /// Use this after calling toModel() to find and assign the parent Client relationship.
    var parentClientId: String { clientId }
}

// MARK: - SupabaseTaskTypeDTO → TaskType

extension SupabaseTaskTypeDTO {
    /// Converts to a TaskType SwiftData model.
    ///
    /// Deviations from plan template:
    /// - TaskType.init uses `display` not `name` — plan template used `name`.
    /// - TaskType has NO `isActive` property — plan template set `tt.isActive`.
    ///   `isDefault` exists and is used instead.
    func toModel() -> TaskType {
        let tt = TaskType(
            id: id,
            display: display,
            color: color,
            companyId: companyId,
            isDefault: isDefault ?? false,
            icon: icon
        )
        tt.displayOrder = displayOrder ?? 0
        tt.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return tt
    }
}

// MARK: - SupabaseProjectDTO → Project

extension SupabaseProjectDTO {
    /// Converts to a Project SwiftData model.
    ///
    /// Deviations from plan template:
    /// - Project.init is `init(id:title:status:)` — plan template used `init(id:title:companyId:)`.
    ///   `companyId` is set as a property after init.
    func toModel() -> Project {
        let resolvedStatus = Status(rawValue: status) ?? .rfq
        let project = Project(id: id, title: title, status: resolvedStatus)
        project.companyId = companyId
        project.clientId = clientId
        project.opportunityId = opportunityId
        project.address = address
        project.latitude = latitude
        project.longitude = longitude
        project.startDate = startDate.flatMap { SupabaseDate.parse($0) }
        project.endDate = endDate.flatMap { SupabaseDate.parse($0) }
        project.duration = duration
        project.notes = notes
        project.projectDescription = description
        project.allDay = allDay ?? false
        project.teamMemberIdsString = (teamMemberIds ?? []).joined(separator: ",")
        project.projectImagesString = (projectImages ?? []).joined(separator: ",")
        project.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return project
    }
}

// MARK: - SupabaseProjectTaskDTO → ProjectTask

extension SupabaseProjectTaskDTO {
    /// Converts to a ProjectTask SwiftData model.
    ///
    /// Deviations from plan template:
    /// - ProjectTask.init requires (id:projectId:taskTypeId:companyId:status:taskColor:).
    ///   Plan template used `init(id:title:projectId:)` which does not exist.
    /// - ProjectTask has NO `title` property — uses `customTitle` and taskType.display.
    /// - ProjectTask has NO `notes` property — uses `taskNotes`.
    /// - ProjectTask has NO `scheduledDate` or `scheduledEndDate` stored properties —
    ///   dates come from the linked CalendarEvent. The plan's template for these does not apply.
    /// - ProjectTask has NO `allDay` property — plan template set this.
    /// - `calendarEventId` is stored as a string on the model for later lookup.
    func toModel() -> ProjectTask {
        let resolvedStatus = TaskStatus(rawValue: status) ?? .booked
        let task = ProjectTask(
            id: id,
            projectId: projectId,
            taskTypeId: taskTypeId ?? "",
            companyId: companyId,
            status: resolvedStatus,
            taskColor: taskColor ?? "#59779F"
        )
        task.customTitle = customTitle
        task.taskNotes = taskNotes
        task.calendarEventId = calendarEventId
        task.displayOrder = displayOrder ?? 0
        task.teamMemberIdsString = (teamMemberIds ?? []).joined(separator: ",")
        task.sourceLineItemId = sourceLineItemId
        task.sourceEstimateId = sourceEstimateId
        task.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return task
    }
}

// MARK: - SupabaseCalendarEventDTO → CalendarEvent

extension SupabaseCalendarEventDTO {
    /// Converts to a CalendarEvent SwiftData model.
    ///
    /// Deviations from plan template:
    /// - CalendarEvent.init requires (id:projectId:companyId:title:startDate:endDate:color:).
    ///   Plan template used `init(id:companyId:startDate:)` which does not exist.
    /// - CalendarEvent has NO `allDay` property — plan template set this.
    /// - CalendarEvent has NO `eventType` stored property accessed directly — it has
    ///   CalendarEventType enum but defaults to .task.
    /// - CalendarEvent has NO `taskId` in its init — it is set as a separate property.
    ///   In the Supabase schema, task linkage flows via project_tasks.calendar_event_id,
    ///   not calendar_events.task_id. The taskId property on the model is set by the
    ///   sync layer after resolving the owning task.
    /// - `teamMemberIds` from Supabase is stored via setTeamMemberIds().
    func toModel() -> CalendarEvent {
        let resolvedStart = startDate.flatMap { SupabaseDate.parse($0) }
        let resolvedEnd = endDate.flatMap { SupabaseDate.parse($0) }
        let event = CalendarEvent(
            id: id,
            projectId: projectId ?? "",
            companyId: companyId,
            title: title,
            startDate: resolvedStart,
            endDate: resolvedEnd,
            color: color ?? "#417394"
        )
        event.setTeamMemberIds(teamMemberIds ?? [])
        event.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        return event
    }
}
