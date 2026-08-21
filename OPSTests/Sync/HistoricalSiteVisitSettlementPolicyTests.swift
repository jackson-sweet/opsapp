//
//  HistoricalSiteVisitSettlementPolicyTests.swift
//  OPSTests
//
//  Historical repair is intentionally stricter than the normal queue: one
//  audited manifest row, complete retained phone evidence, fresh server proof,
//  row-scoped capability, and a second exact approval are all mandatory.
//

import XCTest
@testable import OPS

final class HistoricalSiteVisitSettlementPolicyTests: XCTestCase {
    private let companyID = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let userID = "11111111-1111-4111-8111-111111111111"
    private let opportunityID = "22222222-2222-4222-8222-222222222222"

    func test_manifestContainsOnlyFiveAuditedPreIncidentVisits() {
        let manifest = HistoricalSiteVisitSettlementManifest.preIncidentUnlinkedVisits

        XCTAssertEqual(manifest.entries.count, 5)
        XCTAssertEqual(
            Set(manifest.entries.map(\.visitId)),
            Set([
                "984c6847-2ac6-4bf3-a56e-9eb08f120fdf",
                "b1e9cea3-4c1a-4247-8a1f-c21aa721bbe2",
                "0de1fc17-61d8-4b23-8534-27f7a529b1ce",
                "df4016c4-6269-49d1-aec2-76e7934600c2",
                "4e73b982-c7ad-4303-9f1f-680b26edc10e",
            ])
        )
        XCTAssertEqual(
            manifest.entries.filter { $0.outcome == .settleCompletedHistory }.map(\.visitId),
            ["df4016c4-6269-49d1-aec2-76e7934600c2"]
        )
    }

    func test_plansOneActiveLinkOnlyFromExactPhoneAndServerEvidence() throws {
        let entry = try XCTUnwrap(
            HistoricalSiteVisitSettlementManifest.preIncidentUnlinkedVisits.entries.first
        )
        let phone = makePhone(entry: entry)
        let server = makeServer(entry: entry)

        let plan = try HistoricalSiteVisitSettlementPolicy.plan(
            manifest: .preIncidentUnlinkedVisits,
            phone: phone,
            server: server,
            capability: makeCapability()
        )

        XCTAssertEqual(plan.visitId, entry.visitId)
        XCTAssertEqual(plan.targetOpportunityId, opportunityID)
        XCTAssertEqual(plan.outcome, .recoverActiveLink)
        XCTAssertEqual(plan.operationIds, phone.operations.map(\.id).sorted())
        XCTAssertFalse(plan.approvalDigest.isEmpty)
    }

    func test_completedVisitPlansLocalAccountingOnlyAfterExactContentProof() throws {
        let entry = try XCTUnwrap(
            HistoricalSiteVisitSettlementManifest.preIncidentUnlinkedVisits.entries.first {
                $0.outcome == .settleCompletedHistory
            }
        )
        let contentFingerprint = "f3c58a23e2b49d9ab1740f4f0bf4da31"
        let phone = makePhone(entry: entry, contentFingerprint: contentFingerprint)
        let server = makeServer(entry: entry, contentFingerprint: contentFingerprint)

        let plan = try HistoricalSiteVisitSettlementPolicy.plan(
            manifest: .preIncidentUnlinkedVisits,
            phone: phone,
            server: server,
            capability: makeCapability()
        )

        XCTAssertEqual(plan.outcome, .settleCompletedHistory)
        XCTAssertFalse(plan.permitsServerMutation)
    }

