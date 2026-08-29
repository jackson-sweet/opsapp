//
//  LeadWonPromptEvaluatorTests.swift
//  OPSTests
//
//  D3 of the lead-identity design — bug 9a89b951. The rule that decides whether
//  moving a project into an active status raises the mark-lead-won ask.
//
//  Pinned here rather than through the UI because this is where the judgement
//  lives: the prompt must appear exactly when there is a real decision to make,
//  and must stay silent for every case where showing it would be the app
//  asserting something it does not know (offline), asking twice (declined),
//  reopening something closed (won / lost / discarded), or offering an action
//  the viewer is not entitled to take.
//
//  No network, no SwiftData: fetch and permission arrive as inputs.
//

import XCTest
@testable import OPS

final class LeadWonPromptEvaluatorTests: XCTestCase {

    // MARK: - Status gate

    func testNonActiveStatusesNeverPropose() throws {
        for status in [Status.rfq, .estimated] {
            XCTAssertNil(
                try evaluate(newStatus: status),
                "\(status.rawValue) is not an active status and must not propose"
            )
        }
    }

    func testEveryActiveStatusProposes() throws {
        for status in [Status.accepted, .inProgress, .completed, .closed] {
            XCTAssertNotNil(
                try evaluate(newStatus: status),
                "\(status.rawValue) is an active status and must propose"
            )
        }
    }

    // MARK: - Nothing to propose about

    func testNoLinkedLeadNeverProposes() throws {
        XCTAssertNil(try evaluate(opportunityId: nil))
        XCTAssertNil(try evaluate(opportunityId: "   "))
    }

    func testNoUserNeverProposes() throws {
        XCTAssertNil(try evaluate(userId: nil))
        XCTAssertNil(try evaluate(userId: ""))
    }

    /// Offline, or a row this viewer cannot read at all. Saying nothing is
    /// honest; the next qualifying status change re-evaluates.
    func testMissingServerRowNeverProposes() {
        XCTAssertNil(
            LeadWonPromptEvaluator.proposal(
                newStatus: .accepted,
                projectId: Self.projectId,
                companyId: Self.companyId,
                opportunityId: Self.opportunityId,
                userId: Self.userId,
                canEditLead: { _ in true },
                serverRow: nil
            )
        )
    }

    // MARK: - Already answered, one way or another

    func testTerminalAndWonStagesNeverPropose() throws {
        for stage in ["won", "lost", "discarded"] {
            XCTAssertNil(
                try evaluate(stage: stage),
                "stage \(stage) is settled and must not propose"
            )
        }
    }

    func testDeclinedLeadIsNeverAskedAgain() throws {
        XCTAssertNil(try evaluate(declinedAt: "2026-08-28T19:40:00Z"))
    }

    // MARK: - Entitlement

    func testViewerWithoutLeadEditNeverProposes() throws {
        XCTAssertNil(try evaluate(canEdit: false))
    }

    /// The closure receives the row's assignee, so an `assigned`-scoped policy
    /// can answer for this specific lead rather than in the abstract.
    func testPermissionIsAskedAboutThisRowsAssignee() throws {
        var seen: [String?] = []
        _ = LeadWonPromptEvaluator.proposal(
            newStatus: .accepted,
            projectId: Self.projectId,
            companyId: Self.companyId,
            opportunityId: Self.opportunityId,
            userId: Self.userId,
            canEditLead: { assignedTo in
                seen.append(assignedTo)
                return true
            },
            serverRow: try makeRow(assignedTo: "00000000-0000-0000-0000-0000000000dd")
        )

        XCTAssertEqual(seen, ["00000000-0000-0000-0000-0000000000dd"])
    }

    // MARK: - The proposal itself

    func testHappyPathCarriesTheJobFirstLabelAndLowercasedIds() throws {
        let proposal = try XCTUnwrap(evaluate())

        XCTAssertEqual(proposal.leadLabel, "Cedar deck rebuild")
        XCTAssertEqual(proposal.opportunityId, Self.opportunityId.lowercased())
        XCTAssertEqual(proposal.projectId, Self.projectId.lowercased())
        XCTAssertEqual(proposal.userId, Self.userId.lowercased())
        XCTAssertEqual(proposal.companyId, Self.companyId)
    }

    func testLabelFallsBackToContactNameThenToAGenericPhrase() throws {
        let noTitle = try XCTUnwrap(evaluate(title: nil))
        XCTAssertEqual(noTitle.leadLabel, "Phoebe J. Southwood")

        let blankTitle = try XCTUnwrap(evaluate(title: "   "))
        XCTAssertEqual(blankTitle.leadLabel, "Phoebe J. Southwood")

        let anonymous = try XCTUnwrap(evaluate(title: "   ", contactName: "  "))
        XCTAssertEqual(anonymous.leadLabel, "this lead")
    }

    // MARK: - Fixtures

    /// Uppercase on purpose: `UUID().uuidString` is uppercase and Postgres uuid
    /// columns are lowercase, so the proposal must normalize on the way through.
    private static let opportunityId = "0A887C18-0000-4832-97F0-F302DCAE2E9D"
    private static let projectId     = "1B998D29-1111-4832-97F0-F302DCAE2E9D"
    private static let companyId     = "00000000-0000-0000-0000-0000000000bb"
    private static let userId        = "00000000-0000-0000-0000-0000000000CC"

    private func evaluate(
        newStatus: Status = .accepted,
        opportunityId: String? = LeadWonPromptEvaluatorTests.opportunityId,
        userId: String? = LeadWonPromptEvaluatorTests.userId,
        stage: String = "quoted",
        declinedAt: String? = nil,
        assignedTo: String? = nil,
        title: String? = "Cedar deck rebuild",
        contactName: String? = "Phoebe J. Southwood",
        canEdit: Bool = true
    ) throws -> LeadWonProposal? {
        LeadWonPromptEvaluator.proposal(
            newStatus: newStatus,
            projectId: Self.projectId,
            companyId: Self.companyId,
            opportunityId: opportunityId,
            userId: userId,
            canEditLead: { _ in canEdit },
            serverRow: try makeRow(
                stage: stage,
                declinedAt: declinedAt,
                assignedTo: assignedTo,
                title: title,
                contactName: contactName
            )
        )
    }

    /// Built through the decoder, the way every other OpportunityDTO fixture in
    /// OPSTests is — the DTO has no memberwise initializer to reach.
    private func makeRow(
        stage: String = "quoted",
        declinedAt: String? = nil,
        assignedTo: String? = nil,
        title: String? = "Cedar deck rebuild",
        contactName: String? = "Phoebe J. Southwood"
    ) throws -> OpportunityDTO {
        var fields: [String] = [
            "\"id\":\"\(Self.opportunityId.lowercased())\"",
            "\"company_id\":\"\(Self.companyId)\"",
            "\"stage\":\"\(stage)\"",
            "\"stage_entered_at\":\"2026-08-20T12:00:00Z\"",
            "\"created_at\":\"2026-08-01T12:00:00Z\"",
            "\"updated_at\":\"2026-08-28T12:00:00Z\""
        ]
        if let title { fields.append("\"title\":\"\(title)\"") }
        if let contactName { fields.append("\"contact_name\":\"\(contactName)\"") }
        if let declinedAt { fields.append("\"won_prompt_declined_at\":\"\(declinedAt)\"") }
        if let assignedTo { fields.append("\"assigned_to\":\"\(assignedTo)\"") }

        let json = "{\(fields.joined(separator: ","))}"
        return try JSONDecoder().decode(OpportunityDTO.self, from: Data(json.utf8))
    }
}
