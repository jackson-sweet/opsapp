//
//  LeadDetailViewModel.swift
//  OPS
//
//  Loads activities, follow-ups, and stage transitions for one opportunity.
//

import SwiftUI

@MainActor
class LeadDetailViewModel: ObservableObject {
    @Published var activities: [Activity] = []
    @Published var followUps: [FollowUp] = []
    @Published var stageTransitions: [StageTransition] = []
    @Published var isLoading = false
    @Published var loadError: String? = nil

    private let opportunityId: String
    private let companyId: String
    private let repository: OpportunityRepository

    init(opportunityId: String, companyId: String) {
        self.opportunityId = opportunityId
        self.companyId = companyId
        self.repository = OpportunityRepository(companyId: companyId)
    }

    func loadAll() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        async let actsTask: () = loadActivities()
        async let fusTask: () = loadFollowUps()
        async let stsTask: () = loadStageTransitions()
        _ = await (actsTask, fusTask, stsTask)
    }

    private func loadActivities() async {
        do {
            let dtos = try await repository.fetchActivities(for: opportunityId)
            activities = dtos.map { $0.toModel() }
        } catch { print("[LeadDetail] activities failed: \(error)") }
    }

    private func loadFollowUps() async {
        do {
            let dtos = try await repository.fetchFollowUps(for: opportunityId)
            followUps = dtos.map { $0.toModel() }
        } catch { print("[LeadDetail] follow-ups failed: \(error)") }
    }

    private func loadStageTransitions() async {
        do {
            let dtos = try await repository.fetchStageTransitions(for: opportunityId)
            stageTransitions = dtos.map { $0.toModel() }
        } catch { print("[LeadDetail] transitions failed: \(error)") }
    }

    func logActivity(type: ActivityType, subject: String?, body: String?, direction: String? = nil, outcome: String? = nil, durationMinutes: Int? = nil, callSource: String? = nil, callerNumber: String? = nil, callStartedAt: Date? = nil) async throws {
        let dto = CreateActivityDTO(
            opportunityId: opportunityId,
            companyId: companyId,
            type: type.rawValue,
            subject: subject,
            bodyText: body,
            direction: direction,
            outcome: outcome,
            durationMinutes: durationMinutes,
            callSource: callSource,
            callerNumber: callerNumber,
            callStartedAt: callStartedAt.map { SupabaseDate.format($0) }
        )
        let resultDTO = try await repository.logActivity(dto)
        activities.insert(resultDTO.toModel(), at: 0)
    }

    func addFollowUp(title: String, description: String?, type: FollowUpType, dueAt: Date, reminderAt: Date?, assignedTo: String?) async throws {
        let dto = CreateFollowUpDTO(
            companyId: companyId,
            opportunityId: opportunityId,
            title: title,
            description: description,
            type: type.rawValue,
            dueAt: SupabaseDate.format(dueAt),
            reminderAt: reminderAt.map { SupabaseDate.format($0) },
            assignedTo: assignedTo
        )
        let resultDTO = try await repository.createFollowUp(dto)
        followUps.append(resultDTO.toModel())
        followUps.sort { $0.dueAt < $1.dueAt }
    }
}
