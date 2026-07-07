//
//  ActivityTargetTests.swift
//  OPSTests
//
//  Proves the unified `ActivityTarget` maps each case to EXACTLY ONE parent
//  column + id (opportunity / client / project), and that `.unbound` maps to
//  none. This is the guard that keeps the `activities` single-parent invariant
//  (a row carries opportunity_id OR client_id OR project_id, never two) intact
//  at the type level. Also pins the display metadata (name / subtitle / source
//  badge / companyId) each case surfaces to the picker + locked-target UI.
//

import XCTest
@testable import OPS

final class ActivityTargetTests: XCTestCase {

    // MARK: - Fixtures

    private func makeOpportunity() -> Opportunity {
        let opp = Opportunity(
            id: "opp1",
            companyId: "co-opp",
            contactName: "Eric Devlin",
            stage: .quoting
        )
        opp.address = "123 Main St"
        return opp
    }

    private func makeClient() -> Client {
        let c = Client(
            id: "cli1",
            name: "Acme Roofing",
            companyId: "co-client"
        )
        c.address = "77 Warehouse Rd"
        return c
    }

    private func makeProject() -> Project {
        let p = Project(id: "prj1", title: "Devlin roof replacement", status: .inProgress)
        p.companyId = "co-project"
        p.address = "123 Main St"
        return p
    }

    // MARK: - parentKey: exactly one parent, nil for .unbound

    func test_opportunityTarget_mapsToOpportunityParentOnly() {
        let target = ActivityTarget.opportunity(makeOpportunity())
        XCTAssertEqual(target.parentKey, .opportunity("opp1"))
    }

    func test_clientTarget_mapsToClientParentOnly() {
        let target = ActivityTarget.client(makeClient())
        XCTAssertEqual(target.parentKey, .client("cli1"))
    }

    func test_projectTarget_mapsToProjectParentOnly() {
        let target = ActivityTarget.project(makeProject())
        XCTAssertEqual(target.parentKey, .project("prj1"))
    }

    func test_unboundTarget_mapsToNoParent() {
        XCTAssertNil(ActivityTarget.unbound.parentKey)
    }

    // MARK: - displayName (real field names)

    func test_displayName_opportunity_usesContactName() {
        XCTAssertEqual(ActivityTarget.opportunity(makeOpportunity()).displayName, "Eric Devlin")
    }

    func test_displayName_client_usesName() {
        XCTAssertEqual(ActivityTarget.client(makeClient()).displayName, "Acme Roofing")
    }

    func test_displayName_project_usesTitle() {
        XCTAssertEqual(ActivityTarget.project(makeProject()).displayName, "Devlin roof replacement")
    }

    // MARK: - sourceBadge

    func test_sourceBadge_perCase() {
        XCTAssertEqual(ActivityTarget.opportunity(makeOpportunity()).sourceBadge, "LEAD")
        XCTAssertEqual(ActivityTarget.client(makeClient()).sourceBadge, "CLIENT")
        XCTAssertEqual(ActivityTarget.project(makeProject()).sourceBadge, "JOB")
        XCTAssertNil(ActivityTarget.unbound.sourceBadge)
    }

    // MARK: - subtitle (stage / status label; address fallback)

    func test_subtitle_opportunity_usesStageDisplayName() {
        XCTAssertEqual(ActivityTarget.opportunity(makeOpportunity()).subtitle, PipelineStage.quoting.displayName)
    }

    func test_subtitle_project_usesStatusDisplayName() {
        XCTAssertEqual(ActivityTarget.project(makeProject()).subtitle, Status.inProgress.displayName)
    }

    func test_subtitle_client_usesAddress() {
        XCTAssertEqual(ActivityTarget.client(makeClient()).subtitle, "77 Warehouse Rd")
    }

    func test_subtitle_unbound_isNil() {
        XCTAssertNil(ActivityTarget.unbound.subtitle)
    }

    // MARK: - companyId

    func test_companyId_perCase() {
        XCTAssertEqual(ActivityTarget.opportunity(makeOpportunity()).companyId, "co-opp")
        XCTAssertEqual(ActivityTarget.client(makeClient()).companyId, "co-client")
        XCTAssertEqual(ActivityTarget.project(makeProject()).companyId, "co-project")
        XCTAssertNil(ActivityTarget.unbound.companyId)
    }
}
