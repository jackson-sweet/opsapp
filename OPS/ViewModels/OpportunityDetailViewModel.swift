//
//  OpportunityDetailViewModel.swift
//  OPS
//
//  ViewModel for the Opportunity detail screen — activities, follow-ups, stage actions.
//

import SwiftUI

@MainActor
class OpportunityDetailViewModel: ObservableObject {
    @Published var activities: [Activity] = []
    @Published var followUps: [FollowUp] = []
    @Published var isLoading = false
    @Published var error: String? = nil

    private var repository: OpportunityRepository?

    func setup(companyId: String) {
        repository = OpportunityRepository(companyId: companyId)
    }

    func loadDetails(for opportunityId: String) async {
        guard let repo = repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let fetchedActivities = repo.fetchActivities(for: opportunityId)
            async let fetchedFollowUps = repo.fetchFollowUps(for: opportunityId)
            let (actDTOs, fuDTOs) = try await (fetchedActivities, fetchedFollowUps)
            activities = actDTOs.map { $0.toModel() }
            followUps = fuDTOs.map { $0.toModel() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func logActivity(opportunityId: String, companyId: String, type: ActivityType, body: String?) async {
        guard let repo = repository else { return }
        let dto = CreateActivityDTO(
            opportunityId: opportunityId,
            companyId: companyId,
            type: type.rawValue,
            body: body
        )
        do {
            let created = try await repo.logActivity(dto)
            activities.insert(created.toModel(), at: 0)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createFollowUp(opportunityId: String, companyId: String, type: FollowUpType, dueAt: Date, notes: String?) async {
        guard let repo = repository else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dto = CreateFollowUpDTO(
            opportunityId: opportunityId,
            companyId: companyId,
            type: type.rawValue,
            dueAt: formatter.string(from: dueAt),
            notes: notes
        )
        do {
            let created = try await repo.createFollowUp(dto)
            followUps.append(created.toModel())
            followUps.sort { $0.dueAt < $1.dueAt }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