    func test_rejectsUnknownVisitStaleServerConflictAndMissingCapability() throws {
        let entry = try XCTUnwrap(
            HistoricalSiteVisitSettlementManifest.preIncidentUnlinkedVisits.entries.first
        )
        let phone = makePhone(entry: entry)
        let server = makeServer(entry: entry)

        XCTAssertThrowsError(
            try HistoricalSiteVisitSettlementPolicy.plan(
                manifest: .preIncidentUnlinkedVisits,
                phone: phone.replacing(visitId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
                server: server,
                capability: makeCapability()
            )
        ) { XCTAssertEqual($0 as? HistoricalSiteVisitSettlementError, .visitOutsideManifest) }

        XCTAssertThrowsError(
            try HistoricalSiteVisitSettlementPolicy.plan(
                manifest: .preIncidentUnlinkedVisits,
                phone: phone,
                server: server.replacing(updatedAt: entry.expectedServerUpdatedAt.addingTimeInterval(1)),
                capability: makeCapability()
            )
        ) { XCTAssertEqual($0 as? HistoricalSiteVisitSettlementError, .serverSnapshotChanged) }

        XCTAssertThrowsError(
            try HistoricalSiteVisitSettlementPolicy.plan(
                manifest: .preIncidentUnlinkedVisits,
                phone: phone,
                server: server.replacing(opportunityId: opportunityID),
                capability: makeCapability()
            )
        ) { XCTAssertEqual($0 as? HistoricalSiteVisitSettlementError, .serverAlreadyLinked) }

        XCTAssertThrowsError(
            try HistoricalSiteVisitSettlementPolicy.plan(
                manifest: .preIncidentUnlinkedVisits,
                phone: phone,
                server: server,
                capability: makeCapability(canEdit: false)
            )
        ) { XCTAssertEqual($0 as? HistoricalSiteVisitSettlementError, .capabilityDenied) }
    }

    func test_rejectsInFlightOperationAndConflictingPhoneRelationship() throws {
        let entry = try XCTUnwrap(
            HistoricalSiteVisitSettlementManifest.preIncidentUnlinkedVisits.entries.first
        )
        let base = makePhone(entry: entry)
        let inFlight = base.operations[0].replacing(status: "inProgress")

        XCTAssertThrowsError(
            try HistoricalSiteVisitSettlementPolicy.plan(
                manifest: .preIncidentUnlinkedVisits,
                phone: base.replacing(operations: [inFlight]),
                server: makeServer(entry: entry),
                capability: makeCapability()
            )
        ) { XCTAssertEqual($0 as? HistoricalSiteVisitSettlementError, .operationInFlight) }

        XCTAssertThrowsError(
            try HistoricalSiteVisitSettlementPolicy.plan(
                manifest: .preIncidentUnlinkedVisits,
                phone: base.replacing(
                    childRelationships: [
                        .init(
                            entityType: SyncEntityType.siteVisitArtifact.rawValue,
                            entityId: "33333333-3333-4333-8333-333333333333",
                            siteVisitId: entry.visitId,
                            companyId: companyID,
                            opportunityId: "44444444-4444-4444-8444-444444444444"
                        ),
                    ]
                ),
                server: makeServer(entry: entry),
                capability: makeCapability()
            )
        ) { XCTAssertEqual($0 as? HistoricalSiteVisitSettlementError, .phoneRelationshipConflict) }
    }

    func test_approvalMustMatchEveryImmutablePlanIdentity() throws {
        let entry = try XCTUnwrap(
            HistoricalSiteVisitSettlementManifest.preIncidentUnlinkedVisits.entries.first
        )
        let plan = try HistoricalSiteVisitSettlementPolicy.plan(
            manifest: .preIncidentUnlinkedVisits,
            phone: makePhone(entry: entry),
            server: makeServer(entry: entry),
            capability: makeCapability()
        )
        let approval = HistoricalSiteVisitSettlementApproval(
            approvalDigest: plan.approvalDigest,
            actorUserId: userID,
            companyId: companyID,
            visitId: entry.visitId,
            targetOpportunityId: opportunityID,
            outcome: plan.outcome,
            approvedAt: Date(timeIntervalSince1970: 1_787_000_000)
        )

        XCTAssertNoThrow(try HistoricalSiteVisitSettlementPolicy.validate(approval, for: plan))
        XCTAssertThrowsError(
            try HistoricalSiteVisitSettlementPolicy.validate(
                approval.replacing(targetOpportunityId: "55555555-5555-4555-8555-555555555555"),
                for: plan
            )
        ) { XCTAssertEqual($0 as? HistoricalSiteVisitSettlementError, .approvalMismatch) }
    }

    // MARK: - Fixtures

    private func makePhone(
        entry: HistoricalSiteVisitSettlementManifest.Entry,
        contentFingerprint: String? = nil
    ) -> HistoricalSiteVisitPhoneEvidence {
        let operation = HistoricalSiteVisitOperationEvidence(
            id: "66666666-6666-4666-8666-666666666666",
            entityType: SyncEntityType.siteVisit.rawValue,
            entityId: entry.visitId,
            operationType: "update",
            status: "parked",
            companyId: companyID,
            siteVisitId: entry.visitId,
            envelopeEntityId: entry.visitId,
            changedFields: ["opportunity_id"]
        )
        return HistoricalSiteVisitPhoneEvidence(
            visitId: entry.visitId,
            companyId: companyID,
            status: entry.expectedServerStatus,
            deletedAt: nil,
            targetOpportunityId: opportunityID,
            targetOpportunityCompanyId: companyID,
            targetOpportunityAssignedTo: userID,
            targetOpportunityIsActive: true,
            childRelationships: [],
            operations: [operation],
            contentFingerprint: contentFingerprint
        )
    }

    private func makeServer(
        entry: HistoricalSiteVisitSettlementManifest.Entry,
        contentFingerprint: String? = nil
    ) -> HistoricalSiteVisitServerEvidence {
        HistoricalSiteVisitServerEvidence(
            visitId: entry.visitId,
            companyId: companyID,
            status: entry.expectedServerStatus,
            opportunityId: nil,
            deletedAt: nil,
            updatedAt: entry.expectedServerUpdatedAt,
            childRelationships: [],
            contentFingerprint: contentFingerprint
        )
    }

    private func makeCapability(canEdit: Bool = true) -> HistoricalSiteVisitCapabilityEvidence {
        HistoricalSiteVisitCapabilityEvidence(
            actorUserId: userID,
            companyId: companyID,
            canEditTargetOpportunity: canEdit
        )
    }
}
