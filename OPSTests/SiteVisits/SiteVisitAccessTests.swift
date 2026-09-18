//
//  SiteVisitAccessTests.swift
//  OPSTests
//
//  CREW SITE VISITS · P1 — pins the pure access rules: assignment is the
//  grant, walk-up capture is a permission, and every lead-authority action a
//  crew member cannot perform stays closed. Fixtures are invented people and
//  ids only.
//

import XCTest
@testable import OPS

final class SiteVisitAccessTests: XCTestCase {
    private let crewId = "11111111-aaaa-4aaa-8aaa-111111111111"
    private let officeId = "22222222-bbbb-4bbb-8bbb-222222222222"
    private let companyId = "33333333-cccc-4ccc-8ccc-333333333333"
    private let otherCompanyId = "44444444-dddd-4ddd-8ddd-444444444444"
    private let leadId = "55555555-eeee-4eee-8eee-555555555555"
    private let otherLeadId = "66666666-ffff-4fff-8fff-666666666666"
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - Fixtures

    private func policy(_ permissions: [String: String], userId: String? = nil) -> LeadAccessPolicy {
        LeadAccessPolicy(
            currentUserId: userId ?? crewId,
            permissions: permissions,
            explicitPermissionKeys: LeadAccessPolicy.granularPermissionKeys
        )
    }

    /// Crew preset: no pipeline grant at all.
    private var crewPolicy: LeadAccessPolicy { policy([:]) }

    /// Assigned-scope sales rep.
    private var assignedRepPolicy: LeadAccessPolicy {
        policy([
            "pipeline.view": "assigned",
            "pipeline.edit": "assigned",
            "pipeline.convert": "assigned",
        ])
    }

    /// Office: every lead, company-wide.
    private var officePolicy: LeadAccessPolicy {
        policy([
            "pipeline.create": "all",
            "pipeline.view": "all",
            "pipeline.edit": "all",
            "pipeline.convert": "all",
        ], userId: officeId)
    }

    private func visit(
        id: String,
        opportunityId: String? = nil,
        assigneeIds: [String] = [],
        status: SiteVisitStatus = .scheduled,
        companyId: String? = nil,
        completedAt: Date? = nil,
        deletedAt: Date? = nil,
        scheduledAt: Date? = nil,
        bookedAt: Date? = nil,
        createdAt: Date? = nil
    ) -> SiteVisitAccessCandidate {
        SiteVisitAccessCandidate(
            id: id,
            companyId: companyId ?? self.companyId,
            opportunityId: opportunityId,
            assigneeIds: assigneeIds,
            status: status,
            completedAt: completedAt,
            deletedAt: deletedAt,
            scheduledAt: scheduledAt,
            bookedAt: bookedAt,
            createdAt: createdAt ?? now.addingTimeInterval(-86_400)
        )
    }

    // MARK: - Assignment

    func testIsAssigneeMatchesCaseInsensitively() {
        XCTAssertTrue(SiteVisitAccess.isAssignee(assigneeIds: [crewId], userId: crewId.uppercased()))
        XCTAssertTrue(SiteVisitAccess.isAssignee(assigneeIds: [crewId.uppercased()], userId: crewId))
        XCTAssertTrue(SiteVisitAccess.isAssignee(assigneeIds: [officeId, " \(crewId) "], userId: crewId))
    }

    func testIsAssigneeRejectsMissingIdentityAndOtherUsers() {
        XCTAssertFalse(SiteVisitAccess.isAssignee(assigneeIds: [crewId], userId: nil))
        XCTAssertFalse(SiteVisitAccess.isAssignee(assigneeIds: [crewId], userId: ""))
        XCTAssertFalse(SiteVisitAccess.isAssignee(assigneeIds: [], userId: crewId))
        XCTAssertFalse(SiteVisitAccess.isAssignee(assigneeIds: [officeId], userId: crewId))
    }

