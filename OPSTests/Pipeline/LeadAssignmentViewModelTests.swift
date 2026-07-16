//
//  LeadAssignmentViewModelTests.swift
//  OPSTests
//
//  Focused contract tests for the first-class lead-detail assignment workflow.
//

import XCTest
import Supabase
@testable import OPS

@MainActor
final class LeadAssignmentViewModelTests: XCTestCase {
    func testCandidateEnvelopeDecodesOnlyGuardedPickerFields() throws {
        let envelope = try JSONDecoder().decode(
            OpportunityAssignmentCandidates.self,
            from: Data(
                #"""
                {
                  "can_unassign": true,
                  "candidates": [
                    {
                      "id": "user-jason",
                      "first_name": "Jason",
                      "last_name": "Zavarella",
                      "profile_image_url": "https://cdn.example/jason.jpg",
                      "user_color": "#6F94B0"
                    },
                    {
                      "id": "user-amy",
                      "first_name": null,
                      "last_name": null,
                      "profile_image_url": null,
                      "user_color": null
                    }
                  ]
                }
                """#.utf8
            )
        )

        XCTAssertTrue(envelope.canUnassign)
        XCTAssertEqual(envelope.candidates.map(\.id), ["user-jason", "user-amy"])
        XCTAssertEqual(envelope.candidates.first?.displayName, "Jason Zavarella")
        XCTAssertEqual(envelope.candidates.last?.displayName, "")
    }

    func testOfflineCandidateLoadFailsClosedWithoutCallingRepository() async {
        let repository = AssignmentRepositoryMock()
        let lead = makeLead()
        let viewModel = LeadAssignmentViewModel(
            opportunity: lead,
            repository: repository
        )

        await viewModel.loadCandidates(isOnline: false)

        XCTAssertEqual(repository.listCandidatesCallCount, 0)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertFalse(viewModel.canUnassign)
        XCTAssertEqual(
            viewModel.errorMessage,
            "Connect to internet to reassign this lead."
        )
    }

    func testMutationDoesNotChangeLeadUntilGuardedResponseReturns() async throws {
        let repository = AssignmentRepositoryMock()
        repository.candidateResponses = [
            .success(candidateEnvelope(canUnassign: false))
        ]
        repository.suspendChange = true

        let lead = makeLead(assignedTo: "user-jason", assignmentVersion: 7)
        let viewModel = LeadAssignmentViewModel(
            opportunity: lead,
            repository: repository
        )
        await viewModel.loadCandidates(isOnline: true)

        let task = Task {
            await viewModel.changeAssignment(to: "user-amy", isOnline: true)
        }
        await waitUntil { repository.pendingChange != nil }

        XCTAssertEqual(lead.assignedTo, "user-jason")
        XCTAssertEqual(lead.assignmentVersion, 7)
        XCTAssertEqual(repository.lastChange?.expectedAssignedTo, "user-jason")
        XCTAssertEqual(repository.lastChange?.expectedAssignmentVersion, 7)
        XCTAssertEqual(repository.lastChange?.newAssignedTo, "user-amy")

        repository.resumeChange(
            with: try OpportunityAssignmentChangeResult(
                ok: true,
                conflict: false,
                assignedTo: "user-amy",
                assignmentVersion: 8,
                eventId: "event-1"
            )
        )

        let outcome = await task.value
        XCTAssertEqual(outcome, .updated)
        XCTAssertEqual(lead.assignedTo, "user-amy")
        XCTAssertEqual(lead.assignmentVersion, 8)
    }

    func testAssignedScopeCannotSubmitUnassignWhenGuardedEnvelopeForbidsIt() async {
        let repository = AssignmentRepositoryMock()
        repository.candidateResponses = [
            .success(candidateEnvelope(canUnassign: false))
        ]
        let lead = makeLead()
        let viewModel = LeadAssignmentViewModel(
            opportunity: lead,
            repository: repository
        )
        await viewModel.loadCandidates(isOnline: true)

        let outcome = await viewModel.changeAssignment(to: nil, isOnline: true)

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(repository.changeCallCount, 0)
        XCTAssertEqual(
            viewModel.errorMessage,
            "This assignment option is no longer available. Refresh and try again."
        )
        XCTAssertEqual(lead.assignedTo, "user-jason")
    }

    func testConflictAppliesReturnedStateThenRefreshesSnapshotAndCandidates() async throws {
        let repository = AssignmentRepositoryMock()
        repository.candidateResponses = [
            .success(candidateEnvelope(canUnassign: false)),
            .success(
                OpportunityAssignmentCandidates(
                    canUnassign: true,
                    candidates: [
                        OpportunityAssignmentCandidate(
                            id: "user-chris",
                            firstName: "Chris",
                            lastName: "Ng",
                            profileImageURL: nil,
                            userColor: nil
                        )
                    ]
                )
            )
        ]
        repository.changeResponse = .success(
            try OpportunityAssignmentChangeResult(
                ok: false,
                conflict: true,
                assignedTo: "user-amy",
                assignmentVersion: 8,
                eventId: nil
            )
        )
        repository.snapshotResponse = .success(
            OpportunityAssignmentSnapshot(
                assignedTo: "user-chris",
                assignmentVersion: 9
            )
        )

        let lead = makeLead(assignedTo: "user-jason", assignmentVersion: 7)
        let viewModel = LeadAssignmentViewModel(
            opportunity: lead,
            repository: repository
        )
        await viewModel.loadCandidates(isOnline: true)

        let outcome = await viewModel.changeAssignment(
            to: "user-amy",
            isOnline: true
        )

        XCTAssertEqual(outcome, .conflict)
        XCTAssertEqual(repository.fetchSnapshotCallCount, 1)
        XCTAssertEqual(repository.listCandidatesCallCount, 2)
        XCTAssertEqual(lead.assignedTo, "user-chris")
        XCTAssertEqual(lead.assignmentVersion, 9)
        XCTAssertEqual(viewModel.candidates.map(\.id), ["user-chris"])
        XCTAssertTrue(viewModel.canUnassign)
        XCTAssertEqual(
            viewModel.errorMessage,
            "Assignment changed. Review the current assignee and try again."
        )
    }

    func testAssignmentAccessLostDoesNotExposeReplacementAssignee() async {
        let repository = AssignmentRepositoryMock()
        repository.candidateResponses = [
            .success(candidateEnvelope(canUnassign: false))
        ]
        repository.changeResponse = .failure(
            PostgrestError(
                code: "42501",
                message: "assignment_access_lost"
            )
        )

        let lead = makeLead(assignedTo: "user-jason", assignmentVersion: 7)
        let viewModel = LeadAssignmentViewModel(
            opportunity: lead,
            repository: repository
        )
        await viewModel.loadCandidates(isOnline: true)

        let outcome = await viewModel.changeAssignment(
            to: "user-amy",
            isOnline: true
        )

        XCTAssertEqual(outcome, .accessLost)
        XCTAssertEqual(lead.assignedTo, "user-jason")
        XCTAssertEqual(lead.assignmentVersion, 7)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertFalse(viewModel.canUnassign)
    }

    func testOfflineMutationFailsClosedWithoutCallingRepository() async {
        let repository = AssignmentRepositoryMock()
        repository.candidateResponses = [
            .success(candidateEnvelope(canUnassign: false))
        ]
        let lead = makeLead(assignedTo: "user-jason", assignmentVersion: 7)
        let viewModel = LeadAssignmentViewModel(
            opportunity: lead,
            repository: repository
        )
        await viewModel.loadCandidates(isOnline: true)

        let outcome = await viewModel.changeAssignment(
            to: "user-amy",
            isOnline: false
        )

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(repository.changeCallCount, 0)
        XCTAssertEqual(lead.assignedTo, "user-jason")
        XCTAssertEqual(lead.assignmentVersion, 7)
        XCTAssertEqual(
            viewModel.errorMessage,
            "Connect to internet to reassign this lead."
        )
    }

    func testLowerVersionResponseCannotRegressRealtimeState() async throws {
        let repository = AssignmentRepositoryMock()
        repository.candidateResponses = [
            .success(candidateEnvelope(canUnassign: false)),
            .success(candidateEnvelope(canUnassign: false))
        ]
        repository.changeResponse = .success(
            try OpportunityAssignmentChangeResult(
                ok: true,
                conflict: false,
                assignedTo: "user-amy",
                assignmentVersion: 8,
                eventId: "event-stale"
            )
        )
        repository.snapshotResponse = .success(
            OpportunityAssignmentSnapshot(
                assignedTo: "user-jason",
                assignmentVersion: 9
            )
        )

        let lead = makeLead(assignedTo: "user-jason", assignmentVersion: 9)
        let viewModel = LeadAssignmentViewModel(
            opportunity: lead,
            repository: repository
        )
        await viewModel.loadCandidates(isOnline: true)

        let outcome = await viewModel.changeAssignment(
            to: "user-amy",
            isOnline: true
        )

        XCTAssertEqual(outcome, .conflict)
        XCTAssertEqual(lead.assignedTo, "user-jason")
        XCTAssertEqual(lead.assignmentVersion, 9)
        XCTAssertEqual(repository.fetchSnapshotCallCount, 1)
        XCTAssertEqual(repository.listCandidatesCallCount, 2)
    }

    func testInvalidNonConflictResponseDoesNotMutateLead() async throws {
        let repository = AssignmentRepositoryMock()
        repository.candidateResponses = [
            .success(candidateEnvelope(canUnassign: false))
        ]
        repository.changeResponse = .success(
            try OpportunityAssignmentChangeResult(
                ok: false,
                conflict: false,
                assignedTo: "user-amy",
                assignmentVersion: 8,
                eventId: nil
            )
        )

        let lead = makeLead(assignedTo: "user-jason", assignmentVersion: 7)
        let viewModel = LeadAssignmentViewModel(
            opportunity: lead,
            repository: repository
        )
        await viewModel.loadCandidates(isOnline: true)

        let outcome = await viewModel.changeAssignment(
            to: "user-amy",
            isOnline: true
        )

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(lead.assignedTo, "user-jason")
        XCTAssertEqual(lead.assignmentVersion, 7)
    }

    func testAccessLostDispositionDismissesStaleDetailAndRefreshesScope() {
        let disposition = LeadAssignmentMutationDisposition.resolve(
            outcome: .accessLost,
            retainsLeadAccess: true
        )

        XCTAssertTrue(disposition.dismissPicker)
        XCTAssertTrue(disposition.dismissLead)
        XCTAssertTrue(disposition.refreshLeads)
        XCTAssertFalse(disposition.showSuccess)
    }

    func testAssignedAwayDispositionDismissesDetailAfterSuccessfulTransfer() {
        let disposition = LeadAssignmentMutationDisposition.resolve(
            outcome: .updated,
            retainsLeadAccess: false
        )

        XCTAssertTrue(disposition.dismissPicker)
        XCTAssertTrue(disposition.dismissLead)
        XCTAssertTrue(disposition.refreshLeads)
        XCTAssertTrue(disposition.showSuccess)
    }

    func testCurrentTargetIsAClientSideNoop() async {
        let repository = AssignmentRepositoryMock()
        repository.candidateResponses = [
            .success(candidateEnvelope(canUnassign: true))
        ]
        let lead = makeLead()
        let viewModel = LeadAssignmentViewModel(
            opportunity: lead,
            repository: repository
        )
        await viewModel.loadCandidates(isOnline: true)

        let outcome = await viewModel.changeAssignment(
            to: "user-jason",
            isOnline: true
        )

        XCTAssertEqual(outcome, .unchanged)
        XCTAssertEqual(repository.changeCallCount, 0)
        XCTAssertNil(viewModel.errorMessage)
    }

    private func makeLead(
        assignedTo: String? = "user-jason",
        assignmentVersion: Int64 = 4
    ) -> Opportunity {
        let lead = Opportunity(
            id: "lead-1",
            companyId: "company-1",
            contactName: "Helen Calloway"
        )
        lead.assignedTo = assignedTo
        lead.assignmentVersion = assignmentVersion
        return lead
    }

    private func candidateEnvelope(
        canUnassign: Bool
    ) -> OpportunityAssignmentCandidates {
        OpportunityAssignmentCandidates(
            canUnassign: canUnassign,
            candidates: [
                OpportunityAssignmentCandidate(
                    id: "user-jason",
                    firstName: "Jason",
                    lastName: "Zavarella",
                    profileImageURL: nil,
                    userColor: nil
                ),
                OpportunityAssignmentCandidate(
                    id: "user-amy",
                    firstName: "Amy",
                    lastName: "Chen",
                    profileImageURL: nil,
                    userColor: nil
                )
            ]
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "Timed out waiting for async test condition")
    }
}

@MainActor
private final class AssignmentRepositoryMock: LeadAssignmentRepositoryProtocol {
    struct ChangeCall: Equatable {
        let opportunityId: String
        let expectedAssignmentVersion: Int64
        let expectedAssignedTo: String?
        let newAssignedTo: String?
    }

    var candidateResponses: [Result<OpportunityAssignmentCandidates, Error>] = []
    var changeResponse: Result<OpportunityAssignmentChangeResult, Error>?
    var snapshotResponse: Result<OpportunityAssignmentSnapshot, Error>?
    var suspendChange = false
    var pendingChange: CheckedContinuation<OpportunityAssignmentChangeResult, Error>?

    private(set) var listCandidatesCallCount = 0
    private(set) var changeCallCount = 0
    private(set) var fetchSnapshotCallCount = 0
    private(set) var lastChange: ChangeCall?

    func listAssignmentCandidates(
        opportunityId: String
    ) async throws -> OpportunityAssignmentCandidates {
        listCandidatesCallCount += 1
        guard !candidateResponses.isEmpty else {
            throw TestError.missingResponse
        }
        return try candidateResponses.removeFirst().get()
    }

    func changeAssignment(
        opportunityId: String,
        expectedAssignmentVersion: Int64,
        expectedAssignedTo: String?,
        newAssignedTo: String?,
        source: OpportunityAssignmentSource,
        suggestionId: String?,
        metadata: [String: AnyJSON]
    ) async throws -> OpportunityAssignmentChangeResult {
        changeCallCount += 1
        lastChange = ChangeCall(
            opportunityId: opportunityId,
            expectedAssignmentVersion: expectedAssignmentVersion,
            expectedAssignedTo: expectedAssignedTo,
            newAssignedTo: newAssignedTo
        )
        if suspendChange {
            return try await withCheckedThrowingContinuation { continuation in
                pendingChange = continuation
            }
        }
        guard let changeResponse else { throw TestError.missingResponse }
        return try changeResponse.get()
    }

    func fetchAssignmentSnapshot(
        opportunityId: String
    ) async throws -> OpportunityAssignmentSnapshot {
        fetchSnapshotCallCount += 1
        guard let snapshotResponse else { throw TestError.missingResponse }
        return try snapshotResponse.get()
    }

    func resumeChange(with result: OpportunityAssignmentChangeResult) {
        pendingChange?.resume(returning: result)
        pendingChange = nil
    }

    private enum TestError: Error {
        case missingResponse
    }
}
