//
//  TrashRecoveryPolicy.swift
//  OPS
//
//  Pure recovery planning and presentation contracts for Settings > Trash.
//  A task is never restored while its required Project parent remains deleted;
//  the UI presents that dependency as one explicit combined restore instead.
//

import Foundation

enum TrashSegment: String, CaseIterable, Hashable {
    case projects = "PROJECTS"
    case clients = "CLIENTS"
    case tasks = "TASKS"
}

// MARK: - Neutral segment appearance

/// Symbolic design tokens keep the contrast rule testable without comparing
/// opaque SwiftUI `Color` values. TrashView resolves these to OPSStyle tokens.
enum TrashSegmentToken: Equatable {
    case clear
    case text
    case text2
    case surfaceActive
    case fillNeutral
    case fillNeutralDim
    case opsAccent
}

struct TrashSegmentAppearance: Equatable {
    let labelInk: TrashSegmentToken
    let countInk: TrashSegmentToken
    let countFill: TrashSegmentToken
    let segmentFill: TrashSegmentToken

    var usesAccent: Bool {
        [labelInk, countInk, countFill, segmentFill].contains(.opsAccent)
    }

    static func resolve(isSelected: Bool) -> TrashSegmentAppearance {
        if isSelected {
            return TrashSegmentAppearance(
                labelInk: .text,
                countInk: .text,
                countFill: .fillNeutral,
                segmentFill: .surfaceActive
            )
        }
        return TrashSegmentAppearance(
            labelInk: .text2,
            countInk: .text2,
            countFill: .fillNeutralDim,
            segmentFill: .clear
        )
    }
}

// MARK: - Restore planning

enum TrashRecoveryEntityKind: String, Equatable, Hashable {
    case project
    case client
    case task

    var segment: TrashSegment {
        switch self {
        case .project: return .projects
        case .client: return .clients
        case .task: return .tasks
        }
    }

    var authorityLabel: String { rawValue.uppercased() }
}

struct TrashRecoveryEntityRef: Identifiable, Equatable, Hashable {
    let kind: TrashRecoveryEntityKind
    let id: String
    let title: String

    var stableID: String { "\(kind.rawValue):\(id)" }
}

enum TrashRecoveryUnsupportedReason: Equatable {
    case projectNotOnDevice
}

enum TrashRecoveryAvailability: Equatable {
    case ready
    case parentRequired(TrashRecoveryEntityRef)
    case unsupported(TrashRecoveryUnsupportedReason)
}

struct TrashRecoveryPlan: Equatable {
    let primary: TrashRecoveryEntityRef
    let availability: TrashRecoveryAvailability
    /// Parent-first order for local persistence and outbound sync records.
    let restoreOrder: [TrashRecoveryEntityRef]

    var actionLabel: String {
        switch availability {
        case .ready:
            return "RESTORE"
        case .parentRequired(let parent):
            return "RESTORE \(primary.kind.authorityLabel) + \(parent.kind.authorityLabel)"
        case .unsupported:
            return "RESTORE UNAVAILABLE"
        }
    }

    var isRestorable: Bool { !restoreOrder.isEmpty }
}

enum TrashRecoveryPolicy {
    static func plan(for project: Project) -> TrashRecoveryPlan {
        let entity = TrashRecoveryEntityRef(
            kind: .project,
            id: project.id,
            title: project.title
        )
        return TrashRecoveryPlan(
            primary: entity,
            availability: .ready,
            restoreOrder: [entity]
        )
    }

    static func plan(for client: Client) -> TrashRecoveryPlan {
        let entity = TrashRecoveryEntityRef(
            kind: .client,
            id: client.id,
            title: client.name
        )
        return TrashRecoveryPlan(
            primary: entity,
            availability: .ready,
            restoreOrder: [entity]
        )
    }

    static func plan(for task: ProjectTask, projects: [Project]) -> TrashRecoveryPlan {
        let taskEntity = TrashRecoveryEntityRef(
            kind: .task,
            id: task.id,
            title: task.displayTitle
        )
        guard let project = projects.first(where: { $0.id == task.projectId }) ?? task.project else {
            return TrashRecoveryPlan(
                primary: taskEntity,
                availability: .unsupported(.projectNotOnDevice),
                restoreOrder: []
            )
        }
        guard project.deletedAt != nil else {
            return TrashRecoveryPlan(
                primary: taskEntity,
                availability: .ready,
                restoreOrder: [taskEntity]
            )
        }

        let projectEntity = TrashRecoveryEntityRef(
            kind: .project,
            id: project.id,
            title: project.title
        )
        return TrashRecoveryPlan(
            primary: taskEntity,
            availability: .parentRequired(projectEntity),
            restoreOrder: [projectEntity, taskEntity]
        )
    }
}

