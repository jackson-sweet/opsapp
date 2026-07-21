//
//  UnscheduledReviewRepository.swift
//  OPS
//
//  Server-confirmed mutations for Unassigned Review. Each mutation re-reads
//  the authoritative task revision, then commits through the guarded review
//  RPC so a card never advances on an optimistic local-only write.
//

import Foundation
import Supabase

enum UnscheduledReviewRepositoryError: LocalizedError {
    case conflict
    case terminalState
    case crewChanged
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .conflict:
            return "Task changed while it was being reviewed"
        case .terminalState:
            return "Task is no longer active"
        case .crewChanged:
            return "Task crew changed while it was being scheduled"
        case .invalidResponse:
            return "Task update returned an invalid response"
        }
    }
}

struct UnscheduledReviewScheduleCommit: Sendable {
    let startDate: Date
    let endDate: Date
    let alreadyScheduled: Bool
}

final class UnscheduledReviewRepository {
    private struct RevisionRow: Decodable {
        let status: String
        let teamMemberIDs: [String]
        let startDate: String?
        let endDate: String?
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case status
            case teamMemberIDs = "team_member_ids"
            case startDate = "start_date"
            case endDate = "end_date"
            case updatedAt = "updated_at"
        }
    }

    private struct MutationParams: Encodable {
        let p_task_id: String
        let p_expected_updated_at: String
        let p_action: String
        let p_expected_team_member_ids: [String]?
        let p_patch: [String: AnyJSON]
        let p_idempotency_key: String?
    }

    private struct MutationResult: Decodable {
        let ok: Bool
        let conflict: Bool
        let changed: Bool?
        let updatedAt: String?
        let alreadyScheduled: Bool?

        enum CodingKeys: String, CodingKey {
            case ok
            case conflict
            case changed
            case updatedAt = "updated_at"
            case alreadyScheduled = "already_scheduled"
        }
    }

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    @MainActor
    convenience init() {
        self.init(client: SupabaseService.shared.client)
    }

    func assignCrew(
        taskID: String,
        baseline: Set<String>,
        selected: Set<String>
    ) async throws -> [String] {
        // One CAS retry rebases the operator's picker delta over a concurrent
        // crew update without dropping the remote member.
        for attempt in 0..<2 {
            let revision = try await fetchRevision(taskID)
            try requireActive(revision)
            let current = Set(revision.teamMemberIDs.map { $0.lowercased() })
            let rebased = ReviewCrewAssignmentRebase.rebase(
                baseline: Set(baseline.map { $0.lowercased() }),
                selected: Set(selected.map { $0.lowercased() }),
                current: current
            )
            guard !rebased.isEmpty else {
                throw UnscheduledReviewRepositoryError.invalidResponse
            }

            do {
                try await mutate(
                    taskID: taskID,
                    revision: revision,
                    action: "assign",
                    expectedCrew: Array(current),
                    patch: [
                        "team_member_ids": .array(
                            rebased.sorted().map(AnyJSON.string)
                        )
                    ]
                )
                return rebased.sorted()
            } catch UnscheduledReviewRepositoryError.conflict where attempt == 0 {
                continue
            }
        }
        throw UnscheduledReviewRepositoryError.conflict
    }

    func schedule(
        taskID: String,
        expectedCrew: Set<String>,
        startDate: Date,
        endDate: Date,
        scheduleLocked: Bool
    ) async throws -> UnscheduledReviewScheduleCommit {
        let revision = try await fetchRevision(taskID)
        try requireActive(revision)

        if let existingStart = revision.startDate.flatMap(SupabaseDate.parse) {
            let existingEnd = revision.endDate.flatMap(SupabaseDate.parse) ?? existingStart
            return UnscheduledReviewScheduleCommit(
                startDate: existingStart,
                endDate: existingEnd,
                alreadyScheduled: true
            )
        }

        let authoritativeCrew = Set(revision.teamMemberIDs.map { $0.lowercased() })
        guard authoritativeCrew == Set(expectedCrew.map { $0.lowercased() }) else {
            throw UnscheduledReviewRepositoryError.crewChanged
        }

        let duration = max(
            1,
            (Calendar.current.dateComponents(
                [.day],
                from: startDate,
                to: endDate
            ).day ?? 0) + 1
        )
        try await mutate(
            taskID: taskID,
            revision: revision,
            action: "schedule",
            expectedCrew: Array(authoritativeCrew),
            patch: [
                "start_date": .string(SupabaseDate.format(startDate)),
                "end_date": .string(SupabaseDate.format(endDate)),
                "duration": .integer(duration),
                "schedule_locked": .bool(scheduleLocked),
            ]
        )
        return UnscheduledReviewScheduleCommit(
            startDate: startDate,
            endDate: endDate,
            alreadyScheduled: false
        )
    }

    func complete(taskID: String) async throws {
        let revision = try await fetchRevision(taskID)
        if revision.status == TaskStatus.completed.rawValue { return }
        try requireActive(revision)
        try await mutate(
            taskID: taskID,
            revision: revision,
            action: "complete",
            expectedCrew: revision.teamMemberIDs,
            patch: [:],
            idempotencyKey: TaskCompletionSync.stableCompletionIdempotencyKey(
                taskId: taskID
            )
        )
    }

    func cancel(taskID: String) async throws {
        let revision = try await fetchRevision(taskID)
        if revision.status == TaskStatus.cancelled.rawValue { return }
        try requireActive(revision)
        try await mutate(
            taskID: taskID,
            revision: revision,
            action: "cancel",
            expectedCrew: revision.teamMemberIDs,
            patch: [:]
        )
    }

    private func fetchRevision(_ taskID: String) async throws -> RevisionRow {
        try await client
            .from("project_tasks")
            .select("status,team_member_ids,start_date,end_date,updated_at")
            .eq("id", value: taskID)
            .single()
            .execute()
            .value
    }

    private func requireActive(_ revision: RevisionRow) throws {
        guard revision.status == TaskStatus.active.rawValue else {
            throw UnscheduledReviewRepositoryError.terminalState
        }
    }

    private func mutate(
        taskID: String,
        revision: RevisionRow,
        action: String,
        expectedCrew: [String]?,
        patch: [String: AnyJSON],
        idempotencyKey: String? = nil
    ) async throws {
        let result: MutationResult = try await client
            .rpc(
                "mutate_task_from_unassigned_review",
                params: MutationParams(
                    p_task_id: taskID,
                    p_expected_updated_at: revision.updatedAt,
                    p_action: action,
                    p_expected_team_member_ids: expectedCrew,
                    p_patch: patch,
                    p_idempotency_key: idempotencyKey
                )
            )
            .execute()
            .value
        guard result.ok else {
            if result.conflict {
                throw UnscheduledReviewRepositoryError.conflict
            }
            throw UnscheduledReviewRepositoryError.invalidResponse
        }
    }
}
