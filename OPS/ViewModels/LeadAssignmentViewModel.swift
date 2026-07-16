//
//  LeadAssignmentViewModel.swift
//  OPS
//
//  Guarded, server-authoritative assignment state for LeadDetailView.
//

import Foundation
import Combine
import Supabase

@MainActor
protocol LeadAssignmentRepositoryProtocol: AnyObject {
    func listAssignmentCandidates(
        opportunityId: String
    ) async throws -> OpportunityAssignmentCandidates

    func changeAssignment(
        opportunityId: String,
        expectedAssignmentVersion: Int64,
        expectedAssignedTo: String?,
        newAssignedTo: String?,
        source: OpportunityAssignmentSource,
        suggestionId: String?,
        metadata: [String: AnyJSON]
    ) async throws -> OpportunityAssignmentChangeResult

    func fetchAssignmentSnapshot(
        opportunityId: String
    ) async throws -> OpportunityAssignmentSnapshot
}

extension OpportunityRepository: LeadAssignmentRepositoryProtocol {}

enum LeadAssignmentMutationOutcome: Equatable {
    case unchanged
    case updated
    case conflict
    case accessLost
    case failed
}

/// Pure routing contract consumed by LeadDetailView. Keeping dismissal and
/// scoped-refresh decisions outside the SwiftUI closure makes the two
/// access-revocation paths independently testable.
struct LeadAssignmentMutationDisposition: Equatable {
    let dismissPicker: Bool
    let dismissLead: Bool
    let refreshLeads: Bool
    let showSuccess: Bool

    static func resolve(
        outcome: LeadAssignmentMutationOutcome,
        retainsLeadAccess: Bool
    ) -> LeadAssignmentMutationDisposition {
        switch outcome {
        case .updated:
            return LeadAssignmentMutationDisposition(
                dismissPicker: true,
                dismissLead: !retainsLeadAccess,
                refreshLeads: true,
                showSuccess: true
            )

        case .conflict:
            return LeadAssignmentMutationDisposition(
                dismissPicker: !retainsLeadAccess,
                dismissLead: !retainsLeadAccess,
                refreshLeads: true,
                showSuccess: false
            )

        case .accessLost:
            return LeadAssignmentMutationDisposition(
                dismissPicker: true,
                dismissLead: true,
                refreshLeads: true,
                showSuccess: false
            )

        case .unchanged, .failed:
            return LeadAssignmentMutationDisposition(
                dismissPicker: false,
                dismissLead: false,
                refreshLeads: false,
                showSuccess: false
            )
        }
    }
}

@MainActor
final class LeadAssignmentViewModel: ObservableObject {
    @Published private(set) var candidates: [OpportunityAssignmentCandidate] = []
    @Published private(set) var canUnassign = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    let opportunity: Opportunity

    private let repository: LeadAssignmentRepositoryProtocol
    private var candidateLoadGeneration = 0

    init(
        opportunity: Opportunity,
        repository: LeadAssignmentRepositoryProtocol? = nil
    ) {
        self.opportunity = opportunity
        self.repository = repository ?? OpportunityRepository(
            companyId: opportunity.companyId
        )
    }

    func loadCandidates(isOnline: Bool) async {
        candidateLoadGeneration &+= 1
        let generation = candidateLoadGeneration

        errorMessage = nil
        isLoading = true

        guard isOnline else {
            candidates = []
            canUnassign = false
            isLoading = false
            errorMessage = "Connect to internet to reassign this lead."
            return
        }

        do {
            let response = try await repository.listAssignmentCandidates(
                opportunityId: opportunity.id
            )
            guard generation == candidateLoadGeneration else { return }
            candidates = response.candidates
            canUnassign = response.canUnassign
            isLoading = false
        } catch is CancellationError {
            guard generation == candidateLoadGeneration else { return }
            isLoading = false
        } catch {
            guard generation == candidateLoadGeneration else { return }
            candidates = []
            canUnassign = false
            isLoading = false
            errorMessage = "Team members unavailable. Try again."
        }
    }

