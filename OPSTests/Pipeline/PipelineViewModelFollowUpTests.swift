//
//  PipelineViewModelFollowUpTests.swift
//  OPSTests
//
//  The UI may only move a lead after the server returns the reconciled,
//  provider-confirmed opportunity. Pending and unknown delivery remain visibly
//  unresolved and never receive an optimistic HANDLED mutation.
//

import XCTest
@testable import OPS

@MainActor
final class PipelineViewModelFollowUpTests: XCTestCase {
    private let opportunityId = "6bac5d9d-44c5-4af5-b36c-48beb64cbbdc"

    func testReconciledFollowUpAppliesCanonicalOpportunityToExistingInstance() async throws {
        let comeback = try XCTUnwrap(SupabaseDate.parse("2026-07-26T18:00:00Z"))
        let service = LeadFollowUpServiceStub(
            result: .reconciled(
                opportunity: try canonicalOpportunity(),
                comebackAt: comeback
            )
        )
        let viewModel = makeViewModel(service: service)
        let lead = localLead()
        viewModel.allOpportunities = [lead]

        let outcome = await viewModel.sendFollowUp(opportunityId: opportunityId)

        guard case .sent(let returnedComeback) = outcome else {
            return XCTFail("Expected sent, got \(outcome)")
        }
        XCTAssertEqual(returnedComeback, comeback)
        XCTAssertTrue(viewModel.allOpportunities[0] === lead)
        XCTAssertEqual(lead.handledAt, SupabaseDate.parse("2026-07-23T18:00:00Z"))
        XCTAssertEqual(lead.nextFollowUpAt, comeback)
        XCTAssertEqual(lead.lastMessageDirection, "out")
        XCTAssertEqual(viewModel.followUpProgress(for: opportunityId), .idle)
    }

    func testProviderAcceptedPendingDoesNotOptimisticallyAdvanceLead() async {
        let service = LeadFollowUpServiceStub(
            result: .providerAcceptedPending(intentId: "intent-pending")
        )
        let viewModel = makeViewModel(service: service)
        let lead = localLead()
        viewModel.allOpportunities = [lead]

        let outcome = await viewModel.sendFollowUp(opportunityId: opportunityId)

        guard case .syncing = outcome else {
            return XCTFail("Expected syncing, got \(outcome)")
        }
        XCTAssertNil(lead.handledAt)
        XCTAssertEqual(viewModel.followUpProgress(for: opportunityId), .syncing)
    }

    func testDeliveryUnknownDoesNotOptimisticallyAdvanceLead() async {
        let service = LeadFollowUpServiceStub(
            result: .deliveryUnknown(intentId: "intent-unknown")
        )
        let viewModel = makeViewModel(service: service)
        let lead = localLead()
        viewModel.allOpportunities = [lead]

        let outcome = await viewModel.sendFollowUp(opportunityId: opportunityId)

        guard case .unknown = outcome else {
            return XCTFail("Expected unknown, got \(outcome)")
        }
        XCTAssertNil(lead.handledAt)
        XCTAssertEqual(viewModel.followUpProgress(for: opportunityId), .unknown)
    }

    func testAlreadyInProgressDisablesFollowUpWithoutOfferingHandledFallback() async {
        let service = LeadFollowUpServiceStub(
            result: .alreadyInProgress(intentId: "intent-other-device")
        )
        let viewModel = makeViewModel(service: service)
        let lead = localLead()
        viewModel.allOpportunities = [lead]

        let outcome = await viewModel.sendFollowUp(opportunityId: opportunityId)

        guard case .unknown = outcome else {
            return XCTFail("Expected unknown, got \(outcome)")
        }
        XCTAssertEqual(viewModel.followUpProgress(for: opportunityId), .unknown)
        XCTAssertTrue(viewModel.canSendFollowUp(for: lead))
        XCTAssertEqual(
            LeadChaseStrip.action(
                for: .dueToday,
                canSendFollowUp: viewModel.canSendFollowUp(for: lead)
            ),
            .sendFollowUp
        )
        XCTAssertEqual(
            LeadChaseStrip.actionLabel(for: .sendFollowUp, progress: .unknown),
            "CHECK EMAIL"
        )
        XCTAssertNil(lead.handledAt)
    }