    func testIsAssigneeReadsTheSwiftDataVisitsAssigneeIds() {
        let model = SiteVisit(companyId: companyId, assigneeIds: [crewId.uppercased()])
        XCTAssertTrue(SiteVisitAccess.isAssignee(model, userId: crewId))
        XCTAssertFalse(SiteVisitAccess.isAssignee(model, userId: officeId))
        // `assignedTo` alone is not the server's assignment grant.
        let legacy = SiteVisit(companyId: companyId)
        legacy.assignedTo = crewId
        XCTAssertFalse(SiteVisitAccess.isAssignee(legacy, userId: crewId))
    }

    // MARK: - Walk-up capture

    func testCanStartWalkUpForCaptureOnlyOrConvertAnyButNotNeither() {
        XCTAssertTrue(SiteVisitAccess.canStartWalkUp(canCapture: true, canConvertAny: false))
        XCTAssertTrue(SiteVisitAccess.canStartWalkUp(canCapture: false, canConvertAny: true))
        XCTAssertTrue(SiteVisitAccess.canStartWalkUp(canCapture: true, canConvertAny: true))
        XCTAssertFalse(SiteVisitAccess.canStartWalkUp(canCapture: false, canConvertAny: false))
    }

    func testCanStartWalkUpReadsThePermissionStoreAndThePipelineFlag() {
        let crew = PermissionStore()
        crew.apply(PermissionPayload(
            roleId: "crew-role", roleName: "Crew", roleHierarchy: 5,
            permissions: [SiteVisitAccess.capturePermission: "all"],
            explicitPermissionKeys: [SiteVisitAccess.capturePermission],
            isAdmin: false
        ), userId: crewId)
        XCTAssertTrue(SiteVisitAccess.canStartWalkUp(permissionStore: crew))

        // The permission belongs to the pipeline flag: a disabled flag blocks it.
        crew.blockedByFlags = Set(FeatureFlagService.staticFlagDefinitions["pipeline"] ?? [])
        XCTAssertFalse(SiteVisitAccess.canStartWalkUp(permissionStore: crew))

        let unassigned = PermissionStore()
        unassigned.apply(PermissionPayload(
            roleId: "unassigned-role", roleName: "Unassigned", roleHierarchy: 6,
            permissions: [:], explicitPermissionKeys: [], isAdmin: false
        ), userId: crewId)
        XCTAssertFalse(SiteVisitAccess.canStartWalkUp(permissionStore: unassigned))

        let rep = PermissionStore()
        rep.apply(PermissionPayload(
            roleId: "rep-role", roleName: "Rep", roleHierarchy: 4,
            permissions: ["pipeline.view": "assigned", "pipeline.edit": "assigned", "pipeline.convert": "assigned"],
            explicitPermissionKeys: LeadAccessPolicy.granularPermissionKeys,
            isAdmin: false
        ), userId: crewId)
        XCTAssertTrue(SiteVisitAccess.canStartWalkUp(permissionStore: rep),
                      "pipeline.convert at any scope still starts a walk-up")

        let admin = PermissionStore()
        admin.apply(PermissionService.adminPayload(), userId: officeId)
        XCTAssertTrue(SiteVisitAccess.canStartWalkUp(permissionStore: admin))
    }

    // MARK: - Registry

    func testSiteVisitsCaptureIsRegisteredAsAnAllOnlyPermissionUnderThePipelineFlag() throws {
        let definition = try XCTUnwrap(PermissionRegistry.definition(for: "site_visits.capture"))
        XCTAssertEqual(definition.label, "Start site visits")
        XCTAssertEqual(definition.category, "Site Visits")
        XCTAssertEqual(definition.allowedLevels, [.off, .all])
        XCTAssertFalse(definition.hiddenFromEditor)
        XCTAssertTrue(PermissionRegistry.categories.contains("Site Visits"))
        XCTAssertEqual(PermissionRegistry.featureFlag(for: "Site Visits"), "pipeline")
        XCTAssertTrue((FeatureFlagService.staticFlagDefinitions["pipeline"] ?? []).contains("site_visits.capture"))
        XCTAssertEqual(PermissionService.adminPayload().permissions["site_visits.capture"], "all",
                       "admins hold the new permission through the registry")
    }