struct TrashRestoreResult: Equatable {
    let restored: [TrashRecoveryEntityRef]
}

enum TrashRestoreError: LocalizedError {
    case contextUnavailable
    case entityNotOnDevice(TrashRecoveryEntityKind)
    case projectNotOnDevice
    case parentRestoreRequired(String)
    case nothingToRestore
    case persistenceFailed(String)
    case syncQueueFailed

    var errorDescription: String? {
        switch self {
        case .contextUnavailable:
            return "Recovery storage is not ready. Reopen Trash and try again."
        case .entityNotOnDevice(let kind):
            return "This \(kind.rawValue) is not on this device. Sync, then try again."
        case .projectNotOnDevice:
            return "The task's project is not on this device. Sync, then try again."
        case .parentRestoreRequired(let title):
            return "Restore \(title) with this task to keep the project link intact."
        case .nothingToRestore:
            return "This record is already restored."
        case .persistenceFailed:
            return "Could not save the restore on this device. Check storage and try again."
        case .syncQueueFailed:
            return "Restored locally, but sync could not be queued. Reopen Trash and try again."
        }
    }
}

// MARK: - Row presentation

enum TrashRecoveryThumbnailSource: Equatable {
    case projectPhoto(String)
    case clientProfile(String)
    case fallback(TrashRecoveryEntityKind)

    var urlString: String? {
        switch self {
        case .projectPhoto(let url), .clientProfile(let url): return url
        case .fallback: return nil
        }
    }

    var isCircular: Bool {
        if case .clientProfile = self { return true }
        return false
    }
}

