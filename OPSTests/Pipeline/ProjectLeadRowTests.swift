//
//  ProjectLeadRowTests.swift
//  OPSTests
//
//  Bug a3c4e216 — "no way to match a project to a lead". The 2026-07-22 work
//  shipped LEAD-side matching only (inside ConvertToProjectSheet); the PROJECT
//  side, where the bug was filed, had zero lead UI. An operator standing on a
//  project that obviously belongs to a won lead had no affordance at all.
//
//  These pin the project-side row's state machine and its candidate rule. The
//  row is HIDDEN rather than empty when nothing can be matched: an affordance
//  advertising an impossible action is worse than no affordance, and the
//  server only accepts a link whose target shares the lead's address.
//

import XCTest
@testable import OPS

final class ProjectLeadRowTests: XCTestCase {

    // MARK: - Fixtures

    private func lead(
        id: String,
        clientId: String? = "client-1",
        address: String? = "3998 Holland Ave, Victoria BC",
        stage: PipelineStage = .won,
        projectId: String? = nil,
        companyId: String = "company-1",
        label: String = "Holland Ave deck"
    ) -> ProjectLeadRow.LeadCandidate {
        ProjectLeadRow.LeadCandidate(
            id: id,
            companyId: companyId,
            clientId: clientId,
            address: address,
            stage: stage,
            projectId: projectId,
            label: label
        )
    }

    private var project: ProjectLeadRow.ProjectContext {
        ProjectLeadRow.ProjectContext(
            companyId: "company-1",
            clientId: "client-1",
            address: "3998 Holland Ave, Victoria BC"
        )
    }

    // MARK: - Row presentation

    /// A project that already knows its lead shows it and opens it.
    func testLinkedProjectShowsTheLeadAndSurvivesAnUnhydratedName() {
        XCTAssertEqual(
            ProjectLeadRow.presentation(
                opportunityId: "lead-1",
                leadLabel: "Holland Ave deck",
                candidateCount: 0,
                canMatch: true
            ),
            .linked(label: "Holland Ave deck")
        )
        XCTAssertEqual(
            ProjectLeadRow.presentation(
                opportunityId: "lead-1",
                leadLabel: nil,
                candidateCount: 0,
                canMatch: true
            ),
            .linked(label: "LINKED LEAD")
        )
        XCTAssertEqual(
            ProjectLeadRow.presentation(
                opportunityId: "   ",
                leadLabel: nil,
                candidateCount: 2,
                canMatch: true
            ),
            .match(candidateCount: 2),
            "a blank id is not a link"
        )
    }

    /// Unlinked with real candidates and the permission to act — the only
    /// state that earns a MATCH LEAD affordance.
    func testUnlinkedProjectWithCandidatesOffersMatch() {
        XCTAssertEqual(
            ProjectLeadRow.presentation(
                opportunityId: nil,
                leadLabel: nil,
                candidateCount: 3,
                canMatch: true
            ),
            .match(candidateCount: 3)
        )
    }

    /// No candidates, or no permission — the row disappears entirely. It never
    /// renders an em dash or a disabled button.
    func testRowIsHiddenWhenNothingCanBeMatched() {
        XCTAssertEqual(
            ProjectLeadRow.presentation(
                opportunityId: nil,
                leadLabel: nil,
                candidateCount: 0,
                canMatch: true
            ),
            .hidden
        )
        XCTAssertEqual(
            ProjectLeadRow.presentation(
                opportunityId: nil,
                leadLabel: nil,
                candidateCount: 5,
                canMatch: false
            ),
            .hidden
        )
    }

    // MARK: - Candidate rule

    /// The happy case: a won, unconverted lead on the same client and address.
    func testWonUnconvertedSameClientLeadIsACandidate() {
        let candidates = ProjectLeadRow.matchableLeads(
            project: project,
            leads: [lead(id: "lead-1")]
        )
        XCTAssertEqual(candidates.map(\.id), ["lead-1"])
    }

    /// Only WON leads convert. An open lead is still being worked.
    func testUnwonLeadsAreNotCandidates() {
        let candidates = ProjectLeadRow.matchableLeads(
            project: project,
            leads: [
                lead(id: "open", stage: .newLead),
                lead(id: "lost", stage: .lost),
                lead(id: "won", stage: .won),
            ]
        )
        XCTAssertEqual(candidates.map(\.id), ["won"])
    }

    /// A lead that already converted owns a project. Offering it here would
    /// invite a second link the server will reject.
    func testAlreadyConvertedLeadsAreNotCandidates() {
        let candidates = ProjectLeadRow.matchableLeads(
            project: project,
            leads: [
                lead(id: "converted", projectId: "project-other"),
                lead(id: "free"),
            ]
        )
        XCTAssertEqual(candidates.map(\.id), ["free"])
    }

    /// Address equality is normalized the same way the create-address
    /// fingerprint is — casing and punctuation must not split a match.
    func testAddressMatchIsNormalized() {
        let candidates = ProjectLeadRow.matchableLeads(
            project: project,
            leads: [
                lead(id: "same", clientId: nil, address: "3998 holland ave, victoria bc"),
                lead(id: "different", clientId: nil, address: "4000 Holland Ave, Victoria BC"),
            ]
        )
        XCTAssertEqual(candidates.map(\.id), ["same"])
    }

    /// The server forbids linking across addresses, so a same-client lead at a
    /// different address is NOT a candidate — offering it would dead-end the
    /// operator at commit.
    func testSameClientDifferentAddressIsNotACandidate() {
        let candidates = ProjectLeadRow.matchableLeads(
            project: project,
            leads: [lead(id: "elsewhere", address: "12 Douglas St, Victoria BC")]
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    /// A lead with no address cannot prove sameness — the server rejects it.
    func testAddresslessLeadIsNotACandidate() {
        let candidates = ProjectLeadRow.matchableLeads(
            project: project,
            leads: [lead(id: "blank", address: "   ")]
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    /// A project with no address of its own has nothing to match against.
    func testProjectWithoutAnAddressHasNoCandidates() {
        let candidates = ProjectLeadRow.matchableLeads(
            project: ProjectLeadRow.ProjectContext(
                companyId: "company-1",
                clientId: "client-1",
                address: nil
            ),
            leads: [lead(id: "lead-1")]
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    /// Company isolation is absolute, whatever the address says.
    func testForeignCompanyLeadsAreNeverCandidates() {
        let candidates = ProjectLeadRow.matchableLeads(
            project: project,
            leads: [lead(id: "foreign", companyId: "company-2")]
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    /// The client is not a filter — the server does not require it — but when
    /// several leads share an address, the one on this project's client is the
    /// likelier answer and must be the first thing the operator reads.
    func testSameClientCandidatesAreOrderedFirst() {
        let candidates = ProjectLeadRow.matchableLeads(
            project: project,
            leads: [
                lead(id: "other-client-a", clientId: "client-9"),
                lead(id: "same-client", clientId: "client-1"),
                lead(id: "other-client-b", clientId: nil),
            ]
        )
        XCTAssertEqual(
            candidates.map(\.id),
            ["same-client", "other-client-a", "other-client-b"]
        )
    }
}
