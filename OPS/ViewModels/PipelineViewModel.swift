//
//  PipelineViewModel.swift
//  OPS
//
//  ViewModel for Pipeline CRM — manages opportunities, stage filtering, and optimistic updates.
//

import SwiftUI

@MainActor
class PipelineViewModel: ObservableObject {
    @Published var opportunities: [Opportunity] = []
    @Published var selectedStage: PipelineStage = .newLead
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    private var repository: OpportunityRepository?

    var filteredOpportunities: [Opportunity] {
        opportunities.filter { $0.stage == selectedStage }
    }

    var weightedPipelineValue: Double {
        opportunities
            .filter { !$0.stage.isTerminal }
            .reduce(0) { $0 + $1.weightedValue }
    }

    var activeDealsCount: Int {
        opportunities.filter { !$0.stage.isTerminal }.count
    }

    var stagesWithCounts: [(stage: PipelineStage, count: Int)] {
        PipelineStage.allCases.map { stage in
            (stage, opportunities.filter { $0.stage == stage }.count)
        }
    }

    func setup(companyId: String) {
        repository = OpportunityRepository(companyId: companyId)
    }

    func loadOpportunities() async {
        guard let repo = repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let dtos = try await repo.fetchAll()
            opportunities = dtos.map { $0.toModel() }
            // Auto-select first non-empty stage
            if let first = PipelineStage.allCases.first(where: { stage in
                opportunities.contains { $0.stage == stage }
            }) {
                selectedStage = first
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func advanceStage(opportunity: Opportunity) async {
        guard let nextStage = opportunity.stage.next,
              let repo = repository else { return }
        let originalStage = opportunity.stage
        // Optimistic update
        opportunity.stage = nextStage
        do {
            let updated = try await repo.advanceStage(opportunityId: opportunity.id, to: nextStage)
            opportunity.stage = PipelineStage(rawValue: updated.stage) ?? nextStage
        } catch {
            opportunity.stage = originalStage
            self.error = "Failed to advance stage"
        }
    }

    func markLost(opportunity: Opportunity, reason: String) async {
        guard let repo = repository else { return }
        do {
            _ = try await repo.advanceStage(opportunityId: opportunity.id, to: .lost, lossReason: reason)
            opportunity.stage = .lost
        } catch {
            self.error = error.localizedDescription
        }
    }

    func markWon(opportunity: Opportunity) async {
        guard let repo = repository else { return }
        do {
            _ = try await repo.advanceStage(opportunityId: opportunity.id, to: .won)
            opportunity.stage = .won
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createOpportunity(contactName: String, contactEmail: String?, contactPhone: String?, jobDescription: String?, estimatedValue: Double?, source: String?, companyId: String) async {
        guard let repo = repository else { return }
        let dto = CreateOpportunityDTO(
            companyId: companyId,
            contactName: contactName,
            contactEmail: contactEmail,
            contactPhone: contactPhone,
            jobDescription: jobDescription,
            estimatedValue: estimatedValue,
            source: source
        )
        do {
            let created = try await repo.create(dto)
            opportunities.insert(created.toModel(), at: 0)
            selectedStage = .newLead
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteOpportunity(_ opportunity: Opportunity) async {
        guard let repo = repository else { return }
        do {
            try await repo.delete(opportunity.id)
            opportunities.removeAll { $0.id == opportunity.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