    // MARK: - Lead authority

    func testLeadAuthorityWithAnUnknownAssigneeOnlySatisfiesAllScope() {
        XCTAssertEqual(SiteVisitAccess.leadAuthority(policy: crewPolicy, assignedTo: nil), .none)
        XCTAssertEqual(
            SiteVisitAccess.leadAuthority(policy: assignedRepPolicy, assignedTo: nil),
            SiteVisitLeadAuthority(canView: false, canEdit: false, canConvert: false, canCreate: false)
        )
        XCTAssertEqual(
            SiteVisitAccess.leadAuthority(policy: assignedRepPolicy, assignedTo: crewId.uppercased()),
            SiteVisitLeadAuthority(canView: true, canEdit: true, canConvert: true, canCreate: false)
        )
        XCTAssertEqual(
            SiteVisitAccess.leadAuthority(policy: officePolicy, assignedTo: nil),
            SiteVisitLeadAuthority(canView: true, canEdit: true, canConvert: true, canCreate: true)
        )
    }

    // MARK: - START / RESUME relay

    func testLeadsTabOwnsTheIntentWhenTheUserHasLeadsAccessAndALead() {
        XCTAssertEqual(
            SiteVisitAccess.resolveStart(
                leadId: leadId, siteVisitId: "visit-a", hasLeadsAccess: true,
                userId: officeId, companyId: companyId, candidates: [], now: now
            ),
            .leadsTab
        )
    }

    func testAssigneeWithoutLeadsAccessOpensTheExactVisitById() {
        let target = visit(id: "visit-a", opportunityId: leadId, assigneeIds: [crewId])
        let sibling = visit(id: "visit-b", opportunityId: leadId, assigneeIds: [crewId], status: .inProgress)
        XCTAssertEqual(
            SiteVisitAccess.resolveStart(
                leadId: leadId, siteVisitId: "VISIT-A", hasLeadsAccess: false,
                userId: crewId, companyId: companyId, candidates: [sibling, target], now: now
            ),
            .rootCapture(visitId: "visit-a")
        )
    }

    func testAssigneeMatchedByLeadIdPrefersTheVisitAlreadyOnSite() {
        let booked = visit(id: "visit-booked", opportunityId: leadId, assigneeIds: [crewId],
                           scheduledAt: now, bookedAt: now)
        let onSite = visit(id: "visit-on-site", opportunityId: leadId, assigneeIds: [crewId],
                           status: .inProgress)
        XCTAssertEqual(
            SiteVisitAccess.resolveStart(
                leadId: leadId.uppercased(), siteVisitId: nil, hasLeadsAccess: false,
                userId: crewId, companyId: companyId, candidates: [booked, onSite], now: now
            ),
            .rootCapture(visitId: "visit-on-site")
        )
    }

    func testAssigneeMatchedByLeadIdPicksTheBookingNearestNow() {
        let far = visit(id: "visit-far", opportunityId: leadId, assigneeIds: [crewId],
                        scheduledAt: now.addingTimeInterval(3 * 86_400), bookedAt: now)
        let near = visit(id: "visit-near", opportunityId: leadId, assigneeIds: [crewId],
                         scheduledAt: now.addingTimeInterval(1_800), bookedAt: now)
        XCTAssertEqual(
            SiteVisitAccess.resolveStart(
                leadId: leadId, siteVisitId: nil, hasLeadsAccess: false,
                userId: crewId, companyId: companyId, candidates: [far, near], now: now
            ),
            .rootCapture(visitId: "visit-near")
        )
    }

    func testAStaleVisitIdFallsBackToTheLeadsOpenAssignedVisit() {
        let open = visit(id: "visit-open", opportunityId: leadId, assigneeIds: [crewId])
        XCTAssertEqual(
            SiteVisitAccess.resolveStart(
                leadId: leadId, siteVisitId: "visit-gone", hasLeadsAccess: false,
                userId: crewId, companyId: companyId, candidates: [open], now: now
            ),
            .rootCapture(visitId: "visit-open")
        )
    }

