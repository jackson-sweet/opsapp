//
//  ClientLeadsViewModelTests.swift
//  OPSTests
//
//  Pure-transform coverage for the client-profile Leads section view model:
//  view-scope filtering, open/closed split, archived/deleted/other-client
//  exclusion, sort order, and outcome tallies.
//

import XCTest
@testable import OPS

@MainActor
final class ClientLeadsViewModelTests: XCTestCase {

    // pipeline.view == all → every lead is viewable.
    private func policyAll() -> LeadAccessPolicy {
        LeadAccessPolicy(currentUserId: "u1",
                         permissions: ["pipeline.view": "all"],
                         explicitPermissionKeys: ["pipeline.view"])
    }

    // pipeline.view == assigned → only leads assigned to u1 are viewable.
    private func policyAssigned() -> LeadAccessPolicy {
        LeadAccessPolicy(currentUserId: "u1",
                         permissions: ["pipeline.view": "assigned"],
                         explicitPermissionKeys: ["pipeline.view"])
    }

    private func lead(id: String,
                      clientId: String,
                      stage: PipelineStage,
                      assignedTo: String? = "u1",
                      archived: Bool = false,
                      deleted: Bool = false,
                      activity: Date = Date(timeIntervalSince1970: 1_000)) -> Opportunity {
        let o = Opportunity(id: id, companyId: "c1", contactName: "N", stage: stage)
        o.clientId = clientId
        o.assignedTo = assignedTo
        o.lastActivityAt = activity
        if archived { o.archivedAt = Date() }
        if deleted { o.deletedAt = Date() }
        return o
    }

    func test_splitsOpenVsTerminal_andExcludesArchivedDeletedAndOtherClients() {
        let vm = ClientLeadsViewModel()
        vm.apply([
            lead(id: "1", clientId: "CL", stage: .quoting),
            lead(id: "2", clientId: "CL", stage: .won),
            lead(id: "3", clientId: "CL", stage: .lost),
            lead(id: "4", clientId: "CL", stage: .newLead, archived: true),   // hidden
            lead(id: "5", clientId: "CL", stage: .quoted, deleted: true),      // hidden
            lead(id: "6", clientId: "OTHER", stage: .newLead),                 // wrong client
        ], clientId: "CL", policy: policyAll())

        XCTAssertEqual(vm.openLeads.map(\.id), ["1"])
        XCTAssertEqual(Set(vm.closedLeads.map(\.id)), ["2", "3"])
        XCTAssertEqual(vm.tally.won, 1)
        XCTAssertEqual(vm.tally.lost, 1)
        XCTAssertEqual(vm.tally.discarded, 0)
        XCTAssertTrue(vm.tally.hasAny)
    }

    func test_assignedScope_hidesLeadsNotAssignedToUser() {
        let vm = ClientLeadsViewModel()
        vm.apply([
            lead(id: "mine",   clientId: "CL", stage: .quoting, assignedTo: "u1"),
            lead(id: "theirs", clientId: "CL", stage: .quoting, assignedTo: "u2"),
        ], clientId: "CL", policy: policyAssigned())

        XCTAssertEqual(vm.openLeads.map(\.id), ["mine"])
    }

    func test_openSortedByMostRecentActivity() {
        let vm = ClientLeadsViewModel()
        vm.apply([
            lead(id: "old", clientId: "CL", stage: .quoting, activity: Date(timeIntervalSince1970: 10)),
            lead(id: "new", clientId: "CL", stage: .quoting, activity: Date(timeIntervalSince1970: 99)),
        ], clientId: "CL", policy: policyAll())

        XCTAssertEqual(vm.openLeads.map(\.id), ["new", "old"])
    }

    func test_emptyWhenNothingViewable() {
        let vm = ClientLeadsViewModel()
        vm.apply([], clientId: "CL", policy: policyAll())
        XCTAssertTrue(vm.openLeads.isEmpty)
        XCTAssertTrue(vm.closedLeads.isEmpty)
        XCTAssertFalse(vm.tally.hasAny)
    }
}
