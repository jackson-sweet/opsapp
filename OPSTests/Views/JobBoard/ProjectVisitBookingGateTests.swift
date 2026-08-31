//
//  ProjectVisitBookingGateTests.swift
//  OPSTests
//
//  Bug 7d94c9f3 — the project action bar's BOOK VISIT / REBOOK entry is
//  decided by a pure gate so the rule is testable without the view hierarchy.
//
//  The gate is deliberately STRICTER than the server: `book_site_visit`
//  requires `pipeline.edit` (scope-aware against assigned_to), while the gate
//  demands `pipeline.convert`, whose scope is `leastPermissive(convert, edit)`
//  and therefore always a subset. A rendered verb can never come back 42501,
//  and the project bar speaks the same visit grammar as every lead surface.
//

import XCTest
@testable import OPS

final class ProjectVisitBookingGateTests: XCTestCase {

    // MARK: - Fixtures

    private static let companyId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

    private func makeLead(assignedTo: String?) -> Opportunity {
        let lead = Opportunity(
            id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            companyId: Self.companyId,
            contactName: "Dana Rowe",
            stage: .won
        )
        lead.assignedTo = assignedTo
        lead.projectId = "cccccccc-cccc-cccc-cccc-cccccccccccc"
        return lead
    }

    private func makePolicy(
        currentUserId: String? = "u1",
        permissions: [String: String],
        explicit: Set<String> = []
    ) -> LeadAccessPolicy {
        LeadAccessPolicy(
            currentUserId: currentUserId,
            permissions: permissions,
            explicitPermissionKeys: explicit
        )
    }

    private var allScopeConvertPolicy: LeadAccessPolicy {
        makePolicy(permissions: [
            "pipeline.view": "all",
            "pipeline.edit": "all",
            "pipeline.convert": "all"
        ])
    }

    // MARK: - No linked lead

    /// A manually created (never converted) project has no lead to anchor a
    /// booking to — `book_site_visit` takes `p_opportunity_id`. Hide the entry
    /// rather than render a verb that cannot commit.
    func testHiddenWhenNoLinkedLead() {
        XCTAssertFalse(
            ProjectVisitBookingGate.canOffer(
                projectStatus: .inProgress,
                lead: nil,
                policy: allScopeConvertPolicy
            ),
            "no linked lead ⇒ no booking entry"
        )
    }

    // MARK: - Project status boundary

    /// Finished work takes no new site visits from this surface — the same
    /// boundary the bar's COMPLETE PROJECT verb respects.
    func testHiddenOnCompletedClosedArchivedProjects() {
        for status in [Status.completed, .closed, .archived] {
            XCTAssertFalse(
                ProjectVisitBookingGate.canOffer(
                    projectStatus: status,
                    lead: makeLead(assignedTo: "u1"),
                    policy: allScopeConvertPolicy
                ),
                "\(status.rawValue) projects must not offer a visit booking"
            )
        }
    }

    /// Every live status keeps the entry — a pre-start walkthrough on an
    /// accepted or in-progress job is the use case the bug names.
    func testOfferedOnEveryLiveProjectStatus() {
        for status in [Status.rfq, .estimated, .accepted, .inProgress] {
            XCTAssertTrue(
                ProjectVisitBookingGate.canOffer(
                    projectStatus: status,
                    lead: makeLead(assignedTo: "u1"),
                    policy: allScopeConvertPolicy
                ),
                "\(status.rawValue) projects must offer a visit booking"
            )
        }
    }

    // MARK: - Permission grammar

    func testOfferedWithAllScopeConvert() {
        XCTAssertTrue(
            ProjectVisitBookingGate.canOffer(
                projectStatus: .inProgress,
                lead: makeLead(assignedTo: "u2"),
                policy: allScopeConvertPolicy
            ),
            "all-scope convert reaches any lead, assignee irrelevant"
        )
    }

    /// Assigned-scope convert follows the LEAD's assignee, not the project's
    /// crew — booking is a pipeline act on the opportunity row.
    func testAssignedScopeFollowsLeadAssignee() {
        let policy = makePolicy(permissions: [
            "pipeline.view": "assigned",
            "pipeline.edit": "assigned",
            "pipeline.convert": "assigned"
        ])

        XCTAssertTrue(
            ProjectVisitBookingGate.canOffer(
                projectStatus: .inProgress,
                lead: makeLead(assignedTo: "u1"),
                policy: policy
            ),
            "assigned scope + own lead ⇒ offered"
        )
        XCTAssertFalse(
            ProjectVisitBookingGate.canOffer(
                projectStatus: .inProgress,
                lead: makeLead(assignedTo: "u2"),
                policy: policy
            ),
            "assigned scope + someone else's lead ⇒ hidden"
        )
        XCTAssertFalse(
            ProjectVisitBookingGate.canOffer(
                projectStatus: .inProgress,
                lead: makeLead(assignedTo: nil),
                policy: policy
            ),
            "assigned scope + unassigned lead ⇒ hidden (fails closed)"
        )
    }

    /// An explicit convert revoke hides the entry even though the SERVER would
    /// accept the booking on `pipeline.edit` alone. Consistency with every
    /// other lead surface beats maximal exposure: a user who cannot convert
    /// this lead anywhere else must not be handed a visit verb here.
    func testEditWithoutConvertGrantHides() {
        let policy = makePolicy(
            permissions: [
                "pipeline.view": "all",
                "pipeline.edit": "all"
            ],
            explicit: ["pipeline.convert"]
        )

        XCTAssertFalse(
            ProjectVisitBookingGate.canOffer(
                projectStatus: .inProgress,
                lead: makeLead(assignedTo: "u1"),
                policy: policy
            ),
            "explicit pipeline.convert revoke ⇒ hidden"
        )
    }

    /// No pipeline grants at all (a crew persona with no lead access) — the
    /// project bar must not become a back door into the pipeline.
    func testNoPipelineGrantsHides() {
        XCTAssertFalse(
            ProjectVisitBookingGate.canOffer(
                projectStatus: .inProgress,
                lead: makeLead(assignedTo: "u1"),
                policy: makePolicy(permissions: [:])
            ),
            "no pipeline grants ⇒ hidden"
        )
    }

    /// The gate is stage-blind by design: the linked lead of a converted
    /// project is WON, and `book_site_visit` performs no stage check
    /// (verified against the live function body 2026-08-31). A WON lead
    /// booking a pre-start walkthrough is the intended path.
    func testStageIsNotConsulted() {
        for stage in [PipelineStage.newLead, .qualifying, .won] {
            let lead = makeLead(assignedTo: "u1")
            lead.stage = stage
            XCTAssertTrue(
                ProjectVisitBookingGate.canOffer(
                    projectStatus: .inProgress,
                    lead: lead,
                    policy: allScopeConvertPolicy
                ),
                "stage \(stage.rawValue) must not gate the project-side booking entry"
            )
        }
    }
}