    func testLeadsAccessWithoutALeadStillResumesAnAssignedLeadlessVisit() {
        let leadless = visit(id: "visit-walkup", assigneeIds: [officeId], status: .inProgress)
        XCTAssertEqual(
            SiteVisitAccess.resolveStart(
                leadId: nil, siteVisitId: "visit-walkup", hasLeadsAccess: true,
                userId: officeId, companyId: companyId, candidates: [leadless], now: now
            ),
            .rootCapture(visitId: "visit-walkup")
        )
    }

    func testRelayDeniesClosedUnassignedAndForeignVisits() {
        let candidates = [
            visit(id: "completed", opportunityId: leadId, assigneeIds: [crewId], status: .completed, completedAt: now),
            visit(id: "cancelled", opportunityId: leadId, assigneeIds: [crewId], status: .cancelled),
            visit(id: "deleted", opportunityId: leadId, assigneeIds: [crewId], deletedAt: now),
            visit(id: "someone-else", opportunityId: leadId, assigneeIds: [officeId]),
            visit(id: "other-company", opportunityId: leadId, assigneeIds: [crewId], companyId: otherCompanyId),
        ]
        for id in candidates.map(\.id) {
            XCTAssertEqual(
                SiteVisitAccess.resolveStart(
                    leadId: leadId, siteVisitId: id, hasLeadsAccess: false,
                    userId: crewId, companyId: companyId, candidates: candidates, now: now
                ),
                .denied,
                "\(id) must not open"
            )
        }
        XCTAssertEqual(
            SiteVisitAccess.resolveStart(
                leadId: nil, siteVisitId: nil, hasLeadsAccess: false,
                userId: crewId, companyId: companyId, candidates: [], now: now
            ),
            .denied
        )
        XCTAssertEqual(
            SiteVisitAccess.resolveStart(
                leadId: otherLeadId, siteVisitId: nil, hasLeadsAccess: false,
                userId: crewId, companyId: companyId,
                candidates: [visit(id: "visit-a", opportunityId: leadId, assigneeIds: [crewId])], now: now
            ),
            .denied
        )
    }

    // MARK: - Calendar dialog

    private func actions(
        _ status: SiteVisitStatus,
        today: Bool = true,
        leads: Bool,
        convert: Bool,
        hasLead: Bool = true,
        booking: Bool = true,
        canOpen: Bool = true
    ) -> [SiteVisitCalendarAction] {
        SiteVisitAccess.calendarActions(
            status: status, isToday: today, hasLeadsAccess: leads, canConvertAny: convert,
            hasLead: hasLead, hasBookingSnapshot: booking, canOpenVisit: canOpen
        )
    }

    func testCrewAssigneeSeesStartTodayAndResumeOnSiteButNoLeadOrBookingActions() {
        XCTAssertEqual(actions(.scheduled, leads: false, convert: false), [.startNow])
        XCTAssertEqual(actions(.scheduled, today: false, leads: false, convert: false), [])
        XCTAssertEqual(actions(.inProgress, leads: false, convert: false), [.resumeVisit])
        XCTAssertEqual(actions(.inProgress, today: false, leads: false, convert: false), [.resumeVisit])
    }

    func testOfficeSeesTheFullSetWhereTheStateAllowsIt() {
        XCTAssertEqual(actions(.scheduled, leads: true, convert: true), [.startNow, .reschedule, .openLead])
        XCTAssertEqual(actions(.scheduled, today: false, leads: true, convert: true), [.reschedule, .openLead])
        XCTAssertEqual(actions(.inProgress, leads: true, convert: true), [.resumeVisit, .openLead])
    }

    func testRescheduleNeedsConvertALeadAndARealBooking() {
        XCTAssertEqual(actions(.scheduled, today: false, leads: true, convert: false), [.openLead])
        XCTAssertEqual(actions(.scheduled, today: false, leads: true, convert: true, booking: false), [.openLead])
        XCTAssertEqual(actions(.scheduled, today: false, leads: true, convert: true, hasLead: false), [])
    }

