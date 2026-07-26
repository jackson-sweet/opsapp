//
//  ProjectTaskDuplication.swift
//  OPS
//
//  Safe duplication contract for Project Details task actions.
//

import Foundation

enum ProjectTaskDuplicationError: Error, Equatable, LocalizedError {
    case invalidDependencyOverrides

    var errorDescription: String? {
        switch self {
        case .invalidDependencyOverrides:
            return "The task's dependency settings could not be copied."
        }
    }
}

enum ProjectTaskDuplication {
    /// The UI gate mirrors the live `project_tasks` INSERT policy: duplicating
    /// is task creation, not project editing. Deleted source rows and
    /// mention-only project access are never eligible.
    static func canDuplicate(
        canCreateTasks: Bool,
        isMentionOnly: Bool,
        sourceDeletedAt: Date?
    ) -> Bool {
        canCreateTasks && !isMentionOnly && sourceDeletedAt == nil
    }

    /// Produce the complete, testable create contract for an independent copy.
    /// Definition fields survive; operational scheduling, provenance, and
    /// pairing fields are deliberately reset.
    static func makeDTO(
        from source: ProjectTask,
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        displayOrder: Int
    ) throws -> SupabaseProjectTaskDTO {
        let dependencyOverrides: [TaskTypeDependency]?
        if let json = source.dependencyOverridesJSON {
            guard let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([TaskTypeDependency].self, from: data) else {
                throw ProjectTaskDuplicationError.invalidDependencyOverrides
            }
            dependencyOverrides = decoded
        } else {
            dependencyOverrides = nil
        }

        return SupabaseProjectTaskDTO(
            id: id.lowercased(),
            bubbleId: nil,
            companyId: source.companyId,
            projectId: source.projectId,
            taskTypeId: source.taskTypeId.isEmpty ? nil : source.taskTypeId,
            customTitle: source.customTitle,
            taskNotes: source.taskNotes,
            status: TaskStatus.active.rawValue,
            taskColor: source.taskColor,
            displayOrder: displayOrder,
            teamMemberIds: source.getTeamMemberIds(),
            sourceLineItemId: nil,
            sourceEstimateId: nil,
            startDate: nil,
            endDate: nil,
            duration: source.duration,
            dependencyOverrides: dependencyOverrides,
            startTime: nil,
            endTime: nil,
            pairedFromTaskId: nil,
            scheduleLocked: false,
            deletedAt: nil,
            createdAt: ISO8601DateFormatter().string(from: createdAt)
        )
    }
}