    func testNewerInboundClearsPendingTransportStateAndYieldsToYourMove() async {
        let service = LeadFollowUpServiceStub(
            result: .providerAcceptedPending(intentId: "intent-pending")
        )
        let viewModel = makeViewModel(service: service)
        let lead = localLead()
        viewModel.allOpportunities = [lead]

        _ = await viewModel.sendFollowUp(opportunityId: opportunityId)
        XCTAssertEqual(viewModel.followUpProgress(for: opportunityId), .syncing)

        lead.lastOutboundAt = Date().addingTimeInterval(-60)
        lead.lastInboundAt = Date()
        lead.lastMessageDirection = "in"
        viewModel.reconcileFollowUpProgressWithLoadedLeads()

        XCTAssertEqual(viewModel.followUpProgress(for: opportunityId), .idle)
        XCTAssertFalse(viewModel.canSendFollowUp(for: lead))
    }

    func testUnavailableFollowUpFallsBackToHandledAction() async {
        let service = LeadFollowUpServiceStub(
            result: .unavailable(reason: "no_safe_thread")
        )
        let viewModel = makeViewModel(service: service)
        let lead = localLead()
        viewModel.allOpportunities = [lead]
        XCTAssertTrue(viewModel.canSendFollowUp(for: lead))

        let outcome = await viewModel.sendFollowUp(opportunityId: opportunityId)

        guard case .unavailable = outcome else {
            return XCTFail("Expected unavailable, got \(outcome)")
        }
        XCTAssertFalse(viewModel.canSendFollowUp(for: lead))
        XCTAssertNil(lead.handledAt)
    }

    func testImmutableReceiptConfirmsSendWithoutOptimisticallyMutatingTheLead() async throws {
        let comeback = try XCTUnwrap(SupabaseDate.parse("2026-07-26T18:00:00Z"))
        let service = LeadFollowUpServiceStub(
            result: .reconciledReceipt(comebackAt: comeback)
        )
        let viewModel = makeViewModel(service: service)
        let lead = localLead()
        viewModel.allOpportunities = [lead]

        let outcome = await viewModel.sendFollowUp(opportunityId: opportunityId)

        guard case .sent(let returnedComeback) = outcome else {
            return XCTFail("Expected sent from immutable receipt, got \(outcome)")
        }
        XCTAssertEqual(returnedComeback, comeback)
        XCTAssertNil(lead.handledAt)
        XCTAssertEqual(viewModel.followUpProgress(for: opportunityId), .idle)
    }

    private func makeViewModel(service: LeadFollowUpServiceProtocol) -> PipelineViewModel {
        let viewModel = PipelineViewModel(followUpService: service)
        viewModel.setup(companyId: "company-id", currentUserId: "user-id")
        return viewModel
    }

    private func localLead() -> Opportunity {
        let lead = Opportunity(
            id: opportunityId,
            companyId: "company-id",
            contactName: "Crystal",
            stage: .quoted
        )
        lead.contactEmail = "crystal@example.com"
        lead.nextFollowUpAt = Date().addingTimeInterval(-86_400)
        return lead
    }

    private func canonicalOpportunity() throws -> OpportunityDTO {
        let json = """
        {
          "id": "\(opportunityId)",
          "company_id": "company-id",
          "contact_name": "Crystal",
          "contact_email": "crystal@example.com",
          "stage": "quoted",
          "stage_entered_at": "2026-07-01T18:00:00Z",
          "assignment_version": 0,
          "next_follow_up_at": "2026-07-26T18:00:00Z",
          "last_activity_at": "2026-07-23T18:00:00Z",
          "correspondence_count": 4,
          "outbound_count": 3,
          "inbound_count": 1,
          "last_outbound_at": "2026-07-23T18:00:00Z",
          "last_message_direction": "out",
          "handled_at": "2026-07-23T18:00:00Z",
          "created_at": "2026-06-01T18:00:00Z",
          "updated_at": "2026-07-23T18:00:00Z"
        }
        """
        return try JSONDecoder().decode(OpportunityDTO.self, from: Data(json.utf8))
    }
}

@MainActor
private final class LeadFollowUpServiceStub: LeadFollowUpServiceProtocol {
    private let result: LeadFollowUpResult

    init(result: LeadFollowUpResult) {
        self.result = result
    }

    func sendFollowUp(
        opportunityId: String,
        scope: LeadFollowUpAttemptScope
    ) async -> LeadFollowUpResult {
        result
    }
}