    func testStartAndResumeStayOffCardsTheUserCannotOpen() {
        XCTAssertEqual(actions(.scheduled, leads: false, convert: false, canOpen: false), [])
        XCTAssertEqual(actions(.inProgress, leads: false, convert: false, canOpen: false), [])
        XCTAssertTrue(SiteVisitAccess.canOpenVisit(hasLeadsAccess: true, hasLead: true, isAssignee: false))
        XCTAssertFalse(SiteVisitAccess.canOpenVisit(hasLeadsAccess: true, hasLead: false, isAssignee: false))
        XCTAssertTrue(SiteVisitAccess.canOpenVisit(hasLeadsAccess: false, hasLead: true, isAssignee: true))
        XCTAssertFalse(SiteVisitAccess.canOpenVisit(hasLeadsAccess: false, hasLead: true, isAssignee: false))
    }

    // MARK: - Capture gates

    func testCrewOnAnAssignedLeadVisitGetsEveryBindingActionClosed() {
        let gates = SiteVisitAccess.captureGates(
            policy: crewPolicy, boundLeadId: leadId, boundLeadAssignedTo: nil, isProjectLinked: false
        )
        XCTAssertEqual(gates, SiteVisitCaptureGates(
            canChangeBinding: false,
            canSearchLeads: false,
            canCreateLead: false,
            canCreateProject: false,
            canMoveLeadStage: false,
            canPersistAddressToLead: false,
            canDiscardVisit: false
        ))
    }

    func testAssignedScopeRepHasAuthorityOnlyOnTheirOwnLead() {
        let own = SiteVisitAccess.captureGates(
            policy: assignedRepPolicy, boundLeadId: leadId, boundLeadAssignedTo: crewId, isProjectLinked: false
        )
        XCTAssertTrue(own.canChangeBinding)
        XCTAssertTrue(own.canSearchLeads)
        XCTAssertTrue(own.canCreateProject)
        XCTAssertTrue(own.canMoveLeadStage)
        XCTAssertTrue(own.canPersistAddressToLead)
        XCTAssertTrue(own.canDiscardVisit)
        XCTAssertFalse(own.canCreateLead, "a bound visit never offers CREATE LEAD")

        let colleagues = SiteVisitAccess.captureGates(
            policy: assignedRepPolicy, boundLeadId: leadId, boundLeadAssignedTo: officeId, isProjectLinked: false
        )
        XCTAssertFalse(colleagues.canChangeBinding)
        XCTAssertFalse(colleagues.canMoveLeadStage)
        XCTAssertFalse(colleagues.canCreateProject)
        XCTAssertFalse(colleagues.canDiscardVisit)

        let briefSnapshot = SiteVisitAccess.captureGates(
            policy: assignedRepPolicy, boundLeadId: leadId, boundLeadAssignedTo: nil, isProjectLinked: false
        )
        XCTAssertFalse(briefSnapshot.canMoveLeadStage, "unknown assignee never satisfies an assigned scope")
    }

    func testOfficeKeepsTodaysCaptureOnABoundLead() {
        let gates = SiteVisitAccess.captureGates(
            policy: officePolicy, boundLeadId: leadId, boundLeadAssignedTo: nil, isProjectLinked: false
        )
        XCTAssertTrue(gates.canChangeBinding)
        XCTAssertTrue(gates.canCreateProject)
        XCTAssertTrue(gates.canMoveLeadStage)
        XCTAssertTrue(gates.canPersistAddressToLead)
        XCTAssertTrue(gates.canDiscardVisit)
    }

