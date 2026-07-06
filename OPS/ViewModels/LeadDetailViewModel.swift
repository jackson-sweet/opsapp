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
    private let activityRepository: ActivityRepository

    init(opportunityId: String, companyId: String) {
        self.opportunityId = opportunityId
        self.companyId = companyId
        self.repository = OpportunityRepository(companyId: companyId)
        self.activityRepository = ActivityRepository(companyId: companyId)
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

    /// `createdBy` MUST be the operator's Supabase `users.id`
    /// (`dataController.currentUser?.id`) — never the Firebase UID. Routed
    /// through `ActivityRepository` (the unified activity write path) rather
    /// than `OpportunityRepository.logActivity`.
    func logActivity(type: ActivityType, subject: String?, body: String?, direction: String? = nil, outcome: String? = nil, durationMinutes: Int? = nil, callSource: String? = nil, callerNumber: String? = nil, callStartedAt: Date? = nil, createdBy: String?) async throws {
        let resultDTO = try await activityRepository.logActivity(
            target: .opportunity(makeOpportunityStub()),
            type: type,
            subject: subject,
            body: body,
            direction: direction,
            outcome: outcome,
            durationMinutes: durationMinutes,
            callSource: callSource,
            callerNumber: callerNumber,
            callStartedAt: callStartedAt,
            createdBy: createdBy
        )
        activities.insert(resultDTO.toModel(), at: 0)
    }

    /// `ActivityTarget.opportunity` carries the full model (its `parentKey`
    /// only reads `.id`, but the enum case requires an `Opportunity`). This
    /// view model only ever holds `opportunityId`/`companyId` strings, so a
    /// minimal stub is built at the call boundary rather than widening the
    /// view model's stored state.
    private func makeOpportunityStub() -> Opportunity {
        Opportunity(id: opportunityId, companyId: companyId, contactName: "", stage: .newLead)
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
