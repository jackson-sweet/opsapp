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
        company.seatGraceStartDate = seatGraceStartDate.flatMap { SupabaseDate.parse($0) }
        company.hasPrioritySupport = hasPrioritySupport ?? false
        company.stripeCustomerId = stripeCustomerId
        company.externalId = companyCode
        company.accountHolderId = accountHolderId
        company.preciseSchedulingEnabled = preciseSchedulingEnabled ?? false
        company.skipWeekendsInAutoSchedule = skipWeekendsInAutoSchedule ?? true
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
    /// - User.hasCompletedAppOnboarding reads onboardingCompleted["ios"] (JSONB column).
    func toModel() -> User {
        let resolvedRole = role.flatMap { UserRole(rawValue: $0) } ?? .unassigned
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

        let onboardingIos = onboardingCompleted?["ios"] ?? false
        print("[DTO] User \(id): onboarding_completed raw=\(String(describing: onboardingCompleted)), ios=\(onboardingIos)")
        user.hasCompletedAppOnboarding = onboardingIos
        user.hasCompletedAppTutorial = hasCompletedTutorial ?? false
        user.devPermission = devPermission ?? false
        user.latitude = latitude
        user.longitude = longitude
        user.locationName = locationName
        user.isActive = isActive ?? true
        user.specialPermissions = specialPermissions ?? []
        user.emergencyContactName = emergencyContactName
        user.emergencyContactPhone = emergencyContactPhone
        user.emergencyContactRelationship = emergencyContactRelationship
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

        // Encode dependencies array into JSON string for SwiftData storage
        if let deps = dependencies, !deps.isEmpty,
           let data = try? JSONEncoder().encode(deps),
           let json = String(data: data, encoding: .utf8) {
            tt.dependenciesJSON = json
        }

        // Store default team member IDs as comma-separated string
        if let ids = defaultTeamMemberIds, !ids.isEmpty {
            tt.defaultTeamMemberIdsString = ids.joined(separator: ",")
        }

        if let dd = defaultDuration, dd >= 1 {
            tt.defaultDuration = dd
        }

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
        project.createdAt = createdAt.flatMap { SupabaseDate.parse($0) }
        project.createdBy = createdBy
        project.updatedAt = updatedAt.flatMap { SupabaseDate.parse($0) }
        return project
    }

    func toVinylOrderMarkerModel() -> ProjectVinylOrderMarker {
        ProjectVinylOrderMarker(
            projectId: id,
            status: resolvedVinylOrderStatus,
            orderedAt: vinylOrderedAt.flatMap { SupabaseDate.parse($0) },
            orderedBy: vinylOrderedBy,
            sourceProjectUpdatedAt: updatedAt.flatMap { SupabaseDate.parse($0) }
        )
    }

    var resolvedVinylOrderStatus: ProjectVinylOrderStatus {
        ProjectVinylOrderStatus(rawValue: vinylOrderStatus ?? "") ?? .notOrdered
    }
}

// MARK: - SupabaseProjectTaskDTO → ProjectTask

extension SupabaseProjectTaskDTO {
    func toModel() -> ProjectTask {
        let resolvedStatus = TaskStatus(rawValue: status) ?? .active
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
        task.displayOrder = displayOrder ?? 0
        task.teamMemberIdsString = (teamMemberIds ?? []).joined(separator: ",")
        task.sourceLineItemId = sourceLineItemId
        task.sourceEstimateId = sourceEstimateId
        task.startDate = startDate.flatMap { SupabaseDate.parse($0) }
        task.endDate = endDate.flatMap { SupabaseDate.parse($0) }
        task.duration = duration ?? 1

        // Encode dependency overrides into JSON string for SwiftData storage
        if let overrides = dependencyOverrides, !overrides.isEmpty,
           let data = try? JSONEncoder().encode(overrides),
           let json = String(data: data, encoding: .utf8) {
            task.dependencyOverridesJSON = json
        }

        // Parse "HH:mm" time strings into Date objects (today's date with that time)
        if let st = startTime {
            task.startTime = Self.parseTime(st) ?? task.startTime
        }
        if let et = endTime {
            task.endTime = Self.parseTime(et) ?? task.endTime
        }

        task.pairedFromTaskId = pairedFromTaskId
        task.scheduleLocked = scheduleLocked ?? false

        task.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        task.createdAt = createdAt.flatMap { SupabaseDate.parse($0) }
        return task
    }

    /// Parse an "HH:mm" string into a Date with today's date and that time.
    private static func parseTime(_ timeString: String) -> Date? {
        let parts = timeString.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }
        return Calendar.current.date(from: DateComponents(hour: hour, minute: minute))
    }
}