enum TrashRecoveryThumbnailSourceResolver {
    static func project(_ project: Project, syncedPhotos: [ProjectPhoto]) -> TrashRecoveryThumbnailSource {
        let photos = syncedPhotos.filter { $0.projectId == project.id }
        if let url = project.mergedGalleryImageURLs(syncedPhotos: photos).first,
           !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .projectPhoto(url)
        }
        return .fallback(.project)
    }

    static func client(_ client: Client) -> TrashRecoveryThumbnailSource {
        if let url = normalized(client.profileImageURL) {
            return .clientProfile(url)
        }
        return .fallback(.client)
    }

    static func task(
        _ task: ProjectTask,
        projects: [Project],
        syncedPhotos: [ProjectPhoto]
    ) -> TrashRecoveryThumbnailSource {
        guard let project = projects.first(where: { $0.id == task.projectId }) ?? task.project else {
            return .fallback(.task)
        }
        let projectSource = self.project(project, syncedPhotos: syncedPhotos)
        if case .projectPhoto = projectSource { return projectSource }
        return .fallback(.task)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

struct TrashRecoveryDetail: Identifiable, Equatable {
    let label: String
    let value: String

    var id: String { label }
}

struct TrashRecoveryRowDescriptor: Identifiable, Equatable {
    let id: String
    let kind: TrashRecoveryEntityKind
    let title: String
    let metadataLines: [String]
    let details: [TrashRecoveryDetail]
    let thumbnail: TrashRecoveryThumbnailSource
    let plan: TrashRecoveryPlan

    var segment: TrashSegment { kind.segment }

    static func project(
        _ project: Project,
        syncedPhotos: [ProjectPhoto],
        now: Date = Date()
    ) -> TrashRecoveryRowDescriptor {
        let plan = TrashRecoveryPolicy.plan(for: project)
        let clientName = normalized(project.effectiveClientName)
        let location = normalized(project.address)
        let firstLine = clientName ?? location ?? "STATUS · \(project.status.displayName.uppercased())"
        let secondLine = [
            TrashRecoveryCopy.deletedLine(project.deletedAt, now: now),
            TrashRecoveryCopy.count(project.tasks.count, singular: "TASK"),
        ].joined(separator: " · ")

        var details = [
            TrashRecoveryDetail(label: "TYPE", value: "PROJECT"),
            TrashRecoveryDetail(label: "DELETED", value: TrashRecoveryCopy.deletedValue(project.deletedAt, now: now)),
            TrashRecoveryDetail(label: "STATUS", value: project.status.displayName.uppercased()),
        ]
        if let clientName { details.append(.init(label: "CLIENT", value: clientName)) }
        if let location { details.append(.init(label: "ADDRESS", value: location)) }

        return TrashRecoveryRowDescriptor(
            id: plan.primary.stableID,
            kind: .project,
            title: project.title,
            metadataLines: [firstLine, secondLine],
            details: details,
            thumbnail: TrashRecoveryThumbnailSourceResolver.project(project, syncedPhotos: syncedPhotos),
            plan: plan
        )
    }

    static func client(_ client: Client, now: Date = Date()) -> TrashRecoveryRowDescriptor {
        let plan = TrashRecoveryPolicy.plan(for: client)
        let contact = normalized(client.email)
            ?? normalized(client.phoneNumber)
            ?? normalized(client.address)
            ?? "NO CONTACT ON FILE"
        let secondLine = [
            TrashRecoveryCopy.deletedLine(client.deletedAt, now: now),
            TrashRecoveryCopy.count(client.projects.count, singular: "PROJECT"),
        ].joined(separator: " · ")

        var details = [
            TrashRecoveryDetail(label: "TYPE", value: "CLIENT"),
            TrashRecoveryDetail(label: "DELETED", value: TrashRecoveryCopy.deletedValue(client.deletedAt, now: now)),
        ]
        if let email = normalized(client.email) { details.append(.init(label: "EMAIL", value: email)) }
        if let phone = normalized(client.phoneNumber) { details.append(.init(label: "PHONE", value: phone)) }
        if let address = normalized(client.address) { details.append(.init(label: "ADDRESS", value: address)) }

        return TrashRecoveryRowDescriptor(
            id: plan.primary.stableID,
            kind: .client,
            title: client.name,
            metadataLines: [contact, secondLine],
            details: details,
            thumbnail: TrashRecoveryThumbnailSourceResolver.client(client),
            plan: plan
        )
    }

    static func task(
        _ task: ProjectTask,
        projects: [Project],
        syncedPhotos: [ProjectPhoto],
        now: Date = Date()
    ) -> TrashRecoveryRowDescriptor {
        let project = projects.first(where: { $0.id == task.projectId }) ?? task.project
        let plan = TrashRecoveryPolicy.plan(for: task, projects: projects)
        let projectLine = project?.title ?? "PROJECT NOT ON DEVICE"
        let secondLine = [
            TrashRecoveryCopy.deletedLine(task.deletedAt, now: now),
            "STATUS · \(task.status.displayName.uppercased())",
        ].joined(separator: " · ")

        var details = [
            TrashRecoveryDetail(label: "TYPE", value: "TASK"),
            TrashRecoveryDetail(label: "DELETED", value: TrashRecoveryCopy.deletedValue(task.deletedAt, now: now)),
            TrashRecoveryDetail(label: "STATUS", value: task.status.displayName.uppercased()),
            TrashRecoveryDetail(label: "PROJECT", value: projectLine),
        ]
        if let startDate = task.startDate {
            details.append(.init(label: "SCHEDULED", value: TrashRecoveryCopy.calendarDate(startDate)))
        }

        return TrashRecoveryRowDescriptor(
            id: plan.primary.stableID,
            kind: .task,
            title: task.displayTitle,
            metadataLines: [projectLine, secondLine],
            details: details,
            thumbnail: TrashRecoveryThumbnailSourceResolver.task(
                task,
                projects: projects,
                syncedPhotos: syncedPhotos
            ),
            plan: plan
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

enum TrashRecoveryCopy {
    static func deletedLine(_ deletedAt: Date?, now: Date) -> String {
        "DELETED \(deletedValue(deletedAt, now: now))"
    }

    static func deletedValue(_ deletedAt: Date?, now: Date) -> String {
        guard let deletedAt else { return "—" }
        let seconds = max(0, now.timeIntervalSince(deletedAt))
        if seconds < 3_600 { return "<1H AGO" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))H AGO" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400))D AGO" }
        if seconds < 2_592_000 { return "\(Int(seconds / 604_800))W AGO" }
        return calendarDate(deletedAt)
    }

    static func calendarDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year()).uppercased()
    }

    static func count(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "S")"
    }
}
