//
//  ActivityRepositoryTests.swift
//  OPSTests
//
//  Proves the pure `ActivityRepository.buildDTO(...)` normalizer:
//   - sets EXACTLY ONE parent (opportunity/client/project) matching the target,
//     and none for `.unbound`;
//   - always stamps `company_id` and `created_by`;
//   - clamps `direction` to inbound/outbound/nil (a bogus value → nil);
//   - normalizes an empty/blank `outcome` → nil;
//   - normalizes `durationMinutes == 0` (or negative) → nil.
//
//  buildDTO is static + pure so this needs no live SupabaseClient.
//

import XCTest
@testable import OPS

final class ActivityRepositoryTests: XCTestCase {

    // MARK: - Fixtures

    private func makeOpportunity() -> Opportunity {
        Opportunity(id: "opp1", companyId: "co-opp", contactName: "Eric Devlin", stage: .quoting)
    }

    private func makeClient() -> Client {
        Client(id: "cli1", name: "Acme Roofing", companyId: "co-client")
    }

    private func makeProject() -> Project {
        let p = Project(id: "prj1", title: "Devlin roof", status: .inProgress)
        p.companyId = "co-project"
        return p
    }

    private func build(
        target: ActivityTarget,
        type: String = "note",
        subject: String? = nil,
        body: String? = nil,
        direction: String? = nil,
        outcome: String? = nil,
        durationMinutes: Int? = nil,
        callSource: String? = nil,
        callerNumber: String? = nil,
        callStartedAt: String? = nil,
        siteVisitId: String? = nil,
        createdBy: String? = "user-1"
    ) -> CreateActivityDTO {
        ActivityRepository.buildDTO(
            target: target,
            companyId: "co-explicit",
            type: type,
            subject: subject,
            body: body,
            direction: direction,
            outcome: outcome,
            durationMinutes: durationMinutes,
            callSource: callSource,
            callerNumber: callerNumber,
            callStartedAt: callStartedAt,
            siteVisitId: siteVisitId,
            createdBy: createdBy
        )
    }

    // MARK: - Exactly one parent

    func test_opportunityTarget_setsOnlyOpportunityId() {
        let dto = build(target: .opportunity(makeOpportunity()))
        XCTAssertEqual(dto.opportunityId, "opp1")
        XCTAssertNil(dto.clientId)
        XCTAssertNil(dto.projectId)
    }

    func test_clientTarget_setsOnlyClientId() {
        let dto = build(target: .client(makeClient()))
        XCTAssertEqual(dto.clientId, "cli1")
        XCTAssertNil(dto.opportunityId)
        XCTAssertNil(dto.projectId)
    }

    func test_projectTarget_setsOnlyProjectId() {
        let dto = build(target: .project(makeProject()))
        XCTAssertEqual(dto.projectId, "prj1")
        XCTAssertNil(dto.opportunityId)
        XCTAssertNil(dto.clientId)
    }

    func test_unboundTarget_setsNoParent() {
        let dto = build(target: .unbound)
        XCTAssertNil(dto.opportunityId)
        XCTAssertNil(dto.clientId)
        XCTAssertNil(dto.projectId)
    }

    // MARK: - company_id + created_by always present

    func test_companyIdAndCreatedByAlwaysStamped() {
        let dto = build(target: .unbound, createdBy: "user-42")
        XCTAssertEqual(dto.companyId, "co-explicit")
        XCTAssertEqual(dto.createdBy, "user-42")
    }

    // MARK: - direction clamped to inbound/outbound/nil

    func test_direction_inboundPreserved() {
        XCTAssertEqual(build(target: .unbound, direction: "inbound").direction, "inbound")
    }

    func test_direction_outboundPreserved() {
        XCTAssertEqual(build(target: .unbound, direction: "outbound").direction, "outbound")
    }

    func test_direction_bogusBecomesNil() {
        XCTAssertNil(build(target: .unbound, direction: "sideways").direction)
    }

    func test_direction_nilStaysNil() {
        XCTAssertNil(build(target: .unbound, direction: nil).direction)
    }

    func test_clampDirection_directly() {
        XCTAssertEqual(ActivityRepository.clampDirection("inbound"), "inbound")
        XCTAssertEqual(ActivityRepository.clampDirection("outbound"), "outbound")
        XCTAssertNil(ActivityRepository.clampDirection("INBOUND"))
        XCTAssertNil(ActivityRepository.clampDirection(""))
        XCTAssertNil(ActivityRepository.clampDirection(nil))
    }

    // MARK: - outcome empty → nil

    func test_outcome_blankBecomesNil() {
        XCTAssertNil(build(target: .unbound, outcome: "").outcome)
        XCTAssertNil(build(target: .unbound, outcome: "   ").outcome)
    }

    func test_outcome_nonBlankPreserved() {
        XCTAssertEqual(build(target: .unbound, outcome: "left voicemail").outcome, "left voicemail")
    }

    // MARK: - durationMinutes == 0 (or negative) → nil

    func test_duration_zeroBecomesNil() {
        XCTAssertNil(build(target: .unbound, durationMinutes: 0).durationMinutes)
    }

    func test_duration_negativeBecomesNil() {
        XCTAssertNil(build(target: .unbound, durationMinutes: -5).durationMinutes)
    }

    func test_duration_positivePreserved() {
        XCTAssertEqual(build(target: .unbound, durationMinutes: 6).durationMinutes, 6)
    }

    func test_duration_nilStaysNil() {
        XCTAssertNil(build(target: .unbound, durationMinutes: nil).durationMinutes)
    }

    // MARK: - pass-through fields

    func test_passThroughFields_preserved() {
        let dto = build(
            target: .opportunity(makeOpportunity()),
            type: "call",
            subject: "Roof quote",
            body: "Talked through pricing",
            callSource: "manual",
            callerNumber: "+15551234",
            callStartedAt: "2026-07-05T10:00:00Z",
            siteVisitId: "sv-1"
        )
        XCTAssertEqual(dto.type, "call")
        XCTAssertEqual(dto.subject, "Roof quote")
        XCTAssertEqual(dto.bodyText, "Talked through pricing")
        XCTAssertEqual(dto.callSource, "manual")
        XCTAssertEqual(dto.callerNumber, "+15551234")
        XCTAssertEqual(dto.callStartedAt, "2026-07-05T10:00:00Z")
        XCTAssertEqual(dto.siteVisitId, "sv-1")
    }
}