    func changeAssignment(
        to newAssignedTo: String?,
        isOnline: Bool
    ) async -> LeadAssignmentMutationOutcome {
        guard !isSaving else { return .failed }

        errorMessage = nil

        guard isOnline else {
            errorMessage = "Connect to internet to reassign this lead."
            return .failed
        }

        if normalized(newAssignedTo) == normalized(opportunity.assignedTo) {
            return .unchanged
        }

        guard isAvailableTarget(newAssignedTo) else {
            errorMessage = "This assignment option is no longer available. Refresh and try again."
            return .failed
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let result = try await repository.changeAssignment(
                opportunityId: opportunity.id,
                expectedAssignmentVersion: opportunity.assignmentVersion,
                expectedAssignedTo: opportunity.assignedTo,
                newAssignedTo: newAssignedTo,
                source: .manual,
                suggestionId: nil,
                metadata: [:]
            )

            // A realtime refresh can advance this object while the guarded RPC
            // is in flight. Never regress the monotonic version in that race.
            if result.assignmentVersion < opportunity.assignmentVersion {
                await reconcileConflict()
                errorMessage = "Assignment changed. Review the current assignee and try again."
                return .conflict
            }

            if result.conflict {
                apply(
                    assignedTo: result.assignedTo,
                    assignmentVersion: result.assignmentVersion
                )
                await reconcileConflict()
                errorMessage = "Assignment changed. Review the current assignee and try again."
                return .conflict
            }

            guard result.ok else {
                errorMessage = "Assignment failed. Refresh and try again."
                return .failed
            }

            apply(
                assignedTo: result.assignedTo,
                assignmentVersion: result.assignmentVersion
            )
            return .updated
        } catch is CancellationError {
            return .failed
        } catch {
            if isAssignmentAccessLost(error) {
                // The guarded RPC intentionally withholds the replacement
                // assignee when assigned-scope authority disappeared while
                // this screen was stale. Drop every picker capability without
                // mutating the cached lead; the parent destroys the view and
                // requests a scoped server refresh.
                candidateLoadGeneration &+= 1
                candidates = []
                canUnassign = false
                errorMessage = nil
                return .accessLost
            }
            errorMessage = "Assignment failed. Refresh and try again."
            return .failed
        }
    }

    private func isAvailableTarget(_ userId: String?) -> Bool {
        guard let userId else { return canUnassign }
        return candidates.contains {
            normalized($0.id) == normalized(userId)
        }
    }

    private func reconcileConflict() async {
        candidateLoadGeneration &+= 1

        if let snapshot = try? await repository.fetchAssignmentSnapshot(
            opportunityId: opportunity.id
        ), snapshot.assignmentVersion >= opportunity.assignmentVersion {
            apply(
                assignedTo: snapshot.assignedTo,
                assignmentVersion: snapshot.assignmentVersion
            )
        }

        if let response = try? await repository.listAssignmentCandidates(
            opportunityId: opportunity.id
        ) {
            candidates = response.candidates
            canUnassign = response.canUnassign
        } else {
            candidates = []
            canUnassign = false
        }
    }

    private func apply(
        assignedTo: String?,
        assignmentVersion: Int64
    ) {
        opportunity.assignedTo = assignedTo
        opportunity.assignmentVersion = assignmentVersion
    }

    private func normalized(_ value: String?) -> String? {
        value?.lowercased()
    }

    private func isAssignmentAccessLost(_ error: Error) -> Bool {
        if let postgrestError = error as? PostgrestError {
            return postgrestError.code == "42501"
                && postgrestError.message.contains("assignment_access_lost")
        }

        // Preserve the stable server token if a future Supabase transport
        // wraps PostgrestError before it reaches this boundary.
        return String(describing: error).contains("assignment_access_lost")
    }
}