    func testProjectLinkedVisitWithNoLeadIsLockedUnlessLeadEditIsCompanyWide() {
        let crew = SiteVisitAccess.captureGates(
            policy: crewPolicy, boundLeadId: nil, boundLeadAssignedTo: nil, isProjectLinked: true
        )
        XCTAssertFalse(crew.canChangeBinding)
        XCTAssertFalse(crew.canSearchLeads)
        XCTAssertFalse(crew.canCreateLead)
        XCTAssertFalse(crew.canDiscardVisit)
        XCTAssertFalse(crew.canMoveLeadStage)

        let office = SiteVisitAccess.captureGates(
            policy: officePolicy, boundLeadId: nil, boundLeadAssignedTo: nil, isProjectLinked: true
        )
        XCTAssertTrue(office.canChangeBinding)
        XCTAssertTrue(office.canDiscardVisit)
        XCTAssertFalse(office.canMoveLeadStage, "no lead, no stage")
    }

    func testLeadlessWalkUpKeepsTodaysBehaviourBehindLeadGrants() {
        let crew = SiteVisitAccess.captureGates(
            policy: crewPolicy, boundLeadId: nil, boundLeadAssignedTo: nil, isProjectLinked: false
        )
        XCTAssertFalse(crew.canSearchLeads, "lead search needs a lead view grant")
        XCTAssertFalse(crew.canChangeBinding)
        XCTAssertFalse(crew.canCreateLead, "CREATE LEAD needs pipeline create")
        XCTAssertTrue(crew.canDiscardVisit, "a crew member's own walk-up stays discardable")

        let office = SiteVisitAccess.captureGates(
            policy: officePolicy, boundLeadId: nil, boundLeadAssignedTo: nil, isProjectLinked: false
        )
        XCTAssertTrue(office.canSearchLeads)
        XCTAssertTrue(office.canChangeBinding)
        XCTAssertTrue(office.canCreateLead)
        XCTAssertTrue(office.canDiscardVisit)
    }

    func testANewVisitIsOnlyMintedUnderTheAuthorityTheServerChecks() {
        XCTAssertFalse(SiteVisitAccess.canCreateVisit(
            policy: crewPolicy, boundLeadId: leadId, boundLeadAssignedTo: nil, canStartWalkUp: true
        ), "walk-up authority never mints a lead-bound visit")
        XCTAssertTrue(SiteVisitAccess.canCreateVisit(
            policy: officePolicy, boundLeadId: leadId, boundLeadAssignedTo: nil, canStartWalkUp: false
        ))
        XCTAssertTrue(SiteVisitAccess.canCreateVisit(
            policy: crewPolicy, boundLeadId: nil, boundLeadAssignedTo: nil, canStartWalkUp: true
        ))
        XCTAssertFalse(SiteVisitAccess.canCreateVisit(
            policy: crewPolicy, boundLeadId: nil, boundLeadAssignedTo: nil, canStartWalkUp: false
        ))
    }

    // MARK: - Reminder routing

    func testReminderLandsOnTheVisitsDayByIdThenByAssignedLead() {
        let day = now.addingTimeInterval(2 * 86_400)
        let assigned = visit(id: "visit-a", opportunityId: leadId, assigneeIds: [crewId],
                             scheduledAt: day, bookedAt: now)
        let colleagues = visit(id: "visit-b", opportunityId: leadId, assigneeIds: [officeId],
                               scheduledAt: now.addingTimeInterval(600), bookedAt: now)

        XCTAssertEqual(SiteVisitAccess.reminderFocusDate(
            leadId: leadId, siteVisitId: "VISIT-A", userId: crewId, candidates: [colleagues, assigned], now: now
        ), day)
        XCTAssertEqual(SiteVisitAccess.reminderFocusDate(
            leadId: leadId, siteVisitId: nil, userId: crewId, candidates: [colleagues, assigned], now: now
        ), day, "only the user's own visits date a lead-id-only reminder")
        XCTAssertNil(SiteVisitAccess.reminderFocusDate(
            leadId: otherLeadId, siteVisitId: nil, userId: crewId, candidates: [assigned], now: now
        ))
        XCTAssertNil(SiteVisitAccess.reminderFocusDate(
            leadId: nil, siteVisitId: nil, userId: crewId, candidates: [assigned], now: now
        ))
    }
}
